# devops/scripts/setup-supabase-projects.md
One-time manual setup — not automated, since it happens once per project
lifetime and Supabase's Terraform coverage for full project provisioning
is limited. Run through this checklist when standing up iTANGO's
infrastructure for the first time.

## 1. Create two Supabase projects

Via the Supabase Dashboard (not CLI, for the initial project creation):
- `itango-staging`
- `itango-production`

Different regions can be used if desired, but for lowest latency to
Nigerian users, choose the closest available region (at time of writing,
Supabase does not have a West Africa region — pick the closest EU region).

## 2. Apply database migrations to each

```bash
supabase link --project-ref <staging-project-ref>
supabase db push   # applies database/migrations/*.sql in order

# repeat for production once staging is verified
supabase link --project-ref <production-project-ref>
supabase db push
```

## 3. Create Storage buckets

| Bucket | Access | Used by |
|---|---|---|
| `story-media` | Public read | `uploadStoryMedia()` in the mobile app's story creator — stories are semi-public content by design |
| `message-media` | **Private** — signed URLs only | `uploadMessageMedia()` — image/voice-note/video attachments in DMs and event rooms. Deliberately NOT public: a public bucket would mean anyone who guesses or intercepts a URL could view private message attachments, which defeats the point of the check-in-gated/DM privacy model elsewhere in this app. Add a Storage RLS policy scoping reads to conversation participants (mirrors the `conversation_participants` check already used for `messages` table RLS in migration 010). |
| `event-covers` | Public read | Event cover images (organizer dashboard) |
| `avatars` | Public read | Profile avatars |

Create via Dashboard → Storage → New bucket, marking each public. Bucket-
level RLS (who can *upload*, not just read) should restrict writes to
`auth.uid()`-scoped paths — e.g. a policy requiring the upload path start
with the uploader's own user ID, matching the `$userId/...` path structure
`uploadStoryMedia()` already uses.

## 4. Configure secrets on each project (Project Settings → Edge Functions → Secrets)

Required for the Edge Functions in `backend/supabase/functions/` to work:

| Secret | Used by |
|---|---|
| `PAYSTACK_SECRET_KEY` | `tickets-purchase`, `webhooks-paystack` |
| `QR_SIGNING_SECRET` | `checkins`, `tickets-purchase` — generate via `openssl rand -hex 32`, **different value per environment** |
| `APP_BASE_URL` | `tickets-purchase` (PSP callback URL) — `https://staging.itango.app` or `https://itango.app` |
| `FCM_SERVICE_ACCOUNT_JSON` | `send-push-notification` — can share one Firebase project across environments, or use separate Firebase projects for staging/production (recommended, so test push notifications never risk reaching real users) |

## 5. Deploy Edge Functions

```bash
supabase functions deploy --project-ref <project-ref>
```

Automated per-environment in `.github/workflows/deploy-staging.yml` and
`deploy-production.yml` — this manual step is only for the very first deploy
before CI is wired up.

## 6. Configure the payment webhook URLs

In the Paystack dashboard (separate test-mode and live-mode API keys —
Paystack's own environment separation), set the webhook URL to:
- Staging: `https://<staging-ref>.supabase.co/functions/v1/webhooks-paystack`
- Production: `https://<production-ref>.supabase.co/functions/v1/webhooks-paystack`

## 7. Configure the push notification database webhook

Database → Webhooks → New webhook, on both projects:
- Table: `notifications`, Event: `INSERT`
- URL: `https://<project-ref>.supabase.co/functions/v1/send-push-notification`

## 8. Record project refs as GitHub Actions secrets

`SUPABASE_STAGING_PROJECT_REF`, `SUPABASE_PRODUCTION_PROJECT_REF`,
`SUPABASE_ACCESS_TOKEN` (a personal/service access token with deploy
permissions) — consumed by the CI/CD workflows in `.github/workflows/`.
