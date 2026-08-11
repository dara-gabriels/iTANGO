# iTANGO — Feature Completeness Audit
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
