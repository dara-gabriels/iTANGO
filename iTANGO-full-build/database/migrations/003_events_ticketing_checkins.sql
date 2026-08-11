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
create index idx_tickets_available on tickets (event_id) where quantity_sold < quantity_total;

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
