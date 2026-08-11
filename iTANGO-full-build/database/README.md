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

## Testing approach for this schema (feeds into Phase 14)

1. **Migration idempotency test** — `supabase db reset` twice in CI, confirm no errors.
2. **RLS policy tests** — for each policy in `010_rls_policies.sql`, a paired test asserting both the allowed case and the denied case (e.g. "user A cannot read user B's `check_ins` row"; "user A can read their own"). This is the single highest-value test suite in the whole schema — an RLS gap is a data breach, not a bug.
3. **Trigger correctness tests** — insert a `check_ins` row, assert: `events.live_attendee_count` incremented, `energy_score_events` row created with `reason = 'event_checkin'`, `profiles.energy_score` recomputed, and the user was added to the event's `conversation_participants`.
4. **Load test targets** — `nearby_events` and `discover_people` are called on nearly every app open; benchmark p95 latency at expected concurrent-user counts before Phase 7 mobile integration locks in assumptions about client-side caching needs.
