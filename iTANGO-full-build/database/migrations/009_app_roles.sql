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
