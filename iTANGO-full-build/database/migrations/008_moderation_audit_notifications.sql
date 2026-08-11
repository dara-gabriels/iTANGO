-- =============================================================================
-- Migration 008: Moderation, Audit, Notifications
-- =============================================================================

create table reports (
    id uuid primary key default uuid_generate_v4(),
    reporter_id uuid not null references profiles(id) on delete set null,
    target_type report_target_type not null,
    target_id uuid not null, -- polymorphic; not FK-enforced across differing target tables
    reason text not null,
    details text,
    status report_status not null default 'open',
    reviewed_by uuid references profiles(id),
    reviewed_at timestamptz,
    created_at timestamptz not null default now()
);
create index idx_reports_status on reports (status);
create index idx_reports_target on reports (target_type, target_id);

create type moderation_action_type as enum ('warn', 'content_removed', 'suspended', 'banned', 'dismissed');
create table moderation_actions (
    id uuid primary key default uuid_generate_v4(),
    report_id uuid references reports(id) on delete set null,
    moderator_id uuid not null references profiles(id),
    target_type report_target_type not null,
    target_id uuid not null,
    action moderation_action_type not null,
    notes text,
    created_at timestamptz not null default now()
);
create index idx_moderation_actions_target on moderation_actions (target_type, target_id);

-- -----------------------------------------------------------------------------
-- audit_logs — append-only, RLS-locked (see 09_rls_policies.sql). Every
-- admin/moderator action must write here for compliance (GDPR/NDPR §8 of
-- Master Plan).
-- -----------------------------------------------------------------------------
create table audit_logs (
    id uuid primary key default uuid_generate_v4(),
    actor_id uuid references profiles(id),
    action text not null,
    target_type text,
    target_id uuid,
    metadata jsonb,
    ip_address inet,
    created_at timestamptz not null default now()
);
create index idx_audit_logs_actor on audit_logs (actor_id, created_at desc);
create index idx_audit_logs_target on audit_logs (target_type, target_id);

-- Prevent updates/deletes at the DB level — audit logs are immutable even to admins.
create or replace function forbid_audit_log_mutation()
returns trigger as $$
begin
    raise exception 'audit_logs is append-only; % is not permitted', tg_op;
end;
$$ language plpgsql;

create trigger trg_audit_logs_no_update before update on audit_logs
    for each row execute function forbid_audit_log_mutation();
create trigger trg_audit_logs_no_delete before delete on audit_logs
    for each row execute function forbid_audit_log_mutation();

-- -----------------------------------------------------------------------------
-- notifications
-- -----------------------------------------------------------------------------
create type notification_type as enum (
    'event_reminder', 'checkin_confirmed', 'new_message', 'new_follower',
    'friend_request', 'post_like', 'post_comment', 'ticket_confirmed',
    'voucher_available', 'achievement_earned', 'organizer_announcement'
);

create table notifications (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references profiles(id) on delete cascade,
    type notification_type not null,
    payload jsonb not null default '{}',
    read_at timestamptz,
    created_at timestamptz not null default now()
);
create index idx_notifications_user_unread on notifications (user_id, created_at desc) where read_at is null;
