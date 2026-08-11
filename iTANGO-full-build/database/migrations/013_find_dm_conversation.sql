-- =============================================================================
-- Migration 013 (Phase 7 addendum): find_dm_conversation
-- Needed by the Flutter chat feature's `startOrGetDmConversation` helper
-- (mobile/lib/features/chat/domain/chat_models.dart) so "Say Hi" from
-- Discover and "Message" from Profile converge on one DM thread instead of
-- creating a duplicate conversation every time either entry point is used.
-- =============================================================================

create or replace function find_dm_conversation(p_user_a uuid, p_user_b uuid)
returns uuid as $$
    select cp1.conversation_id
    from conversation_participants cp1
    join conversation_participants cp2
        on cp1.conversation_id = cp2.conversation_id and cp2.user_id = p_user_b
    join conversations c on c.id = cp1.conversation_id
    where cp1.user_id = p_user_a
      and c.type = 'dm'
    limit 1;
$$ language sql stable;
