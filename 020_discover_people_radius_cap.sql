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
    order by distance_km asc
    limit least(coalesce(p_limit, 30), 50); -- same reasoning applied to result count, not just radius
$$ language sql stable;

comment on function discover_people is
    'Radius capped at 15km and result count at 50 INSIDE this function, not just in the discover-people Edge Function wrapper — see migration 020 for why the wrapper alone was not sufficient (the mobile client bypasses it via direct RPC).';
