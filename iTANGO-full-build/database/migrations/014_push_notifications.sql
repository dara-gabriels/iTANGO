-- =============================================================================
-- Migration 014: Push Notification Infrastructure
-- Two concerns: (1) storing FCM device tokens, (2) triggers that populate
-- the `notifications` table (created in migration 008) when something
-- notification-worthy happens. Actual push DELIVERY (calling FCM) is a
-- separate concern handled by the send-push-notification Edge Function,
-- invoked via a Supabase Database Webhook on INSERT to `notifications` —
-- keeping "decide something is notification-worthy" (SQL trigger) separate
-- from "deliver it" (Edge Function calling an external API) so the DB
-- transaction never blocks on a network call to FCM.
-- =============================================================================

create table device_tokens (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references profiles(id) on delete cascade,
    fcm_token text not null,
    platform text not null default 'unknown', -- 'ios' | 'android'
    created_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now(),

    unique (user_id, fcm_token)
);
create index idx_device_tokens_user on device_tokens (user_id);

alter table device_tokens enable row level security;
create policy "device_tokens_select_own" on device_tokens for select using (user_id = auth.uid());
create policy "device_tokens_insert_own" on device_tokens for insert with check (user_id = auth.uid());
create policy "device_tokens_update_own" on device_tokens for update using (user_id = auth.uid());
create policy "device_tokens_delete_own" on device_tokens for delete using (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- Trigger: new_message → notify other conversation participants
-- Skips the sender and skips participants who are currently "active" in the
-- room — that presence check is a client/Realtime concern, not modeled here;
-- this trigger notifies ALL other participants every message, which is
-- correct for DMs but would be noisy for a busy event room. Flagged as a
-- follow-up: event_room notifications should likely be rate-limited or
-- digested rather than one push per message (see note in Phase 5 backend
-- README about deferring notification fan-out logic out of hot paths).
-- -----------------------------------------------------------------------------
create or replace function notify_new_message()
returns trigger as $$
begin
    if new.sender_id is null then
        return new; -- system messages don't need a "new message" notification
    end if;

    insert into notifications (user_id, type, payload)
    select cp.user_id, 'new_message', jsonb_build_object(
        'conversation_id', new.conversation_id,
        'message_id', new.id,
        'sender_id', new.sender_id,
        'preview', left(coalesce(new.content, ''), 80)
    )
    from conversation_participants cp
    where cp.conversation_id = new.conversation_id
      and cp.user_id <> new.sender_id
      and coalesce(cp.is_muted, false) = false;

    return new;
end;
$$ language plpgsql;

create trigger trg_notify_new_message after insert on messages
    for each row execute function notify_new_message();

-- -----------------------------------------------------------------------------
-- Trigger: achievement_earned
-- -----------------------------------------------------------------------------
create or replace function notify_achievement_earned()
returns trigger as $$
declare
    v_achievement_name text;
begin
    select name into v_achievement_name from achievements where id = new.achievement_id;

    insert into notifications (user_id, type, payload)
    values (new.user_id, 'achievement_earned', jsonb_build_object(
        'achievement_id', new.achievement_id,
        'name', v_achievement_name
    ));
    return new;
end;
$$ language plpgsql;

create trigger trg_notify_achievement_earned after insert on user_achievements
    for each row execute function notify_achievement_earned();

-- -----------------------------------------------------------------------------
-- Trigger: ticket_confirmed (fires when a ticket_purchases row flips to paid)
-- -----------------------------------------------------------------------------
create or replace function notify_ticket_confirmed()
returns trigger as $$
begin
    if new.status = 'paid' and old.status <> 'paid' then
        insert into notifications (user_id, type, payload)
        values (new.user_id, 'ticket_confirmed', jsonb_build_object(
            'ticket_purchase_id', new.id,
            'qr_code', new.qr_code
        ));
    end if;
    return new;
end;
$$ language plpgsql;

create trigger trg_notify_ticket_confirmed after update on ticket_purchases
    for each row execute function notify_ticket_confirmed();

-- -----------------------------------------------------------------------------
-- Trigger: checkin_confirmed
-- -----------------------------------------------------------------------------
create or replace function notify_checkin_confirmed()
returns trigger as $$
declare
    v_event_title text;
begin
    select title into v_event_title from events where id = new.event_id;

    insert into notifications (user_id, type, payload)
    values (new.user_id, 'checkin_confirmed', jsonb_build_object(
        'event_id', new.event_id,
        'event_title', v_event_title
    ));
    return new;
end;
$$ language plpgsql;

create trigger trg_notify_checkin_confirmed after insert on check_ins
    for each row execute function notify_checkin_confirmed();
