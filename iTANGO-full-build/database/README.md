# iTANGO Database — Phase 4 Deliverable

## Contents

| File | Covers |
|---|---|
| `01-ERD-and-design-decisions.md` | ERD (Mermaid), rationale for the non-obvious schema decisions, indexing strategy, scale-graduation notes |
| `migrations/001_extensions_enums_identity.sql` | PostGIS/citext/trigram extensions, all enums, `profiles`, badges, vibe tags, follows/friendships |
| `migrations/002_businesses_venues_communities.sql` | Businesses, venues (geo-indexed), communities |
| `migrations/003_events_ticketing_checkins.sql` | Events, RSVPs, **check-ins** (the core trust primitive), tickets, ticket purchases, reviews |
| `migrations/004_messaging.sql` | Conversations (DM/group/event-room), messages, reactions, room engagement snapshots, check-in → auto-join trigger |
| `migrations/005_payments_wallets_vouchers.sql` | Payments ledger (multi-PSP), split payments, wallets, voucher economy, organizer payouts |
| `migrations/006_energy_score_achievements.sql` | Energy score ledger + recompute functions, percentile job, achievements |
| `migrations/007_social_feed.sql` | Posts, likes, comments, bookmarks, stories, highlights |
| `migrations/008_moderation_audit_notifications.sql` | Reports, moderation actions, immutable audit log, notifications |
| `migrations/009_app_roles.sql` | Admin/moderator/organizer role table + RLS helper functions |
| `migrations/010_rls_policies.sql` | Row Level Security policies for every sensitive table |
| `migrations/011_query_functions.sql` | `nearby_events`, `discover_people`, `home_feed_posts` — the highest-QPS screens, as indexed SQL functions rather than N+1 client queries |
| `migrations/012_wallet_settlement_function.sql` | Atomic wallet debit function (`FOR UPDATE` row lock, avoids overdraft under concurrent purchases) — added during Phase 5, called by the `tickets-purchase` Edge Function for wallet payments |
| `migrations/013_find_dm_conversation.sql` | Helper used by the chat feature's "start or get DM" flow, so Discover's "Say Hi" and Profile's "Message" converge on one thread instead of duplicating conversations |
| `migrations/014_push_notifications.sql` | `device_tokens` table + triggers that populate `notifications` for new messages, check-ins, ticket confirmations, and achievements |
| `migrations/015_admin_moderation.sql` | Ban/unban functions with audit-log writes, scoped to admin/moderator roles |
| `migrations/016_event_approval_workflow.sql` | `platform_settings` toggle for self-publish vs. admin-approval-required, plus `publish_event`/`approve_event`/`reject_event` functions |
| `migrations/017_fix_events_visibility_status_check.sql` | **Security fix** — the original public-visibility RLS policy (migration 010) never checked event `status`, meaning a draft/pending event marked "public" was visible to anyone. Fixed here; see the file's own comment for why it's a new migration rather than an edit to 010. |
| `migrations/018_message_media_storage_rls.sql` | Storage RLS for the private `message-media` bucket — scopes attachment reads to conversation participants only |
| `migrations/019_staff_checkin_rls.sql` | RLS policy allowing an event's organizer (or an admin) to insert a check-in on an attendee's behalf — required for the staff QR check-in flow; the original check-in policy only allowed self-insert |

## Running the migrations

```bash
# Local (Supabase CLI)
supabase db reset               # applies all migrations in migrations/ in filename order
supabase migration list         # verify order/status

# Or directly against a Postgres connection string
for f in migrations/*.sql; do
  psql "$DATABASE_URL" -f "$f"
done
```

Migrations are numbered and must run in order — later files reference tables/columns created in earlier ones (e.g. `profiles.currently_at_event_id` FK is added in migration 003 after `events` exists, since it would otherwise be a forward reference within migration 001).

## What's intentionally deferred to Phase 5 (Backend APIs)

- Edge Function implementations that call these tables/functions (e.g. the actual Paystack webhook handler that inserts into `payments`)
- Storage bucket policies for media (avatars, event covers, post media) — schema references `*_url text` columns; bucket-level RLS is a Supabase Storage concern, covered in Phase 5
- Full-text/semantic search (pgvector embeddings for AI-powered recommendations) — intentionally not in Phase 4, since it depends on the AI Engineer's embedding strategy in Phase 13

## Testing (see `tests/README.md` for full detail)

Real pgTAP tests exist now, not just a described approach:

1. **`tests/001_rls_policies_test.sql`** — the highest-value test file in this project: check-in privacy, the check-in-gated-chat trust boundary, payment isolation, audit-log immutability, voucher ownership, profile write scoping.
2. **`tests/002_event_approval_test.sql`** — proves the migration 017 fix holds: a pending/unapproved event stays invisible to the public even with `visibility = 'public'` set.
3. **`tests/003_staff_checkin_rls_test.sql`** — proves an organizer can check in an attendee on their behalf, but a random user cannot check anyone into someone else's event.

Run via `supabase test db`. Coverage gaps are documented explicitly in `tests/README.md` rather than implied to be exhaustive.

## Further testing strategy (feeds into Phase 14)

4. **Migration idempotency test** — `supabase db reset` twice in CI, confirm no errors. Automated in `.github/workflows/ci.yml`'s `database-ci` job.
5. **Trigger correctness tests** — insert a `check_ins` row, assert: `events.live_attendee_count` incremented, `energy_score_events` row created with `reason = 'event_checkin'`, `profiles.energy_score` recomputed, and the user was added to the event's `conversation_participants`. Not yet a dedicated pgTAP file — the RLS tests above exercise this path indirectly but don't assert on it directly.
6. **Load test targets** — `nearby_events` and `discover_people` are called on nearly every app open; benchmark p95 latency at expected concurrent-user counts before mobile integration locks in assumptions about client-side caching needs.
