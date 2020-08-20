output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive = true
}

output "ingress_ip" {
  value = azurerm_public_ip.aks_ingress.ip_address
}

output "aks_pod_identity_name" {
  value = "aks-${random_id.aks.hex}-pod-identity-default"
}

output "aks_pod_identity_id" {
  value = azurerm_user_assigned_identity.aks_pod_identity.id
}

output "aks_pod_identity_client_id" {
  value = azurerm_user_assigned_identity.aks_pod_identity.client_id
}
