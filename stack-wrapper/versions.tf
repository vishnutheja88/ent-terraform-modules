terraform {
  # terraform-aws-modules/rds v7 requires >= 1.11.1
  required_version = ">= 1.11.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.59, < 7.0"
    }
  }

  # Partial configuration. Stage 2/3 inject, from the DynamoDB registry + CodeBuild env:
  #   -backend-config="bucket=<central state bucket>"
  #   -backend-config="key=<tf_state_key from registry>"     e.g. payments/dev/terraform.tfstate
  #   -backend-config="region=<shared services region>"
  #   -backend-config="dynamodb_table=<central lock table>"
  #   -backend-config="kms_key_id=<state KMS key ARN>"
  backend "s3" {
    encrypt = true
  }
}
