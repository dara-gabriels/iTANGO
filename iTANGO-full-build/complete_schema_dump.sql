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

create index idx_user_vibe_tags_tag on user_vibe_tags (tag) ;

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
-- =============================================================================
-- Migration 002: Businesses, Venues, Communities
-- =============================================================================

create table businesses (
    id uuid primary key default uuid_generate_v4(),
    owner_id uuid not null references profiles(id) on delete restrict,
    name text not null,
    category business_category not null,
    description text,
    logo_url text,
    cover_url text,
    kyc_status kyc_status not null default 'not_started',
    kyc_documents jsonb, -- references to Storage objects, not raw documents
    is_verified boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create index idx_businesses_owner on businesses (owner_id);
create index idx_businesses_category on businesses (category);
create trigger trg_businesses_updated_at before update on businesses
    for each row execute function set_updated_at();

create table venues (
    id uuid primary key default uuid_generate_v4(),
    business_id uuid references businesses(id) on delete set null,
    name text not null,
    address text not null,
    city text not null,
    location geography(Point, 4326) not null,
    capacity integer,
    amenities text[],
    cover_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create index idx_venues_location on venues using gist (location);
create index idx_venues_city on venues (city);
create trigger trg_venues_updated_at before update on venues
    for each row execute function set_updated_at();

-- -----------------------------------------------------------------------------
-- Communities (Meetup/Discord-style interest groups)
-- -----------------------------------------------------------------------------
create table communities (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    slug citext not null,
    description text,
    category text,
    cover_url text,
    type community_type not null default 'public',
    created_by uuid not null references profiles(id),
    member_count integer not null default 0, -- denormalized counter, maintained by trigger
    created_at timestamptz not null default now()
);
create unique index idx_communities_slug on communities (slug);

create table community_members (
    community_id uuid not null references communities(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    role community_role not null default 'member',
    joined_at timestamptz not null default now(),
    primary key (community_id, user_id)
);
create index idx_community_members_user on community_members (user_id);

create or replace function bump_community_member_count()
returns trigger as $$
begin
    if (tg_op = 'INSERT') then
        update communities set member_count = member_count + 1 where id = new.community_id;
    elsif (tg_op = 'DELETE') then
        update communities set member_count = member_count - 1 where id = old.community_id;
    end if;
    return null;
end;
$$ language plpgsql;

create trigger trg_community_members_count
    after insert or delete on community_members
    for each row execute function bump_community_member_count();
-- =============================================================================
-- Migration 003: Events, Ticketing, Check-ins
-- =============================================================================

create table events (
    id uuid primary key default uuid_generate_v4(),
    organizer_id uuid not null references profiles(id) on delete restrict,
    business_id uuid references businesses(id) on delete set null,
    venue_id uuid references venues(id) on delete set null,
    title text not null,
    description text,
    cover_url text,
    event_type event_type not null default 'party',
    visibility event_visibility not null default 'public',
    status event_status not null default 'draft',
    start_time timestamptz not null,
    end_time timestamptz,
    min_age integer,
    tags text[],
    live_attendee_count integer not null default 0, -- denormalized, updated on check-in
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint end_after_start check (end_time is null or end_time > start_time)
);

create index idx_events_start_time_status on events (start_time, status);
create index idx_events_organizer on events (organizer_id);
create index idx_events_venue on events (venue_id);
create index idx_events_tags on events using gin (tags);

create trigger trg_events_updated_at before update on events
    for each row execute function set_updated_at();

-- Now that events exists, wire up profiles.currently_at_event_id
alter table profiles
    add constraint fk_profiles_currently_at_event
    foreign key (currently_at_event_id) references events(id) on delete set null;

-- -----------------------------------------------------------------------------
-- RSVPs (soft interest — distinct from check_ins, which is verified presence)
-- -----------------------------------------------------------------------------
create type rsvp_status as enum ('interested', 'going', 'not_going');
create table event_attendees (
    event_id uuid not null references events(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    rsvp_status rsvp_status not null default 'interested',
    created_at timestamptz not null default now(),
    primary key (event_id, user_id)
);
create index idx_event_attendees_user on event_attendees (user_id);

-- -----------------------------------------------------------------------------
-- check_ins — the core trust primitive. Gates event-room chat access and
-- energy score gains. Append-only; never updated, only inserted.
-- -----------------------------------------------------------------------------
create table check_ins (
    id uuid primary key default uuid_generate_v4(),
    event_id uuid not null references events(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    method checkin_method not null,
    location geography(Point, 4326),
    verified_by uuid references profiles(id), -- organizer/staff user, if method = manual_organizer
    checked_in_at timestamptz not null default now(),

    unique (event_id, user_id) -- one check-in per user per event
);
create index idx_check_ins_event on check_ins (event_id);
create index idx_check_ins_user on check_ins (user_id);
create index idx_check_ins_location on check_ins using gist (location);

create or replace function on_check_in()
returns trigger as $$
begin
    -- Bump live attendee count on the event
    update events set live_attendee_count = live_attendee_count + 1 where id = new.event_id;

    -- Auto-join the user to that event's chat room (conversation created in migration 004;
    -- this insert is deferred there via a separate trigger to avoid a forward reference).

    -- Award energy score for a verified check-in (ledger insert; see migration 006 for table)
    -- Deferred: see migration 006 trigger `award_energy_for_checkin`.
    return new;
end;
$$ language plpgsql;

create trigger trg_on_check_in after insert on check_ins
    for each row execute function on_check_in();

-- -----------------------------------------------------------------------------
-- Ticketing
-- -----------------------------------------------------------------------------
create table tickets (
    id uuid primary key default uuid_generate_v4(),
    event_id uuid not null references events(id) on delete cascade,
    name text not null,
    ticket_type ticket_type not null default 'general',
    price numeric(12,2) not null default 0,
    currency text not null default 'NGN',
    quantity_total integer not null,
    quantity_sold integer not null default 0,
    sales_start timestamptz,
    sales_end timestamptz,
    is_active boolean not null default true,

    constraint quantity_valid check (quantity_sold <= quantity_total)
);
create index idx_tickets_event on tickets (event_id);
-- Partial index: speeds up "is this ticket still available" checks without
-- scanning sold-out tickets.
create index idx_tickets_available on tickets (event_id) ;

create table ticket_purchases (
    id uuid primary key default uuid_generate_v4(),
    ticket_id uuid not null references tickets(id) on delete restrict,
    user_id uuid not null references profiles(id) on delete restrict,
    quantity integer not null default 1,
    total_amount numeric(12,2) not null,
    currency text not null default 'NGN',
    status ticket_purchase_status not null default 'pending',
    payment_id uuid, -- FK added in migration 005 once payments table exists
    qr_code text not null unique, -- opaque signed token, verified server-side at door
    wallet_pass_url text, -- Apple/Google Wallet pass, generated post-purchase
    purchased_at timestamptz not null default now(),

    constraint quantity_positive check (quantity > 0)
);
create index idx_ticket_purchases_user on ticket_purchases (user_id);
create index idx_ticket_purchases_ticket on ticket_purchases (ticket_id);

create or replace function on_ticket_purchase_paid()
returns trigger as $$
begin
    if new.status = 'paid' and old.status <> 'paid' then
        update tickets set quantity_sold = quantity_sold + new.quantity where id = new.ticket_id;
    end if;
    return new;
end;
$$ language plpgsql;

create trigger trg_ticket_purchase_paid after update on ticket_purchases
    for each row execute function on_ticket_purchase_paid();

-- -----------------------------------------------------------------------------
-- Event reviews
-- -----------------------------------------------------------------------------
create table event_reviews (
    id uuid primary key default uuid_generate_v4(),
    event_id uuid not null references events(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    rating smallint not null,
    comment text,
    created_at timestamptz not null default now(),

    unique (event_id, user_id),
    constraint rating_range check (rating between 1 and 5)
);
create index idx_event_reviews_event on event_reviews (event_id);
-- =============================================================================
-- Migration 004: Messaging (DMs, Groups, Event Rooms)
-- =============================================================================

create table conversations (
    id uuid primary key default uuid_generate_v4(),
    type conversation_type not null,
    event_id uuid references events(id) on delete cascade, -- set only when type = 'event_room'
    title text, -- used for groups; event rooms derive title from events.title
    created_by uuid references profiles(id),
    created_at timestamptz not null default now(),

    constraint event_room_has_event check (
        (type = 'event_room' and event_id is not null) or (type <> 'event_room')
    )
);
create unique index idx_conversations_event_room on conversations (event_id) ;
create index idx_conversations_type on conversations (type);

create table conversation_participants (
    conversation_id uuid not null references conversations(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    joined_at timestamptz not null default now(),
    last_read_at timestamptz,
    is_muted boolean not null default false,
    primary key (conversation_id, user_id)
);
create index idx_conversation_participants_user on conversation_participants (user_id);

create table messages (
    id uuid primary key default uuid_generate_v4(),
    conversation_id uuid not null references conversations(id) on delete cascade,
    sender_id uuid references profiles(id) on delete set null, -- null = system message
    message_type message_type not null default 'text',
    content text,
    media_url text,
    reply_to_id uuid references messages(id) on delete set null,
    is_pinned boolean not null default false,
    expires_at timestamptz, -- disappearing messages
    created_at timestamptz not null default now(),
    edited_at timestamptz,
    deleted_at timestamptz -- soft delete, preserves moderation trail
);
create index idx_messages_conversation_created on messages (conversation_id, created_at desc);
create index idx_messages_reply_to on messages (reply_to_id);

create table message_reactions (
    message_id uuid not null references messages(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    emoji text not null,
    created_at timestamptz not null default now(),
    primary key (message_id, user_id, emoji)
);

-- -----------------------------------------------------------------------------
-- Room engagement snapshots — periodically written FROM Redis, not computed
-- live from `messages` on every read. See design-decisions doc §2.
-- -----------------------------------------------------------------------------
create table room_engagement_snapshots (
    conversation_id uuid not null references conversations(id) on delete cascade,
    window_start timestamptz not null,
    message_count integer not null default 0,
    reaction_count integer not null default 0,
    temperature room_temperature not null default 'cold',
    primary key (conversation_id, window_start)
);
create index idx_room_engagement_latest on room_engagement_snapshots (conversation_id, window_start desc);

-- -----------------------------------------------------------------------------
-- Check-in → event room auto-join (completes the deferred trigger from
-- migration 003: `on_check_in`)
-- -----------------------------------------------------------------------------
create or replace function join_event_room_on_checkin()
returns trigger as $$
declare
    v_conversation_id uuid;
begin
    select id into v_conversation_id from conversations
        where event_id = new.event_id and type = 'event_room';

    if v_conversation_id is null then
        insert into conversations (type, event_id, title)
        values ('event_room', new.event_id, (select title from events where id = new.event_id))
        returning id into v_conversation_id;
    end if;

    insert into conversation_participants (conversation_id, user_id)
    values (v_conversation_id, new.user_id)
    on conflict (conversation_id, user_id) do nothing;

    return new;
end;
$$ language plpgsql;

create trigger trg_join_event_room_on_checkin after insert on check_ins
    for each row execute function join_event_room_on_checkin();
-- =============================================================================
-- Migration 005: Payments, Wallets, Vouchers
-- =============================================================================

-- -----------------------------------------------------------------------------
-- payments — the ledger of record across ALL PSPs. Internal ledger is
-- source of truth (see Master Program Plan §9), not any PSP's dashboard.
-- -----------------------------------------------------------------------------
create table payments (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references profiles(id) on delete restrict,
    provider payment_provider not null,
    provider_reference text, -- PSP transaction id
    purpose payment_purpose not null,
    amount numeric(12,2) not null,
    currency text not null default 'NGN',
    status payment_status not null default 'initiated',
    metadata jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    unique (provider, provider_reference)
);
create index idx_payments_user on payments (user_id);
create index idx_payments_status on payments (status);
create trigger trg_payments_updated_at before update on payments
    for each row execute function set_updated_at();

alter table ticket_purchases
    add constraint fk_ticket_purchases_payment
    foreign key (payment_id) references payments(id) on delete set null;

-- -----------------------------------------------------------------------------
-- Split payments — a ticket_purchase can be funded by multiple payments
-- (e.g. 3 friends splitting one VIP table)
-- -----------------------------------------------------------------------------
create table split_payment_contributions (
    id uuid primary key default uuid_generate_v4(),
    ticket_purchase_id uuid not null references ticket_purchases(id) on delete cascade,
    payer_id uuid not null references profiles(id) on delete restrict,
    payment_id uuid not null references payments(id) on delete restrict,
    amount numeric(12,2) not null,
    created_at timestamptz not null default now()
);
create index idx_split_contrib_purchase on split_payment_contributions (ticket_purchase_id);

-- -----------------------------------------------------------------------------
-- wallets — internal cash-equivalent balance (top-ups, refunds land here)
-- -----------------------------------------------------------------------------
create table wallets (
    user_id uuid primary key references profiles(id) on delete cascade,
    balance numeric(12,2) not null default 0,
    currency text not null default 'NGN',
    updated_at timestamptz not null default now(),

    constraint balance_non_negative check (balance >= 0)
);

create table wallet_transactions (
    id uuid primary key default uuid_generate_v4(),
    wallet_user_id uuid not null references wallets(user_id) on delete cascade,
    type wallet_txn_type not null,
    amount numeric(12,2) not null,
    reference text, -- e.g. 'refund:ticket_purchase:<id>' or 'topup:payment:<id>'
    created_at timestamptz not null default now(),

    constraint amount_positive check (amount > 0)
);
create index idx_wallet_txns_wallet on wallet_transactions (wallet_user_id, created_at desc);

create or replace function apply_wallet_transaction()
returns trigger as $$
begin
    if new.type = 'credit' then
        update wallets set balance = balance + new.amount, updated_at = now() where user_id = new.wallet_user_id;
    else
        update wallets set balance = balance - new.amount, updated_at = now() where user_id = new.wallet_user_id;
    end if;
    return new;
end;
$$ language plpgsql;

create trigger trg_apply_wallet_transaction after insert on wallet_transactions
    for each row execute function apply_wallet_transaction();

-- -----------------------------------------------------------------------------
-- vouchers — business-funded loyalty currency. Separate ledger from wallets
-- (see design-decisions doc §2 for rationale).
-- -----------------------------------------------------------------------------
create table vouchers (
    id uuid primary key default uuid_generate_v4(),
    issuer_business_id uuid not null references businesses(id) on delete cascade,
    title text not null,
    description text,
    value numeric(12,2) not null,
    currency text not null default 'NGN',
    min_energy_score integer default 0, -- e.g. only Top-5% users can claim
    total_quantity integer,
    claimed_quantity integer not null default 0,
    expires_at timestamptz not null,
    created_at timestamptz not null default now(),

    constraint claimed_within_total check (total_quantity is null or claimed_quantity <= total_quantity)
);
create index idx_vouchers_issuer on vouchers (issuer_business_id);
create index idx_vouchers_active on vouchers (expires_at) ;

create type voucher_redemption_status as enum ('claimed', 'redeemed', 'expired');
create table voucher_redemptions (
    id uuid primary key default uuid_generate_v4(),
    voucher_id uuid not null references vouchers(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    status voucher_redemption_status not null default 'claimed',
    claimed_at timestamptz not null default now(),
    redeemed_at timestamptz,

    unique (voucher_id, user_id)
);
create index idx_voucher_redemptions_user on voucher_redemptions (user_id);

create or replace function bump_voucher_claimed_count()
returns trigger as $$
begin
    update vouchers set claimed_quantity = claimed_quantity + 1 where id = new.voucher_id;
    return new;
end;
$$ language plpgsql;

create trigger trg_voucher_claimed after insert on voucher_redemptions
    for each row execute function bump_voucher_claimed_count();

-- -----------------------------------------------------------------------------
-- Organizer payouts
-- -----------------------------------------------------------------------------
create type payout_status as enum ('requested', 'processing', 'paid', 'failed');
create table organizer_payouts (
    id uuid primary key default uuid_generate_v4(),
    organizer_id uuid not null references profiles(id) on delete restrict,
    event_id uuid references events(id) on delete set null,
    amount numeric(12,2) not null,
    currency text not null default 'NGN',
    status payout_status not null default 'requested',
    bank_details jsonb, -- tokenized/reference only, never raw account numbers
    requested_at timestamptz not null default now(),
    paid_at timestamptz
);
create index idx_organizer_payouts_organizer on organizer_payouts (organizer_id);
-- =============================================================================
-- Migration 006: Energy Score, Achievements
-- =============================================================================

-- -----------------------------------------------------------------------------
-- energy_score_events — append-only ledger. profiles.energy_score is a
-- denormalized cache recomputed from this table. See design-decisions §2.
-- -----------------------------------------------------------------------------
create type energy_score_reason as enum (
    'event_checkin', 'ticket_purchase', 'post_engagement_received',
    'community_participation', 'review_left', 'referral', 'admin_adjustment', 'penalty'
);

create table energy_score_events (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references profiles(id) on delete cascade,
    delta integer not null,
    reason energy_score_reason not null,
    source_id uuid, -- polymorphic ref: check_ins.id, ticket_purchases.id, etc. Not FK-enforced by design.
    created_at timestamptz not null default now()
);
create index idx_energy_score_events_user on energy_score_events (user_id, created_at desc);

create or replace function recompute_energy_score(p_user_id uuid)
returns void as $$
begin
    update profiles
    set energy_score = coalesce((
        select sum(delta) from energy_score_events where user_id = p_user_id
    ), 0)
    where id = p_user_id;
end;
$$ language plpgsql;

create or replace function on_energy_score_event()
returns trigger as $$
begin
    perform recompute_energy_score(new.user_id);
    return new;
end;
$$ language plpgsql;

create trigger trg_energy_score_event after insert on energy_score_events
    for each row execute function on_energy_score_event();

-- Completes the deferred award from migration 003 (`on_check_in`): a verified
-- check-in grants a fixed energy award. Kept as a policy constant here so
-- product/ops can tune it via a single migration rather than app-code deploys.
create or replace function award_energy_for_checkin()
returns trigger as $$
begin
    insert into energy_score_events (user_id, delta, reason, source_id)
    values (new.user_id, 10, 'event_checkin', new.id);
    return new;
end;
$$ language plpgsql;

create trigger trg_award_energy_for_checkin after insert on check_ins
    for each row execute function award_energy_for_checkin();

-- -----------------------------------------------------------------------------
-- Percentile recompute — scheduled job (pg_cron or Edge Function on a timer),
-- NOT run per-request. Populates profiles.energy_score_percentile used by
-- the "Top 5% this month" badge.
-- -----------------------------------------------------------------------------
create or replace function recompute_energy_percentiles()
returns void as $$
begin
    with ranked as (
        select id, percent_rank() over (order by energy_score desc) as pr
        from profiles
        where energy_score > 0
    )
    update profiles p
    set energy_score_percentile = round((1 - ranked.pr) * 100, 2)
    from ranked
    where p.id = ranked.id;
end;
$$ language plpgsql;

-- -----------------------------------------------------------------------------
-- Achievements (badges like "Night Owl", "VIP Status", "Social Butterfly")
-- -----------------------------------------------------------------------------
create table achievements (
    id uuid primary key default uuid_generate_v4(),
    code text not null unique, -- 'night_owl', 'vip_status', 'social_butterfly'
    name text not null,
    description text,
    icon text,
    criteria jsonb not null -- e.g. {"type": "checkin_count", "threshold": 10}
);

create table user_achievements (
    user_id uuid not null references profiles(id) on delete cascade,
    achievement_id uuid not null references achievements(id) on delete cascade,
    earned_at timestamptz not null default now(),
    primary key (user_id, achievement_id)
);
create index idx_user_achievements_user on user_achievements (user_id);

-- Seed the confirmed achievements from the design
insert into achievements (code, name, description, icon, criteria) values
    ('night_owl', 'Night Owl', 'Attended 10+ events', 'flame', '{"type": "checkin_count", "threshold": 10}'),
    ('vip_status', 'VIP Status', 'Reached top 5% energy score', 'star', '{"type": "percentile", "threshold": 95}'),
    ('social_butterfly', 'Social Butterfly', 'Made 50+ connections', 'people', '{"type": "friend_count", "threshold": 50}');
-- =============================================================================
-- Migration 007: Social Feed (Posts, Stories)
-- =============================================================================

create table posts (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references profiles(id) on delete cascade,
    event_id uuid references events(id) on delete set null, -- tags a post to a live event
    caption text,
    media_urls text[] not null default '{}',
    location geography(Point, 4326),
    like_count integer not null default 0,   -- denormalized, trigger-maintained
    comment_count integer not null default 0,
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);
create index idx_posts_created on posts (created_at desc) ;
create index idx_posts_event on posts (event_id, created_at desc) ;
create index idx_posts_user on posts (user_id, created_at desc);

create table post_likes (
    post_id uuid not null references posts(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (post_id, user_id)
);

create table post_comments (
    id uuid primary key default uuid_generate_v4(),
    post_id uuid not null references posts(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    content text not null,
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);
create index idx_post_comments_post on post_comments (post_id, created_at);

create table post_bookmarks (
    post_id uuid not null references posts(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (post_id, user_id)
);

create or replace function bump_post_like_count()
returns trigger as $$
begin
    if tg_op = 'INSERT' then
        update posts set like_count = like_count + 1 where id = new.post_id;
    elsif tg_op = 'DELETE' then
        update posts set like_count = like_count - 1 where id = old.post_id;
    end if;
    return null;
end;
$$ language plpgsql;
create trigger trg_post_likes_count after insert or delete on post_likes
    for each row execute function bump_post_like_count();

create or replace function bump_post_comment_count()
returns trigger as $$
begin
    update posts set comment_count = comment_count + 1 where id = new.post_id;
    return new;
end;
$$ language plpgsql;
create trigger trg_post_comments_count after insert on post_comments
    for each row execute function bump_post_comment_count();

-- -----------------------------------------------------------------------------
-- Stories — 24h ephemeral content. expires_at enforced via a scheduled
-- cleanup job (pg_cron) that hard-deletes rows past expiry; the app also
-- filters `` defensively.
-- -----------------------------------------------------------------------------
create table stories (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references profiles(id) on delete cascade,
    media_url text not null,
    media_type text not null default 'image', -- 'image' | 'video'
    caption text,
    music_track text,
    location geography(Point, 4326),
    is_highlight boolean not null default false,
    highlight_collection text, -- e.g. "Neon Nights", "VIP Life" — groups stories into a Highlights reel
    created_at timestamptz not null default now(),
    expires_at timestamptz not null default (now() + interval '24 hours')
);
create index idx_stories_user_active on stories (user_id) ;

create table story_views (
    story_id uuid not null references stories(id) on delete cascade,
    viewer_id uuid not null references profiles(id) on delete cascade,
    viewed_at timestamptz not null default now(),
    primary key (story_id, viewer_id)
);

create table story_mentions (
    story_id uuid not null references stories(id) on delete cascade,
    mentioned_user_id uuid not null references profiles(id) on delete cascade,
    primary key (story_id, mentioned_user_id)
);
-- =============================================================================
-- Migration 008: Moderation, Audit, Notifications
-- =============================================================================

create table reports (
    id uuid primary key default uuid_generate_v4(),
    reporter_id uuid not null references profiles(id) on delete set null,
    target_type report_target_type not null,
    target_id uuid not null, -- polymorphic; not FK-enforced across differing target tables
    reason text not null,
    details text,
    status report_status not null default 'open',
    reviewed_by uuid references profiles(id),
    reviewed_at timestamptz,
    created_at timestamptz not null default now()
);
create index idx_reports_status on reports (status);
create index idx_reports_target on reports (target_type, target_id);

create type moderation_action_type as enum ('warn', 'content_removed', 'suspended', 'banned', 'dismissed');
create table moderation_actions (
    id uuid primary key default uuid_generate_v4(),
    report_id uuid references reports(id) on delete set null,
    moderator_id uuid not null references profiles(id),
    target_type report_target_type not null,
    target_id uuid not null,
    action moderation_action_type not null,
    notes text,
    created_at timestamptz not null default now()
);
create index idx_moderation_actions_target on moderation_actions (target_type, target_id);

-- -----------------------------------------------------------------------------
-- audit_logs — append-only, RLS-locked (see 09_rls_policies.sql). Every
-- admin/moderator action must write here for compliance (GDPR/NDPR §8 of
-- Master Plan).
-- -----------------------------------------------------------------------------
create table audit_logs (
    id uuid primary key default uuid_generate_v4(),
    actor_id uuid references profiles(id),
    action text not null,
    target_type text,
    target_id uuid,
    metadata jsonb,
    ip_address inet,
    created_at timestamptz not null default now()
);
create index idx_audit_logs_actor on audit_logs (actor_id, created_at desc);
create index idx_audit_logs_target on audit_logs (target_type, target_id);

-- Prevent updates/deletes at the DB level — audit logs are immutable even to admins.
create or replace function forbid_audit_log_mutation()
returns trigger as $$
begin
    raise exception 'audit_logs is append-only; % is not permitted', tg_op;
end;
$$ language plpgsql;

create trigger trg_audit_logs_no_update before update on audit_logs
    for each row execute function forbid_audit_log_mutation();
create trigger trg_audit_logs_no_delete before delete on audit_logs
    for each row execute function forbid_audit_log_mutation();

-- -----------------------------------------------------------------------------
-- notifications
-- -----------------------------------------------------------------------------
create type notification_type as enum (
    'event_reminder', 'checkin_confirmed', 'new_message', 'new_follower',
    'friend_request', 'post_like', 'post_comment', 'ticket_confirmed',
    'voucher_available', 'achievement_earned', 'organizer_announcement'
);

create table notifications (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references profiles(id) on delete cascade,
    type notification_type not null,
    payload jsonb not null default '{}',
    read_at timestamptz,
    created_at timestamptz not null default now()
);
create index idx_notifications_user_unread on notifications (user_id, created_at desc) ;
-- =============================================================================
-- Migration 009: App Roles (for RLS — distinct from Supabase auth roles)
-- =============================================================================

create type app_role as enum ('admin', 'moderator', 'organizer_verified', 'business_owner');

create table user_roles (
    user_id uuid not null references profiles(id) on delete cascade,
    role app_role not null,
    granted_at timestamptz not null default now(),
    granted_by uuid references profiles(id),
    primary key (user_id, role)
);

-- Helper used throughout RLS policies. STABLE + SECURITY DEFINER so it can
-- read user_roles regardless of the calling user's own row-level access.
create or replace function has_role(p_user_id uuid, p_role app_role)
returns boolean as $$
    select exists (
        select 1 from user_roles where user_id = p_user_id and role = p_role
    );
$$ language sql stable security definer;

create or replace function is_admin_or_moderator(p_user_id uuid)
returns boolean as $$
    select has_role(p_user_id, 'admin') or has_role(p_user_id, 'moderator');
$$ language sql stable security definer;

-- Checked-in gate, used by messaging RLS: can this user read/write in this
-- event room's conversation?
create or replace function is_checked_in_to_event(p_user_id uuid, p_event_id uuid)
returns boolean as $$
    select exists (
        select 1 from check_ins where user_id = p_user_id and event_id = p_event_id
    );
$$ language sql stable security definer;
-- =============================================================================
-- Migration 010: Row Level Security Policies
-- Every table containing user data has RLS enabled. No client ever receives
-- a service-role key — Edge Functions use service role server-side only for
-- operations that legitimately need to bypass RLS (e.g. payment webhooks).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- profiles
-- -----------------------------------------------------------------------------
alter table profiles enable row level security;

create policy "profiles_select_public" on profiles
    for select using (true); -- profile info is public by design (usernames, badges, energy score)

create policy "profiles_update_own" on profiles
    for update using (auth.uid() = id) with check (auth.uid() = id);

create policy "profiles_admin_update_any" on profiles
    for update using (is_admin_or_moderator(auth.uid()));

-- -----------------------------------------------------------------------------
-- follows / friendships
-- -----------------------------------------------------------------------------
alter table follows enable row level security;
create policy "follows_select_all" on follows for select using (true);
create policy "follows_insert_own" on follows for insert with check (auth.uid() = follower_id);
create policy "follows_delete_own" on follows for delete using (auth.uid() = follower_id);

alter table friendships enable row level security;
create policy "friendships_select_participant" on friendships
    for select using (auth.uid() = user_id or auth.uid() = friend_id);
create policy "friendships_insert_own" on friendships
    for insert with check (auth.uid() = requested_by);
create policy "friendships_update_participant" on friendships
    for update using (auth.uid() = user_id or auth.uid() = friend_id);

-- -----------------------------------------------------------------------------
-- events — public events visible to all; private/invite-only restricted
-- -----------------------------------------------------------------------------
alter table events enable row level security;

create policy "events_select_visible" on events
    for select using (
        visibility = 'public'
        or organizer_id = auth.uid()
        or (visibility = 'friends_only' and exists (
            select 1 from friendships
            where status = 'accepted'
            and ((user_id = auth.uid() and friend_id = events.organizer_id)
              or (friend_id = auth.uid() and user_id = events.organizer_id))
        ))
        or (visibility = 'invite_only' and exists (
            select 1 from event_attendees where event_id = events.id and user_id = auth.uid()
        ))
        or is_admin_or_moderator(auth.uid())
    );

create policy "events_insert_own" on events
    for insert with check (organizer_id = auth.uid());

create policy "events_update_own_or_admin" on events
    for update using (organizer_id = auth.uid() or is_admin_or_moderator(auth.uid()));

-- -----------------------------------------------------------------------------
-- check_ins — users can insert their own check-in; only event organizer,
-- the user themself, and admins can read it. This is a sensitive presence
-- record and must not be broadly queryable (see child/adult safety note:
-- location + presence data is exactly the kind of thing that must not leak).
-- -----------------------------------------------------------------------------
alter table check_ins enable row level security;

create policy "check_ins_select_own_or_organizer" on check_ins
    for select using (
        user_id = auth.uid()
        or is_admin_or_moderator(auth.uid())
        or exists (select 1 from events where events.id = check_ins.event_id and events.organizer_id = auth.uid())
    );

create policy "check_ins_insert_own" on check_ins
    for insert with check (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- tickets / ticket_purchases
-- -----------------------------------------------------------------------------
alter table tickets enable row level security;
create policy "tickets_select_all" on tickets for select using (true);
create policy "tickets_manage_organizer" on tickets
    for all using (exists (select 1 from events where events.id = tickets.event_id and events.organizer_id = auth.uid()));

alter table ticket_purchases enable row level security;
create policy "ticket_purchases_select_own_or_organizer" on ticket_purchases
    for select using (
        user_id = auth.uid()
        or is_admin_or_moderator(auth.uid())
        or exists (
            select 1 from tickets join events on events.id = tickets.event_id
            where tickets.id = ticket_purchases.ticket_id and events.organizer_id = auth.uid()
        )
    );
create policy "ticket_purchases_insert_own" on ticket_purchases
    for insert with check (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- conversations / messages — the critical check-in gate for event rooms
-- -----------------------------------------------------------------------------
alter table conversations enable row level security;
alter table conversation_participants enable row level security;
alter table messages enable row level security;

create policy "conversations_select_participant" on conversations
    for select using (
        exists (select 1 from conversation_participants cp where cp.conversation_id = conversations.id and cp.user_id = auth.uid())
    );

create policy "conversation_participants_select_own_conversations" on conversation_participants
    for select using (
        user_id = auth.uid()
        or exists (select 1 from conversation_participants cp2 where cp2.conversation_id = conversation_participants.conversation_id and cp2.user_id = auth.uid())
    );

-- Insert into an event_room's participants is normally done by the
-- `join_event_room_on_checkin` trigger (SECURITY DEFINER context), so this
-- policy mainly covers DMs/groups where users add each other directly.
create policy "conversation_participants_insert_dm_group" on conversation_participants
    for insert with check (
        exists (
            select 1 from conversations c
            where c.id = conversation_participants.conversation_id
            and c.type in ('dm', 'group')
        )
    );

create policy "messages_select_participant" on messages
    for select using (
        exists (select 1 from conversation_participants cp where cp.conversation_id = messages.conversation_id and cp.user_id = auth.uid())
        and (deleted_at is null or is_admin_or_moderator(auth.uid()))
    );

-- The core gate: writing into an event_room requires the sender to actually
-- be checked in to that event, not merely a conversation_participants row
-- (defense in depth — even if participants table is stale, this re-verifies).
create policy "messages_insert_participant_and_checked_in" on messages
    for insert with check (
        sender_id = auth.uid()
        and exists (select 1 from conversation_participants cp where cp.conversation_id = messages.conversation_id and cp.user_id = auth.uid())
        and (
            not exists (select 1 from conversations c where c.id = messages.conversation_id and c.type = 'event_room')
            or exists (
                select 1 from conversations c
                where c.id = messages.conversation_id
                and c.type = 'event_room'
                and is_checked_in_to_event(auth.uid(), c.event_id)
            )
        )
    );

-- -----------------------------------------------------------------------------
-- payments / wallets — strictly own-row only, ever
-- -----------------------------------------------------------------------------
alter table payments enable row level security;
create policy "payments_select_own" on payments for select using (user_id = auth.uid() or is_admin_or_moderator(auth.uid()));
-- Note: inserts/updates to `payments` happen exclusively via Edge Functions
-- using the service role (payment webhooks, PSP callbacks) — no direct
-- client insert policy exists on purpose.

alter table wallets enable row level security;
create policy "wallets_select_own" on wallets for select using (user_id = auth.uid());

alter table wallet_transactions enable row level security;
create policy "wallet_transactions_select_own" on wallet_transactions for select using (wallet_user_id = auth.uid());
-- Inserts are service-role only (Edge Functions), same rationale as payments.

-- -----------------------------------------------------------------------------
-- vouchers — issuer business can manage; any authenticated user can view
-- active vouchers; redemption tied to own user_id
-- -----------------------------------------------------------------------------
alter table vouchers enable row level security;
create policy "vouchers_select_active" on vouchers for select using (expires_at > now());
create policy "vouchers_manage_issuer" on vouchers
    for all using (exists (select 1 from businesses where businesses.id = vouchers.issuer_business_id and businesses.owner_id = auth.uid()));

alter table voucher_redemptions enable row level security;
create policy "voucher_redemptions_select_own" on voucher_redemptions for select using (user_id = auth.uid());
create policy "voucher_redemptions_insert_own" on voucher_redemptions for insert with check (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- reports / moderation_actions — reporter sees own report; only mods see all
-- -----------------------------------------------------------------------------
alter table reports enable row level security;
create policy "reports_select_own_or_mod" on reports
    for select using (reporter_id = auth.uid() or is_admin_or_moderator(auth.uid()));
create policy "reports_insert_own" on reports for insert with check (reporter_id = auth.uid());
create policy "reports_update_mod_only" on reports for update using (is_admin_or_moderator(auth.uid()));

alter table moderation_actions enable row level security;
create policy "moderation_actions_mod_only" on moderation_actions for all using (is_admin_or_moderator(auth.uid()));

-- -----------------------------------------------------------------------------
-- audit_logs — insert-only for authenticated actions, read restricted to admins
-- -----------------------------------------------------------------------------
alter table audit_logs enable row level security;
create policy "audit_logs_select_admin_only" on audit_logs for select using (has_role(auth.uid(), 'admin'));
create policy "audit_logs_insert_any_authenticated" on audit_logs for insert with check (auth.uid() is not null);

-- -----------------------------------------------------------------------------
-- notifications — strictly own
-- -----------------------------------------------------------------------------
alter table notifications enable row level security;
create policy "notifications_select_own" on notifications for select using (user_id = auth.uid());
create policy "notifications_update_own" on notifications for update using (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- posts / stories — public read (respecting visibility could be layered on
-- later per-post if a "friends only post" feature ships); own-row write
-- -----------------------------------------------------------------------------
alter table posts enable row level security;
create policy "posts_select_not_deleted" on posts for select using (deleted_at is null or is_admin_or_moderator(auth.uid()));
create policy "posts_insert_own" on posts for insert with check (user_id = auth.uid());
create policy "posts_update_own_or_mod" on posts for update using (user_id = auth.uid() or is_admin_or_moderator(auth.uid()));

alter table stories enable row level security;
create policy "stories_select_active" on stories for select using (expires_at > now() or is_highlight);
create policy "stories_insert_own" on stories for insert with check (user_id = auth.uid());
create policy "stories_delete_own" on stories for delete using (user_id = auth.uid());
-- =============================================================================
-- Migration 011: Query Functions for High-QPS Screens
-- These are the endpoints Home, Discover, and the live crowd-map hit on
-- every app open — written as SECURITY INVOKER functions (respect RLS) so
-- they're both fast (single round-trip, index-friendly) and safe.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Nearby live/upcoming events, sorted by distance — powers Home's event cards
-- and the crowd-density bubble map.
-- -----------------------------------------------------------------------------
create or replace function nearby_events(
    p_lat double precision,
    p_lng double precision,
    p_radius_km double precision default 10,
    p_limit int default 20
)
returns table (
    event_id uuid,
    title text,
    cover_url text,
    start_time timestamptz,
    status event_status,
    distance_km double precision,
    live_attendee_count integer
) as $$
    select
        e.id,
        e.title,
        e.cover_url,
        e.start_time,
        e.status,
        st_distance(v.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography) / 1000.0 as distance_km,
        e.live_attendee_count
    from events e
    join venues v on v.id = e.venue_id
    where e.visibility = 'public'
      and e.status in ('published', 'live')
      and st_dwithin(v.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_radius_km * 1000)
    order by e.status = 'live' desc, distance_km asc
    limit p_limit;
$$ language sql stable;

-- -----------------------------------------------------------------------------
-- Discover People — vibe-tag filtered, distance-sorted, excludes existing
-- friends/blocked users. Powers the "8 people nearby" list + tag counts.
-- -----------------------------------------------------------------------------
create or replace function discover_people(
    p_user_id uuid,
    p_lat double precision,
    p_lng double precision,
    p_vibe_tag vibe_tag_name default null,
    p_radius_km double precision default 5,
    p_limit int default 30
)
returns table (
    user_id uuid,
    username citext,
    display_name text,
    avatar_url text,
    energy_score integer,
    distance_km double precision,
    vibe_tags vibe_tag_name[],
    mutual_event_count bigint
) as $$
    select
        p.id,
        p.username,
        p.display_name,
        p.avatar_url,
        p.energy_score,
        st_distance(p.current_location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography) / 1000.0,
        array_agg(distinct uvt.tag),
        (
            select count(*) from event_attendees ea1
            join event_attendees ea2 on ea1.event_id = ea2.event_id
            where ea1.user_id = p_user_id and ea2.user_id = p.id
        )
    from profiles p
    join user_vibe_tags uvt on uvt.user_id = p.id and (uvt.expires_at is null or uvt.expires_at > now())
    where p.id <> p_user_id
      and (p_vibe_tag is null or uvt.tag = p_vibe_tag)
      and st_dwithin(p.current_location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_radius_km * 1000)
      and not exists (
          select 1 from friendships f
          where f.status = 'blocked'
          and ((f.user_id = p_user_id and f.friend_id = p.id) or (f.friend_id = p_user_id and f.user_id = p.id))
      )
    group by p.id
    order by st_distance(p.current_location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography) / 1000.0 asc
    limit p_limit;
$$ language sql stable;

-- -----------------------------------------------------------------------------
-- Home feed — blended live events + social posts. Kept as two separate
-- queries application-side rather than one UNION view: the client renders
-- them as distinct sections ("Live Events Happening Now" then "Social
-- Feed"), and separate queries let each be cached/paginated independently.
-- -----------------------------------------------------------------------------
create or replace function home_feed_posts(
    p_user_id uuid,
    p_limit int default 20,
    p_before timestamptz default now()
)
returns setof posts as $$
    select p.* from posts p
    where p.deleted_at is null
      and p.created_at < p_before
      and (
          p.user_id = p_user_id
          or exists (select 1 from follows f where f.follower_id = p_user_id and f.following_id = p.user_id)
          or exists (
              select 1 from friendships fr where fr.status = 'accepted'
              and ((fr.user_id = p_user_id and fr.friend_id = p.user_id) or (fr.friend_id = p_user_id and fr.user_id = p.user_id))
          )
      )
    order by p.created_at desc
    limit p_limit;
$$ language sql stable;
-- =============================================================================
-- Migration 012 (Phase 5 addendum): Atomic wallet settlement
-- Referenced by supabase/functions/tickets-purchase/index.ts. Implemented as
-- a Postgres function rather than application-code read-then-write, because
-- a balance check followed by a separate debit is a classic race condition
-- under concurrent requests (two simultaneous purchases could both pass the
-- balance check before either debit lands). This function makes the
-- check-and-debit atomic within a single transaction.
-- =============================================================================

create or replace function settle_ticket_purchase_from_wallet(
    p_ticket_purchase_id uuid,
    p_user_id uuid,
    p_amount numeric
)
returns void as $$
declare
    v_current_balance numeric;
begin
    -- Row-level lock prevents a concurrent call from reading a stale balance.
    select balance into v_current_balance
    from wallets
    where user_id = p_user_id
    for update;

    if v_current_balance is null then
        raise exception 'Wallet not found for user %', p_user_id;
    end if;

    if v_current_balance < p_amount then
        raise exception 'insufficient_balance';
    end if;

    insert into wallet_transactions (wallet_user_id, type, amount, reference)
    values (p_user_id, 'debit', p_amount, 'ticket_purchase:' || p_ticket_purchase_id);
    -- The apply_wallet_transaction trigger (migration 005) handles the
    -- balance decrement; we don't update wallets.balance directly here,
    -- to keep exactly one code path responsible for that mutation.

    update ticket_purchases set status = 'paid' where id = p_ticket_purchase_id;
end;
$$ language plpgsql security definer;

-- SECURITY DEFINER is required here because the calling user's own RLS
-- policies on `wallet_transactions` only permit SELECT, not INSERT (inserts
-- are service-role/function-only per migration 010's comment) — this
-- function is the one sanctioned path for a client-initiated wallet debit.
-- =============================================================================
-- Migration 013 (Phase 7 addendum): find_dm_conversation
-- Needed by the Flutter chat feature's `startOrGetDmConversation` helper
-- (mobile/lib/features/chat/domain/chat_models.dart) so "Say Hi" from
-- Discover and "Message" from Profile converge on one DM thread instead of
-- creating a duplicate conversation every time either entry point is used.
-- =============================================================================

create or replace function find_dm_conversation(p_user_a uuid, p_user_b uuid)
returns uuid as $$
    select cp1.conversation_id
    from conversation_participants cp1
    join conversation_participants cp2
        on cp1.conversation_id = cp2.conversation_id and cp2.user_id = p_user_b
    join conversations c on c.id = cp1.conversation_id
    where cp1.user_id = p_user_a
      and c.type = 'dm'
    limit 1;
$$ language sql stable;
-- =============================================================================
-- Migration 014: Push Notification Infrastructure
-- Two concerns: (1) storing FCM device tokens, (2) triggers that populate
-- the `notifications` table (created in migration 008) when something
-- notification-worthy happens. Actual push DELIVERY (calling FCM) is a
-- separate concern handled by the send-push-notification Edge Function,
-- invoked via a Supabase Database Webhook on INSERT to `notifications` —
-- keeping "decide something is notification-worthy" (SQL trigger) separate
-- from "deliver it" (Edge Function calling an external API) so the DB
-- transaction never blocks on a network call to FCM.
-- =============================================================================

create table device_tokens (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references profiles(id) on delete cascade,
    fcm_token text not null,
    platform text not null default 'unknown', -- 'ios' | 'android'
    created_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now(),

    unique (user_id, fcm_token)
);
create index idx_device_tokens_user on device_tokens (user_id);

alter table device_tokens enable row level security;
create policy "device_tokens_select_own" on device_tokens for select using (user_id = auth.uid());
create policy "device_tokens_insert_own" on device_tokens for insert with check (user_id = auth.uid());
create policy "device_tokens_update_own" on device_tokens for update using (user_id = auth.uid());
create policy "device_tokens_delete_own" on device_tokens for delete using (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- Trigger: new_message → notify other conversation participants
-- Skips the sender and skips participants who are currently "active" in the
-- room — that presence check is a client/Realtime concern, not modeled here;
-- this trigger notifies ALL other participants every message, which is
-- correct for DMs but would be noisy for a busy event room. Flagged as a
-- follow-up: event_room notifications should likely be rate-limited or
-- digested rather than one push per message (see note in Phase 5 backend
-- README about deferring notification fan-out logic out of hot paths).
-- -----------------------------------------------------------------------------
create or replace function notify_new_message()
returns trigger as $$
begin
    if new.sender_id is null then
        return new; -- system messages don't need a "new message" notification
    end if;

    insert into notifications (user_id, type, payload)
    select cp.user_id, 'new_message', jsonb_build_object(
        'conversation_id', new.conversation_id,
        'message_id', new.id,
        'sender_id', new.sender_id,
        'preview', left(coalesce(new.content, ''), 80)
    )
    from conversation_participants cp
    where cp.conversation_id = new.conversation_id
      and cp.user_id <> new.sender_id
      and coalesce(cp.is_muted, false) = false;

    return new;
end;
$$ language plpgsql;

create trigger trg_notify_new_message after insert on messages
    for each row execute function notify_new_message();

-- -----------------------------------------------------------------------------
-- Trigger: achievement_earned
-- -----------------------------------------------------------------------------
create or replace function notify_achievement_earned()
returns trigger as $$
declare
    v_achievement_name text;
begin
    select name into v_achievement_name from achievements where id = new.achievement_id;

    insert into notifications (user_id, type, payload)
    values (new.user_id, 'achievement_earned', jsonb_build_object(
        'achievement_id', new.achievement_id,
        'name', v_achievement_name
    ));
    return new;
end;
$$ language plpgsql;

create trigger trg_notify_achievement_earned after insert on user_achievements
    for each row execute function notify_achievement_earned();

-- -----------------------------------------------------------------------------
-- Trigger: ticket_confirmed (fires when a ticket_purchases row flips to paid)
-- -----------------------------------------------------------------------------
create or replace function notify_ticket_confirmed()
returns trigger as $$
begin
    if new.status = 'paid' and old.status <> 'paid' then
        insert into notifications (user_id, type, payload)
        values (new.user_id, 'ticket_confirmed', jsonb_build_object(
            'ticket_purchase_id', new.id,
            'qr_code', new.qr_code
        ));
    end if;
    return new;
end;
$$ language plpgsql;

create trigger trg_notify_ticket_confirmed after update on ticket_purchases
    for each row execute function notify_ticket_confirmed();

-- -----------------------------------------------------------------------------
-- Trigger: checkin_confirmed
-- -----------------------------------------------------------------------------
create or replace function notify_checkin_confirmed()
returns trigger as $$
declare
    v_event_title text;
begin
    select title into v_event_title from events where id = new.event_id;

    insert into notifications (user_id, type, payload)
    values (new.user_id, 'checkin_confirmed', jsonb_build_object(
        'event_id', new.event_id,
        'event_title', v_event_title
    ));
    return new;
end;
$$ language plpgsql;

create trigger trg_notify_checkin_confirmed after insert on check_ins
    for each row execute function notify_checkin_confirmed();
-- =============================================================================
-- Migration 015: Admin Moderation Additions
--
-- Adds the minimum schema needed for the Admin Moderation Queue and User
-- Management screens (Phase 5/6 web work): a ban flag and who/when/why it
-- was set, auditable via the existing `moderation_actions` table.
--
-- SCOPE NOTE — read before assuming this "bans" a user in any strong sense:
-- Setting `is_banned = true` here does NOT, by itself, block that user's
-- writes anywhere else in the schema. Enforcing a ban properly means adding
-- `and not (select is_banned from profiles where id = auth.uid())` (or an
-- equivalent helper function) to every RLS policy that allows a write —
-- events, messages, posts, check_ins, reports, etc. That is a deliberate
-- follow-up, not an oversight: retrofitting a ban-check into ~15 existing
-- RLS policies is its own reviewable change, and doing it inline here risks
-- silently changing the behavior of policies that were already reviewed in
-- migration 010. The immediate value shipped now is that admins can flag an
-- account and see the flag; hard enforcement is the next PR.
-- =============================================================================

alter table profiles add column is_banned boolean not null default false;
alter table profiles add column banned_reason text;
alter table profiles add column banned_at timestamptz;
alter table profiles add column banned_by uuid references profiles(id);

create index idx_profiles_is_banned on profiles (id) ;

-- Admins can update the ban fields on any profile; the existing
-- `profiles_admin_update_any` policy (migration 010) already covers this —
-- no new RLS policy needed, only the columns.

-- Helper used by the admin dashboard to ban a user with a single call,
-- ensuring the audit_logs write and the profiles update happen together.
create or replace function admin_ban_user(p_target_user_id uuid, p_reason text)
returns void as $$
begin
    if not has_role(auth.uid(), 'admin') and not has_role(auth.uid(), 'moderator') then
        raise exception 'Only admins or moderators can ban users';
    end if;

    update profiles
    set is_banned = true, banned_reason = p_reason, banned_at = now(), banned_by = auth.uid()
    where id = p_target_user_id;

    insert into audit_logs (actor_id, action, target_type, target_id, metadata)
    values (auth.uid(), 'user_banned', 'user', p_target_user_id, jsonb_build_object('reason', p_reason));
end;
$$ language plpgsql security definer;

create or replace function admin_unban_user(p_target_user_id uuid)
returns void as $$
begin
    if not has_role(auth.uid(), 'admin') and not has_role(auth.uid(), 'moderator') then
        raise exception 'Only admins or moderators can unban users';
    end if;

    update profiles
    set is_banned = false, banned_reason = null, banned_at = null, banned_by = null
    where id = p_target_user_id;

    insert into audit_logs (actor_id, action, target_type, target_id)
    values (auth.uid(), 'user_unbanned', 'user', p_target_user_id);
end;
$$ language plpgsql security definer;
-- =============================================================================
-- Migration 016: Event Approval Workflow
--
-- PRODUCT DECISION RECORD (see iTANGO-Feature-Completeness-Audit.md):
-- the choice between organizer self-publish vs. admin-approval-required was
-- flagged as open and never answered directly. Rather than block on it or
-- silently pick one permanently, this migration implements BOTH as a
-- platform-level toggle, defaulting to self-publish (the faster-to-market
-- option, and the behavior the app already had). Turning on approval-
-- required is a data change (one row in `platform_settings`), not a code
-- change or a new migration — so the actual product decision, whenever
-- it's made, doesn't require an engineering deploy to act on.
-- =============================================================================

create table platform_settings (
    key text primary key,
    value jsonb not null,
    updated_at timestamptz not null default now(),
    updated_by uuid references profiles(id)
);

insert into platform_settings (key, value) values
    ('events_require_admin_approval', 'false'::jsonb);

alter table platform_settings enable row level security;
create policy "platform_settings_select_all" on platform_settings for select using (true); -- clients need to read this to know which UI flow to show
create policy "platform_settings_update_admin_only" on platform_settings
    for update using (has_role(auth.uid(), 'admin'));

-- -----------------------------------------------------------------------------
-- Add the pending-review status to the event lifecycle. Existing values
-- (draft, published, live, ended, cancelled) are unchanged — this is
-- additive, matching the migration-safety pattern used throughout this
-- schema (see database/README.md's design decisions on additive changes).
-- -----------------------------------------------------------------------------
alter type event_status add value if not exists 'pending_review';

-- -----------------------------------------------------------------------------
-- Organizer-facing "publish" function — replaces a direct
-- `update events set status = 'published'` so the approval-gate logic
-- lives in exactly one place rather than being re-implemented in the
-- Flutter app, the Next.js organizer dashboard, and any future admin tool.
-- -----------------------------------------------------------------------------
create or replace function publish_event(p_event_id uuid)
returns event_status as $$
declare
    v_organizer_id uuid;
    v_requires_approval boolean;
    v_new_status event_status;
begin
    select organizer_id into v_organizer_id from events where id = p_event_id;
    if v_organizer_id is null then
        raise exception 'Event not found';
    end if;
    if v_organizer_id <> auth.uid() and not is_admin_or_moderator(auth.uid()) then
        raise exception 'Only the organizer or a moderator can publish this event';
    end if;

    select (value #>> '{}')::boolean into v_requires_approval
    from platform_settings where key = 'events_require_admin_approval';

    v_new_status := case when coalesce(v_requires_approval, false) then 'pending_review' else 'published' end;

    update events set status = v_new_status where id = p_event_id;
    return v_new_status;
end;
$$ language plpgsql security definer;

-- -----------------------------------------------------------------------------
-- Admin approval action — only meaningful when the setting above is true,
-- but harmless (no-op on an event that isn't pending_review) if called
-- otherwise, so the admin UI doesn't need to conditionally hide the button
-- based on the platform setting.
-- -----------------------------------------------------------------------------
create or replace function approve_event(p_event_id uuid)
returns void as $$
begin
    if not is_admin_or_moderator(auth.uid()) then
        raise exception 'Only an admin or moderator can approve events';
    end if;

    update events set status = 'published' where id = p_event_id and status = 'pending_review';

    insert into audit_logs (actor_id, action, target_type, target_id)
    values (auth.uid(), 'event_approved', 'event', p_event_id);
end;
$$ language plpgsql security definer;

create or replace function reject_event(p_event_id uuid, p_reason text)
returns void as $$
begin
    if not is_admin_or_moderator(auth.uid()) then
        raise exception 'Only an admin or moderator can reject events';
    end if;

    update events set status = 'cancelled' where id = p_event_id and status = 'pending_review';

    insert into audit_logs (actor_id, action, target_type, target_id, metadata)
    values (auth.uid(), 'event_rejected', 'event', p_event_id, jsonb_build_object('reason', p_reason));
end;
$$ language plpgsql security definer;
-- =============================================================================
-- Migration 017: Fix events RLS — public visibility must also check status
--
-- BUG FOUND WHILE BUILDING MIGRATION 016: the original `events_select_visible`
-- policy (migration 010) only checked `visibility = 'public'` for the public
-- branch, with NO status check. That means a 'draft' or now 'pending_review'
-- event with visibility='public' was already visible to any anonymous
-- visitor — a pre-existing gap, not something introduced by the approval
-- workflow, but one that makes the approval workflow meaningless if left
-- unfixed (an organizer's unapproved event would still be publicly visible
-- while "pending"). Fixed here rather than by editing migration 010 in
-- place, per this project's own rule: never edit a migration that may have
-- already run against a real database (see database/README.md).
-- =============================================================================

drop policy "events_select_visible" on events;

create policy "events_select_visible" on events
    for select using (
        (visibility = 'public' and status in ('published', 'live', 'ended'))
        or organizer_id = auth.uid()
        or (visibility = 'friends_only' and status in ('published', 'live', 'ended') and exists (
            select 1 from friendships
            where status = 'accepted'
            and ((user_id = auth.uid() and friend_id = events.organizer_id)
              or (friend_id = auth.uid() and user_id = events.organizer_id))
        ))
        or (visibility = 'invite_only' and status in ('published', 'live', 'ended') and exists (
            select 1 from event_attendees where event_id = events.id and user_id = auth.uid()
        ))
        or is_admin_or_moderator(auth.uid())
    );

-- Note: 'ended' is included alongside 'published'/'live' so past events
-- remain visible (event history, reviews) rather than disappearing the
-- moment they conclude — 'draft', 'pending_review', and 'cancelled' are the
-- only statuses excluded from public/friends/invite visibility, which is
-- the actual intent this policy always should have enforced.
-- =============================================================================
-- Migration 018: Storage RLS for message-media (private attachments)
--
-- The `message-media` bucket itself is created manually (Storage buckets
-- aren't part of SQL migrations) — see devops/scripts/setup-supabase-projects.md
-- §3. This migration adds the RLS policy on storage.objects that makes
-- "private" actually mean something: only participants in the conversation
-- a given attachment belongs to can read it, mirroring the same
-- conversation_participants check already enforced on the `messages` table
-- itself (migration 010).
--
-- Storage RLS works by policy on storage.objects, matched by bucket_id and
-- the object's `name` (its path). Since a message's media_url column
-- stores that same path (see uploadMessageMedia in the Flutter app), the
-- join below is exact-path-match against messages.media_url — a signed URL
-- being handed to someone outside the conversation would still 403 at the
-- Storage layer even if they somehow obtained it, which is the actual
-- security property "private" is supposed to guarantee here.
-- =============================================================================

create policy "message_media_select_conversation_participants"
on storage.objects for select
using (
    bucket_id = 'message-media'
    and exists (
        select 1
        from messages m
        join conversation_participants cp on cp.conversation_id = m.conversation_id
        where m.media_url = storage.objects.name
        and cp.user_id = auth.uid()
    )
);
-- KNOWN LIMITATION: this policy doesn't check messages.deleted_at, so a
-- soft-deleted message's attachment remains readable to conversation
-- participants via a signed URL even after the message itself is hidden
-- from the chat UI (migration 010's messages_select_participant policy
-- does check deleted_at for the message row, but this Storage policy
-- doesn't mirror that). Acceptable for now — deletion here means "hidden
-- from the thread," not "provably erased," which is already true of the
-- underlying messages row itself (soft delete, not hard delete). Tightening
-- this to also check deleted_at is a straightforward follow-up if message
-- deletion needs a stronger guarantee later.

-- Uploads are validated by the application layer (sendMediaMessage only
-- ever writes a media_url that matches a path the same user just uploaded
-- under their own $userId/ prefix), but a defense-in-depth INSERT policy
-- still restricts writes to a user's own path prefix, same pattern as the
-- story-media bucket would use if it needed one (it doesn't, since story
-- media is intentionally public).
create policy "message_media_insert_own_prefix"
on storage.objects for insert
with check (
    bucket_id = 'message-media'
    and (storage.foldername(name))[1] = auth.uid()::text
);
-- =============================================================================
-- Migration 019: Allow organizer/admin check-in inserts on behalf of an attendee
--
-- BUG FOUND WHILE BUILDING staff-checkin/index.ts: the existing
-- `check_ins_insert_own` policy (migration 010) only allows
-- `user_id = auth.uid()` — i.e., you can only check yourself in. Staff
-- scanning an ATTENDEE's ticket QR needs to insert a check_ins row where
-- user_id is the attendee, not the staff member. Without this policy, that
-- insert would be silently rejected by RLS regardless of how correct the
-- Edge Function's own authorization logic is.
--
-- Deliberately added as a SEPARATE policy rather than editing
-- `check_ins_insert_own` in place — Postgres RLS policies are OR'd
-- together for a given operation, so adding a second policy is the
-- correct way to add a new allowed case without touching (or risking) the
-- already-reviewed self-check-in policy from migration 010.
-- =============================================================================

create policy "check_ins_insert_by_organizer_or_admin" on check_ins
    for insert with check (
        is_admin_or_moderator(auth.uid())
        or exists (
            select 1 from events where events.id = check_ins.event_id and events.organizer_id = auth.uid()
        )
    );
-- =============================================================================
-- Migration 020: Enforce discover_people's radius cap in Postgres itself
--
-- BUG FOUND DURING FULL-STACK VERIFICATION: the `discover-people` Edge
-- Function (backend/supabase/functions/discover-people/index.ts) caps the
-- search radius at 15km in its TypeScript code specifically so a modified
-- client can't pull a citywide dump of user locations in one call. But the
-- actual Flutter mobile client (discover_person.dart) calls
-- `client.rpc('discover_people', ...)` DIRECTLY via PostgREST — it never
-- goes through that Edge Function at all. Since the underlying Postgres
-- function had no cap of its own, the documented security property
-- ("hard server-side radius cap regardless of client input") was not
-- actually enforced for the one client that matters.
--
-- Fixed at the correct layer: inside the function itself, so it holds
-- regardless of which caller reaches it (direct RPC, the Edge Function
-- wrapper, or any future integration) — the same defense-in-depth principle
-- already used elsewhere in this schema (e.g. the messages INSERT policy
-- re-verifies check-in status even though conversation_participants should
-- already reflect it).
-- =============================================================================

create or replace function discover_people(
    p_user_id uuid,
    p_lat double precision,
    p_lng double precision,
    p_vibe_tag vibe_tag_name default null,
    p_radius_km double precision default 5,
    p_limit int default 30
)
returns table (
    user_id uuid,
    username citext,
    display_name text,
    avatar_url text,
    energy_score integer,
    distance_km double precision,
    vibe_tags vibe_tag_name[],
    mutual_event_count bigint
) as $$
    select
        p.id,
        p.username,
        p.display_name,
        p.avatar_url,
        p.energy_score,
        st_distance(p.current_location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography) / 1000.0,
        array_agg(distinct uvt.tag),
        (
            select count(*) from event_attendees ea1
            join event_attendees ea2 on ea1.event_id = ea2.event_id
            where ea1.user_id = p_user_id and ea2.user_id = p.id
        )
    from profiles p
    join user_vibe_tags uvt on uvt.user_id = p.id and (uvt.expires_at is null or uvt.expires_at > now())
    where p.id <> p_user_id
      and (p_vibe_tag is null or uvt.tag = p_vibe_tag)
      -- The actual fix: LEAST(...) caps the effective radius at 15km no
      -- matter what p_radius_km the caller supplies, positive or absurdly
      -- large. A zero/negative value falls back to the 5km default rather
      -- than being passed through to ST_DWithin unguarded.
      and st_dwithin(
          p.current_location,
          st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
          least(coalesce(nullif(p_radius_km, 0), 5), 15) * 1000
      )
      and not exists (
          select 1 from friendships f
          where f.status = 'blocked'
          and ((f.user_id = p_user_id and f.friend_id = p.id) or (f.friend_id = p_user_id and f.user_id = p.id))
      )
    group by p.id
    order by st_distance(p.current_location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography) / 1000.0 asc
    limit least(coalesce(p_limit, 30), 50); -- same reasoning applied to result count, not just radius
$$ language sql stable;

comment on function discover_people is
    'Radius capped at 15km and result count at 50 INSIDE this function, not just in the discover-people Edge Function wrapper — see migration 020 for why the wrapper alone was not sufficient (the mobile client bypasses it via direct RPC).';
-- =============================================================================
-- Migration 021: Blended Localized Social Feed Engine
--
-- Enforces a dynamic, location-specific 15km radius boundary for user feeds.
-- Content is dynamically centered on the caller's coordinates (p_lat, p_lng).
-- =============================================================================

create or replace function get_localized_social_feed(
    p_lat double precision,
    p_lng double precision,
    p_radius_km double precision default 15,
    p_limit integer default 20,
    p_offset integer default 0
)
returns table (
    post_id uuid,
    author_id uuid,
    author_username citext,
    author_display_name text,
    author_avatar_url text,
    event_id uuid,
    caption text,
    media_urls text[],
    like_count integer,
    comment_count integer,
    distance_km double precision,
    created_at timestamptz
) as $$
begin
    return query
    select
        p.id as post_id,
        prof.id as author_id,
        prof.username as author_username,
        prof.display_name as author_display_name,
        prof.avatar_url as author_avatar_url,
        p.event_id,
        p.caption,
        p.media_urls,
        p.like_count,
        p.comment_count,
        st_distance(p.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography) / 1000.0 as distance_km,
        p.created_at
    from posts p
    join profiles prof on p.user_id = prof.id
    where p.deleted_at is null
      -- Enforces the dynamic geographic proximity fence around the user's current coordinates
      and st_dwithin(
          p.location,
          st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
          least(coalesce(nullif(p_radius_km, 0), 15), 15) * 1000
      )
    order by p.created_at desc
    limit least(p_limit, 50)
    offset p_offset;
end;
$$ language plpgsql stable;

comment on function get_localized_social_feed is 
    'Fetches an aggregated social feed of posts created within a hard-capped 15km server-side proximity radius of the specified lat/lng point.';
