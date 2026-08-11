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
    order by distance_km asc
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
