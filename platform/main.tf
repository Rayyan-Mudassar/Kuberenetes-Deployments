resource "kubernetes_annotations" "gp2_not_default" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }
  force = true
}

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com" # the add-on installed by infra/
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer" # create the volume in the same AZ as the pod
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [kubernetes_annotations.gp2_not_default]
}

# ---------- Monitoring: Prometheus + Grafana + Alertmanager ----------
resource "helm_release" "monitoring" {
  name             = "monitoring" # keep this name: your app's ServiceMonitor label is `release: monitoring`
  namespace        = "monitoring"
  create_namespace = true

  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.monitoring_chart_version

  atomic  = true # roll back automatically if the install fails
  timeout = 900

  values = [file("${path.module}/monitoring-values.yaml")]

  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  depends_on = [kubernetes_storage_class_v1.gp3]
}
