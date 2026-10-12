#!/usr/bin/env bash
#
# bootstrap-state-azure.sh — create the Azure remote-state backend for a BYOC install.
#
# Terragrunt stores its state in an Azure Storage container, but Terraform cannot
# create the account that holds its own state (chicken-and-egg). Run this ONCE,
# after `az login`, before `terragrunt init`. It is idempotent: re-running against
# an existing backend is a no-op, so it is safe to retry.
#
# Usage:
#   ./scripts/bootstrap-state-azure.sh \
#     --subscription  <sub-id> \
#     --resource-group rg-autoheal-tfstate \
#     --storage-account stautohealtfstate \
#     --location       centralus \
#     [--container     tfstate]
#
# The three names must match the `remote_state.config` block in your
# examples/<name>/terragrunt.hcl. See docs/CONSUMING.md.

set -euo pipefail

SUBSCRIPTION=""
RESOURCE_GROUP=""
STORAGE_ACCOUNT=""
LOCATION=""
CONTAINER="tfstate"

die() { echo "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription)    SUBSCRIPTION="$2"; shift 2 ;;
    --resource-group)  RESOURCE_GROUP="$2"; shift 2 ;;
    --storage-account) STORAGE_ACCOUNT="$2"; shift 2 ;;
    --location)        LOCATION="$2"; shift 2 ;;
    --container)       CONTAINER="$2"; shift 2 ;;
    -h|--help)         grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                 die "unknown argument: $1" ;;
  esac
done

[[ -n "$SUBSCRIPTION"    ]] || die "--subscription is required"
[[ -n "$RESOURCE_GROUP"  ]] || die "--resource-group is required"
[[ -n "$STORAGE_ACCOUNT" ]] || die "--storage-account is required"
[[ -n "$LOCATION"        ]] || die "--location is required"

# Storage account names are a global namespace: 3-24 chars, lowercase letters and
# digits only. Catch the bad name here instead of 40s into a failed `az` call.
if ! [[ "$STORAGE_ACCOUNT" =~ ^[a-z0-9]{3,24}$ ]]; then
  die "storage-account '$STORAGE_ACCOUNT' is invalid: must be 3-24 lowercase letters/digits, no dashes"
fi

command -v az >/dev/null || die "az CLI not found on PATH"

echo "==> subscription $SUBSCRIPTION"
az account set --subscription "$SUBSCRIPTION" \
  || die "cannot select subscription — run 'az login' and confirm access"

# 1. Resource group ---------------------------------------------------------
if [[ "$(az group exists --name "$RESOURCE_GROUP")" == "true" ]]; then
  echo "==> resource group $RESOURCE_GROUP already exists"
else
  echo "==> creating resource group $RESOURCE_GROUP in $LOCATION"
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o none
fi

# 2. Storage account --------------------------------------------------------
# A name taken in another subscription returns a global-uniqueness error; surface
# it plainly rather than letting a later command fail cryptically.
if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" -o none 2>/dev/null; then
  echo "==> storage account $STORAGE_ACCOUNT already exists"
elif [[ "$(az storage account check-name --name "$STORAGE_ACCOUNT" --query nameAvailable -o tsv)" != "true" ]]; then
  die "storage account name '$STORAGE_ACCOUNT' is already taken (global namespace) — pick another"
else
  echo "==> creating storage account $STORAGE_ACCOUNT"
  az storage account create \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    -o none
  # Blob versioning gives state-file history — cheap insurance against a bad apply.
  az storage account blob-service-properties update \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --enable-versioning true \
    -o none
fi

# 3. Container --------------------------------------------------------------
KEY="$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query '[0].value' -o tsv)"

if [[ "$(az storage container exists --name "$CONTAINER" --account-name "$STORAGE_ACCOUNT" --account-key "$KEY" --query exists -o tsv)" == "true" ]]; then
  echo "==> container $CONTAINER already exists"
else
  echo "==> creating container $CONTAINER"
  az storage container create \
    --name "$CONTAINER" \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$KEY" \
    -o none
fi

cat <<DONE

State backend ready. Put these in your terragrunt.hcl remote_state.config:

  resource_group_name  = "$RESOURCE_GROUP"
  storage_account_name = "$STORAGE_ACCOUNT"
  container_name       = "$CONTAINER"

Next:
  cd examples/<your-copy>
  terragrunt init && terragrunt plan && terragrunt apply
DONE
