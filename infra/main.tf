data "aws_availability_zones" "available" {
  state = "available"
}

# Created by bootstrap/. We only look it up here.
data "aws_iam_role" "github_actions" {
  name = var.github_role_name
}

locals {
  azs      = slice(data.aws_availability_zones.available.names, 0, 2) # 2 AZs = HA without paying for 3
  vpc_cidr = "10.0.0.0/16"

  cluster_admin_policy = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  # Who can talk to the cluster API. Replaces the old aws-auth ConfigMap.
  access_entries = merge(
    {
      github_actions = {
        principal_arn = data.aws_iam_role.github_actions.arn
        policy_associations = {
          admin = {
            policy_arn   = local.cluster_admin_policy
            access_scope = { type = "cluster" }
          }
        }
      }
    },
    {
      for arn in var.admin_principal_arns : arn => {
        principal_arn = arn
        policy_associations = {
          admin = {
            policy_arn   = local.cluster_admin_policy
            access_scope = { type = "cluster" }
          }
        }
      }
    }
  )
}

# ---------------- Network ----------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = local.vpc_cidr
  azs  = local.azs

  # Private /20s: nodes + pods live here (VPC CNI gives every pod a real VPC IP, so leave room)
  private_subnets = [for k, az in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  # Public /24s: only load balancers + the NAT gateway
  public_subnets = [for k, az in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = true # one NAT = cheaper (not HA, fine for learning)
  enable_dns_hostnames = true

  # Tags the AWS load balancer controller uses to pick subnets
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}

# ---------------- IAM role for the EBS CSI driver (IRSA) ----------------
# Without this, PVCs (Postgres, Prometheus, Grafana) stay Pending forever.
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# ---------------- EKS ----------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Public endpoint is required so GitHub-hosted runners can reach the API.
  # Access is still gated by IAM + access entries. Restrict CIDRs if you move to self-hosted runners.
  cluster_endpoint_public_access = true

  enable_irsa         = true  # creates the OIDC provider that IRSA roles trust
  authentication_mode = "API" # use access entries only, no aws-auth ConfigMap

  # We list every admin explicitly instead of "whoever created the cluster",
  # so it works the same from your laptop and from CI.
  enable_cluster_creator_admin_permissions = false
  access_entries                           = local.access_entries

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
    }
  }
}
