-- database/tests/002_event_approval_test.sql
-- Verifies the bug fixed in migration 017 stays fixed: a pending_review
-- (or draft) event must NOT be visible to the public, even with
-- visibility = 'public' set.

begin;
select plan(4);

insert into auth.users (id, email) values
    ('99999999-9999-9999-9999-999999999999', 'organizer2@test.itango.app'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'public_viewer@test.itango.app');

insert into profiles (id, username, display_name) values
    ('99999999-9999-9999-9999-999999999999', 'organizer2', 'Organizer 2'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'viewer', 'Public Viewer');

-- Turn approval ON for this test.
update platform_settings set value = 'true'::jsonb where key = 'events_require_admin_approval';

insert into events (id, organizer_id, title, event_type, visibility, status, start_time)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '99999999-9999-9999-9999-999999999999',
        'Unapproved Event', 'party', 'public', 'draft', now() + interval '2 hours');

set local role authenticated;
set local "request.jwt.claims" to '{"sub": "99999999-9999-9999-9999-999999999999"}';

-- Organizer publishes — with approval required, this should land as
-- pending_review, not published.
select is(
    (select publish_event('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')::text),
    'pending_review',
    'publish_event() returns pending_review when the platform setting requires approval'
);

-- The public viewer must NOT see it yet.
set local "request.jwt.claims" to '{"sub": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}';
select is(
    (select count(*)::int from events where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
    0,
    'A pending_review event is NOT visible to an unrelated public user (the bug fixed in migration 017)'
);

-- A non-admin cannot approve it.
select throws_ok(
    $$ select approve_event('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') $$,
    'Only an admin or moderator can approve events',
    'A regular user cannot call approve_event()'
);

-- An admin approves it, and now the public CAN see it.
reset role;
insert into user_roles (user_id, role)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'admin')
on conflict do nothing;

set local role authenticated;
set local "request.jwt.claims" to '{"sub": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}';
select approve_event('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

select is(
    (select count(*)::int from events where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' and status = 'published'),
    1,
    'After admin approval, the event is published and publicly visible'
);

select * from finish();
rollback;
