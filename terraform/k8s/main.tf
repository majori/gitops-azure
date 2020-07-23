data "terraform_remote_state" "infra" {
  backend = "azurerm"

  config = {
    resource_group_name  = "personal"
    storage_account_name = "storagecf8d4bcc"
    container_name       = "terraformstate"
    key                  = "infra.terraform.tfstate"
  }
}

provider "kubernetes" {
  load_config_file       = "false"
  host                   = data.terraform_remote_state.infra.outputs.kube_config.0.host
  username               = data.terraform_remote_state.infra.outputs.kube_config.0.username
  password               = data.terraform_remote_state.infra.outputs.kube_config.0.password
  client_certificate     = base64decode(data.terraform_remote_state.infra.outputs.kube_config.0.client_certificate)
  client_key             = base64decode(data.terraform_remote_state.infra.outputs.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(data.terraform_remote_state.infra.outputs.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    load_config_file = "false"
    host             = data.terraform_remote_state.infra.outputs.kube_config.0.host
    username         = data.terraform_remote_state.infra.outputs.kube_config.0.username
    password         = data.terraform_remote_state.infra.outputs.kube_config.0.password

    client_certificate     = base64decode(data.terraform_remote_state.infra.outputs.kube_config.0.client_certificate)
    client_key             = base64decode(data.terraform_remote_state.infra.outputs.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(data.terraform_remote_state.infra.outputs.kube_config.0.cluster_ca_certificate)
  }
}

resource "helm_release" "sealed_secrets" {
  name       = "sealed-secrets"
  chart      = "sealed-secrets"
  repository = "https://kubernetes-charts.storage.googleapis.com"
  version    = "1.10.3"
  namespace  = "kube-system"
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

resource "helm_release" "linkerd" {
  name       = "main"
  repository = "https://helm.linkerd.io/stable"
  chart      = "linkerd2"
  version    = "2.8.1"

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
}

resource "kubernetes_namespace" "postgres_operator" {
  metadata {
    name = "postgres-operator"
    annotations = {
      "linkerd.io/inject" : "enabled"
    }
  }
}

resource "helm_release" "postgres_operator" {
  name  = "postgres-operator"
  chart = "https://opensource.zalando.com/postgres-operator/charts/postgres-operator/postgres-operator-1.5.0.tgz"
  # version    = "1.5.0"
  namespace = kubernetes_namespace.postgres_operator.metadata[0].name

  depends_on = [
    helm_release.linkerd,
  ]
}

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
    annotations = {
      "linkerd.io/inject" : "enabled"
    }
  }
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v0.15.1"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [
    helm_release.linkerd,
  ]
}

resource "kubernetes_namespace" "ingress" {
  metadata {
    name = "ingress"
    annotations = {
      "linkerd.io/inject" : "enabled"
    }
  }
}

resource "helm_release" "nginx" {
  name       = "nginx-ingress"
  repository = "https://helm.nginx.com/stable"
  chart      = "nginx-ingress"
  version    = "0.5.2"
  namespace  = kubernetes_namespace.ingress.metadata[0].name

  set {
    name  = "controller.service.loadBalancerIP"
    value = data.terraform_remote_state.infra.outputs.ingress_ip
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-resource-group"
    value = data.terraform_remote_state.infra.outputs.resource_group_name
  }

  depends_on = [
    helm_release.linkerd,
  ]
}

resource "kubernetes_namespace" "flux" {
  metadata {
    name = "flux"
  }
}

resource "tls_private_key" "flux_identity" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "kubernetes_secret" "flux_git_deploy" {
  metadata {
    name      = "flux-git-deploy"
    namespace = kubernetes_namespace.flux.metadata[0].name
  }

  data = {
    identity = tls_private_key.flux_identity.private_key_pem
  }
}

resource "helm_release" "helm_operator" {
  name       = "helm-operator"
  repository = "https://charts.fluxcd.io"
  chart      = "helm-operator"
  version    = "1.1.0"
  namespace  = kubernetes_namespace.flux.metadata[0].name

  set {
    name  = "helm.versions"
    value = "v3"
  }

  set {
    name  = "git.ssh.secretName"
    value = kubernetes_secret.flux_git_deploy.metadata[0].name
  }


  depends_on = [
    helm_release.linkerd,
  ]
}

resource "helm_release" "flux" {
  name       = "flux"
  repository = "https://charts.fluxcd.io"
  chart      = "flux"
  version    = "1.3.0"
  namespace  = kubernetes_namespace.flux.metadata[0].name

  set {
    name  = "git.url"
    value = var.gitops_repo
  }

  set {
    name  = "git.secretName"
    value = kubernetes_secret.flux_git_deploy.metadata[0].name
  }

  depends_on = [
    helm_release.linkerd,
  ]
}