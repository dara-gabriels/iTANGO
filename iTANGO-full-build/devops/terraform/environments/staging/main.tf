# devops/terraform/environments/staging/main.tf

module "cloudflare" {
  source = "../../modules/cloudflare"

  zone_id          = var.cloudflare_zone_id
  environment      = "staging"
  subdomain        = "staging"
  fly_app_hostname = "itango-web-staging.fly.dev"
  root_domain      = var.root_domain
}

module "redis" {
  source      = "../../modules/redis"
  environment = "staging"
}

module "sentry_alerts" {
  source                = "../../modules/sentry-alerts"
  sentry_org            = var.sentry_org
  sentry_project        = var.sentry_project
  environment           = "staging"
  slack_integration_id  = var.slack_integration_id
  slack_channel         = "#itango-staging-alerts"
  # No pagerduty_integration_id passed for staging — deliberately: staging
  # errors get a Slack post, never a page, per the module's own design note.
}

output "staging_hostname" {
  value = module.cloudflare.hostname
}

output "staging_redis_url" {
  value = module.redis.redis_url
}
