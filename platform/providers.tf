terraform {
  required_version = ">= 1.11"

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    helm       = { source = "hashicorp/helm", version = "~> 2.17" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.38" }
  }

  backend "s3" {
    bucket       = "rayyan-tfstate-106002846597"
    key          = "platform/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
}

# The cluster is created by infra/, so we only LOOK IT UP by name here.
# This is why infra and platform are separate: these providers need a cluster that already exists.
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

locals {
  cluster_host = data.aws_eks_cluster.this.endpoint
  cluster_ca   = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token_args   = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
}

# Short-lived token fetched on demand via the AWS CLI (no kubeconfig file, no stored credentials)
provider "kubernetes" {
  host                   = local.cluster_host
  cluster_ca_certificate = local.cluster_ca
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.token_args
  }
}

provider "helm" {
  kubernetes {
    host                   = local.cluster_host
    cluster_ca_certificate = local.cluster_ca
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.token_args
    }
  }
}
