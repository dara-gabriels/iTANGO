# iTANGO — DevOps & Infrastructure (Phase 15)

## 1. What's actually being deployed, and what isn't

Before any Docker/Terraform/CI content, it matters to be precise about what this phase covers, because iTANGO's backend is **Supabase-managed**, not self-hosted:

| Component | Hosting | DevOps scope here |
|---|---|---|
| Postgres, Auth, Realtime, Storage | Supabase (managed) | Migrations deployment, environment separation (staging/prod projects), backup verification — **not** server provisioning, since Supabase runs it |
| Edge Functions | Supabase (managed, Deno runtime) | Deployment automation via CI, secrets management |
| Next.js web app (public site + organizer/admin dashboards) | **Self-hosted container**, per the original tech stack decision (Docker → Kubernetes-ready) | Full Docker + CI/CD + hosting platform choice (this document) |
| Flutter mobile app | App Store / Play Store | CI (lint/test/build) only — store submission requires signing certs and store credentials this environment doesn't have; flagged as a manual/Fastlane follow-up, not silently skipped |
| CDN/WAF | Cloudflare | Terraform-managed |
| Cache/Rate-limit store | Redis (Upstash, managed) | Terraform-managed |
| Error tracking | Sentry | SDK wiring (web, mobile, Edge Functions) + Terraform-managed project config |
| Product analytics | PostHog | SDK wiring only (hosted PostHog Cloud — no infra to manage) |

## 2. Container hosting platform — the decision, and why

The Master Program Plan (§7 scale strategy) already committed to "Docker → Kubernetes-ready; start on managed containers (AWS ECS/Fly.io/Fargate), migrate to EKS/GKE at a scale trigger." This phase has to pick **one** for the initial deploy. Trade-offs:

| Option | Pros | Cons |
|---|---|---|
| **Fly.io** (chosen) | Deploys a Dockerfile directly, no Kubernetes YAML to write yet; built-in health checks and zero-downtime "rolling" releases out of the box; regions close to Lagos (or at least West/South Europe, better latency to Nigeria than US-only platforms); simple Terraform provider | Smaller platform than AWS — less enterprise tooling, fewer compliance certifications if that becomes a requirement later |
| AWS ECS/Fargate | Deepest AWS ecosystem integration, easiest path to EKS later, most enterprise-credible for investor/compliance conversations | Meaningfully more Terraform/IAM complexity for zero added benefit at current scale — provisioning a VPC, ALB, ECS cluster, task definitions, and IAM roles for one Next.js container is disproportionate infrastructure for the traffic this app has today |
| Vercel | Zero-config Next.js deploys, excellent DX | **Rejected**: the original tech stack explicitly chose "Docker, Kubernetes-ready architecture" as a requirement — Vercel's platform is not a Docker/Kubernetes path, so choosing it here would quietly abandon a decision made in Phase 1 without saying so |

**Fly.io is the pick for staging and initial production**, with the documented graduation path to AWS ECS → EKS at the scale triggers already defined in the Master Program Plan. This keeps every artifact (Dockerfile, health checks, container config) portable to ECS/EKS later with no rewrite — only the Terraform "where does this container run" layer changes.

## 3. Environments

Two fully separate environments, not one environment with a flag:

| | Staging | Production |
|---|---|---|
| Supabase project | Separate project (`itango-staging`) | Separate project (`itango-production`) |
| Fly app | `itango-web-staging` | `itango-web-production` |
| Cloudflare | `staging.itango.app` | `itango.app` + `www.itango.app` |
| Deploy trigger | Push to `develop` branch | Push of a `v*` tag on `main` |
| Data | Synthetic/test data only | Real user data — **never** seeded or reset by CI |

This separation is why `database/README.md`'s migration instructions and this phase's CI workflows both take a `SUPABASE_PROJECT_REF` / environment parameter rather than hardcoding one project — the same migration files run against both, in order, but staging always runs first.

## 4. Directory contents

| Path | Purpose |
|---|---|
| `docker/Dockerfile.web` | Multi-stage production Dockerfile for the Next.js app |
| `docker/docker-compose.yml` | Local dev: web app + Redis (Supabase itself runs via `supabase start`, not Docker Compose — see note in that file) |
| `terraform/modules/cloudflare/` | DNS records, WAF rules, rate limiting |
| `terraform/modules/redis/` | Upstash Redis instance |
| `terraform/environments/staging/` and `production/` | Environment-specific variable values and Fly app definitions |
| `../.github/workflows/` | CI (every PR) and CD (staging + production deploy) pipelines |
| `monitoring/` | Sentry SDK wiring for web/mobile/Edge Functions, and an honest note on why Prometheus/Grafana/Loki aren't deployed yet |
| `scripts/` | Deployment and rollback runbook scripts |
