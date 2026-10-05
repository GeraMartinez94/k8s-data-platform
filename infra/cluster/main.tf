terraform {
  required_version = ">= 1.6"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
  }
}

variable "kube_context" {
  type    = string
  default = "kind-data-platform"
}

variable "emulator_image" {
  type        = string
  default     = "localstack/localstack:latest"
  description = "AWS emulator. Swap for a no-token one (e.g. floci/floci:latest) if you prefer."
}

variable "localstack_auth_token" {
  type      = string
  default   = ""
  sensitive = true
}

variable "bucket_name" {
  type    = string
  default = "data-lake-dev"
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

# ---------- Namespaces ----------
resource "kubernetes_namespace" "data" {
  metadata { name = "data" }
}

# ---------- AWS emulator (S3 + IAM) inside the cluster ----------
resource "kubernetes_secret" "emulator" {
  metadata {
    name      = "emulator-token"
    namespace = kubernetes_namespace.data.metadata[0].name
  }
  data = { LOCALSTACK_AUTH_TOKEN = var.localstack_auth_token }
}

resource "kubernetes_deployment" "emulator" {
  metadata {
    name      = "aws-emulator"
    namespace = kubernetes_namespace.data.metadata[0].name
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "aws-emulator" } }
    template {
      metadata { labels = { app = "aws-emulator" } }
      spec {
        container {
          name  = "emulator"
          image = var.emulator_image
          port { container_port = 4566 }
          env {
            name  = "SERVICES"
            value = "s3,iam,sts"
          }
          env_from {
            secret_ref { name = kubernetes_secret.emulator.metadata[0].name }
          }
          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { memory = "1Gi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "emulator" {
  metadata {
    name      = "aws-emulator"
    namespace = kubernetes_namespace.data.metadata[0].name
  }
  spec {
    selector = { app = "aws-emulator" }
    port {
      port        = 4566
      target_port = 4566
    }
  }
}

# ---------- Identity: ServiceAccount + RBAC (least privilege) ----------
resource "kubernetes_service_account" "api" {
  metadata {
    name      = "data-api"
    namespace = kubernetes_namespace.data.metadata[0].name
    # On real EKS you would add:
    # annotations = { "eks.amazonaws.com/role-arn" = "<IAM role ARN>" }   (IRSA)
  }
}

resource "kubernetes_role" "api" {
  metadata {
    name      = "data-api-role"
    namespace = kubernetes_namespace.data.metadata[0].name
  }
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_role_binding" "api" {
  metadata {
    name      = "data-api-binding"
    namespace = kubernetes_namespace.data.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.api.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.api.metadata[0].name
    namespace = kubernetes_namespace.data.metadata[0].name
  }
}

# ---------- Application ----------
resource "kubernetes_deployment" "api" {
  metadata {
    name      = "data-api"
    namespace = kubernetes_namespace.data.metadata[0].name
  }
  spec {
    replicas = 2
    selector { match_labels = { app = "data-api" } }
    template {
      metadata { labels = { app = "data-api" } }
      spec {
        service_account_name = kubernetes_service_account.api.metadata[0].name
        container {
          name              = "api"
          image             = "data-api:dev"
          image_pull_policy = "Never"
          port { container_port = 8000 }
          env {
            name  = "S3_ENDPOINT"
            value = "http://aws-emulator.data.svc.cluster.local:4566"
          }
          env {
            name  = "BUCKET"
            value = var.bucket_name
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
          }
          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { cpu = "250m", memory = "256Mi" }
          }
          security_context {
            run_as_non_root            = true
            run_as_user                = 10001
            allow_privilege_escalation = false
          }
        }
      }
    }
  }
  depends_on = [kubernetes_deployment.emulator]
}

resource "kubernetes_service" "api" {
  metadata {
    name      = "data-api"
    namespace = kubernetes_namespace.data.metadata[0].name
  }
  spec {
    selector = { app = "data-api" }
    port {
      port        = 80
      target_port = 8000
    }
  }
}
