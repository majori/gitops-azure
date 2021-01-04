output "kubeseal_cert" {
  value = tls_self_signed_cert.sealed_secrets.cert_pem
}
