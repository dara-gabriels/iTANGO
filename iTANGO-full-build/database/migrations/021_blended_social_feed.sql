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
