# devops/monitoring/ — Observability

## Honest scope note (read this first)

The Master Program Plan's tech stack lists Prometheus + Grafana + Loki
alongside Sentry and PostHog. **Prometheus/Grafana/Loki are not deployed
in this build, and shouldn't be yet** — here's why, not just "not done":

Prometheus works by *scraping* metrics endpoints on long-running processes.
iTANGO's current architecture has exactly one long-running process (the
Next.js container on Fly) and otherwise runs on managed serverless
platforms (Supabase Edge Functions, Supabase's own Postgres/Auth/Realtime)
that don't expose a scrapable metrics endpoint to self-host Prometheus
against — Supabase provides its own dashboard metrics for its managed
services instead. Standing up Prometheus+Grafana+Loki today would mean
operating a monitoring stack that watches one container, while the actual
backend (Supabase) is observed through a completely different, already-
provided dashboard. That's operational overhead with no matching benefit.

**This becomes worth deploying at the scale-graduation point already
documented in the Master Program Plan §7** — specifically, once the
Realtime/Messaging service is split into its own dedicated, self-managed
workload (the ">10k concurrent WebSocket connections" trigger), because at
that point there's a real fleet of long-running processes worth scraping.
Until then:

| Concern | What actually covers it today |
|---|---|
| Application errors (web, mobile, Edge Functions) | **Sentry** — wired below |
| **Alert routing / on-call paging** | **Sentry → Slack (all environments) + Sentry → PagerDuty (production, error-level+)** — see `devops/terraform/modules/sentry-alerts/` and `devops/scripts/setup-alerting.md` |
| Product analytics, funnels | **PostHog** — SDK wiring below |
| Container-level health | Fly.io's built-in metrics dashboard (CPU/memory/request latency per machine) |
| Database performance | Supabase Dashboard's built-in query performance / connection pool views |
| Uptime | The `/api/health` endpoint + smoke tests in the CD workflows |

## What's wired in this directory

| File | Purpose |
|---|---|
| `sentry.client.config.ts` / `sentry.server.config.ts` / `sentry.edge.config.ts` (in `web/itango-web/`) | Next.js Sentry SDK — client, Node server, and Edge runtime each need separate init files per `@sentry/nextjs`'s requirements |
| `web/itango-web/src/lib/analytics/posthog-provider.tsx` | PostHog wired for the **web app only**, into the root layout |
| `main.dart` (mobile) | `SentryFlutter.init()` wraps the whole app — session replay explicitly disabled, same rationale as web (this app renders other users' photos/messages on screen) |
| `../../backend/supabase/functions/_shared/sentry.ts` | Lightweight direct-to-Sentry-API error reporter for Edge Functions — **not** the full `@sentry/node` or similar SDK, because Supabase's Edge Runtime is a bespoke Deno environment without a verified-compatible official Sentry SDK at time of writing. Wired into `webhooks-paystack` as the reference example; the other five functions need the same three-line addition. |

**Not yet wired:** PostHog for the mobile app (`posthog-flutter` is not in `pubspec.yaml`) — web product analytics exist, mobile doesn't yet. Flagged rather than silently assumed covered by the web SDK, which it isn't.
