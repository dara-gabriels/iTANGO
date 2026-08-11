# devops/terraform/modules/sentry-alerts/main.tf
#
# Manages Sentry ISSUE ALERT RULES — i.e., "when an error matching X
# happens, notify Y." Does NOT and CANNOT manage the underlying Slack/
# PagerDuty integration CONNECTIONS themselves: those go through an OAuth
# handshake in the Sentry UI (Settings → Integrations) that has no
# Terraform-manageable equivalent. This module assumes those integrations
# already exist and references them by name — see
# devops/scripts/setup-alerting.md for the one-time manual connection step
# this depends on, same pattern as Supabase project creation or Apple/Google
# developer account setup elsewhere in this repo.

terraform {
  required_providers {
    sentry = {
      source  = "jianyuan/sentry"
      version = "~> 0.14"
    }
  }
}

variable "sentry_org" {
  type = string
}
variable "sentry_project" {
  type = string
}
variable "environment" {
  type = string
}
variable "slack_integration_id" {
  type        = string
  description = "Internal ID of the already-connected Slack integration (find via Sentry API: GET /api/0/organizations/{org}/integrations/)"
}
variable "slack_channel" {
  type = string
}
variable "pagerduty_integration_id" {
  type        = string
  description = "Internal ID of the already-connected PagerDuty integration. Only required/used for the production environment — see the critical-alert rule below."
  default     = null
}

# -----------------------------------------------------------------------------
# CRITICAL: any error tagged environment=production fires a PagerDuty
# incident (actually pages someone) in addition to Slack. This is the
# highest-severity rule and the only one that should ever wake someone up.
# Restricted to production specifically — a staging error should never page
# anyone at 3am; it should just be visible the next morning.
# -----------------------------------------------------------------------------
resource "sentry_issue_alert" "critical_production" {
  count        = var.environment == "production" && var.pagerduty_integration_id != null ? 1 : 0
  organization = var.sentry_org
  project      = var.sentry_project
  name         = "Critical: Production Error to Page On-Call"

  action_match = "all"
  filter_match = "all"
  frequency    = 30 # don't re-fire for the same issue more than once per 30 minutes

  conditions = jsonencode([
    { id = "sentry.rules.conditions.first_seen_event.FirstSeenEventCondition" },
  ])

  filters = jsonencode([
    { id = "sentry.rules.filters.tagged_event.TaggedEventFilter", key = "environment", match = "eq", value = "production" },
    { id = "sentry.rules.filters.level.LevelFilter", match = "gte", level = "40" }, # 40 = error level or above (error, fatal) — not warnings
  ])

  actions = jsonencode([
    {
      id      = "sentry.integrations.pagerduty.notify_action.PagerDutyNotifyServiceAction"
      account = var.pagerduty_integration_id
      service = "itango-production-oncall"
    },
    {
      id        = "sentry.integrations.slack.notify_action.SlackNotifyServiceAction"
      workspace = var.slack_integration_id
      channel   = var.slack_channel
    },
  ])
}

# -----------------------------------------------------------------------------
# Everything else (warnings, staging errors, non-first-seen recurring
# issues): Slack only. Visible to the team, doesn't wake anyone up.
# -----------------------------------------------------------------------------
resource "sentry_issue_alert" "general_slack" {
  organization = var.sentry_org
  project      = var.sentry_project
  name         = "${var.environment}: New Issue to Slack"

  action_match = "all"
  filter_match = "all"
  frequency    = 60

  conditions = jsonencode([
    { id = "sentry.rules.conditions.first_seen_event.FirstSeenEventCondition" },
  ])

  filters = jsonencode([
    { id = "sentry.rules.filters.tagged_event.TaggedEventFilter", key = "environment", match = "eq", value = var.environment },
  ])

  actions = jsonencode([
    {
      id        = "sentry.integrations.slack.notify_action.SlackNotifyServiceAction"
      workspace = var.slack_integration_id
      channel   = var.slack_channel
    },
  ])
}
