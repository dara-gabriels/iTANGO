-- =============================================================================
-- Migration 016: Event Approval Workflow
--
-- PRODUCT DECISION RECORD (see iTANGO-Feature-Completeness-Audit.md):
-- the choice between organizer self-publish vs. admin-approval-required was
-- flagged as open and never answered directly. Rather than block on it or
-- silently pick one permanently, this migration implements BOTH as a
-- platform-level toggle, defaulting to self-publish (the faster-to-market
-- option, and the behavior the app already had). Turning on approval-
-- required is a data change (one row in `platform_settings`), not a code
-- change or a new migration — so the actual product decision, whenever
-- it's made, doesn't require an engineering deploy to act on.
-- =============================================================================

create table platform_settings (
    key text primary key,
    value jsonb not null,
    updated_at timestamptz not null default now(),
    updated_by uuid references profiles(id)
);

insert into platform_settings (key, value) values
    ('events_require_admin_approval', 'false'::jsonb);

alter table platform_settings enable row level security;
create policy "platform_settings_select_all" on platform_settings for select using (true); -- clients need to read this to know which UI flow to show
create policy "platform_settings_update_admin_only" on platform_settings
    for update using (has_role(auth.uid(), 'admin'));

-- -----------------------------------------------------------------------------
-- Add the pending-review status to the event lifecycle. Existing values
-- (draft, published, live, ended, cancelled) are unchanged — this is
-- additive, matching the migration-safety pattern used throughout this
-- schema (see database/README.md's design decisions on additive changes).
-- -----------------------------------------------------------------------------
alter type event_status add value if not exists 'pending_review';

-- -----------------------------------------------------------------------------
-- Organizer-facing "publish" function — replaces a direct
-- `update events set status = 'published'` so the approval-gate logic
-- lives in exactly one place rather than being re-implemented in the
-- Flutter app, the Next.js organizer dashboard, and any future admin tool.
-- -----------------------------------------------------------------------------
create or replace function publish_event(p_event_id uuid)
returns event_status as $$
declare
    v_organizer_id uuid;
    v_requires_approval boolean;
    v_new_status event_status;
begin
    select organizer_id into v_organizer_id from events where id = p_event_id;
    if v_organizer_id is null then
        raise exception 'Event not found';
    end if;
    if v_organizer_id <> auth.uid() and not is_admin_or_moderator(auth.uid()) then
        raise exception 'Only the organizer or a moderator can publish this event';
    end if;

    select (value #>> '{}')::boolean into v_requires_approval
    from platform_settings where key = 'events_require_admin_approval';

    v_new_status := case when coalesce(v_requires_approval, false) then 'pending_review' else 'published' end;

    update events set status = v_new_status where id = p_event_id;
    return v_new_status;
end;
$$ language plpgsql security definer;

-- -----------------------------------------------------------------------------
-- Admin approval action — only meaningful when the setting above is true,
-- but harmless (no-op on an event that isn't pending_review) if called
-- otherwise, so the admin UI doesn't need to conditionally hide the button
-- based on the platform setting.
-- -----------------------------------------------------------------------------
create or replace function approve_event(p_event_id uuid)
returns void as $$
begin
    if not is_admin_or_moderator(auth.uid()) then
        raise exception 'Only an admin or moderator can approve events';
    end if;

    update events set status = 'published' where id = p_event_id and status = 'pending_review';

    insert into audit_logs (actor_id, action, target_type, target_id)
    values (auth.uid(), 'event_approved', 'event', p_event_id);
end;
$$ language plpgsql security definer;

create or replace function reject_event(p_event_id uuid, p_reason text)
returns void as $$
begin
    if not is_admin_or_moderator(auth.uid()) then
        raise exception 'Only an admin or moderator can reject events';
    end if;

    update events set status = 'cancelled' where id = p_event_id and status = 'pending_review';

    insert into audit_logs (actor_id, action, target_type, target_id, metadata)
    values (auth.uid(), 'event_rejected', 'event', p_event_id, jsonb_build_object('reason', p_reason));
end;
$$ language plpgsql security definer;
