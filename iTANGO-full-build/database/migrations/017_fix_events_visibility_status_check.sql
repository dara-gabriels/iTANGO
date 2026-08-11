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
