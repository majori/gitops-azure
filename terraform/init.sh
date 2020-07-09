set -e

BACKEND_FILE=backend.tf

cd ./infra

if [ -f "$BACKEND_FILE" ]; then
    echo "Abort: $BACKEND_FILE exists"
    exit 0
fi

terraform init -input=false -reconfigure
terraform apply -auto-approve

OUTPUT=$(terraform output -json)

cat > $BACKEND_FILE <<- EOM
terraform {
  backend "azurerm" {
    resource_group_name   = "$(echo $OUTPUT | jq -r '.resource_group_name.value')"
    storage_account_name  = "$(echo $OUTPUT | jq -r '.storage_account_name.value')"
    container_name        = "$(echo $OUTPUT | jq -r '.container_name.value')"
    key                   = "infra.terraform.tfstate"
  }
}
EOM

# Copy local state to the remote state
terraform init -force-copy -input=false

# Remove local state files
rm *.tfstate*