-- database/tests/003_staff_checkin_rls_test.sql
-- Verifies migration 019: an event's organizer can insert a check_ins row
-- on behalf of an attendee (the staff-checkin flow), but an unrelated user
-- cannot do the same for someone else.

begin;
select plan(3);

insert into auth.users (id, email) values
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'organizer3@test.itango.app'),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'attendee@test.itango.app'),
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'randomuser@test.itango.app');

insert into profiles (id, username, display_name) values
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'organizer3', 'Organizer 3'),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'attendee1', 'Attendee'),
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'random1', 'Random User');

insert into events (id, organizer_id, title, event_type, visibility, status, start_time)
values ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'cccccccc-cccc-cccc-cccc-cccccccccccc',
        'Staff Checkin Test Event', 'party', 'public', 'published', now() + interval '1 hour');

set local role authenticated;

-- The organizer checks the attendee in — should succeed.
set local "request.jwt.claims" to '{"sub": "cccccccc-cccc-cccc-cccc-cccccccccccc"}';
select lives_ok(
    $$ insert into check_ins (event_id, user_id, method, verified_by)
       values ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'qr', 'cccccccc-cccc-cccc-cccc-cccccccccccc') $$,
    'Event organizer CAN check in an attendee on their behalf (staff-checkin flow)'
);

select is(
    (select count(*)::int from check_ins where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd' and event_id = 'ffffffff-ffff-ffff-ffff-ffffffffffff'),
    1,
    'The check-in row was actually created with the attendee as user_id, not the organizer'
);

-- A random unrelated user attempts the same thing for a second attendee — must fail.
set local "request.jwt.claims" to '{"sub": "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"}';
select throws_ok(
    $$ insert into check_ins (event_id, user_id, method, verified_by)
       values ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'qr', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee') $$,
    'new row violates row-level security policy for table "check_ins"',
    'An unrelated user (not the organizer, not an admin) CANNOT check anyone into someone else''s event'
);

select * from finish();
rollback;
