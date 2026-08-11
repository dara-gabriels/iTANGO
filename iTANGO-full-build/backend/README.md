# iTANGO Backend — Phase 5 Deliverable

## Contents

| Path | Purpose |
|---|---|
| `openapi.yaml` | Full API contract for MVP scope — source of truth for both client codegen (Flutter/Dio, Next.js) and API documentation |
| `supabase/functions/_shared/http.ts` | Shared response/auth/error helpers used by every function |
| `supabase/functions/checkins/` | **Core trust primitive.** QR signature verification (HMAC-SHA256, constant-time compare), geofence distance check, check-in insert |
| `supabase/functions/tickets-purchase/` | Ticket purchase initiation across PSPs + wallet, split-payment notification fan-out |
| `supabase/functions/webhooks-paystack/` | Signature-verified, idempotent payment webhook handler (service-role client) |
| `supabase/functions/events/` | Organizer event creation with validation beyond single-table constraints |
| `supabase/functions/nearby-events/` | Thin wrapper around the `nearby_events` SQL function (Phase 4) |
| `supabase/functions/discover-people/` | Thin wrapper around `discover_people`, with a hard server-side radius cap regardless of client input |
| `supabase/functions/register-device-token/` | Upserts a device's FCM token, called on login and token refresh |
| `supabase/functions/send-push-notification/` | Triggered by a Supabase DB Webhook on `notifications` INSERT — delivers via FCM HTTP v1 (OAuth2 service-account flow, implemented directly via Web Crypto since Firebase Admin SDK isn't Deno-compatible) |
| `supabase/functions/staff-checkin/` | Organizer/staff-authenticated: scans an **attendee's** ticket QR to check them in — distinct auth model from `checkins/` (self-check-in). Required a new RLS policy (migration 019) since the existing check-in policy only allowed self-insert. |
| `supabase/migrations_addendum/012_wallet_settlement_function.sql` | Atomic wallet debit function (row-locked, avoids race conditions under concurrent purchases) — file into the Phase 4 migrations directory as migration 012 |

## Why so few functions are "thin CRUD"

Most simple reads (profile lookups, event details, ticket listings) are served directly by **Supabase's auto-generated PostgREST API**, protected by the RLS policies from Phase 4 — writing an Edge Function for a plain single-table SELECT would just add latency and a second thing to maintain. Edge Functions exist here specifically where there's:

1. **Multi-step transactional logic** (ticket purchase: create payment → create purchase → call PSP → handle split-pay fan-out)
2. **External API calls** (PSP initialization, PSP webhooks)
3. **Security-sensitive verification** (QR signature check, geofence distance, webhook signature)
4. **Business rules that don't belong in a CHECK constraint** (event start_time validation, venue existence check)

This is a deliberate architectural split, not an inconsistency — it keeps the surface area of custom server code as small as it can be while still being correct.

## Deployment

```bash
# Set secrets (never commit these)
supabase secrets set PAYSTACK_SECRET_KEY=sk_live_xxx
supabase secrets set QR_SIGNING_SECRET=$(openssl rand -hex 32)
supabase secrets set APP_BASE_URL=https://itango.app

# Deploy all functions
supabase functions deploy checkins
supabase functions deploy tickets-purchase
supabase functions deploy webhooks-paystack --no-verify-jwt   # webhooks authenticate via signature, not JWT
supabase functions deploy events
supabase functions deploy nearby-events --no-verify-jwt        # public discovery, RLS still applies
supabase functions deploy discover-people
supabase functions deploy register-device-token
supabase functions deploy send-push-notification --no-verify-jwt   # invoked by DB Webhook, not a user JWT
supabase functions deploy staff-checkin
```

**Push notification wiring (one-time, in the Supabase Dashboard):**
1. Database → Webhooks → Create a new webhook: table `notifications`, event `INSERT`, HTTP request to `https://<project>.supabase.co/functions/v1/send-push-notification`.
2. Set `FCM_SERVICE_ACCOUNT_JSON` as a secret containing the full Firebase service account JSON (Project Settings → Service Accounts → Generate new private key, in the Firebase console).
3. Notification *content* (SQL triggers deciding what's worth notifying about) lives in migration 014; notification *copy* (title/body per type) lives in `send-push-notification/index.ts`'s `NOTIFICATION_COPY` map — add new types in both places together, or a new notification type will insert silently but never push.

Register the deployed webhook URL (`https://<project>.supabase.co/functions/v1/webhooks-paystack`) in the Paystack dashboard under Settings → API Keys & Webhooks.

## Known simplifications flagged for follow-up (not glossed over)

- **QR token re-signing after insert** (`tickets-purchase/index.ts`): the token is signed before the `ticket_purchases.id` exists, using a placeholder. Production implementation should either (a) use a client-generated UUID for the purchase row passed in on insert, or (b) wrap both operations in a single Postgres function that returns the ID mid-transaction for signing. Flagged explicitly in the code comment rather than silently shipped.
- **Flutterwave/Monnify/Fincra initializers**: only Paystack is implemented in full; the others follow an identical structural pattern (`providers/paystack.ts` is the template) and are Phase 5 follow-up work, not architecture that needs to change.
- **Wallet-pass generation and push notifications on successful payment**: intentionally deferred out of the synchronous webhook handler (to avoid risking the PSP's webhook timeout) — these should be enqueued to a job queue (Supabase Queues or a Redis-backed worker) as a Phase 5 follow-up, not bolted into the webhook function directly.
- **Sentry error reporting** (`_shared/sentry.ts`, see `devops/monitoring/README.md` for why it's a lightweight direct-API reporter rather than a full SDK): wired into `webhooks-paystack` as the reference example. Not yet added to the other five functions' catch blocks — a mechanical follow-up, not a design gap.

## Testing strategy (feeds into Phase 14)

1. **Contract tests against `openapi.yaml`** — every implemented endpoint validated against its schema (request and response) using a tool like Dredd or Schemathesis, so client and server can never silently drift.
2. **Webhook replay tests** — recorded real (sanitized) Paystack webhook payloads replayed against a test instance, asserting idempotency (sending the same `charge.success` event twice must not double-credit or double-decrement inventory).
3. **QR forgery tests** — ✅ implemented in `checkins/tests/qr_test.ts`: tampered payload, wrong signing secret, malformed token, and expiry are all covered with real assertions against the actual signing/verification functions, including a simulated bit-flip attack on the payload.
4. **Geofence boundary tests** — ✅ implemented in `checkins/tests/geo_test.ts`, using real Lagos coordinates as sanity checks (a haversine bug that swaps lat/lng produces a wildly wrong distance, not a subtly wrong one, so these tests would catch that class of bug specifically).
5. **Concurrency test for wallet settlement** — fire N simultaneous `settle_ticket_purchase_from_wallet` calls against a wallet with balance for exactly one purchase; exactly one should succeed, confirming the `for update` lock actually prevents overdraft.
