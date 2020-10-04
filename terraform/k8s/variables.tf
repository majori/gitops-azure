variable "gitops_repo_url" {
  type = string
  description = "URL of git repo with Kubernetes manifests; e.g. ssh://git@github.com/fluxcd/flux-get-started"
}

variable "gitops_repo_path" {
  type = string
  description = "Path within git repo to locate Kubernetes manifests (relative path)"
  default = "k8s"
}

variable "letsencrypt_email" {
  type = string
  description = "Let's Encrypt will send certificate expirations to this email address."

  validation {
    condition = can(regex("^[\\w-\\.]+@([\\w-]+\\.)+[\\w-]{2,4}$", var.letsencrypt_email))
    error_message = "The letsencrypt_email must be a valid email address."
  }
}
