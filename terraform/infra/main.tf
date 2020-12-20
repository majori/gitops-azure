provider "azurerm" {
  features {}
}

provider "random" {}

data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

resource "random_id" "aks" {
  byte_length = 4
}

resource "azurerm_public_ip" "aks_ingress" {
  name                = "public-ip-aks-ingress-${random_id.aks.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Basic"
}

locals {
  kubernetes_version = "1.17.9"
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${random_id.aks.hex}"
  dns_prefix          = "aks"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  kubernetes_version  = local.kubernetes_version

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                 = "default"
    node_count           = 3
    vm_size              = "Standard_B2s"
    orchestrator_version = local.kubernetes_version
    os_disk_size_gb      = 64
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "Basic"
  }
}

# Enables usage of user created public IP in AKS ingress
resource "azurerm_role_assignment" "aks_ingress" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}
