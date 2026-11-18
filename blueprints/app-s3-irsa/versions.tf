terraform {
  required_version = ">= 1.10.0"

  required_providers {
    # s3-bucket v5.18 needs >= 6.44, iam v6 >= 6.x; pinned with the platform blueprint
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.59, < 7.0"
    }
  }

  # Partial config: the pipeline passes bucket/key/region
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
