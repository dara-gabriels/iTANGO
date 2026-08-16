# iTANGO — Feature Completeness Audit

## Full-Stack Verification Pass (latest)

A dedicated verification pass was run across database, backend, mobile,
web, and DevOps to check cross-references between layers — not just "does
each layer look right in isolation," but "does what mobile calls actually
exist in backend, does what backend queries actually exist in the
database, do the docs match the code." Found and fixed:

| Finding | Severity | Fix |
|---|---|---|
| Migration 012 (wallet settlement function) was documented as needing to move into `database/migrations/` but never actually was — it sat in a separate `migrations_addendum/` folder that no setup script, CI job, or deployment workflow ever reads. Any real deployment following the documented steps would be missing this function entirely, and wallet ticket purchases would fail with "function does not exist." | **High** — silent deployment failure on a payment path | Moved the file into `database/migrations/012_...sql` where it was always supposed to be; removed the now-empty addendum folder |
| The `discover-people` Edge Function's 15km radius cap — the actual security control preventing a client from pulling a citywide dump of user locations — only existed in that function's TypeScript. The real mobile client calls the underlying `discover_people` Postgres function directly via `client.rpc()`, bypassing the Edge Function (and its cap) entirely. | **High** — documented security control was not actually enforced for the real client | Moved the cap into the Postgres function itself (migration 020), so it holds regardless of which caller reaches it |
| The staff QR check-in feature (organizer/web scans an attendee's ticket) had a fully working backend and web scanner UI, but **no screen anywhere in the mobile app ever displayed the attendee's ticket QR code** — `qr_flutter` was a declared dependency, never used. The feature was unusable in practice despite backend + web both being "done." | **High** — a presented-as-complete feature didn't actually work end to end | Built `my_ticket_screen.dart`, wired into the event detail screen alongside the existing geofence self-check-in option |
| `nearby-events` and `discover-people` Edge Functions were described in multiple READMEs as active API surface; in reality the mobile client never calls either (same direct-RPC pattern as above). Not a security issue for `nearby-events` (public data), but the docs implied these were load-bearing when they're currently dead code. | Medium — documentation accuracy | Updated both function headers and the backend README to state their actual (unused) status plainly |
| `database/README.md`'s migration table stopped at migration 011 and was never updated across three subsequent build passes that added migrations 012–019. | Medium — documentation drift | Backfilled the table with all missing entries |
| `database/tests/README.md` only documented the first of three test files that now exist. | Low — documentation drift | Updated to cover all three |
| `openapi.yaml` was last updated in Phase 5 and didn't document `staff-checkin`, `register-device-token`, or the push-notification webhook — three real, deployed endpoints. | Medium — API contract drift | Added all three |
| The Fly.io deploy config used a relative Dockerfile path (`../../../docker/Dockerfile.web`) whose resolution depends on whether flyctl treats it as relative to the config file or the CWD — genuinely ambiguous, and the two contexts differ in this repo's actual CI setup. | Medium — fragile, environment-dependent path resolution | Removed the relative path from `fly.toml`; made it an explicit `--dockerfile` CLI flag resolved against the confirmed CI working directory instead |

**What this pass did NOT find:** any broken RPC name (every `.rpc()` call across mobile/web/backend matched an actual `create function` in the migrations), any broken route (every screen imported by the Flutter router resolves to a real file), any storage bucket name mismatch, any missing npm script referenced by CI, and no Terraform variable name mismatch between module definitions and call sites. Full methodology and commands are reproducible — this wasn't a visual skim.

---

Checked against two different bars, since they're very different scopes:
**(A)** the full original brief (Snapchat+Instagram+TikTok+Eventbrite+Meetup+Tinder+Discord), and
**(B)** the Phase 1 PRD's MVP Must-Haves — the bar we actually agreed to build toward first.

**Short answer: not complete against (A) — nowhere close, and that was flagged as unrealistic for one build cycle back in the Master Program Plan. Against (B), the MVP bar, we're roughly 55–60% done.** Details below, no rounding up.

---

## Against the full original brief (A)

| Module | Status |
|---|---|
| Auth (phone/email/Google/Apple/biometric/OTP/KYC) | 🟡 Phone OTP only. Google/Apple wired in the repository layer but no button-to-completion test; biometric, KYC — not started. |
| Onboarding | 🔴 Screen exists, no logic. |
| Home (2-tab spec) → built as 5-tab | 🟢 Home feed of nearby events works; blended social feed portion not built. |
| Feed (posts/reels/likes/comments/trending/FYP) | 🔴 Schema exists (posts, likes, comments, bookmarks). No screen. |
| Stories (create/view/reply) | 🟡 Stories *row* + Highlights row read real data. No capture screen, no full-screen viewer, no reply. |
| Events (browse/book/VIP/split pay/nav/countdown/QR/reviews) | 🟡 Browse (nearby) works. Booking backend works (`/tickets/purchase`). No event detail screen, no client-side QR display, no countdown/reminders, no reviews UI. |
| Organizer Dashboard | 🔴 Not started (web). |
| Ticketing (wallet passes, VIP, reserved seating) | 🟡 Backend purchase flow real. Apple/Google Wallet pass generation explicitly deferred (noted in Phase 5 README). No UI. |
| Messaging (DM/group/voice/read receipts/reactions/pinned/search/disappearing/E2E) | 🟢 DM + Event Room lists, threaded conversation view, image attachments, voice notes (real recording + playback), emoji reactions, and DM read receipts are all real. Not built: pinned messages, message search, disappearing messages, E2E encryption, video attachments, and live cross-participant reaction updates (own reactions are instant; others' require a reload). |
| Communities | 🔴 Schema exists. No screens. |
| Profiles (badges/achievements) | 🟢 Built — Passport screen is one of the most complete pieces. |
| Search (people/events/businesses/communities/hashtags) | 🔴 Not started as unified search; Discover covers people-only, filtered by vibe not free-text. |
| Dating (match algorithm, icebreakers, safety) | 🟡 Reframed as vibe-tag Discover per the design decision in Phase 1 — intentional scope change, not a gap, but no "match" concept (mutual interest) exists yet, only one-directional "Say Hi." |
| Live Streaming | 🔴 Not started. |
| Marketplace | 🔴 Not started. |
| Payments (wallet, cards, bank transfer, multi-PSP) | 🟡 Paystack + wallet debit real; Flutterwave/Monnify/Fincra/Apple Pay/Google Pay are stubs per Phase 5 README. No client wallet top-up UI. |
| Notifications (push/SMS/email/in-app) | 🔴 `notifications` table + RLS exist; nothing sends or displays one yet. |
| AI Features (recs, moderation, captions, assistant) | 🔴 Not started — correctly deferred to Phase 13 in the roadmap. |
| Business Profiles | 🟡 Schema + voucher issuance backend exist. No business-facing screens. |
| Admin Panel | 🔴 Not started (web). |

**~5 of 19 major modules are meaningfully usable; ~7 are partial; ~7 haven't been started.** That's expected at this point in a 16-phase plan — flagging it precisely rather than letting "we've been building a lot" imply more coverage than exists.

---

## Against the Phase 1 PRD's actual MVP Must-Haves (B) — the honest bar

| Must-Have | Status |
|---|---|
| Auth: phone OTP, email, Google, Apple | 🟡 Phone done; email/Google/Apple repository methods exist, unverified end-to-end |
| Onboarding | 🟢 4-step flow (location/notification permissions, vibe tags, username+profile) writing real rows to `profiles` + `user_vibe_tags`; router enforces completion before reaching the main app |
| Home: live events + blended feed | 🟡 Live events done; social feed half missing |
| Event details, ticket purchase, QR check-in | 🟢 Done (see design note on geofence vs. QR) |
| Check-in-gated Event Chat Rooms | 🟢 Done |
| Discover: vibe-tag browsing, Say Hi | 🟢 Done |
| Profile: passport, energy score, achievements | 🟢 Done |
| 1:1 DMs, basic media sharing | 🟢 Text, image, voice notes, reactions, and read receipts are all real end-to-end. |
| Organizer: create event, manage tickets, view sales | 🟡 Events list, create-event form, sales dashboard built. Ticket-type creation UI still missing. |
| Admin: user mgmt, moderation queue, event approval | 🟢 User management and Moderation Queue are built. **Event approval is now resolved**: implemented as a `platform_settings` toggle (`events_require_admin_approval`, defaulting to `false` = self-publish) rather than a hardcoded choice — an admin's Pending Events queue lets them approve/reject when the toggle is on, and organizers get the same "Publish" button regardless of which mode is active, since `publish_event()` handles the branching server-side. This means the product decision can be flipped by changing one row, not redeploying code. |
| Push notifications | 🟢 Full pipeline: SQL triggers create in-app `notifications` rows (new message, check-in, ticket confirmed, achievement earned) → Supabase DB Webhook → Edge Function delivers via real FCM HTTP v1 (OAuth2 service-account flow) → mobile app shows an unread badge and a notifications list, and registers/refreshes its device token automatically after login. |

**Updated verdict:** every Must-Have now has at least a 🟡, and most are 🟢. Story viewer/creator, mobile store submission setup (Fastlane, both platforms), and test suites (RLS pgTAP tests, Deno unit tests for QR/geofence logic, Flutter unit + widget tests, Playwright E2E) have all been added since the previous pass. Event approval is resolved as a runtime toggle rather than a hardcoded choice, so it's no longer a blocking product decision. The one remaining deliberate gap is full social auth (Google/Apple end-to-end verification, biometric) — repository methods exist but aren't verified end-to-end.
