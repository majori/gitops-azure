terraform {
  backend "kubernetes" {
    secret_suffix    = "infra"
    load_config_file = true
    config_context   = "personal"
  }
}
