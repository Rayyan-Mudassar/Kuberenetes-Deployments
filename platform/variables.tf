variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "cluster_name" {
  description = "Must match infra/"
  type        = string
  default     = "directory-cluster-tf"
}

variable "grafana_admin_password" {
  description = "Never commit this. CI passes it from the GitHub secret GRAFANA_ADMIN_PASSWORD."
  type        = string
  sensitive   = true
}

variable "monitoring_chart_version" {
  description = "null = latest on first install. After it works, run `helm list -n monitoring` and pin the version here."
  type        = string
  default     = null
}
