set -e

BACKEND_FILE=backend.tf

mkdir -p ~/.terraform.d/plugins
curl \
  -L \
  -o provider.zip \
  https://github.com/hashicorp/terraform-provider-kubernetes-alpha/releases/download/v0.1.0/terraform-provider-kubernetes-alpha_0.1.0_darwin_amd64.zip
unzip provider.zip -d ~/.terraform.d/plugins


cd ./infra

if [ -f "$BACKEND_FILE" ]; then
    echo "Abort: $BACKEND_FILE exists"
    exit 0
fi

terraform init -input=false -reconfigure
terraform apply -auto-approve

terraform output -json | jq -r '.kube_config.value' > ../kubeconfig

cat > $BACKEND_FILE <<- EOM
terraform {
  backend "kubernetes" {
    secret_suffix    = "infra"
    load_config_file = true
    config_path      = "../kubeconfig"
  }
}
EOM

# Copy local state to the remote state
terraform init -force-copy -input=false

# Remove any local state files
rm *.tfstate*