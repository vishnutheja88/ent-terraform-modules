# Self-Service IaC Platform (config-only model)

Application teams push a `values.yaml`; a central pipeline in the Shared Services account
assembles Terraform from this repository at the team's chosen release tag and deploys it into
the team's own AWS account. Teams never write or run Terraform.

This repository plays the role of **`platform-terraform-modules`**. Release it with immutable tags
(`git tag v1.0.0 && git push --tags`); teams pin `platform_version: "v1.0.0"`.

## What lives where

| Path | Purpose | Deployed by / where |
|---|---|---|
| `stack-wrapper/` | Master Wrapper Root Module: parses `values.yaml`, validates it, toggles modules with `count` | Pipeline, into each spoke account |
| `modules/networking` | VPC with public / private / database tiers (wraps vendored terraform-aws-vpc) | via stack-wrapper |
| `modules/ecs` | Fargate cluster + services + ALB (HTTPS when TLS is on) | via stack-wrapper |
| `modules/rds` | Private, encrypted RDS; password in Secrets Manager (wraps vendored terraform-aws-rds) | via stack-wrapper |
| `modules/acm-private-cert` | `aws_acm_certificate` issued by the RAM-shared Subordinate CA | via stack-wrapper |
| `policies/checkov/` | Policy-as-code run on every plan (hard fail) | Stage 2 |
| `platform/pki/` | Root CA, Subordinate CA, RAM share | Central team, Security/PKI account, once |
| `platform/shared-services/` | Pipelines, CodeBuild, Account Registry, state bucket + lock table, KMS, SNS, EventBridge | Central team, Shared Services account, once |
| `platform/shared-services/buildspecs/` | The three stage buildspecs (embedded in CodeBuild, not editable by teams) | with shared-services |
| `platform/account-onboarding/` | Per spoke: deploy role + permissions boundary + registry item | Central team, once per team/env |
| `examples/app-team-payments-infra/` | What a team repo looks like | Team's own repository |

## The 5-stage flow

```
team push (dev/values.yaml)                                         Shared Services account
  │  CodeConnections webhook → CodePipeline V2 trigger (branch + "dev/**" filter)
  ▼
[Source]   captures #{SourceVariables.FullRepositoryName / BranchName / CommitId}
  ▼
[Stage 1 Assemble]  path → env · no *.tf in team repo · registry GetItem "<repo>#<env>"
                    · clone platform repo --branch <platform_version> --depth 1
                    · workspace = stack-wrapper + modules + upstream + policies + values.yaml
  ▼
[Stage 2 Plan]      sts:AssumeRole (ExternalId + session tags) → profile "spoke"
                    · init (central S3 state + DynamoDB lock) · validate · plan -out=tfplan
                    · Checkov on tfplan.json (hard fail) · export +add ~change -destroy
  ▼
[Stage 4 Approve]   prod pipelines only: Manual approval + SNS summary
  ▼
[Stage 3 Apply]     re-check registry · re-assume role · apply -auto-approve tfplan
                    · ACM private cert from the RAM-shared Subordinate CA (if tls.enabled)
                                                                    → team's spoke account
```

Each `(team, environment)` has its own pipeline (`plat-payments-dev`, `plat-payments-prod`, …),
so teams never block each other. Pipelines run in `QUEUED` mode so two pushes to the same
environment apply in order instead of racing on one state file.

### Design notes and deliberate deviations

- **Trigger path.** For GitHub / Bitbucket / GitLab, CodeConnections pushes go straight to
  CodePipeline V2 triggers; there is no EventBridge event for a Git push from those providers.
  EventBridge is used for what it is good at here: routing pipeline outcomes to SNS.
  The changed path is captured by the trigger's file-path filter (`<env>/**`) and verified again in Stage 1.
- **Workspace.** Stage 1 copies `stack-wrapper/` **and** `modules/`, `upstream/`, `policies/`, because
  `stack-wrapper` references `../modules/*` and module `source` cannot be a variable. The
  workspace sits at `$CODEBUILD_SRC_DIR/workspace` because CodeBuild artifacts must be under the source directory.
- **Two sets of credentials.** The S3 backend uses the CodeBuild role (state stays central and
  spoke roles get no access to it). The AWS provider uses the assumed spoke role via the
  `spoke` profile. `allowed_account_ids` makes Terraform refuse any other account.
- **ExternalId never travels in an artifact.** Stages 2 and 3 read it from the registry right before `assume-role`.
- **Artifacts** (workspace, `tfplan`) are encrypted with the platform KMS key in the artifact bucket;
  the injected-vars file and credentials are deleted before artifact upload.

## Bootstrap order

1. **Organization prerequisites (management account)**
   - Enable RAM sharing with AWS Organizations: `aws ram enable-sharing-with-aws-organization`.
   - Spoke accounts exist with a bootstrap role (default `OrganizationAccountAccessRole`).
2. **`platform/pki`** in the Security/PKI account (same region the spokes use).
   Output `subordinate_ca_arn`; distribute `root_certificate_pem` to client trust stores.
3. **`platform/shared-services`** in Shared Services with `subordinate_ca_arn` and your `teams` map.
   Then complete the CodeConnections handshake once in the console and create the
   Secrets Manager secret named in `platform_repo_token_secret_name` (read-only token).
4. **`platform/account-onboarding`** once per team/environment
   (`-var-file=payments-prod.tfvars`, its own state key, e.g. `onboarding/payments-prod.tfstate`).
5. **Tag this repository** (`v1.0.0`). Teams set `platform_version` and push.

All four roots use a partial `backend "s3" {}`; pass `-backend-config` at init (a bootstrap bucket
for the very first run, then the central state bucket).

## DynamoDB Account Registry

Table `<prefix>-account-registry`, PAY_PER_REQUEST, KMS-encrypted, PITR, deletion protection.

| Attribute | Type | Example | Used by |
|---|---|---|---|
| `registry_key` (PK) | S | `app-team-payments-infra#prod` | lookup key `<repo_name>#<environment>` |
| `team` | S | `payments` | tags, metadata |
| `environment` | S | `prod` | cross-check |
| `target_account_id` | S | `222222222222` | provider `allowed_account_ids` |
| `cross_account_role_arn` | S | `arn:aws:iam::222222222222:role/PlatformTerraformDeployRole` | `sts assume-role` |
| `tf_state_key` | S | `payments/prod/terraform.tfstate` | backend `key` |
| `external_id` | S | random UUID | `sts assume-role --external-id` |

Items are written only by `platform/account-onboarding`; CodeBuild has `dynamodb:GetItem` only.

## IAM summary

**Shared Services CodeBuild role** (`<prefix>-codebuild`)
- `logs:CreateLogStream`, `logs:PutLogEvents` on `/platform/codebuild`
- `s3:GetObject/PutObject` on the artifact bucket; `s3:GetObject/PutObject/DeleteObject` on the state bucket; `s3:ListBucket`
- `dynamodb:GetItem/PutItem/DeleteItem/DescribeTable` on the lock table; `dynamodb:GetItem` on the registry
- `kms:Encrypt/Decrypt/GenerateDataKey*/DescribeKey` on the platform key
- `ssm:GetParameter` on `/platform/*`; `secretsmanager:GetSecretValue` on the platform repo token
- `sts:AssumeRole` and `sts:TagSession` (tag keys `platform-repo`, `platform-env` only) on `arn:aws:iam::*:role/PlatformTerraformDeployRole`

**Spoke `PlatformTerraformDeployRole`**
- Trust: only the CodeBuild role ARN (read from SSM at onboarding), with
  `sts:ExternalId` = the spoke's UUID, `aws:RequestTag/platform-repo` = the team's repo,
  `aws:RequestTag/platform-env` = the environment. Team A's pipeline tags its sessions with Team A's
  repo name (taken from CodeConnections metadata, not from the team's files), so it cannot assume Team B's role.
- Permissions: `PowerUserAccess` (no IAM) + `PlatformTerraformDeployPolicy`:
  - create/modify roles **only** with `iam:PermissionsBoundary = PlatformWorkloadBoundary`
  - `iam:PassRole` only to `ecs-tasks`, `vpc-flow-logs`, `rds`, `monitoring.rds`
  - service-linked roles for ECS, ELB, RDS
  - explicit deny on changing the deploy role, the bootstrap role, the boundary or the deploy policy, and on `iam:DeleteRolePermissionsBoundary`
  - ACM request/describe/delete for private certificates

**`PlatformWorkloadBoundary`**: the most any workload role can do (logs, ECR pull, Secrets Manager read,
KMS decrypt, SSM read, S3 object access, metrics/traces); explicit deny on IAM, Organizations, account, `sts:AssumeRole`.

## AWS Private CA and RAM prerequisites

- RAM sharing with Organizations enabled (step 1).
- The Subordinate CA must be **ACTIVE** and in the **same region** as the spoke stacks; `modules/acm-private-cert` checks the region.
- Only the Subordinate CA is associated with the RAM share; the Root CA has no association.
- The default RAM managed permission for Private CA lets member accounts issue end-entity certificates through ACM; ACM renews them automatically while the CA is active.
- Clients must trust the root: distribute `root_certificate_pem` (e.g. via your MDM, AMI bake or container base image).
- Cost: each general-purpose CA is billed monthly (two CAs here) plus a per-certificate fee; check current AWS Private CA pricing.

## Policy-as-code (Checkov, hard fail)

| ID | Rule |
|---|---|
| CKV2_PLAT_1 | RDS storage encrypted |
| CKV2_PLAT_2 | RDS not publicly accessible |
| CKV2_PLAT_3 | RDS instance class on the allowlist |
| CKV2_PLAT_4 | S3 public access block fully on |
| CKV2_PLAT_5 | HTTPS listeners use `ELBSecurityPolicy-TLS13-1-2-2021-06` |
| CKV2_PLAT_6 | EBS volumes encrypted |

Add a policy by dropping a YAML file into `policies/checkov/`; Stage 2 picks up every `id:` automatically.
Rules also exist earlier as Terraform `validation` blocks in `stack-wrapper/variables.tf`
(CIDR ranges, Fargate sizes, instance classes, pinned images, naming, prod guardrails), so most mistakes fail before a plan is even computed.

## Onboarding a new team

1. Create the team's accounts (`team-<name>-dev`, `-prod`, …) and repo `app-team-<name>-infra` (copy `examples/`).
2. Add the team to `teams` in `platform/shared-services` and apply (creates its pipelines).
3. Run `platform/account-onboarding` once per environment.
4. The team pushes `dev/values.yaml`.
