# devops/terraform/modules/cloudflare/main.tf
#
# Manages DNS + edge security for one environment (staging or production).
# Called once per environment from environments/<env>/main.tf with a
# different subdomain and Fly app target.

variable "zone_id" {
  type = string
}
variable "environment" {
  type = string
}
variable "subdomain" {
  type        = string
  description = "e.g. 'staging' or '' (empty = root domain) for production"
}
variable "fly_app_hostname" {
  type = string
}
variable "root_domain" {
  type = string
}

locals {
  record_name = var.subdomain == "" ? var.root_domain : "${var.subdomain}.${var.root_domain}"
}

# -----------------------------------------------------------------------------
# DNS — proxied through Cloudflare (orange-cloud) so WAF/rate-limiting rules
# below actually apply; a DNS-only (grey-cloud) record would bypass them.
# -----------------------------------------------------------------------------
resource "cloudflare_record" "web" {
  zone_id = var.zone_id
  name    = var.subdomain == "" ? "@" : var.subdomain
  type    = "CNAME"
  content = var.fly_app_hostname
  proxied = true
  ttl     = 1 # automatic, required when proxied = true
}

# -----------------------------------------------------------------------------
# WAF — managed ruleset with OWASP Core Rule Set enabled. This is the
# concrete implementation of "OWASP Top 10" and "DDoS Protection" from the
# Master Program Plan's security baseline — enforced at the edge, before
# traffic ever reaches the Next.js container or Supabase.
# -----------------------------------------------------------------------------
resource "cloudflare_ruleset" "waf_managed" {
  zone_id     = var.zone_id
  name        = "${var.environment}-managed-waf"
  description = "OWASP Core Rule Set + Cloudflare Managed Rules"
  kind        = "zone"
  phase       = "http_request_firewall_managed"

  rules {
    action = "execute"
    action_parameters {
      id = "efb7b8c949ac4650a09736fc376e9aee" # Cloudflare Managed Ruleset
    }
    expression  = "true"
    description = "Run Cloudflare Managed Ruleset on all requests"
    enabled     = true
  }
}

# -----------------------------------------------------------------------------
# Rate limiting — protects the most abuse-prone endpoints specifically:
# OTP request (SMS-bombing target) and the public API surface generally.
# Ticket purchase and check-in are deliberately NOT rate-limited here at the
# edge beyond the general API rule — those already have application-level
# protections (unique constraints, signed tokens) and an overly aggressive
# edge rate limit risks blocking a genuine burst of people checking into a
# popular event at the same moment, which is exactly when this app should
# work best, not worst.
# -----------------------------------------------------------------------------
resource "cloudflare_ruleset" "rate_limit_otp" {
  zone_id     = var.zone_id
  name        = "${var.environment}-rate-limit-otp"
  description = "Limit phone/email OTP requests to prevent SMS-bombing abuse"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules {
    action      = "block"
    expression  = "(http.request.uri.path contains \"/auth/v1/otp\")"
    description = "Max 5 OTP requests per phone/IP per 10 minutes"
    enabled     = true

    ratelimit {
      characteristics     = ["cf.colo.id", "ip.src"]
      period              = 600
      requests_per_period = 5
      mitigation_timeout  = 600
    }
  }
}

resource "cloudflare_ruleset" "rate_limit_api" {
  zone_id     = var.zone_id
  name        = "${var.environment}-rate-limit-api-general"
  description = "General API abuse protection"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules {
    action      = "challenge" # challenge, not outright block — legitimate heavy users shouldn't be locked out
    expression  = "(http.request.uri.path contains \"/functions/v1/\")"
    description = "Challenge if a single IP exceeds 300 Edge Function calls/minute"
    enabled     = true

    ratelimit {
      characteristics     = ["ip.src"]
      period              = 60
      requests_per_period = 300
      mitigation_timeout  = 60
    }
  }
}

output "hostname" {
  value = local.record_name
}
