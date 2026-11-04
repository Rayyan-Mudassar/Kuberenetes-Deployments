terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "github_repo" {
  description = "owner/repo that is allowed to assume the role"
  type        = string
  default     = "Rayyan-Mudassar/Kuberenetes-Deployments"
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  state_bucket = "rayyan-tfstate-${data.aws_caller_identity.current.account_id}"
}

# ---------- 1. State bucket ----------
resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled" # lets you recover a corrupted/deleted state file
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- 2. GitHub OIDC -> AWS ----------
# If this errors with "EntityAlreadyExists", the provider already exists in your account:
# import it (terraform import aws_iam_openid_connect_provider.github <arn>) instead of creating it.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's well-known thumbprint (AWS no longer validates it for GitHub, but older provider versions require it)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # ONLY this repo, and ONLY these 3 situations can assume the role:
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:pull_request",           # plan on PRs
        "repo:${var.github_repo}:ref:refs/heads/main",    # plan / app deploy from main
        "repo:${var.github_repo}:environment:production", # apply/destroy (after manual approval)
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "github-actions-terraform"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

# Pragmatic for a learning project: Terraform needs to create VPC/EKS/IAM, so this is broad.
# The OIDC trust policy above is what limits WHO can use it. Tighten this later.
resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "state_bucket_name" {
  description = "Paste into the backend block of infra/providers.tf and platform/providers.tf"
  value       = aws_s3_bucket.state.bucket
}

output "github_actions_role_arn" {
  description = "Put this in the GitHub secret AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}
