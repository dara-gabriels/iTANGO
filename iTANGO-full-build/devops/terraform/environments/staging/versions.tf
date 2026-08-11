# devops/terraform/environments/staging/versions.tf
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 4.0" }
    upstash    = { source = "upstash/upstash", version = "~> 1.5" }
    sentry     = { source = "jianyuan/sentry", version = "~> 0.14" }
  }
  cloud {
    organization = "itango"
    workspaces { name = "itango-staging" }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "upstash" {
  email   = var.upstash_email
  api_key = var.upstash_api_key
}

provider "sentry" {
  token = var.sentry_auth_token
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}
variable "cloudflare_zone_id" {
  type = string
}
variable "upstash_email" {
  type      = string
  sensitive = true
}
variable "upstash_api_key" {
  type      = string
  sensitive = true
}
variable "root_domain" {
  type    = string
  default = "itango.app"
}
variable "sentry_auth_token" {
  type      = string
  sensitive = true
}
variable "sentry_org" {
  type = string
}
variable "sentry_project" {
  type    = string
  default = "itango-web-staging"
}
variable "slack_integration_id" {
  type = string
}
