terraform {
  backend "azurerm" {
    resource_group_name  = "personal"
    storage_account_name = "storagecf8d4bcc"
    container_name       = "terraformstate"
    key                  = "k8s.terraform.tfstate"
  }
}
