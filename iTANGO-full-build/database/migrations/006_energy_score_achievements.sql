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
