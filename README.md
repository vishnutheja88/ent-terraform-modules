# ent-terraform-modules

Rafay-style **environment blueprints** without Rafay: plain Terraform + AWS CodePipeline.
App teams edit **one values file** — `vpc: true`, `eks: true`, `route53: true` … — open a PR, merge.
The pipeline validates, plans, waits for approval (prod), and applies.

```
envs/<env>/values.yaml  ─►  blueprint/        ─►  modules/<wrapper>  ─►  upstream/terraform-aws-<x>
   (Environment)            (Env Template:          (Resource Template:     (vendored public
                             toggles + rules)        org defaults)           terraform-aws-modules)
```

## What's inside

| Layer | Path | Rafay equivalent | Owner |
|---|---|---|---|
| Upstream | `upstream/terraform-aws-{vpc,ec2-instance,iam,route53,eks,kms,security-group}` | — | synced by script, never hand-edited |
| Wrappers | `modules/{vpc,ec2,iam-role,route53,eks,security-group}` | Resource Templates | Platform team |
| Blueprint | `blueprint/` | Environment Template | Platform team |
| Guardrails | `schema/values.schema.json` | Allowed values / selectors | Platform team |
| Inputs | `envs/<env>/values.yaml` | Environment | **App teams** |
| Run engine | `pipeline/buildspec.yml`, `pipeline/infra/` | Env Manager | Platform team (bootstrap once) |

Pinned versions and local patches: [`upstream/VERSIONS.md`](upstream/VERSIONS.md).

## Components and toggles

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

The JSON schema additionally rejects unknown keys, bad CIDRs/ARNs and non-approved instance types before Terraform runs.

## Example `values.yaml`

```yaml
env: dev
region: us-east-1
vpc:     { enabled: true, cidr: 10.20.0.0/16, az_count: 2, nat_gateway: true }
igw:     { enabled: true }
ec2:     { enabled: true, instance_type: t3.micro, count: 1, ingress_ports: [443], ingress_cidrs: [10.20.0.0/16] }
iam:
  enabled: true
  roles:
    app-reader: { trusted_services: [ec2.amazonaws.com], policy_arns: { s3ro: arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess } }
route53: { enabled: true, zone_name: dev.ent.internal, private: true }
eks:
  enabled: true
  version: "1.34"
  node_groups:
    general: { instance_types: [t3.large], min_size: 1, max_size: 3, desired_size: 2 }
```

Already have a VPC? Set `vpc.enabled: false` and add:
```yaml
existing_network:
  vpc_id: vpc-0abc...
  private_subnet_ids: [subnet-0a..., subnet-0b...]
```

## Pipeline flow (one CodePipeline V2 per env)

```
merge to main touching envs/<env>/**
  → Source   : CodeConnections (GitHub or Bitbucket)
  → Plan     : schema check → fmt/validate → plan → checkov scan of the plan
  → Approve  : manual + SNS email (prod)
  → Apply    : applies the exact saved tfplan
```

### Bootstrap (once)

```bash
cd pipeline/infra
cp terraform.tfvars.example terraform.tfvars   # repository_id, approvers, source_provider
terraform init && terraform apply
```
Then **AWS Console → Developer Tools → Settings → Connections →** `ent-tf-src` → **Update pending connection**.

> `same_account_deploy_policy_arns` defaults to AdministratorAccess so EKS/IAM/Route53 work in a lab account.
> In an enterprise, set it to `[]` and deploy through a scoped cross-account `tf-deploy` role (`account_role` in values.yaml).

### Run locally

```bash
cd blueprint
terraform init -backend-config="bucket=<state-bucket>" \
               -backend-config="key=ent-tf/dev/terraform.tfstate" \
               -backend-config="region=us-east-1"
terraform plan -var values_file=../envs/dev/values.yaml
```

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
Tag per wrapper (`vpc/v1.0.0`, `eks/v1.0.0`) so each environment upgrades independently.

## Adding a new component (e.g. `rds: true`)

1. Vendor `terraform-aws-rds` (add it to `PINS` in the sync script).
2. Add `modules/rds` wrapper with a small interface and org defaults.
3. Add the toggle, module block and any precondition to `blueprint/main.tf`.
4. Add the `rds` block to `schema/values.schema.json`.

## License

Wrappers, blueprint and pipeline: yours. Vendored modules in `upstream/` remain under their Apache-2.0 licenses (kept in each folder).
