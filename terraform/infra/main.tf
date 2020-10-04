provider "azurerm" {
  version = "=2.27.0"
  features {}
}

provider "random" {
  version = "=2.2.1"
}

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
    node_count           = 2
    vm_size              = "Standard_B2s"
    orchestrator_version = local.kubernetes_version
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "Basic"
  }

  addon_profile {
    oms_agent {
      enabled = false
    }
    aci_connector_linux {
      enabled = false
    }
    http_application_routing {
      enabled = false
    }
    azure_policy {
      enabled = false
    }
    kube_dashboard {
      enabled = false
    }
  }
}

# Enables usage of user created public IP in AKS ingress
resource "azurerm_role_assignment" "aks_ingress" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
