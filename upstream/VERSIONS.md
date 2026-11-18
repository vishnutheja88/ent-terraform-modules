# Vendored upstream modules

Source: https://github.com/terraform-aws-modules (Apache-2.0, LICENSE kept in each folder).
Vendored without `examples/`, `tests/`, `wrappers/`, `docs/`, `.github/`.
Upgrade with `scripts/sync-upstream.sh` — never edit these folders by hand except for the patches listed below.

| Folder | Upstream repo | Tag |
|---|---|---|
| terraform-aws-vpc | terraform-aws-modules/terraform-aws-vpc | v6.8.0 |
| terraform-aws-ec2-instance | terraform-aws-modules/terraform-aws-ec2-instance | v6.4.1 |
| terraform-aws-iam | terraform-aws-modules/terraform-aws-iam | v6.11.1 |
| terraform-aws-route53 | terraform-aws-modules/terraform-aws-route53 | v6.5.1 |
| terraform-aws-eks | terraform-aws-modules/terraform-aws-eks | v21.30.2 |
| terraform-aws-kms | terraform-aws-modules/terraform-aws-kms | v4.2.2 |
| terraform-aws-security-group | terraform-aws-modules/terraform-aws-security-group | v6.0.0 |
| terraform-aws-s3-bucket | terraform-aws-modules/terraform-aws-s3-bucket | v5.18.0 |
| terraform-aws-rds | terraform-aws-modules/terraform-aws-rds | v7.2.2 |

## Local patches (re-applied automatically by the sync script)

Nested Registry calls rewritten to the vendored copy so CI never reaches the public Registry:

| File | Was | Now |
|---|---|---|
| terraform-aws-eks/main.tf `module "kms"` | `terraform-aws-modules/kms/aws` 4.0.0 | `../terraform-aws-kms` (v4.2.2) |
| terraform-aws-route53/main.tf `module "route53_dnssec_kms"` | `terraform-aws-modules/kms/aws` 4.0.0 | `../terraform-aws-kms` (v4.2.2) |

## Provider floor (union of all modules)

- `hashicorp/aws >= 6.59` (EKS v21; s3-bucket v5.18 needs >= 6.44; rds v7.2 needs >= 6.28)
- Terraform `>= 1.11.1` (rds v7)
- `hashicorp/tls >= 4.0`, `hashicorp/time >= 0.9` (EKS)
