# app-team-payments-infra (example team repository)

This is what an application team's repository looks like: **no `.tf` files**, one folder per
environment, one `values.yaml` per folder. Stage 1 fails the run if any Terraform file appears here.

```
dev/values.yaml       push -> plat-payments-dev      (no approval)
staging/values.yaml   push -> plat-payments-staging  (no approval)
prod/values.yaml      push -> plat-payments-prod     (manual approval via SNS)
```

Only the pipeline for the folder you changed runs.

## Upgrading the platform

Change `platform_version` in `dev/values.yaml` first (e.g. `v1.0.0` → `v1.1.0`), let it apply,
then staging, then prod. Each environment stays on its tag until you bump it.

## What you can set

| Key | Meaning |
|---|---|
| `networking` | VPC CIDR (private, /16–/20), AZ count (2–3), NAT (none/single/per_az) |
| `tls` | Private certificate from the corporate Subordinate CA; the ALB switches to HTTPS |
| `ecs.services.<name>` | Fargate service: image (pinned tag or digest), cpu/memory (Fargate sizes), port, count, health check path, env vars, secrets |
| `rds` | postgres/mysql, allowlisted instance class, storage, multi-AZ; password stored in Secrets Manager |

Everything else (encryption, private subnets, IAM boundaries, logging, deletion protection in prod)
is decided by the platform and cannot be turned off from this file.
