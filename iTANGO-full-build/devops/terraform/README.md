# devops/terraform/ — Usage

## Structure

Each environment (`environments/staging/`, `environments/production/`) is a
**fully independent Terraform root module** — not a single config applied
twice with a `-var-file`. This is deliberate: it makes it structurally
impossible to run `terraform apply` against production while pointed at
staging's state, because they're different Terraform Cloud workspaces
entirely (`itango-staging` / `itango-production`), not a shared workspace
distinguished only by a variable. The `modules/` directory holds the
actual resource definitions shared by both.

## Applying

```bash
# Staging
cd devops/terraform/environments/staging
terraform init
terraform plan -var="cloudflare_api_token=$CF_TOKEN" \
                -var="cloudflare_zone_id=$CF_ZONE_ID" \
                -var="upstash_email=$UPSTASH_EMAIL" \
                -var="upstash_api_key=$UPSTASH_KEY"
terraform apply

# Production — same, from environments/production/. Deliberately not scripted
# as a single "deploy both" command; applying to production should always be
# a conscious, separate action, not a side effect of a staging deploy.
```

In CI, these variables are pulled from GitHub Actions secrets (see
`.github/workflows/terraform-plan.yml`) — `terraform plan` runs automatically
on any PR touching `devops/terraform/**`, but `terraform apply` requires a
manual approval gate (a GitHub Environment protection rule), since
infrastructure changes should never auto-apply on merge the way app code does.

## What Terraform does NOT manage here

- **Supabase projects** — Supabase's Terraform provider coverage is
  currently limited (primarily project-level settings, not full schema/RLS
  management), and the actual schema is already version-controlled as SQL
  migrations in `database/migrations/`, which is the correct source of
  truth for schema — duplicating it into Terraform HCL would create two
  places that could drift. Supabase project creation itself (staging vs.
  production projects) is a one-time manual step, documented in
  `devops/scripts/setup-supabase-projects.md`.
- **Fly.io app resources** — managed via `flyctl` directly (see the
  `fly.staging.toml` / `fly.production.toml` files alongside this) rather
  than Terraform's Fly provider, which is community-maintained and less
  mature than the two providers used here. `flyctl deploy` in CI is the
  actual deployment mechanism; Terraform only manages what points *at* the
  resulting Fly app (the Cloudflare DNS record).
