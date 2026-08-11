-- =============================================================================
-- Migration 001: Extensions, Enums, Core Identity
-- =============================================================================

create extension if not exists "uuid-ossp";
create extension if not exists "postgis";
create extension if not exists "citext";
create extension if not exists "pg_trgm"; -- trigram search for usernames/hashtags/venue names

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------
create type badge_type as enum ('verified', 'creator', 'organizer', 'business');
create type vibe_tag_name as enum ('turnt', 'chill', 'networking', 'dancing', 'foodie', 'music_lover');
create type event_type as enum ('party', 'concert', 'hangout', 'private_party', 'festival', 'sports', 'other');
create type event_visibility as enum ('public', 'friends_only', 'private', 'invite_only');
create type event_status as enum ('draft', 'published', 'live', 'ended', 'cancelled');
create type checkin_method as enum ('qr', 'geofence', 'manual_organizer');
create type ticket_type as enum ('general', 'vip', 'early_bird', 'student', 'group', 'table');
create type ticket_purchase_status as enum ('pending', 'paid', 'refunded', 'cancelled');
create type conversation_type as enum ('dm', 'group', 'event_room');
create type message_type as enum ('text', 'image', 'video', 'audio', 'file', 'location', 'system');
create type payment_provider as enum ('flutterwave', 'paystack', 'monnify', 'fincra', 'apple_pay', 'google_pay', 'wallet');
create type payment_status as enum ('initiated', 'pending', 'succeeded', 'failed', 'refunded');
create type payment_purpose as enum ('ticket', 'voucher_topup', 'wallet_topup', 'organizer_payout', 'marketplace');
create type business_category as enum ('restaurant', 'lounge', 'nightclub', 'hotel', 'artist', 'event_center', 'fashion_brand', 'other');
create type kyc_status as enum ('not_started', 'pending', 'approved', 'rejected');
create type community_type as enum ('public', 'private');
create type community_role as enum ('member', 'moderator', 'admin', 'owner');
create type report_target_type as enum ('user', 'post', 'message', 'event', 'community');
create type report_status as enum ('open', 'reviewing', 'resolved', 'dismissed');
create type wallet_txn_type as enum ('credit', 'debit');
create type room_temperature as enum ('cold', 'warm', 'hot', 'on_fire');

-- -----------------------------------------------------------------------------
-- profiles — 1:1 extension of auth.users (Supabase-managed)
-- -----------------------------------------------------------------------------
create table profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    username citext not null,
    display_name text not null,
    avatar_url text,
    cover_url text,
    bio text,
    phone_number text,
    date_of_birth date,
    gender text,
    home_city text,
    current_location geography(Point, 4326),
    currently_at_event_id uuid, -- FK added after events table exists (migration 003)
    energy_score integer not null default 0,
    energy_score_percentile numeric(5,2), -- e.g. 95.00 = "top 5%"
    is_verified boolean not null default false,
    onboarding_completed boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint username_format check (username ~ '^[a-z0-9_]{3,20}$')
);

create unique index idx_profiles_username on profiles (username);
create index idx_profiles_location on profiles using gist (current_location);
create index idx_profiles_energy_score on profiles (energy_score desc);

comment on column profiles.energy_score is 'Denormalized cache of the latest energy_score_events ledger sum. Never write here directly outside the recompute function.';
comment on column profiles.current_location is 'Last known location, updated by client on foreground/background per privacy settings. Used for nearby-events and nearby-people queries.';

-- -----------------------------------------------------------------------------
-- badges — many-to-many, since a user can hold multiple badge types
-- -----------------------------------------------------------------------------
create table user_badges (
    user_id uuid not null references profiles(id) on delete cascade,
    badge_type badge_type not null,
    granted_at timestamptz not null default now(),
    granted_by uuid references profiles(id),
    primary key (user_id, badge_type)
);

-- -----------------------------------------------------------------------------
-- vibe tags (Discover screen filters: Turnt / Chill / Networking / ...)
-- -----------------------------------------------------------------------------
create table user_vibe_tags (
    user_id uuid not null references profiles(id) on delete cascade,
    tag vibe_tag_name not null,
    set_at timestamptz not null default now(),
    expires_at timestamptz, -- vibe tags are session-like: "tonight I'm feeling..."
    primary key (user_id, tag)
);

create index idx_user_vibe_tags_tag on user_vibe_tags (tag) where expires_at is null or expires_at > now();

-- -----------------------------------------------------------------------------
-- social graph
-- -----------------------------------------------------------------------------
create table follows (
    follower_id uuid not null references profiles(id) on delete cascade,
    following_id uuid not null references profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (follower_id, following_id),
    constraint no_self_follow check (follower_id <> following_id)
);
create index idx_follows_following on follows (following_id);

create type friendship_status as enum ('pending', 'accepted', 'blocked');
create table friendships (
    user_id uuid not null references profiles(id) on delete cascade,
    friend_id uuid not null references profiles(id) on delete cascade,
    status friendship_status not null default 'pending',
    requested_by uuid not null references profiles(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (user_id, friend_id),
    constraint no_self_friend check (user_id <> friend_id)
);
create index idx_friendships_status on friendships (status);

-- updated_at trigger helper (reused by many tables across migrations)
create or replace function set_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

create trigger trg_profiles_updated_at before update on profiles
    for each row execute function set_updated_at();

create trigger trg_friendships_updated_at before update on friendships
    for each row execute function set_updated_at();
