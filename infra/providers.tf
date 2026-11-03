terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state. Replace the bucket with the `state_bucket_name` output from bootstrap/.
  # Backend blocks cannot use variables, so this one line is hardcoded on purpose.
  backend "s3" {
    bucket       = "rayyan-tfstate-106002846597"
    key          = "infra/terraform.tfstate" # separate state per layer
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true # S3-native locking, no DynamoDB table needed
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "people-directory"
      ManagedBy = "terraform"
      Layer     = "infra"
    }
  }
}
