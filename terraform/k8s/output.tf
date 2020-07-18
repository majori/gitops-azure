output "flux_ssh_public_key" {
  value = tls_private_key.flux_identity.public_key_openssh
}
