data "terraform_remote_state" "infra" {
  backend = "kubernetes"

  config = {
    secret_suffix    = "infra"
    load_config_file = true
    config_path      = "../kubeconfig"
  }
}

provider "kubernetes" {
  load_config_file = true
  config_path      = "../kubeconfig"
}

provider "kubernetes-alpha" {
  server_side_planning = true
  config_path          = "../kubeconfig"
}

provider "helm" {
  kubernetes {
    config_path      = "../kubeconfig"
  }
}

resource "tls_private_key" "sealed_secrets" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "sealed_secrets" {
  key_algorithm         = tls_private_key.sealed_secrets.algorithm
  private_key_pem       = tls_private_key.sealed_secrets.private_key_pem
  validity_period_hours = 87600 // 10 years

  subject {
    common_name = "example.com"
  }

  allowed_uses = [
    "encipher_only"
  ]
}

resource "kubernetes_secret" "sealed_secrets" {
  metadata {
    name      = "sealed-secrets-key"
    namespace = "kube-system"
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.key" = tls_private_key.sealed_secrets.private_key_pem
    "tls.crt" = tls_self_signed_cert.sealed_secrets.cert_pem
  }
}

resource "helm_release" "sealed_secrets" {
  name       = "sealed-secrets"
  chart      = "sealed-secrets"
  repository = "https://bitnami-labs.github.io/sealed-secrets"
  version    = "1.13.2"
  namespace  = "kube-system"

  set {
    name  = "secretName"
    value = kubernetes_secret.sealed_secrets.metadata[0].name
  }
}

resource "tls_private_key" "trustanchor_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "trustanchor_cert" {
  key_algorithm         = tls_private_key.trustanchor_key.algorithm
  private_key_pem       = tls_private_key.trustanchor_key.private_key_pem
  validity_period_hours = 87600
  is_ca_certificate     = true

  subject {
    common_name = "identity.linkerd.cluster.local"
  }

  allowed_uses = [
    "crl_signing",
    "cert_signing",
    "server_auth",
    "client_auth"
  ]
}

resource "tls_private_key" "issuer_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "issuer_req" {
  key_algorithm   = tls_private_key.issuer_key.algorithm
  private_key_pem = tls_private_key.issuer_key.private_key_pem

  subject {
    common_name = "identity.linkerd.cluster.local"
  }
}

resource "tls_locally_signed_cert" "issuer_cert" {
  cert_request_pem      = tls_cert_request.issuer_req.cert_request_pem
  ca_key_algorithm      = tls_private_key.trustanchor_key.algorithm
  ca_private_key_pem    = tls_private_key.trustanchor_key.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.trustanchor_cert.cert_pem
  validity_period_hours = 8760
  is_ca_certificate     = true

  allowed_uses = [
    "crl_signing",
    "cert_signing",
    "server_auth",
    "client_auth"
  ]
}

resource "kubernetes_namespace" "linkerd" {
  metadata {
    name = "linkerd"
    labels = {
      "linkerd.io/control-plane-ns"          = "linkerd"
      "config.linkerd.io/admission-webhooks" = "disabled"
      "linkerd.io/is-control-plane"          = "true"
    }
    annotations = {
      "linkerd.io/inject" = "disable"
    }
  }
}

resource "helm_release" "linkerd" {
  name       = "linkerd2"
  repository = "https://helm.linkerd.io/stable"
  chart      = "linkerd2"
  version    = "2.9.1"
  namespace  = kubernetes_namespace.linkerd.metadata[0].name

  set_sensitive {
    name  = "global.identityTrustAnchorsPEM"
    value = tls_self_signed_cert.trustanchor_cert.cert_pem
  }

  set_sensitive {
    name  = "identity.issuer.crtExpiry"
    value = tls_locally_signed_cert.issuer_cert.validity_end_time
  }

  set_sensitive {
    name  = "identity.issuer.tls.crtPEM"
    value = tls_locally_signed_cert.issuer_cert.cert_pem
  }

  set_sensitive {
    name  = "identity.issuer.tls.keyPEM"
    value = tls_private_key.issuer_key.private_key_pem
  }

  set {
    name  = "installNamespace"
    value = false
  }

  set {
    name  = "grafana.enabled"
    value = false
  }

  set {
    name  = "prometheus.enabled"
    value = false
  }
}

resource "kubernetes_namespace" "operators" {
  metadata {
    name = "operators"
  }
}

resource "helm_release" "postgres_operator" {
  name       = "postgres-operator"
  repository = "https://raw.githubusercontent.com/zalando/postgres-operator/master/charts/postgres-operator"
  chart      = "postgres-operator"
  version    = "1.5.0"
  namespace  = kubernetes_namespace.operators.metadata[0].name

  set {
    name  = "resources.requests.cpu"
    value = "10m"
  }

  set {
    name  = "resources.requests.memory"
    value = "20Mi"
  }
}

resource "helm_release" "helm_operator" {
  name       = "helm-operator"
  repository = "https://charts.fluxcd.io"
  chart      = "helm-operator"
  version    = "1.2.0"
  namespace  = kubernetes_namespace.operators.metadata[0].name

  # Supported values:
  # https://github.com/fluxcd/helm-operator/blob/master/chart/helm-operator/values.yaml

  set {
    name  = "helm.versions"
    value = "v3"
  }

  set {
    name = "rbac.create"
    value = false
  }
}

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
    annotations = {
      "linkerd.io/inject" : "enabled"
    }
  }

  depends_on = [
    helm_release.linkerd,
  ]
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.1.0"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name

  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "kubernetes_namespace" "ingresses" {
  metadata {
    name = "ingresses"
    annotations = {
      "linkerd.io/inject" : "enabled"
    }
  }

  depends_on = [
    helm_release.linkerd,
  ]
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "3.15.2"
  namespace  = kubernetes_namespace.ingresses.metadata[0].name

  # FluxCD can not parse digest part of an image, so remove it for now
  set {
    name  = "controller.image.digest"
    value = ""
    type  = "string"
  }

  set {
    name  = "controller.service.loadBalancerIP"
    value = data.terraform_remote_state.infra.outputs.ingress_ip
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-resource-group"
    value = data.terraform_remote_state.infra.outputs.resource_group_name
  }

  set {
    name  = "controller.admissionWebhooks.patch.podAnnotations.linkerd\\.io/inject"
    value = "disabled"
  }
}

resource "kubernetes_namespace" "argo_cd" {
  metadata {
    name = "argo-cd"
    annotations = {
      "linkerd.io/inject" : "enabled"
    }
  }
}

resource "tls_private_key" "argocd_identity" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "helm_release" "argo_cd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "2.11.0"
  namespace  = kubernetes_namespace.argo_cd.metadata[0].name

  set {
    name = "nameOverride"
    value = "argo-cd"
  }

  set {
    name = "server.extraArgs[0]"
    value = "--insecure"
  }

  set {
    name = "server.ingress.hosts[0]"
    value = "cd.majori.dev"
  }

  set {
    name = "server.ingress.enabled"
    value = "true"
  }

  set {
    name = "server.ingress.annotations.kubernetes\\.io/ingress.class"
    value = "nginx"
  }

  set {
    name = "server.ingress.annotations.cert-manager\\.io/cluster-issuer"
    value = "letsencrypt-prod"
  }

  set {
    name = "server.ingress.annotations.cert-manager\\.io/acme-challenge-type"
    value = "http01"
  }

  set {
    name = "server.ingress.annotations.nginx\\.ingress\\.kubernetes\\.io/configuration-snippet"
    value = "proxy_set_header l5d-dst-override $service_name.$namespace.svc.cluster.local:$service_port; grpc_set_header l5d-dst-override $service_name.$namespace.svc.cluster.local:$service_port;"
  }

  set {
    name = "server.ingress.tls[0].hosts[0]"
    value = "cd.majori.dev"
  }
  
  set {
    name = "server.ingress.tls[0].secretName"
    value = "argo-cd-tls"
  }

  depends_on = [
    kubernetes_manifest.cluster_issuer
  ]
}

resource "kubernetes_namespace" "expl_bot" {
  metadata {
    name = "expl-bot"
    annotations = {
      "linkerd.io/inject" : "enabled"
    }
  }
}

resource "kubernetes_manifest" "expl_bot_app" {
  provider = kubernetes-alpha

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind = "Application"
    metadata = {
      name = "expl-bot"
      namespace = kubernetes_namespace.argo_cd.metadata[0].name
    }
    spec = {
      destination = {
        namespace = kubernetes_namespace.expl_bot.metadata[0].name
        server = "https://kubernetes.default.svc"
      }
      project = "default"
      source = {
        path = "k8s/expl-bot"
        repoURL = "https://github.com/majori/gitops-azure.git"
        targetRevision = "HEAD"
      }
      syncPolicy = {
        automated = {}
      }
    }
  }

  depends_on = [
    kubernetes_namespace.expl_bot,
    helm_release.argo_cd
  ]
}

resource "kubernetes_namespace" "piikki" {
  metadata {
    name = "piikki"
    annotations = {
      "linkerd.io/inject" : "enabled"
    }
  }
}

resource "kubernetes_manifest" "piikki_app" {
  provider = kubernetes-alpha

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind = "Application"
    metadata = {
      name = "piikki"
      namespace = kubernetes_namespace.argo_cd.metadata[0].name
    }
    spec = {
      destination = {
        namespace = kubernetes_namespace.piikki.metadata[0].name
        server = "https://kubernetes.default.svc"
      }
      project = "default"
      source = {
        path = "k8s/piikki"
        repoURL = "https://github.com/majori/gitops-azure.git"
        targetRevision = "HEAD"
      }
      syncPolicy = {
        automated = {}
      }
    }
  }

  depends_on = [
    kubernetes_namespace.piikki,
    helm_release.argo_cd
  ]
}

resource "kubernetes_manifest" "cluster_issuer" {
  provider = kubernetes-alpha

  manifest = {
    apiVersion = "cert-manager.io/v1alpha2"
    kind       = "ClusterIssuer"
    metadata = {
      name      = "letsencrypt-prod"
      namespace = kubernetes_namespace.cert_manager.metadata[0].name
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-prod"
        }
        solvers = [{
          selector = {}
          http01 = {
            ingress = {
              class = "nginx"
            }
          }
        }]
      }
    }
  }

  depends_on = [
    helm_release.cert_manager
  ]
}
