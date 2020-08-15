terraform {
  backend "kubernetes" {
    secret_suffix    = "k8s"
    load_config_file = true
    config_path      = "../kubeconfig"
  }
}
