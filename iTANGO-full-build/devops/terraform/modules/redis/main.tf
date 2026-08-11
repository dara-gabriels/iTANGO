# devops/terraform/modules/redis/main.tf
#
# Upstash Redis — used for feed-ranking cache, rate limiting counters
# (application-level, complementing the Cloudflare edge rate limits), and
# session/presence data. Upstash is chosen over self-hosted Redis for the
# same reason Fly.io was chosen over raw EC2: it's the managed option that
# matches "minimal scale architecture able to grade up" — a self-managed
# Redis Cluster only becomes worth the operational cost at the scale
# triggers already documented in the Master Program Plan §7, not before.

variable "environment" {
  type = string
}

resource "upstash_redis_database" "main" {
  database_name = "itango-${var.environment}"
  region        = "eu-west-1" # closest Upstash region to both Fly's ams region and Lagos
  tls           = true

  # Staging runs on Upstash's free/pay-as-you-go tier; production gets
  # eviction disabled, since losing rate-limit or session data unexpectedly
  # in production is a worse failure mode than paying for guaranteed capacity.
  eviction = var.environment == "production" ? false : true
}

output "redis_url" {
  value     = upstash_redis_database.main.endpoint
  sensitive = false
}

output "redis_password" {
  value     = upstash_redis_database.main.password
  sensitive = true
}
