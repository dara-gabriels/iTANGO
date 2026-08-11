# web/itango-web/e2e/ — Playwright E2E Tests

## Why these do NOT run in `ci.yml` (generic PR checks)

`ci.yml`'s web build step uses **placeholder** Supabase credentials
(`https://placeholder.supabase.co`) — sufficient to confirm the app
compiles, but any test that actually calls `supabase.auth.signInWithOtp()`
(like "shows the OTP entry step after a valid phone number is submitted"
in `auth-gating.spec.ts`) would fail against a placeholder backend that
doesn't exist. Running these in the generic PR workflow would either:
(a) fail every PR for a reason unrelated to the PR's actual changes, or
(b) require pointing PR builds at a real Supabase project, which risks
cluttering a real project with test data from every branch.

**Instead, these run post-deploy against the real staging environment**,
where `NEXT_PUBLIC_SUPABASE_URL` points at the actual `itango-staging`
Supabase project. This is added as a job in
`.github/workflows/deploy-staging.yml` (see that file's `e2e-tests` job,
which runs after the `smoke-test` job) — the same reasoning as why the
smoke test itself runs post-deploy rather than pre-deploy.

## What's covered, and what isn't

- `auth-gating.spec.ts` — middleware redirect behavior (unauthenticated
  users kept out of `/organizer`, `/admin`, `/home`), the health check
  regression test (see its inline comment for the specific bug this
  guards against), and login-page client-side validation.
- **Not covered**: actually completing phone OTP login end-to-end. That
  needs either a live SMS-reading step or a Supabase test-mode OTP bypass
  (Supabase supports a fixed test OTP for specific phone number patterns
  in some configurations — worth investigating as a follow-up, not yet
  set up here). Until then, "can a real user actually log in" is verified
  manually before each release, not by this suite.
- **Not covered**: the organizer/admin dashboards' authenticated content
  (creating an event, banning a user) — these need a seeded test account
  with the right role already granted, which requires either a fixture
  script against the staging database or Supabase's admin API to create
  a throwaway test user per run. Flagged as the natural next extension of
  this suite, not done in this pass.
