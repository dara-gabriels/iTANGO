-- =============================================================================
-- Migration 010: Row Level Security Policies
-- Every table containing user data has RLS enabled. No client ever receives
-- a service-role key — Edge Functions use service role server-side only for
-- operations that legitimately need to bypass RLS (e.g. payment webhooks).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- profiles
-- -----------------------------------------------------------------------------
alter table profiles enable row level security;

create policy "profiles_select_public" on profiles
    for select using (true); -- profile info is public by design (usernames, badges, energy score)

create policy "profiles_update_own" on profiles
    for update using (auth.uid() = id) with check (auth.uid() = id);

create policy "profiles_admin_update_any" on profiles
    for update using (is_admin_or_moderator(auth.uid()));

-- -----------------------------------------------------------------------------
-- follows / friendships
-- -----------------------------------------------------------------------------
alter table follows enable row level security;
create policy "follows_select_all" on follows for select using (true);
create policy "follows_insert_own" on follows for insert with check (auth.uid() = follower_id);
create policy "follows_delete_own" on follows for delete using (auth.uid() = follower_id);

alter table friendships enable row level security;
create policy "friendships_select_participant" on friendships
    for select using (auth.uid() = user_id or auth.uid() = friend_id);
create policy "friendships_insert_own" on friendships
    for insert with check (auth.uid() = requested_by);
create policy "friendships_update_participant" on friendships
    for update using (auth.uid() = user_id or auth.uid() = friend_id);

-- -----------------------------------------------------------------------------
-- events — public events visible to all; private/invite-only restricted
-- -----------------------------------------------------------------------------
alter table events enable row level security;

create policy "events_select_visible" on events
    for select using (
        visibility = 'public'
        or organizer_id = auth.uid()
        or (visibility = 'friends_only' and exists (
            select 1 from friendships
            where status = 'accepted'
            and ((user_id = auth.uid() and friend_id = events.organizer_id)
              or (friend_id = auth.uid() and user_id = events.organizer_id))
        ))
        or (visibility = 'invite_only' and exists (
            select 1 from event_attendees where event_id = events.id and user_id = auth.uid()
        ))
        or is_admin_or_moderator(auth.uid())
    );

create policy "events_insert_own" on events
    for insert with check (organizer_id = auth.uid());

create policy "events_update_own_or_admin" on events
    for update using (organizer_id = auth.uid() or is_admin_or_moderator(auth.uid()));

-- -----------------------------------------------------------------------------
-- check_ins — users can insert their own check-in; only event organizer,
-- the user themself, and admins can read it. This is a sensitive presence
-- record and must not be broadly queryable (see child/adult safety note:
-- location + presence data is exactly the kind of thing that must not leak).
-- -----------------------------------------------------------------------------
alter table check_ins enable row level security;

create policy "check_ins_select_own_or_organizer" on check_ins
    for select using (
        user_id = auth.uid()
        or is_admin_or_moderator(auth.uid())
        or exists (select 1 from events where events.id = check_ins.event_id and events.organizer_id = auth.uid())
    );

create policy "check_ins_insert_own" on check_ins
    for insert with check (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- tickets / ticket_purchases
-- -----------------------------------------------------------------------------
alter table tickets enable row level security;
create policy "tickets_select_all" on tickets for select using (true);
create policy "tickets_manage_organizer" on tickets
    for all using (exists (select 1 from events where events.id = tickets.event_id and events.organizer_id = auth.uid()));

alter table ticket_purchases enable row level security;
create policy "ticket_purchases_select_own_or_organizer" on ticket_purchases
    for select using (
        user_id = auth.uid()
        or is_admin_or_moderator(auth.uid())
        or exists (
            select 1 from tickets join events on events.id = tickets.event_id
            where tickets.id = ticket_purchases.ticket_id and events.organizer_id = auth.uid()
        )
    );
create policy "ticket_purchases_insert_own" on ticket_purchases
    for insert with check (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- conversations / messages — the critical check-in gate for event rooms
-- -----------------------------------------------------------------------------
alter table conversations enable row level security;
alter table conversation_participants enable row level security;
alter table messages enable row level security;

create policy "conversations_select_participant" on conversations
    for select using (
        exists (select 1 from conversation_participants cp where cp.conversation_id = conversations.id and cp.user_id = auth.uid())
    );

create policy "conversation_participants_select_own_conversations" on conversation_participants
    for select using (
        user_id = auth.uid()
        or exists (select 1 from conversation_participants cp2 where cp2.conversation_id = conversation_participants.conversation_id and cp2.user_id = auth.uid())
    );

-- Insert into an event_room's participants is normally done by the
-- `join_event_room_on_checkin` trigger (SECURITY DEFINER context), so this
-- policy mainly covers DMs/groups where users add each other directly.
create policy "conversation_participants_insert_dm_group" on conversation_participants
    for insert with check (
        exists (
            select 1 from conversations c
            where c.id = conversation_participants.conversation_id
            and c.type in ('dm', 'group')
        )
    );

create policy "messages_select_participant" on messages
    for select using (
        exists (select 1 from conversation_participants cp where cp.conversation_id = messages.conversation_id and cp.user_id = auth.uid())
        and (deleted_at is null or is_admin_or_moderator(auth.uid()))
    );

-- The core gate: writing into an event_room requires the sender to actually
-- be checked in to that event, not merely a conversation_participants row
-- (defense in depth — even if participants table is stale, this re-verifies).
create policy "messages_insert_participant_and_checked_in" on messages
    for insert with check (
        sender_id = auth.uid()
        and exists (select 1 from conversation_participants cp where cp.conversation_id = messages.conversation_id and cp.user_id = auth.uid())
        and (
            not exists (select 1 from conversations c where c.id = messages.conversation_id and c.type = 'event_room')
            or exists (
                select 1 from conversations c
                where c.id = messages.conversation_id
                and c.type = 'event_room'
                and is_checked_in_to_event(auth.uid(), c.event_id)
            )
        )
    );

-- -----------------------------------------------------------------------------
-- payments / wallets — strictly own-row only, ever
-- -----------------------------------------------------------------------------
alter table payments enable row level security;
create policy "payments_select_own" on payments for select using (user_id = auth.uid() or is_admin_or_moderator(auth.uid()));
-- Note: inserts/updates to `payments` happen exclusively via Edge Functions
-- using the service role (payment webhooks, PSP callbacks) — no direct
-- client insert policy exists on purpose.

alter table wallets enable row level security;
create policy "wallets_select_own" on wallets for select using (user_id = auth.uid());

alter table wallet_transactions enable row level security;
create policy "wallet_transactions_select_own" on wallet_transactions for select using (wallet_user_id = auth.uid());
-- Inserts are service-role only (Edge Functions), same rationale as payments.

-- -----------------------------------------------------------------------------
-- vouchers — issuer business can manage; any authenticated user can view
-- active vouchers; redemption tied to own user_id
-- -----------------------------------------------------------------------------
alter table vouchers enable row level security;
create policy "vouchers_select_active" on vouchers for select using (expires_at > now());
create policy "vouchers_manage_issuer" on vouchers
    for all using (exists (select 1 from businesses where businesses.id = vouchers.issuer_business_id and businesses.owner_id = auth.uid()));

alter table voucher_redemptions enable row level security;
create policy "voucher_redemptions_select_own" on voucher_redemptions for select using (user_id = auth.uid());
create policy "voucher_redemptions_insert_own" on voucher_redemptions for insert with check (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- reports / moderation_actions — reporter sees own report; only mods see all
-- -----------------------------------------------------------------------------
alter table reports enable row level security;
create policy "reports_select_own_or_mod" on reports
    for select using (reporter_id = auth.uid() or is_admin_or_moderator(auth.uid()));
create policy "reports_insert_own" on reports for insert with check (reporter_id = auth.uid());
create policy "reports_update_mod_only" on reports for update using (is_admin_or_moderator(auth.uid()));

alter table moderation_actions enable row level security;
create policy "moderation_actions_mod_only" on moderation_actions for all using (is_admin_or_moderator(auth.uid()));

-- -----------------------------------------------------------------------------
-- audit_logs — insert-only for authenticated actions, read restricted to admins
-- -----------------------------------------------------------------------------
alter table audit_logs enable row level security;
create policy "audit_logs_select_admin_only" on audit_logs for select using (has_role(auth.uid(), 'admin'));
create policy "audit_logs_insert_any_authenticated" on audit_logs for insert with check (auth.uid() is not null);

-- -----------------------------------------------------------------------------
-- notifications — strictly own
-- -----------------------------------------------------------------------------
alter table notifications enable row level security;
create policy "notifications_select_own" on notifications for select using (user_id = auth.uid());
create policy "notifications_update_own" on notifications for update using (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- posts / stories — public read (respecting visibility could be layered on
-- later per-post if a "friends only post" feature ships); own-row write
-- -----------------------------------------------------------------------------
alter table posts enable row level security;
create policy "posts_select_not_deleted" on posts for select using (deleted_at is null or is_admin_or_moderator(auth.uid()));
create policy "posts_insert_own" on posts for insert with check (user_id = auth.uid());
create policy "posts_update_own_or_mod" on posts for update using (user_id = auth.uid() or is_admin_or_moderator(auth.uid()));

alter table stories enable row level security;
create policy "stories_select_active" on stories for select using (expires_at > now() or is_highlight);
create policy "stories_insert_own" on stories for insert with check (user_id = auth.uid());
create policy "stories_delete_own" on stories for delete using (user_id = auth.uid());
