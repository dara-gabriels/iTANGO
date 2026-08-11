# devops/scripts/setup-alerting.md

## Honest framing

Same pattern as `setup-supabase-projects.md` and `mobile/itango/store-assets/STORE_SUBMISSION_SETUP.md`:
the Terraform module (`devops/terraform/modules/sentry-alerts/`) automates
**alert rules** (what fires when), but the underlying **integration
connections** (Sentry ↔ Slack, Sentry ↔ PagerDuty) require an OAuth
handshake in each service's UI that no Terraform provider can complete on
your behalf. This is the one-time checklist for that handshake.

## 1. Connect Slack (free, ~5 minutes)

1. Sentry → Settings → Integrations → Slack → Add Workspace.
2. Authorize Sentry to post to your workspace.
3. Create two channels if they don't exist: `#itango-staging-alerts`,
   `#itango-production-alerts`. Separate channels, not one — staging noise
   should never bury a production signal.
4. Find the integration ID: `GET https://sentry.io/api/0/organizations/{org}/integrations/`
   with your Sentry auth token — this is `slack_integration_id` in Terraform.

## 2. Connect PagerDuty (free tier: up to 5 users, no credit card required)

**Only needed for production paging.** Skip this if the team is small
enough that "someone sees the Slack message" is an acceptable response
time for now — Slack-only alerting (step 1) is a completely reasonable
starting point, and PagerDuty is worth adding when there's an actual
on-call rotation to route to, not before.

1. Create a free PagerDuty account at pagerduty.com.
2. Create a Service named `itango-production-oncall` (Services → New Service).
3. Set up an escalation policy — even a one-person policy ("page this person, and if unacknowledged in 15 min, page them again") is better than PagerDuty's default of paging no one.
4. PagerDuty → Integrations → add the Sentry integration to the service, which generates an integration key.
5. In Sentry: Settings → Integrations → PagerDuty → Add Installation, paste the key.
6. Find the integration ID the same way as Slack's, for `pagerduty_integration_id` in Terraform.

## 3. Apply the Terraform module

```bash
cd devops/terraform/environments/production
terraform apply -var="sentry_auth_token=$SENTRY_TOKEN" \
                 -var="sentry_org=itango" \
                 -var="slack_integration_id=$SLACK_INTEGRATION_ID" \
                 -var="pagerduty_integration_id=$PAGERDUTY_INTEGRATION_ID" \
                 # ...plus the cloudflare/upstash vars from before
```

Repeat for staging without the PagerDuty variable.

## 4. What this actually gets you

| Severity | Environment | Routes to |
|---|---|---|
| Any new issue | Staging | Slack `#itango-staging-alerts` |
| Any new issue | Production | Slack `#itango-production-alerts` |
| Error-level or above, first occurrence | Production only | **Slack AND PagerDuty** (pages whoever's on-call) |

This directly answers the gap flagged in the Feature Completeness Audit —
"Sentry captures errors; nothing pages a human yet." After this setup,
something does. What it does NOT do: define who's actually on the PagerDuty
rotation, what the response-time SLA is, or what happens if the on-call
person doesn't respond — those are team/process decisions this build pass
can't make on your behalf, tracked as open items in
`devops/scripts/incident-runbook.md`'s On-Call Escalation section.
