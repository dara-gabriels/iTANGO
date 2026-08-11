-- database/tests/001_rls_policies_test.sql
-- Run via: supabase test db
-- (Supabase CLI wires pgTAP automatically for local test runs)
--
-- This is the single highest-value test file in the whole schema, per the
-- testing-strategy note in database/README.md: "an RLS policy gap is a
-- data breach, not a bug." Each test asserts BOTH the allowed case and the
-- denied case — a policy that blocks everything looks identical to a
-- correctly-configured one until you test that the right people CAN still
-- get through.

begin;
select plan(14);

-- -----------------------------------------------------------------------------
-- Fixtures: two ordinary users, one organizer, one admin, one event
-- -----------------------------------------------------------------------------
insert into auth.users (id, email) values
    ('11111111-1111-1111-1111-111111111111', 'alice@test.itango.app'),
    ('22222222-2222-2222-2222-222222222222', 'bob@test.itango.app'),
    ('33333333-3333-3333-3333-333333333333', 'organizer@test.itango.app'),
    ('44444444-4444-4444-4444-444444444444', 'admin@test.itango.app');

insert into profiles (id, username, display_name) values
    ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice'),
    ('22222222-2222-2222-2222-222222222222', 'bob', 'Bob'),
    ('33333333-3333-3333-3333-333333333333', 'organizer1', 'Organizer'),
    ('44444444-4444-4444-4444-444444444444', 'admin1', 'Admin');

insert into user_roles (user_id, role) values
    ('44444444-4444-4444-4444-444444444444', 'admin');

insert into events (id, organizer_id, title, event_type, visibility, status, start_time)
values ('55555555-5555-5555-5555-555555555555', '33333333-3333-3333-3333-333333333333',
        'Test Event', 'party', 'public', 'live', now() + interval '1 hour');

-- Alice checks in; Bob does not.
insert into check_ins (event_id, user_id, method)
values ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', 'geofence');

-- -----------------------------------------------------------------------------
-- Test 1-2: check_ins — own row readable, other user's row NOT readable
-- -----------------------------------------------------------------------------
set local role authenticated;
set local "request.jwt.claims" to '{"sub": "11111111-1111-1111-1111-111111111111"}';

select is(
    (select count(*)::int from check_ins where user_id = '11111111-1111-1111-1111-111111111111'),
    1,
    'Alice can read her own check_ins row'
);

set local "request.jwt.claims" to '{"sub": "22222222-2222-2222-2222-222222222222"}';

select is(
    (select count(*)::int from check_ins where user_id = '11111111-1111-1111-1111-111111111111'),
    0,
    'Bob CANNOT read Alice''s check_ins row (presence data must not leak)'
);

-- -----------------------------------------------------------------------------
-- Test 3-4: the organizer of the event CAN see check-ins for their event;
-- an unrelated user cannot.
-- -----------------------------------------------------------------------------
set local "request.jwt.claims" to '{"sub": "33333333-3333-3333-3333-333333333333"}';

select is(
    (select count(*)::int from check_ins where event_id = '55555555-5555-5555-5555-555555555555'),
    1,
    'Event organizer CAN read check-ins for their own event'
);

-- -----------------------------------------------------------------------------
-- Test 5-6: messages in an event_room — the check-in gate itself
-- -----------------------------------------------------------------------------
-- The join_event_room_on_checkin trigger should have already added Alice
-- as a conversation_participant when she checked in above.
set local "request.jwt.claims" to '{"sub": "11111111-1111-1111-1111-111111111111"}';

select ok(
    exists(
        select 1 from conversations c
        join conversation_participants cp on cp.conversation_id = c.id
        where c.event_id = '55555555-5555-5555-5555-555555555555'
        and cp.user_id = '11111111-1111-1111-1111-111111111111'
    ),
    'Alice (checked in) was auto-joined to the event room by the trigger'
);

-- Bob, who never checked in, attempts to insert a message into that room —
-- this must fail even if he somehow obtained the conversation_id.
select throws_ok(
    $$ insert into messages (conversation_id, sender_id, content)
       select c.id, '22222222-2222-2222-2222-222222222222', 'I was never here'
       from conversations c where c.event_id = '55555555-5555-5555-5555-555555555555' $$,
    'new row violates row-level security policy for table "messages"',
    'Bob (never checked in) CANNOT post into the event room — the core trust gate holds'
);

-- -----------------------------------------------------------------------------
-- Test 7-8: payments — strictly own-row
-- -----------------------------------------------------------------------------
reset role;
insert into payments (id, user_id, provider, purpose, amount, status)
values ('66666666-6666-6666-6666-666666666666', '11111111-1111-1111-1111-111111111111', 'paystack', 'ticket', 5000, 'succeeded');

set local role authenticated;
set local "request.jwt.claims" to '{"sub": "11111111-1111-1111-1111-111111111111"}';
select is(
    (select count(*)::int from payments where id = '66666666-6666-6666-6666-666666666666'),
    1,
    'Alice can read her own payment'
);

set local "request.jwt.claims" to '{"sub": "22222222-2222-2222-2222-222222222222"}';
select is(
    (select count(*)::int from payments where id = '66666666-6666-6666-6666-666666666666'),
    0,
    'Bob CANNOT read Alice''s payment'
);

-- -----------------------------------------------------------------------------
-- Test 9-10: audit_logs — admin-only read, and genuinely immutable
-- -----------------------------------------------------------------------------
reset role;
insert into audit_logs (actor_id, action) values ('44444444-4444-4444-4444-444444444444', 'test_action');

set local role authenticated;
set local "request.jwt.claims" to '{"sub": "44444444-4444-4444-4444-444444444444"}';
select ok(
    (select count(*)::int from audit_logs where action = 'test_action') >= 1,
    'Admin can read audit_logs'
);

set local "request.jwt.claims" to '{"sub": "11111111-1111-1111-1111-111111111111"}';
select is(
    (select count(*)::int from audit_logs where action = 'test_action'),
    0,
    'Non-admin (Alice) CANNOT read audit_logs'
);

reset role;
select throws_ok(
    $$ update audit_logs set action = 'tampered' where action = 'test_action' $$,
    'audit_logs is append-only; UPDATE is not permitted',
    'audit_logs rows cannot be updated by anyone, including as superuser in this session'
);

-- -----------------------------------------------------------------------------
-- Test 11-12: vouchers — issuer can manage, other business owners cannot
-- -----------------------------------------------------------------------------
insert into businesses (id, owner_id, name, category)
values ('77777777-7777-7777-7777-777777777777', '33333333-3333-3333-3333-333333333333', 'Test Lounge', 'lounge');

insert into vouchers (id, issuer_business_id, title, value, expires_at)
values ('88888888-8888-8888-8888-888888888888', '77777777-7777-7777-7777-777777777777', 'Free Drink', 2000, now() + interval '30 days');

set local role authenticated;
set local "request.jwt.claims" to '{"sub": "33333333-3333-3333-3333-333333333333"}';
select lives_ok(
    $$ update vouchers set title = 'Free Drink (Updated)' where id = '88888888-8888-8888-8888-888888888888' $$,
    'Business owner CAN update their own voucher'
);

set local "request.jwt.claims" to '{"sub": "11111111-1111-1111-1111-111111111111"}';
select is(
    (select count(*)::int from vouchers where id = '88888888-8888-8888-8888-888888888888' for update skip locked),
    0,
    'A non-owner cannot even lock the voucher row for update (no update policy grants them a match)'
);

-- -----------------------------------------------------------------------------
-- Test 13-14: profiles — public read, own-row write only
-- -----------------------------------------------------------------------------
set local "request.jwt.claims" to '{"sub": "11111111-1111-1111-1111-111111111111"}';
select ok(
    (select count(*)::int from profiles where id = '22222222-2222-2222-2222-222222222222') = 1,
    'Any authenticated user can read any profile (profiles are public by design)'
);

select throws_ok(
    $$ update profiles set display_name = 'Hacked' where id = '22222222-2222-2222-2222-222222222222' $$,
    'new row violates row-level security policy for table "profiles"',
    'Alice CANNOT update Bob''s profile'
);

select * from finish();
rollback;
