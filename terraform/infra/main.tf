provider "azurerm" {
  version = "=2.20.0"
  features {}

  subscription_id = "0c85512e-cd7a-41b3-ae82-cdc864b7deb8"
  tenant_id       = "a951d4b8-d93b-4425-a116-6a0b4efbb964"
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

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${random_id.aks.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
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
      enabled                    = true
      log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
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

resource "azurerm_container_registry" "main" {
  name                = "acr${random_id.aks.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
}

# Enables usage of user created public IP in AKS ingress
resource "azurerm_role_assignment" "aks_ingress" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

resource "azurerm_user_assigned_identity" "aks_pod_identity" {
  name                = "aks-${random_id.aks.hex}-pod-identity-default"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}
