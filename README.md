# ent-terraform-modules

Rafay-style **environment blueprints** without Rafay: plain Terraform + AWS CodePipeline.
Teams edit **one small values file** — `vpc: true`, `eks: true`, or "give my app an S3 bucket" — open a PR, merge.
The pipeline validates, plans, waits for approval (prod), and applies.

```
envs/<env>/*.yaml  ─►  blueprints/<name>/  ─►  modules/<wrapper>  ─►  upstream/terraform-aws-<x>
  (Environment)        (Env Template:          (Resource Template:     (vendored public
                        toggles + rules)        org defaults)           terraform-aws-modules)
```

## Two ways to use this repo

| Model | Who writes values | Where it runs | Start here |
|---|---|---|---|
| **Self-service platform (config-only)** | App teams, in their own `app-team-<name>-infra` repos | Central pipelines in a Shared Services account, deploying into each team's spoke account, with private TLS from a RAM-shared Subordinate CA | [`docs/self-service-platform.md`](docs/self-service-platform.md), `stack-wrapper/`, `platform/` |
| Rafay-style blueprints (single repo) | Platform team, in `envs/` of this repo | One pipeline per values file in one account | sections below, `blueprints/` |

## What's inside

| Layer | Path | Rafay equivalent | Owner |
|---|---|---|---|
| Upstream | `upstream/terraform-aws-{vpc,ec2-instance,iam,route53,eks,kms,security-group,s3-bucket,rds}` | — | synced by script, never hand-edited |
| Wrappers | `modules/{vpc,ec2,iam-role,route53,eks,security-group,s3,irsa,networking,ecs,rds,acm-private-cert}` | Resource Templates | Platform team |
| Blueprints | `blueprints/platform/`, `blueprints/app-s3-irsa/` | Environment Templates | Platform team |
| Guardrails | `schema/<blueprint>.schema.json` | Allowed values / selectors | Platform team |
| Inputs | `envs/<env>/platform.yaml`, `envs/<env>/apps/<app>.yaml` | Environments | Platform team / **app teams** |
| Run engine | `pipeline/buildspec.yml`, `pipeline/infra/` | Env Manager | Platform team (bootstrap once) |

Every values file names its blueprint (`blueprint: platform` or `blueprint: app-s3-irsa`) and gets **its own Terraform state**,
so an app's bucket can be created or deleted without touching the VPC or EKS.

Pinned versions and local patches: [`upstream/VERSIONS.md`](upstream/VERSIONS.md).

## Blueprint 1: `platform` (VPC, EC2, IAM, Route53, EKS)

| Toggle | Wrapper → upstream | Notes |
|---|---|---|
| `vpc.enabled` | `modules/vpc` → terraform-aws-vpc | /20 public + private subnets per AZ, EKS/ELB subnet tags, default SG locked down, optional flow logs |
| `igw.enabled` | (input to vpc) | Creates IGW + public subnets |
| `vpc.nat_gateway` | (input to vpc) | Single NAT (dev) or one per AZ (prod) |
| `ec2.enabled` | `modules/ec2` → terraform-aws-ec2-instance + `modules/security-group` | N instances, shared SG, SSM instance profile, IMDSv2, encrypted gp3 root |
| `iam.enabled` | `modules/iam-role` → terraform-aws-iam//modules/iam-role | One role per key in `iam.roles`, optional permissions boundary |
| `route53.enabled` | `modules/route53` → terraform-aws-route53 (→ kms for DNSSEC) | Private/public zone + records |
| `eks.enabled` | `modules/eks` → terraform-aws-eks (→ kms) | Managed node groups, KMS secrets encryption, core add-ons, control-plane logs |

### Dependency rules (enforced at `plan`)

- `igw` requires `vpc`; `vpc.nat_gateway` requires `igw`
- `ec2` / `eks` / private `route53` require `vpc` **or** `existing_network` (bring your own VPC)
- `ec2.public` requires `igw`
- `eks` on a new VPC requires `vpc.nat_gateway` (nodes must pull images)

```yaml
# envs/dev/platform.yaml (shortened)
blueprint: platform
env: dev
region: us-east-1
vpc:     { enabled: true, cidr: 10.20.0.0/16, az_count: 2, nat_gateway: true }
igw:     { enabled: true }
ec2:     { enabled: true, instance_type: t3.micro, count: 1 }
route53: { enabled: true, zone_name: dev.ent.internal, private: true }
eks:
  enabled: true
  version: "1.34"
  node_groups:
    general: { instance_types: [t3.large], min_size: 1, max_size: 3, desired_size: 2 }
```

Already have a VPC? Set `vpc.enabled: false` and add `existing_network: { vpc_id: vpc-…, private_subnet_ids: [subnet-…] }`.

## Blueprint 2: `app-s3-irsa` (S3 bucket + IRSA role for one app)

Plugs into an **existing** EKS cluster (looked up by name, never created) and gives one Kubernetes
service account access to one S3 bucket — no access keys anywhere.

```yaml
# envs/dev/apps/orders.yaml
blueprint: app-s3-irsa
env: dev
region: us-east-1
app: orders
cluster_name: ent-dev-eks        # from the platform blueprint
s3:
  versioning: true
  expire_days: 90
irsa:
  namespace: orders
  service_account: orders-api
  access: read-write             # read-only | read-write
```

| Creates | Wrapper → upstream | Built-in rules |
|---|---|---|
| S3 bucket `dev-orders-<account id>` | `modules/s3` → terraform-aws-s3-bucket | public access blocked, encrypted (AES256 or your KMS key), TLS-only policy, owner-enforced, versioned, optional expiry |
| IAM role `dev-orders-s3` | `modules/irsa` → terraform-aws-iam//modules/iam-role-for-service-accounts | trust = only `orders:orders-api` via the cluster's OIDC provider; permissions = only this bucket |

The blueprint outputs `role_arn` and a ready-to-apply ServiceAccount:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: orders-api
  namespace: orders
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account>:role/dev-orders-s3
```

Pods with `serviceAccountName: orders-api` then get short-lived credentials for that bucket.

**New app?** Copy `orders.yaml` to `envs/<env>/apps/<app>.yaml`, change `app` and `irsa`, and add a pipeline entry (below).

## Pipeline flow (one CodePipeline V2 per values file)

```
merge to main touching that values file
  → Source   : CodeConnections (GitHub or Bitbucket)
  → Plan     : read blueprint from the file → schema check → fmt/validate → plan → checkov scan
  → Approve  : manual + SNS email (when require_approval = true)
  → Apply    : applies the exact saved tfplan
```

State key per file: `envs/dev/apps/orders.yaml` → `s3://<state-bucket>/ent-tf/dev/apps/orders.tfstate`.

### Bootstrap (once)

```bash
cd pipeline/infra
cp terraform.tfvars.example terraform.tfvars   # repository_id, approvers, pipelines
terraform init && terraform apply
```

```hcl
pipelines = {
  dev-platform  = { values_file = "envs/dev/platform.yaml",    require_approval = false }
  prod-platform = { values_file = "envs/prod/platform.yaml",   require_approval = true }
  dev-orders    = { values_file = "envs/dev/apps/orders.yaml", require_approval = false }
}
```

Then **AWS Console → Developer Tools → Settings → Connections →** `ent-tf-src` → **Update pending connection**.

> `same_account_deploy_policy_arns` defaults to AdministratorAccess so EKS/IAM/Route53 work in a lab account.
> In an enterprise, set it to `[]` and deploy through a scoped cross-account `tf-deploy` role (`account_role` in values files).

### Run locally

```bash
cd blueprints/app-s3-irsa          # or blueprints/platform
terraform init -backend-config="bucket=<state-bucket>" \
               -backend-config="key=ent-tf/dev/apps/orders.tfstate" \
               -backend-config="region=us-east-1"
terraform plan -var values_file=../../envs/dev/apps/orders.yaml
```

Order matters the first time: apply `envs/dev/platform.yaml` with `eks.enabled: true` before any app that names that cluster.

## Upgrading upstream modules

```bash
scripts/sync-upstream.sh eks v21.31.0     # bump one
scripts/sync-upstream.sh                  # re-vendor all pins
```
The script clones the tag, strips examples/tests, and rewrites nested public-Registry calls
(e.g. EKS → KMS) to the vendored copies. Point `UPSTREAM_BASE` at your Bitbucket mirror to sync from there.
Then update `upstream/VERSIONS.md`, run validate + a dev plan, and tag the wrapper (`eks/v1.1.0`).

## Consuming from another repo (enterprise pattern)

```hcl
module "vpc" {
  source = "git::https://github.com/vishnutheja88/ent-terraform-modules.git//modules/vpc?ref=vpc/v1.0.0"
  ...
}
```
Tag per wrapper (`vpc/v1.0.0`, `s3/v1.0.0`) so each consumer upgrades independently.

## Adding a new blueprint

1. Vendor any new upstream module (add it to `PINS` in the sync script).
2. Add wrappers in `modules/` with a small interface and org defaults.
3. Create `blueprints/<name>/` that reads `values_file` and calls the wrappers.
4. Add `schema/<name>.schema.json` (include `"blueprint": { "const": "<name>" }`).
5. Add a values file with `blueprint: <name>` and a `pipelines` entry.

Next ideas: EKS Pod Identity as an alternative to IRSA (`auth: pod-identity`), an ArgoCD add-ons blueprint (Rafay "Cluster Blueprints").

## License

Wrappers, blueprints and pipeline: yours. Vendored modules in `upstream/` remain under their Apache-2.0 licenses (kept in each folder).
