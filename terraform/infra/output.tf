output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.main.kube_config
  sensitive = true
}

output "ingress_ip" {
  value = azurerm_public_ip.aks_ingress.ip_address
}
