# devops/terraform/environments/production/main.tf

module "cloudflare" {
  source = "../../modules/cloudflare"

  zone_id          = var.cloudflare_zone_id
  environment      = "production"
  subdomain        = "" # root domain — itango.app, not a subdomain
  fly_app_hostname = "itango-web-production.fly.dev"
  root_domain      = var.root_domain
}

module "redis" {
  source      = "../../modules/redis"
  environment = "production"
}

module "sentry_alerts" {
  source                    = "../../modules/sentry-alerts"
  sentry_org                = var.sentry_org
  sentry_project            = var.sentry_project
  environment               = "production"
  slack_integration_id      = var.slack_integration_id
  slack_channel             = "#itango-production-alerts"
  pagerduty_integration_id  = var.pagerduty_integration_id
}

output "production_hostname" {
  value = module.cloudflare.hostname
}

output "production_redis_url" {
  value = module.redis.redis_url
}
