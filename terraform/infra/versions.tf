terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "=2.27.0"
    }
    random = {
      source = "hashicorp/random"
      version = "=2.2.1"
    }
  }
  required_version = ">= 0.13"
}
