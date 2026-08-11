# devops/scripts/incident-runbook.md

## The one thing to understand before anything else

**Automatic rollback (via `deploy-production.yml`) only reverts the web
app's container image. It does NOT revert database migrations.** This is
not an oversight — automatically reversing a schema migration in production
is often more dangerous than the bug that triggered the rollback (e.g. a
migration that added a NOT NULL column and backfilled it: reverting it
without also reverting every row written since could silently corrupt
data). Schema rollback is always a deliberate, human-reviewed decision.

Practical implication: if a release's smoke test fails and the web app auto
rolls back, but that release *also* included a migration, the rolled-back
web app is now running against a database schema from a slightly newer
release than the code expects. This is usually fine for additive migrations
(new tables/columns the old code just doesn't use) and NOT fine for
migrations that renamed or removed something the old code still reads.
**Check the migration diff for the failed release before assuming rollback
fixed everything.**

---

## Scenario: Production smoke test failed, auto-rollback fired

1. Confirm the rollback actually completed: `flyctl status --config devops/terraform/environments/production/fly.production.toml`
2. Check what migration(s) shipped in the failed release: look at `database/migrations/` diff for that tag.
3. If the migration was purely additive (new table, new nullable column, new function) — no further action needed, the rolled-back code simply won't use the new schema yet.
4. If the migration altered or removed something — this needs a human decision, not automation:
   - Write a forward-fix migration (never edit a migration file that already ran in production — see database/README.md)
   - Or restore the previous code version's compatibility by fixing the actual bug and re-releasing, rather than fighting the schema
5. Check Sentry (see `devops/monitoring/`) for the actual error that failed the smoke test / caused the issue — the health check endpoint is intentionally shallow (see its code comment) and won't tell you *why* something's wrong, only *that* something is.

## Scenario: Need to roll back manually (not via the automated path)

```bash
# Find the previous working release's image
flyctl releases --config devops/terraform/environments/production/fly.production.toml

# Roll back to it
flyctl deploy --config devops/terraform/environments/production/fly.production.toml \
  --image <previous-image-ref> --strategy immediate --remote-only
```

## Scenario: Paystack webhook signature failures spiking

Check `audit_logs` for `action = 'webhook_signature_failed'` entries
(written by `webhooks-paystack/index.ts` on every failed verification).
A spike usually means either:
- Paystack rotated their webhook secret and `PAYSTACK_SECRET_KEY` wasn't updated (check Paystack dashboard vs. Supabase secret)
- Someone is probing the webhook endpoint (expected occasionally, not actionable unless sustained)

## Scenario: A user reports they were double-charged for a ticket

The `payments` table's `unique (provider, provider_reference)` constraint
(migration 005) makes true double-charging at the database level structurally
impossible for a single payment reference — check whether this is actually
two *separate* payment attempts (e.g. they retried after a slow response)
by querying `payments` for that user_id around the timestamp in question.
If it's genuinely two successful charges, the refund path is a manual
Paystack dashboard action today — no self-serve refund UI exists yet
(tracked in the Feature Completeness Audit).

## On-call escalation

Alert routing is now wired (see `devops/scripts/setup-alerting.md` for the
one-time Slack/PagerDuty connection this depends on, and
`devops/terraform/modules/sentry-alerts/` for the rules themselves):

- Any new issue in staging or production posts to a dedicated Slack channel.
- A production error (or worse), on first occurrence, additionally pages
  whoever's on the PagerDuty rotation for the `itango-production-oncall`
  service.

**What is still a genuine open decision, not an engineering gap:**
- **Who is actually on the PagerDuty rotation.** The setup doc creates the
  service and an escalation policy skeleton; populating it with real
  people and a real schedule is a team decision.
- **Response-time SLA** — how long before an unacknowledged page escalates
  further, and to whom.
- **What "resolved" means for a page** — does the on-call person just fix
  it, or is there a postmortem requirement above some severity threshold.

None of these can be answered by this build pass; they're operational
decisions for whoever runs iTANGO day-to-day. The infrastructure to act on
those decisions once made now exists — it didn't before.
