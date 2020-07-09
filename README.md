1. `cd terraform`
2. `./init.sh`

```
kubeseal kubeseal --fetch-cert \
--controller-namespace=kube-system \
--controller-name=sealed-secrets \
> pub-cert.pem
```
