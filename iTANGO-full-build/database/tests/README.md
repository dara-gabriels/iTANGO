# database/tests/ — RLS Policy Tests (pgTAP)

## Running

```bash
supabase test db
```

Requires the `pgtap` extension, which Supabase's local test runner enables
automatically. This does NOT run against staging/production — it spins up
a throwaway local Postgres instance, applies all migrations, runs the
tests inside a transaction that's rolled back at the end (`begin`/`rollback`
in the test file), and reports pass/fail. Safe to run repeatedly with no
side effects.

## Why this file, specifically, matters more than most tests in this project

Per the note in `database/README.md`'s testing strategy: **an RLS policy
gap is a data breach, not a bug.** Application-level tests catch "the
button doesn't work." This file catches "a user can read another user's
private data by querying the table directly, bypassing the UI entirely" —
a class of bug that's invisible in normal QA (the app never exposes it)
and catastrophic in production (anyone with basic API knowledge can find it).

## Coverage in `001_rls_policies_test.sql`

- `check_ins`: own-row read, organizer-of-event read, cross-user denial
- `messages` in event rooms: the core check-in trust gate — a user who
  never checked in cannot post, even with a valid conversation_id
- `payments`: strict own-row isolation
- `audit_logs`: admin-only read, genuine append-only immutability (the
  `forbid_audit_log_mutation` trigger from migration 008)
- `vouchers`: issuing business owner can manage, others cannot
- `profiles`: public read (by design) but own-row-only write

## What's NOT yet covered here (honest gap, not exhaustive)

- `ticket_purchases`, `wallets`, `friendships`, `communities`,
  `reports`/`moderation_actions` policies exist (migration 010) but don't
  have dedicated pgTAP tests yet — same pattern as above, straightforward
  to extend, just not done in this pass. Prioritized the highest-risk
  tables (money, presence data, audit trail) first.
- Storage bucket RLS (avatars, event covers, post media) — Supabase
  Storage policies are configured separately from table RLS and aren't
  covered by this SQL-only test file.
