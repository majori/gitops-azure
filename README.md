1. `cd terraform`
2. `./init.sh`

## How to create Sealed Secret certificate

```
terraform output -json | jq -r '.kubeseal_cert.value' > kubeseal-cert.pem
```

## TODO:

- Modify init.sh so that it checks if backend already exists without looking the backend.tf file. If backend exists, it generates the backend.tf based on the existing backend. This way backend.tf could be gitignored and backend information does not need to committed. Use case: CI
- Is it possible to make `k8s` Terraform cloud-agnostic? For example ingress annotations could be defined in a variable.
- Using Github CLI to upload new deploy keys to repository (or just add documentation how to do that)
