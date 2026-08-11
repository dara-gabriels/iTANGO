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
