1. `cd terraform`
2. `./init.sh`

```
terraform output -json | jq -r '.kubeseal_cert.value' > kubeseal-cert.pem
```
