output "flux_ssh_public_key" {
  value = tls_private_key.flux_identity.public_key_openssh
}

output "kubeseal_cert" {
  value = tls_self_signed_cert.sealed_secrets.cert_pem
}
