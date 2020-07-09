output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "storage_account_key" {
  value     = azurerm_storage_account.main.primary_access_key
  sensitive = true
}

output "storage_account_container" {
  value = azurerm_storage_container.terraform.name
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.main.kube_config
  sensitive = true
}

output "ingress_ip" {
  value = azurerm_public_ip.aks_ingress.ip_address
}
