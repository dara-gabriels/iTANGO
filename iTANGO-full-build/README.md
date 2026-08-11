# iTANGO — Full Build Snapshot
Generated: Phase 1–7 + Phase 14 (partial) + Phase 15 (Product, Design, Database, Backend, Mobile, Web, Onboarding/Notifications/Admin, DevOps, Testing, Store Submission)

## How to read this archive

| Folder/File | What it is |
|---|---|
| `iTANGO-Master-Program-Plan.md` | Start here — full 16-phase roadmap, architecture strategy, scale-graduation triggers |
| `iTANGO-PRD.md` | MVP scope, personas, success metrics |
| `iTANGO-Design-Tokens-and-Mechanics.md` | Product mechanics extracted from the real Figma prototype (Energy Score, check-in-gated chat, voucher economy) |
| `iTANGO-Feature-Completeness-Audit.md` | **Read this to know what's actually done vs. stubbed** — updated after every build pass, no rounding up |
| `design-system/` | Single source of truth tokens + generated Flutter theme + Tailwind/CSS, reconciled to the real iTango logo |
| `database/` | 17 Postgres migrations + `tests/` (pgTAP RLS policy tests — the highest-value tests in this project) |
| `backend/` | OpenAPI spec + Supabase Edge Functions + Deno unit tests for the security-critical QR/geofence logic |
| `mobile/itango/` | Flutter app + `test/` (unit/widget tests) + `android/fastlane/`, `ios/fastlane/`, `store-assets/` (store submission automation and setup checklist) |
| `web/itango-web/` | Next.js app (public site, organizer dashboard, admin dashboard) + `e2e/` (Playwright tests) |
| `devops/` | Docker, Terraform, monitoring, incident runbook |
| `.github/workflows/` | CI, staging/production CD with rollback, Terraform plan, mobile release |

## Quick status

The consumer core loop (discover → buy ticket → check in → unlock chat → view/post stories → message with media/voice/reactions) and the organizer core loop (create → publish → sell → view sales → scan attendees in at the door) are both real end-to-end. Admin moderation, user management, and event approval (a runtime toggle, not a hardcoded choice) are wired. Production alerting now routes to Slack (all environments) and PagerDuty (production, error-level+) once the one-time integration connection is done. Test coverage exists at every layer — database RLS, backend crypto/geo logic, mobile state machines, web E2E — each with an honest README stating what's covered and what's a documented gap rather than a faked pass.

## Not yet built (as of this snapshot)

- Full Google/Apple sign-in verification end-to-end, biometric login
- Video attachments in messages and in stories (image + voice notes are real)
- Live cross-participant reaction updates (your own reactions are instant; others' need a reload)
- iOS release signing certificates (Fastlane `match` is configured; the certs themselves need Apple Developer Program enrollment)
- Full automated test coverage — what exists is real but intentionally not exhaustive; each test README says precisely where the line is
- Who's actually on the PagerDuty on-call rotation, and the response-time SLA — the alert-routing *infrastructure* is built (see `devops/scripts/setup-alerting.md`), staffing the rotation is a team decision this build pass can't make

