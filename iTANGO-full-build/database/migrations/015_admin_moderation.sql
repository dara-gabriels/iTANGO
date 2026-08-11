-- =============================================================================
-- Migration 015: Admin Moderation Additions
--
-- Adds the minimum schema needed for the Admin Moderation Queue and User
-- Management screens (Phase 5/6 web work): a ban flag and who/when/why it
-- was set, auditable via the existing `moderation_actions` table.
--
-- SCOPE NOTE — read before assuming this "bans" a user in any strong sense:
-- Setting `is_banned = true` here does NOT, by itself, block that user's
-- writes anywhere else in the schema. Enforcing a ban properly means adding
-- `and not (select is_banned from profiles where id = auth.uid())` (or an
-- equivalent helper function) to every RLS policy that allows a write —
-- events, messages, posts, check_ins, reports, etc. That is a deliberate
-- follow-up, not an oversight: retrofitting a ban-check into ~15 existing
-- RLS policies is its own reviewable change, and doing it inline here risks
-- silently changing the behavior of policies that were already reviewed in
-- migration 010. The immediate value shipped now is that admins can flag an
-- account and see the flag; hard enforcement is the next PR.
-- =============================================================================

alter table profiles add column is_banned boolean not null default false;
alter table profiles add column banned_reason text;
alter table profiles add column banned_at timestamptz;
alter table profiles add column banned_by uuid references profiles(id);

create index idx_profiles_is_banned on profiles (id) where is_banned = true;

-- Admins can update the ban fields on any profile; the existing
-- `profiles_admin_update_any` policy (migration 010) already covers this —
-- no new RLS policy needed, only the columns.

-- Helper used by the admin dashboard to ban a user with a single call,
-- ensuring the audit_logs write and the profiles update happen together.
create or replace function admin_ban_user(p_target_user_id uuid, p_reason text)
returns void as $$
begin
    if not has_role(auth.uid(), 'admin') and not has_role(auth.uid(), 'moderator') then
        raise exception 'Only admins or moderators can ban users';
    end if;

    update profiles
    set is_banned = true, banned_reason = p_reason, banned_at = now(), banned_by = auth.uid()
    where id = p_target_user_id;

    insert into audit_logs (actor_id, action, target_type, target_id, metadata)
    values (auth.uid(), 'user_banned', 'user', p_target_user_id, jsonb_build_object('reason', p_reason));
end;
$$ language plpgsql security definer;

create or replace function admin_unban_user(p_target_user_id uuid)
returns void as $$
begin
    if not has_role(auth.uid(), 'admin') and not has_role(auth.uid(), 'moderator') then
        raise exception 'Only admins or moderators can unban users';
    end if;

    update profiles
    set is_banned = false, banned_reason = null, banned_at = null, banned_by = null
    where id = p_target_user_id;

    insert into audit_logs (actor_id, action, target_type, target_id)
    values (auth.uid(), 'user_unbanned', 'user', p_target_user_id);
end;
$$ language plpgsql security definer;
