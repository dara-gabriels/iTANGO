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
