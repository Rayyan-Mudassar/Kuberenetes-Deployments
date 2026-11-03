variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "cluster_name" {
  description = "Use a NEW name while your console-built cluster still exists, or the names collide."
  type        = string
  default     = "directory-cluster-tf"
}

variable "kubernetes_version" {
  description = "Pick a version currently in standard support. Older versions cost extra (extended support)."
  type        = string
  default     = "1.34"
}

variable "node_instance_type" {
  description = "t3.medium is the realistic minimum for kube-prometheus-stack + your app."
  type        = string
  default     = "t3.medium"
}

variable "github_role_name" {
  description = "IAM role created by bootstrap/. Gets cluster-admin via an EKS access entry."
  type        = string
  default     = "github-actions-terraform"
}

variable "admin_principal_arns" {
  description = "Your own IAM user/role ARN(s) so kubectl works from your laptop/VM."
  type        = list(string)
  default     = ["arn:aws:iam::106002846597:user/rayyan1"]
}
