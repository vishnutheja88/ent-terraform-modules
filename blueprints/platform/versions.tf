terraform {
  # >= 1.10 for S3 native state locking (use_lockfile)
  required_version = ">= 1.10.0"

  required_providers {
    # Must satisfy every vendored upstream module (EKS v21 needs >= 6.59)
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.59, < 7.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }

  # Partial config: bucket/key/region come from the pipeline via -backend-config
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
