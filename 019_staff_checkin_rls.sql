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
