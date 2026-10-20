# Runbook: Autoheal on an existing AKS cluster, public endpoints

This runbook installs Autoheal end to end on an AKS cluster that you already
have. The cluster stays in its subscription (the **cluster subscription**).
All the other Autoheal resources go in a second subscription (the **data
subscription**). The two VNets are not connected. The data services use public
endpoints with firewalls. [The one-pager](azure-two-subscriptions-public.md)
explains the layout, and [the comparison](azure-subscription-options.md) shows
its limits.

The runbook has two roles. One person can do both:

- The **cluster owner** prepares the cluster (steps 1 to 6 and step 10).
- The **deployer** runs Terraform in the data subscription (steps 7 to 9 and
  steps 11 to 13).

## Choose how you run Terraform

| | Terragrunt (state in Azure Blob) | Terraform Enterprise |
|---|---|---|
| Where Terraform runs | Your machine or your pipeline | The Terraform Enterprise workers |
| Where the state is | A storage account in the data subscription | The Terraform Enterprise workspace |
| How Terraform signs in to Azure | Your `az login`, or the pipeline's identity | The workspace identity, with OIDC and no password |
| How the chart is installed | The app folder, with Terragrunt | Helm, from your machine |

Steps 7, 8, 9 and 11 have one part for each: **With Terragrunt** and **With
Terraform Enterprise**. All the other steps are the same.

## Time

| Step | Hands-on | Waiting |
|------|----------|---------|
| 1 to 6: prepare the cluster | 30 min | 10 to 15 min for step 3; none when you skip it |
| 7 to 8: state or workspace, settings | 30 min (Terraform Enterprise: 45 min) | |
| 9: apply the infra | 5 min | 30 to 45 min |
| 10: NSG rule | 5 min | |
| 11: install the application | 10 min | 10 to 20 min |
| 12: check | 10 min | |
| 13 (optional): single sign-on | 20 min | |

These times are estimates. Plan half a day for a first install.

## Before you start

You must have:

- An AKS cluster on a subnet of a VNet that you manage. A cluster on the
  VNet that AKS makes for itself does not fit this runbook.
- A path from your machine to the cluster's API server on TCP 443. Step 4 and
  step 11 use it. Step 2 shows how to check it.
- A data subscription in the same Microsoft Entra tenant as the cluster.
- Owner on the cluster subscription and Kubernetes admin rights in the
  cluster, or the cluster owner's help for steps 1 to 6 and step 10. Owner on
  the subscription does not give Kubernetes rights; step 4 shows how to get
  them.
- For the deployer: Owner, or Contributor and User Access Administrator, on the
  data subscription.
- With Terraform Enterprise: access to your organization, and its public
  egress addresses (the addresses of the Terraform Enterprise workers or
  agents).
- An LLM provider, for example an Azure OpenAI resource with a key.
- A TLS certificate, with its private key, that covers `hostname`,
  `auth.<hostname>` and `auth-app.<hostname>`. The Autoheal proxy serves it.
  [Get a TLS certificate](#get-a-tls-certificate) shows how to make one.

Install these tools:

| Tool | For | Install |
|------|-----|---------|
| `az` CLI | both | https://learn.microsoft.com/cli/azure/install-azure-cli |
| `kubectl` and `kubelogin` | both | `az aks install-cli` installs both. It writes to `/usr/local/bin`, so it may need `sudo`: `sudo az aks install-cli`. On macOS, `brew install kubectl Azure/kubelogin/kubelogin` also works |
| `git`, `curl`, `jq`, `python3` | both | any version |
| Terraform 1.7 or later, or OpenTofu | Terragrunt | Terragrunt runs `tofu` from your PATH. To use Terraform, `export TG_TF_PATH=terraform` |
| Terragrunt | Terragrunt | https://terragrunt.gruntwork.io/docs/getting-started/install/ |
| Helm 3 | Terraform Enterprise | https://helm.sh/docs/intro/install/ |

`kubectl` cannot sign in to a cluster with Entra ID by itself. It runs
`kubelogin` to get a token for each request. The chart install in step 11 uses
`kubelogin` too. Make sure that each tool is installed:

```bash
az version
kubectl version --client
kubelogin --version
jq --version
tofu version || terraform version   # Terragrunt
terragrunt --version                # Terragrunt
helm version                        # Terraform Enterprise
```

> **Version.** This layout needs autoheal-byoc-infra **2.2.0 or later**. Step 1
> sets `INFRA_REF` to the release tag `v2.2.0` when it exists, and to the
> branch `feat/azure-two-subscriptions` until then. The later steps use it, so
> you change nothing yourself.

## Step 1: Sign in and set your values

Open one shell and keep it open. Every later step uses the variables you set
here. Steps 1 to 6 work from any folder. From step 7, the commands go to the
folders that they need themselves.

Sign in to Azure:

```bash
az login
```

`az login` opens a browser for the sign-in. Then it asks two questions in the
shell:

- **Tenant**, when your account is in more than one tenant. Pick the tenant
  that has both subscriptions. To skip this question, sign in with
  `az login --tenant <tenant ID>`.
- **Subscription**: a numbered list. Pick any subscription. The steps select
  the correct one with `az account set` each time they change subscription.

Set your values. This is the only block where you type values; the later
steps use these variables:

```bash
# Where this runbook keeps its files: a new folder, not inside a git checkout
export WORK_DIR="$HOME/autoheal-install"

# The cluster, in the cluster subscription
export CLUSTER_SUB="<cluster subscription ID>"
export AKS_RG="<resource group of the cluster>"
export AKS_NAME="<cluster name>"
export K8S_NAMESPACE="autoheal"        # the Kubernetes namespace that the cluster owner gives you

# The data subscription
export DATA_SUB="<data subscription ID>"
export LOCATION="<region of the cluster, for example eastus2>"
export NAME_PREFIX="acme"              # your short name; it starts every Azure resource name
export ENVIRONMENT="prod"
export RUNNER_CIDR="10.70.0.0/16"      # address range of the runner VNet; it is never connected to your VNet

# The Terraform state (with Terragrunt only): a new storage account that step 7 makes.
# Its name is made for you, unique in Azure; a later shell reads it back from root.hcl.
export STATE_RG="rg-${NAME_PREFIX}-tfstate"
export STATE_ACCOUNT=$(sed -n 's/.*storage_account_name *= *"\([a-z0-9]*\)".*/\1/p' \
  "$WORK_DIR/acme-autoheal/root.hcl" 2>/dev/null | grep -vx stacmetfstate)
[ -n "$STATE_ACCOUNT" ] ||
  export STATE_ACCOUNT="st$(echo "$NAME_PREFIX" | tr -cd 'a-z0-9' | cut -c1-9)tfstate$(openssl rand -hex 3)"

# Autoheal
export AUTOHEAL_HOSTNAME="autoheal.acme.example"   # the name users open; also auth.<name> and auth-app.<name>
export DNS_ZONE_ID=""                  # ID of an Azure DNS zone in the data subscription that holds the name; empty: you make the records
export ADMIN_EMAIL="<email of the first admin>"
export LLM_PROVIDER="azure-openai"
export LLM_ENDPOINT="https://<resource>.openai.azure.com/openai/v1/"   # not read with a gateway
export LLM_MODEL="gpt-5-mini"
export LLM_GATEWAY_URL=""              # Portkey: the gateway's OpenAI-compatible root, ending in /v1; empty: call the provider directly
export PORTKEY_CONFIG_FILE=""          # Portkey OSS only: its config JSON, with the routing and the provider keys; keep it outside any repository
export TLS_CERT_FILE="$HOME/certs/fullchain.pem"   # certificate chain for the three names; see "Get a TLS certificate" at the end
export TLS_KEY_FILE="$HOME/certs/privkey.pem"      # its private key
```

Make sure that every value is set. This command names each value that is
empty or still has a `<...>` placeholder; it must show nothing. Run it again
whenever you open a new shell:

```bash
for v in CLUSTER_SUB AKS_RG AKS_NAME K8S_NAMESPACE DATA_SUB LOCATION NAME_PREFIX ENVIRONMENT \
         RUNNER_CIDR STATE_RG STATE_ACCOUNT AUTOHEAL_HOSTNAME ADMIN_EMAIL LLM_PROVIDER LLM_ENDPOINT \
         LLM_MODEL TLS_CERT_FILE TLS_KEY_FILE WORK_DIR; do
  [ "$v" = LLM_ENDPOINT ] && [ -n "$LLM_GATEWAY_URL" ] && continue
  eval "val=\${$v}"
  case "$val" in ""|*"<"*) echo "Set $v in step 1";; esac
done
```

The autoheal-byoc-infra version to use: the release tag when it exists, the
branch until then:

```bash
export INFRA_REF=$(git ls-remote --tags https://github.com/autohealai/autoheal-byoc-infra.git refs/tags/v2.2.0 |
  grep -q . && echo v2.2.0 || echo feat/azure-two-subscriptions)
echo "$INFRA_REF"
```

Set the deployer: the identity that Terraform signs in as.

**With Terragrunt.** To deploy as yourself:

```bash
export DEPLOYER_ID=$(az ad signed-in-user show --query id -o tsv)
export DEPLOYER_TYPE=User
```

For a pipeline service principal, set `DEPLOYER_ID` to its object ID and
`DEPLOYER_TYPE=ServicePrincipal`.

**With Terraform Enterprise.** The deployer is the identity of the workspace:
an app registration that the workspace signs in as with OIDC. This makes it,
or finds it when it exists:

```bash
export TFE_ISSUER="https://app.terraform.io"   # or the address of your Terraform Enterprise, for example https://tfe.example.com
export TFE_ORG="<organization>"
export TFE_PROJECT="Default Project"
export TFE_WORKSPACE="autoheal-infra-prod"

export APP_ID=$(az ad app list --display-name "tfe-autoheal-byoc" --query "[0].appId" -o tsv)
[ -n "$APP_ID" ] || export APP_ID=$(az ad app create --display-name "tfe-autoheal-byoc" --query appId -o tsv)
az ad sp show --id "$APP_ID" -o none 2>/dev/null || az ad sp create --id "$APP_ID" -o none
for phase in plan apply; do
  az ad app federated-credential show --id "$APP_ID" --federated-credential-id "tfe-${TFE_WORKSPACE}-${phase}" -o none 2>/dev/null ||
    az ad app federated-credential create --id "$APP_ID" -o none --parameters "{
      \"name\": \"tfe-${TFE_WORKSPACE}-${phase}\",
      \"issuer\": \"${TFE_ISSUER}\",
      \"subject\": \"organization:${TFE_ORG}:project:${TFE_PROJECT}:workspace:${TFE_WORKSPACE}:run_phase:${phase}\",
      \"audiences\": [\"api://AzureADTokenExchange\"]
    }"
done
export DEPLOYER_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)
export DEPLOYER_TYPE=ServicePrincipal
```

## Step 2: Check the cluster

The first command selects the cluster subscription, whatever you picked at
sign-in.

```bash
az account set --subscription "$CLUSTER_SUB"
az aks show -g "$AKS_RG" -n "$AKS_NAME" --query "{
  entraId: aadProfile.managed,
  azureRbac: aadProfile.enableAzureRbac,
  oidcIssuer: oidcIssuerProfile.enabled,
  workloadIdentity: securityProfile.workloadIdentity.enabled,
  keyVaultAddon: addonProfiles.azureKeyvaultSecretsProvider.enabled,
  subnet: agentPoolProfiles[0].vnetSubnetId,
  outboundType: networkProfile.outboundType,
  nodeResourceGroup: nodeResourceGroup,
  privateCluster: apiServerAccessProfile.enablePrivateCluster,
  authorizedIpRanges: apiServerAccessProfile.authorizedIpRanges}" -o yaml
```

Make sure that:

- `entraId` and `azureRbac` are `true`. If not, see
  [Entra ID or Azure RBAC is off](#entra-id-or-azure-rbac-is-off).
- `subnet` is not empty. If it is, see
  [The cluster uses the VNet that AKS made](#the-cluster-uses-the-vnet-that-aks-made).
- `privateCluster` is not `true`, and `authorizedIpRanges` is empty. If not,
  see [Your machine cannot reach the API server](#your-machine-cannot-reach-the-api-server).

Step 3 turns on the other features.

## Step 3 (optional): Turn on the cluster features

Skip this step when step 2 shows `true` for `oidcIssuer`, `workloadIdentity`
and `keyVaultAddon`. Otherwise, run the command for each feature that does not
show `true`:

```bash
# oidcIssuer or workloadIdentity
az aks update -g "$AKS_RG" -n "$AKS_NAME" --enable-oidc-issuer --enable-workload-identity
# keyVaultAddon
az aks enable-addons -g "$AKS_RG" -n "$AKS_NAME" --addons azure-keyvault-secrets-provider
```

Each command takes 5 to 10 minutes.

## Step 4: Make the namespace and prepare the AKS subnet

Connect to the cluster, and make sure that your machine reaches the API
server:

```bash
az aks get-credentials -g "$AKS_RG" -n "$AKS_NAME" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
kubectl get --raw /readyz --request-timeout=20s; echo
```

The last command must show `ok`. A timeout means
that your machine cannot reach the API server. See
[Your machine cannot reach the API server](#your-machine-cannot-reach-the-api-server).

Make the namespace. The command makes it only when it does not exist, so it
works for a new namespace and for one you already have:

```bash
kubectl get namespace "$K8S_NAMESPACE" >/dev/null 2>&1 && echo "namespace $K8S_NAMESPACE exists" ||
  kubectl create namespace "$K8S_NAMESPACE"
```

It shows `namespace/<name> created` when it makes the namespace, and
`namespace <name> exists` when the namespace was there already. In that case,
do the next check. `Error from server (Forbidden)` means that
you have no Kubernetes rights in the cluster. See
[You cannot make the namespace](#you-cannot-make-the-namespace).

A namespace that exists already must not hold a different Autoheal install.
This command must show nothing, or only the release of this install when you
run the runbook again:

```bash
kubectl get secrets -n "$K8S_NAMESPACE" -l owner=helm,name=autoheal
```

If it shows a release from a different install, see
[The namespace holds another install](#the-namespace-holds-another-install).

Look at the service endpoints of the subnet:

```bash
export AKS_SUBNET_ID=$(az aks show -g "$AKS_RG" -n "$AKS_NAME" --query "agentPoolProfiles[0].vnetSubnetId" -o tsv)
az network vnet subnet show --ids "$AKS_SUBNET_ID" --query "serviceEndpoints[].service" -o tsv
```

No output means the subnet has no service endpoints yet. That is correct; go
on. If the list shows `Microsoft.KeyVault`, stop and see
[Key Vault service endpoint on the subnet](#key-vault-service-endpoint-on-the-subnet).

Add `Microsoft.Storage` and keep the endpoints that are already there:

```bash
az network vnet subnet update --ids "$AKS_SUBNET_ID" --service-endpoints \
  $(az network vnet subnet show --ids "$AKS_SUBNET_ID" --query "serviceEndpoints[].service" -o tsv | grep -vx Microsoft.Storage) \
  Microsoft.Storage
```

This change applies to all workloads on the subnet. They then reach Azure
Storage in this region through the service endpoint.

## Step 5: Reserve the two addresses

The static public IP for Temporal, in the node resource group:

```bash
export NODE_RG=$(az aks show -g "$AKS_RG" -n "$AKS_NAME" --query nodeResourceGroup -o tsv)
export TEMPORAL_IP=$(az network public-ip create -g "$NODE_RG" -n pip-autoheal-temporal \
  --location "$LOCATION" --sku Standard --allocation-method Static --query publicIp.ipAddress -o tsv)
echo "$TEMPORAL_IP"
```

The proxy address: where users open Autoheal. The chart puts the Autoheal
proxy, which serves the web app and the login over HTTPS, behind an internal
load balancer on this address. The DNS records for `hostname`,
`auth.<hostname>` and `auth-app.<hostname>` point to it. It is a private
address, so only machines on the cluster's network reach it.

It must be a free address in the AKS subnet. AKS gives addresses to nodes and
pods from the start of the subnet, so the address comes from the end. This
command tries the addresses from the end of the subnet, and keeps the first one
that Azure shows as free:

```bash
export SUBNET_PREFIX=$(az network vnet subnet show --ids "$AKS_SUBNET_ID" \
  --query "addressPrefix || addressPrefixes[0]" -o tsv)
unset PROXY_IP
for n in $(seq 2 20); do
  IP=$(python3 -c 'import ipaddress,sys; print(ipaddress.ip_network(sys.argv[1])[-int(sys.argv[2])])' "$SUBNET_PREFIX" "$n")
  if [ "$(az network vnet check-ip-address -g "$(echo "$AKS_SUBNET_ID" | cut -d/ -f5)" \
        -n "$(echo "$AKS_SUBNET_ID" | cut -d/ -f9)" --ip-address "$IP" --query available -o tsv)" = "true" ]; then
    export PROXY_IP="$IP"; break
  fi
done
echo "PROXY_IP=${PROXY_IP:-none found}"
```

It must show an address. The last address of a subnet is Azure's, so the
command starts one before it.

## Step 6: Get the outbound addresses and give the deployer its roles

The public outbound addresses of the cluster. Postgres and the Key Vaults let
in only these addresses, so they must stay fixed. For the `outboundType`
`loadBalancer` from step 2, this command finds them:

```bash
export EGRESS_IPS=$(az aks show -g "$AKS_RG" -n "$AKS_NAME" \
  --query "networkProfile.loadBalancerProfile.effectiveOutboundIPs[].id" -o tsv |
  xargs -n1 az network public-ip show --query ipAddress -o tsv --ids |
  sed 's|$|/32|' | paste -sd' ' -)
echo "$EGRESS_IPS"
```

It must show one or more addresses. For another `outboundType`, see
[Other outbound types](#other-outbound-types).

The deployer's roles:

```bash
export AKS_ID=$(az aks show -g "$AKS_RG" -n "$AKS_NAME" --query id -o tsv)
for grant in \
  "Azure Kubernetes Service Cluster User Role|$AKS_ID" \
  "Azure Kubernetes Service RBAC Admin|$AKS_ID/namespaces/$K8S_NAMESPACE" \
  "Reader|$AKS_SUBNET_ID" \
  "Network Contributor|$AKS_SUBNET_ID"; do
  az role assignment create --assignee-object-id "$DEPLOYER_ID" \
    --assignee-principal-type "$DEPLOYER_TYPE" \
    --role "${grant%%|*}" --scope "${grant#*|}" -o none
done
```

Role grants can take up to 10 minutes to take effect.

## Step 7: Prepare the data subscription

For both, register the resource providers:

```bash
az account set --subscription "$DATA_SUB"
for ns in Microsoft.DBforPostgreSQL Microsoft.Cache Microsoft.Storage \
          Microsoft.KeyVault Microsoft.Network Microsoft.ManagedIdentity Microsoft.Compute; do
  az provider register --namespace "$ns"
done
```

### With Terragrunt: the deployment repository and the state storage account

Your deployment repository holds only settings, not our Terraform code. Each
`terragrunt.hcl` points at a tag of autoheal-byoc-infra, and Terragrunt
downloads the code at that tag on every run. The tag is `infra_version` in
`versions.hcl`. The layout is the same as for
[one subscription](getting-started.md). This step makes these folders in
`$WORK_DIR`:

```text
$WORK_DIR/                     for example ~/autoheal-install
  autoheal-byoc-infra/         a copy, for the starter files and the state script; not your repository
  acme-autoheal/               your deployment repository
    root.hcl                   the state backend, for every environment
    prod/
      versions.hcl             the infra tag and the chart version
      infra/terragrunt.hcl     the infra inputs (step 8)
      app/terragrunt.hcl       the app inputs (step 11)
      app/values-customer.yaml your chart settings (step 11)
```

```bash
mkdir -p "$WORK_DIR" && cd "$WORK_DIR"
[ -d autoheal-byoc-infra ] || git clone --branch "$INFRA_REF" https://github.com/autohealai/autoheal-byoc-infra.git
mkdir -p acme-autoheal
[ -e acme-autoheal/root.hcl ] || cp autoheal-byoc-infra/examples/azure/root.hcl acme-autoheal/
[ -e acme-autoheal/prod ] || cp -R autoheal-byoc-infra/examples/azure/split-public acme-autoheal/prod
cd "$WORK_DIR/acme-autoheal"
```

You can run these commands again. They keep a copy and files that are there
already, so they do not overwrite your edits.

To keep your settings in git, make `acme-autoheal` a git repository of your
own (`git init`) and push it to your own remote. For a second environment, copy
`prod/` to `staging/` and change its inputs. Each environment folder has its
own state.

Put the names of the state storage in `root.hcl`, then make the storage account
and its container:

```bash
if [ -z "$STATE_RG" ] || [ -z "$STATE_ACCOUNT" ] || [ -z "${STATE_ACCOUNT##*<*}" ]; then
  echo "Set STATE_RG and STATE_ACCOUNT in step 1 first"
else
  cd "$WORK_DIR/acme-autoheal"
  perl -pi -e 's/^(\s*resource_group_name\s*=\s*)"[^"]*"/$1"$ENV{STATE_RG}"/;
               s/^(\s*storage_account_name\s*=\s*)"[^"]*"/$1"$ENV{STATE_ACCOUNT}"/' root.hcl
  grep -n 'resource_group_name\|storage_account_name\|container_name' root.hcl
  "$WORK_DIR/autoheal-byoc-infra/scripts/bootstrap-state-azure.sh" \
    --subscription "$DATA_SUB" --resource-group "$STATE_RG" \
    --storage-account "$STATE_ACCOUNT" --location "$LOCATION"
fi
```

The script also gives you Storage Blob Data Contributor on the account. A
pipeline identity needs the same role.

### With Terraform Enterprise: the workspace

Give the workspace identity its rights in the data subscription:

```bash
az role assignment create --assignee "$APP_ID" --role "Contributor" --scope "/subscriptions/$DATA_SUB"
az role assignment create --assignee "$APP_ID" --role "User Access Administrator" --scope "/subscriptions/$DATA_SUB"
```

Then, in Terraform Enterprise, do Step 6 and Step 8 of Part B in
[terraform-enterprise.md](terraform-enterprise.md):

- Make the workspace `autoheal-infra-prod`, with the Terraform working
  directory `compositions/azure`, on a branch of your copy that has 2.2.0 or
  later. Set the workspace Terraform version to 1.7 or later.
- Add the four environment variables for the sign-in. `ARM_SUBSCRIPTION_ID`
  is `$DATA_SUB`. The composition reads the cluster in the cluster subscription
  with the same identity.

The workspace keeps the state. You do not make a storage account.

## Step 8: Set the inputs

The public address of the apply host. The Key Vaults let it in, so that
Terraform can write the vault entries.

**With Terragrunt**, on this machine:

```bash
export DEPLOYER_IPS="$(curl -s https://api.ipify.org)/32"
echo "$DEPLOYER_IPS"
```

**With Terraform Enterprise**, the public egress addresses of the workers or
agents:

```bash
export DEPLOYER_IPS="<address>/32"   # several: separate them with spaces
```

For both, write the inputs into `$WORK_DIR/inputs.hcl`:

```bash
cat > "$WORK_DIR/inputs.hcl" <<EOF
namespace       = "$NAME_PREFIX"
environment     = "$ENVIRONMENT"
location        = "$LOCATION"
subscription_id = "$DATA_SUB"

existing_aks_cluster_id = "$AKS_ID"
cluster_network_path    = "public"
existing_network = {
  aks_subnet_id = "$AKS_SUBNET_ID"
  temporal_ip   = "$TEMPORAL_IP"
  proxy_ip      = "$PROXY_IP"
}
service_accounts          = { namespace = "$K8S_NAMESPACE" }
workload_egress_ip_ranges = [$(echo "$EGRESS_IPS" | tr ' ' '\n' | sed 's/.*/"&"/' | paste -sd, -)]
deployer_ip_ranges        = [$(echo "$DEPLOYER_IPS" | tr ' ' '\n' | sed 's/.*/"&"/' | paste -sd, -)]
network_cidr              = "$RUNNER_CIDR"

hostname  = "$AUTOHEAL_HOSTNAME"
edge_mode = "loadbalancer"
$([ -n "$DNS_ZONE_ID" ] && echo "existing_dns_zone_id = \"$DNS_ZONE_ID\"" || echo "create_dns_records = false")
EOF
cat "$WORK_DIR/inputs.hcl"
```

Without `DNS_ZONE_ID`, Terraform makes no DNS records, and step 9 lists the
records for you to make. See
[The DNS zone is not in the data subscription](#the-dns-zone-is-not-in-the-data-subscription).

**With Terragrunt.** Write the infra folder from the inputs. Its `source` line
downloads our code at the release tag, or at the branch until the release:

```bash
cd "$WORK_DIR/acme-autoheal/prod/infra"
[ "$INFRA_REF" = "v2.2.0" ] && SOURCE_REF='v${local.v.infra_version}' || SOURCE_REF="$INFRA_REF"
{
  cat <<EOF
# The cloud resources in the data subscription. Written by step 8 of
# docs/azure-two-subscriptions-public-runbook.md.

locals { v = read_terragrunt_config(find_in_parent_folders("versions.hcl")).locals }

include "root" { path = find_in_parent_folders("root.hcl") }

terraform {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure?ref=$SOURCE_REF"
}

inputs = {
  autoheal_version = local.v.chart_version

EOF
  sed 's/^/  /; s/^  $//' "$WORK_DIR/inputs.hcl"
  echo "}"
} > terragrunt.hcl
cat terragrunt.hcl
```

Set the namespace and the `source` line of the app folder:

```bash
cd "$WORK_DIR/acme-autoheal/prod/app"
perl -pi -e 's/^(\s*namespace\s*=\s*)"[^"]*"/$1"$ENV{K8S_NAMESPACE}"/' terragrunt.hcl
[ "$INFRA_REF" = "v2.2.0" ] || perl -pi -e 's/\?ref=v\$\{local\.v\.infra_version\}/?ref=$ENV{INFRA_REF}/' terragrunt.hcl
grep -n 'source =\|^ *namespace ' terragrunt.hcl
```

Set the secrets as environment variables. They never go in a file:

```bash
export TF_VAR_tls_certificate=$(jq -n --rawfile c "$TLS_CERT_FILE" --rawfile k "$TLS_KEY_FILE" \
  '{certificate: $c, private_key: $k}')
```

Without a gateway (`LLM_GATEWAY_URL` empty), the key of your LLM provider:

```bash
export TF_VAR_llm_api_key="<your LLM provider key>"
```

With a Portkey gateway, the gateway secrets instead. The gateway holds the
provider keys:

```bash
unset TF_VAR_llm_api_key
export TF_VAR_llm_gateway_api_key="<Portkey API key; Portkey OSS ignores it, so any value, for example unused>"
[ -z "$PORTKEY_CONFIG_FILE" ] ||
  export TF_VAR_llm_gateway_extra_headers="$(jq -cn --arg cfg "$(jq -c . "$PORTKEY_CONFIG_FILE")" '{"x-portkey-config": $cfg}')"
```

**With Terraform Enterprise.** In the workspace, open **Variables**, and add
each line of the output below as a variable of the category **Terraform**. The
key is the name before `=`; the value is the part after it. For
`existing_network`, `service_accounts` and the two `_ranges` lists, tick
**HCL**:

```bash
cat "$WORK_DIR/inputs.hcl"
echo 'autoheal_version = "1.0.0-rc.8"'
```

Add the secrets as **Sensitive** variables of the category **Terraform**.
`tls_certificate`, with **HCL** ticked, takes the output of this command:

```bash
jq -n --rawfile c "$TLS_CERT_FILE" --rawfile k "$TLS_KEY_FILE" '{certificate: $c, private_key: $k}'
```

Without a gateway, add `llm_api_key` with your LLM provider key. With a Portkey
gateway, add `llm_gateway_api_key` with the Portkey API key (any value for
Portkey OSS) and, for Portkey OSS, `llm_gateway_extra_headers` with the output
of this command:

```bash
jq -cn --arg cfg "$(jq -c . "$PORTKEY_CONFIG_FILE")" '{"x-portkey-config": $cfg}'
```

For a certificate from a private CA, see
[A certificate from a private CA](#a-certificate-from-a-private-ca).

## Step 9: Apply the infra

**With Terragrunt:**

```bash
cd "$WORK_DIR/acme-autoheal/prod/infra"
terragrunt plan
terragrunt apply
```

Read the plan before you type `yes`. Then read the outputs, and keep the runner
address:

```bash
terragrunt output temporal_public_endpoint         # the runner address
terragrunt output required_cluster_owner_actions   # the list from steps 2 to 6, with real values
terragrunt output required_dns_records             # empty when Terraform made the records; else see "The DNS zone is not in the data subscription"
export RUNNER_IP=$(terragrunt output -json temporal_public_endpoint | jq -r '.allowed_source_ranges[0]' | cut -d/ -f1)
```

**With Terraform Enterprise:** in the workspace, click **Actions**, then
**Start new run**. Read the plan, then click **Confirm & Apply**. Then open the
**Outputs** tab. Keep the address in `temporal_public_endpoint.allowed_source_ranges`,
without `/32`:

```bash
export RUNNER_IP="<the address>"
```

Save the value of `autoheal_values_yaml` for step 11. Run this command, paste
the value, then press Ctrl-D:

```bash
cat > "$WORK_DIR/values-infra.yaml"
```

Read `required_cluster_owner_actions` and `required_dns_records` there too.
When `required_dns_records` is not empty, see
[The DNS zone is not in the data subscription](#the-dns-zone-is-not-in-the-data-subscription).

For both, when the plan stops with an error, the message names the
input to change. The apply takes 30 to 45 minutes; Postgres and Redis are the
slow parts.

## Step 10: Let the runner through the subnet NSG

When the AKS subnet has an NSG, add two rules to it: let only the runner reach
the Temporal address on TCP 7233 and 8083, and deny all other sources. Without
an NSG, AKS opens its own NSG for the load balancers, and the command does
nothing. The rules take the first free priorities from 300:

```bash
az account set --subscription "$CLUSTER_SUB"
export NSG_ID=$(az network vnet subnet show --ids "$AKS_SUBNET_ID" --query networkSecurityGroup.id -o tsv)
echo "NSG: ${NSG_ID:-none}"
if [ -n "$NSG_ID" ]; then
  export NSG_RG=$(echo "$NSG_ID" | cut -d/ -f5) NSG_NAME=$(echo "$NSG_ID" | cut -d/ -f9)
  USED=$(az network nsg rule list -g "$NSG_RG" --nsg-name "$NSG_NAME" \
    --query "[?name!='allow-autoheal-runner' && name!='deny-others-to-autoheal-temporal'].priority" -o tsv)
  ALLOW_PRIORITY=300; while echo "$USED" | grep -qx "$ALLOW_PRIORITY"; do ALLOW_PRIORITY=$((ALLOW_PRIORITY+1)); done
  DENY_PRIORITY=$((ALLOW_PRIORITY+1)); while echo "$USED" | grep -qx "$DENY_PRIORITY"; do DENY_PRIORITY=$((DENY_PRIORITY+1)); done
  az network nsg rule create -g "$NSG_RG" --nsg-name "$NSG_NAME" -o none \
    -n allow-autoheal-runner --priority "$ALLOW_PRIORITY" --direction Inbound --access Allow --protocol Tcp \
    --source-address-prefixes "$RUNNER_IP" --destination-address-prefixes "$TEMPORAL_IP" \
    --destination-port-ranges 7233 8083
  az network nsg rule create -g "$NSG_RG" --nsg-name "$NSG_NAME" -o none \
    -n deny-others-to-autoheal-temporal --priority "$DENY_PRIORITY" --direction Inbound --access Deny --protocol '*' \
    --source-address-prefixes '*' --destination-address-prefixes "$TEMPORAL_IP" \
    --destination-port-ranges 7233 8083
  echo "Rules added at priorities $ALLOW_PRIORITY and $DENY_PRIORITY"
fi
```

## Step 11: Install the application

Your chart settings go in `values-customer.yaml`. Where the file is:

```bash
export VALUES_FILE="$WORK_DIR/acme-autoheal/prod/app/values-customer.yaml"   # with Terragrunt
# export VALUES_FILE="$WORK_DIR/values-customer.yaml"                      # with Terraform Enterprise
```

Write it. Single sign-on stays off here; step 13 adds it after the install:

```bash
mkdir -p "$(dirname "$VALUES_FILE")"
cat > "$VALUES_FILE" <<EOF
# Your chart settings. Written by step 11 of docs/azure-two-subscriptions-public-runbook.md.
# Do not set global.infra: those values come from the infra.
global:
  adminEmail: $ADMIN_EMAIL
  tenant:
    name: $NAME_PREFIX
  edge:
    mode: loadbalancer
    exposure: internal
    tls:
      secretName: autoheal-tls
  llm:
    provider: $LLM_PROVIDER
    model: $LLM_MODEL
$(if [ -n "$LLM_GATEWAY_URL" ]; then
  printf '    gateway:\n      enabled: true\n      kind: portkey\n      baseUrl: %s\n' "$LLM_GATEWAY_URL"
else
  printf '    endpoint: %s\n    apiKeyVaultEntry: llm-api-key\n' "$LLM_ENDPOINT"
fi)
  sso:
    enabled: false
  imageRegistry: ""
EOF
cat "$VALUES_FILE"
```

For an Azure OpenAI resource, the endpoint ends in `/openai/v1/`, and the
resource also needs an embedding deployment named `text-embedding-3-large`.
See Step 7 of [getting-started.md](getting-started.md). With a gateway, see
[A Portkey gateway](#a-portkey-gateway).

**With Terragrunt:**

```bash
cd "$WORK_DIR/acme-autoheal/prod/app"
terragrunt plan
terragrunt apply
```

The apply installs the chart in `$K8S_NAMESPACE` and makes the two public load
balancers on `$TEMPORAL_IP`.

**With Terraform Enterprise.** The workers have no `kubelogin`, so you
install the chart from your machine with Helm. Helm signs in as you, with the
access from step 4. Install the chart:

```bash
cd "$WORK_DIR"
helm upgrade --install autoheal oci://public.ecr.aws/e4h3h0d9/charts/autoheal \
  --version 1.0.0-rc.8 -n "$K8S_NAMESPACE" \
  -f values-infra.yaml -f "$VALUES_FILE" --atomic --wait --timeout 20m
```

Then make the two public load balancers on `$TEMPORAL_IP`, open only to the
runner, with a network policy for each:

```bash
kubectl apply -n "$K8S_NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: temporal-frontend-public
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-ipv4: "$TEMPORAL_IP"
spec:
  type: LoadBalancer
  externalTrafficPolicy: Local
  loadBalancerSourceRanges: ["$RUNNER_IP/32"]
  selector:
    app.kubernetes.io/name: temporal
    app.kubernetes.io/instance: autoheal
    app.kubernetes.io/component: frontend
  ports:
    - { name: grpc-rpc, port: 7233, targetPort: rpc, protocol: TCP }
---
apiVersion: v1
kind: Service
metadata:
  name: api-server-go-public
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-ipv4: "$TEMPORAL_IP"
spec:
  type: LoadBalancer
  externalTrafficPolicy: Local
  loadBalancerSourceRanges: ["$RUNNER_IP/32"]
  selector:
    app.kubernetes.io/name: api-server-go
    app.kubernetes.io/instance: autoheal
  ports:
    - { name: internal, port: 8083, targetPort: 8083, protocol: TCP }
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: temporal-frontend-public
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: temporal
      app.kubernetes.io/instance: autoheal
      app.kubernetes.io/component: frontend
  policyTypes: [Ingress]
  ingress:
    - from: [{ ipBlock: { cidr: "$RUNNER_IP/32" } }]
      ports: [{ port: 7233, protocol: TCP }]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-server-go-public
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: api-server-go
      app.kubernetes.io/instance: autoheal
  policyTypes: [Ingress]
  ingress:
    - from: [{ ipBlock: { cidr: "$RUNNER_IP/32" } }]
      ports: [{ port: 8083, protocol: TCP }]
EOF
```

These are the same objects that the app folder makes with Terragrunt.

For both, the install takes 10 to 20 minutes.

## Step 12: Check that it works

```bash
kubectl get pods -n "$K8S_NAMESPACE"      # all Running and ready
kubectl get svc -n "$K8S_NAMESPACE" temporal-frontend-public api-server-go-public   # EXTERNAL-IP is $TEMPORAL_IP
kubectl get secrets -n "$K8S_NAMESPACE"   # the secrets synced from Key Vault
```

The runner VMs connect to Temporal:

```bash
az account set --subscription "$DATA_SUB"
az vmss run-command invoke -g "rg-$NAME_PREFIX-$ENVIRONMENT-autoheal" -n "$NAME_PREFIX-$ENVIRONMENT-autoheal-runner" \
  --instance-id 0 --command-id RunShellScript --scripts "docker logs --tail 30 runner-go"
```

The log must show a connection to `$TEMPORAL_IP:7233`.

With a gateway, model calls go to the gateway. Start a chat in Autoheal, then
check that each line names the gateway address, not the provider:

```bash
kubectl logs -n "$K8S_NAMESPACE" deploy/agents-py-worker --since=10m | grep 'HTTP Request: POST'
```

Only the runner can reach Temporal. From your own machine, this command must
time out:

```bash
nc -vz -w 5 "$TEMPORAL_IP" 7233
```

Open Autoheal from a machine on the cluster's network. The proxy address
`$PROXY_IP` is private:

```bash
echo "https://$AUTOHEAL_HOSTNAME"
```

## Step 13 (optional): Turn on single sign-on

Single sign-on is set up after the install. The chart does not configure your
identity provider in this version: you add it in the Zitadel console, which
Autoheal uses for sign-in.

Get the password of the first admin, from the install vault:

```bash
az account set --subscription "$DATA_SUB"
export VAULT_NAME=$(cd "$WORK_DIR/acme-autoheal/prod/infra" && terragrunt output -json autoheal_values | jq -r .global.infra.keyVault.name)   # with Terragrunt
# export VAULT_NAME=$(grep -A2 'keyVault:' "$WORK_DIR/values-infra.yaml" | sed -n 's/.*name: *//p')          # with Terraform Enterprise
az keyvault secret show --vault-name "$VAULT_NAME" --name first-admin-password --query value -o tsv
echo "https://auth.$AUTOHEAL_HOSTNAME"
```

The vault firewall lets in the apply host, so run this on the machine of step 8.
Then:

1. Open the address that the last command shows, and sign in as `$ADMIN_EMAIL`
   with that password. Zitadel asks for a new password.
2. In your identity provider, for example Microsoft Entra ID, make an app
   registration for Autoheal, with a client secret.
3. In the Zitadel console, add the identity provider with the client ID and the
   secret of step 2. Zitadel shows the redirect URI; add it to the app
   registration of step 2.

Users then sign in to `https://$AUTOHEAL_HOSTNAME` with your identity provider.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Step 4 shows `Error from server (Forbidden)` | You have no Kubernetes rights in the cluster | See [You cannot make the namespace](#you-cannot-make-the-namespace) |
| Step 4 or step 11 times out with `dial tcp <address>:443: i/o timeout` | Your machine cannot reach the API server | See [Your machine cannot reach the API server](#your-machine-cannot-reach-the-api-server) |
| Step 9 stops on "workload_egress_ip_ranges" or "temporal_ip" | An input from step 8 is missing or private | Set it as the message says |
| Step 9 fails with 403 on Key Vault entries | `deployer_ip_ranges` is not the address of the apply host | Find the address again (step 8) and update the input |
| Step 9 fails to add the subnet to the storage account | No service endpoint, or no Network Contributor on the subnet | Do the service endpoint part of step 4, or the last grant of step 6 |
| Step 9 fails to read the cluster or the subnet | Role grants not in effect yet, or given to another identity | Wait 10 minutes and apply again. With Terraform Enterprise: check that `DEPLOYER_ID` is the workspace identity |
| With Terraform Enterprise: the run fails to sign in to Azure | The OIDC links or the environment variables of step 7 | Check Step 4 of Part A and Step 8 of Part B in [terraform-enterprise.md](terraform-enterprise.md) |
| Step 11 fails with Forbidden | The namespace role is missing or not in effect yet, or the namespace is not `$K8S_NAMESPACE` | Check step 6 and step 11, wait, then try again |
| The secrets-sync job fails to sign in to Key Vault | `service_accounts.namespace` is not `$K8S_NAMESPACE` | Fix it in step 8 and apply step 9 again |
| The proxy pod waits for the Secret `autoheal-tls` | `tls_certificate` was not set in step 8 | Set it and apply step 9 again |
| Step 13 shows `Forbidden` from Key Vault | The vault firewall does not let in this machine, or you are not the deployer | Run it on the machine of step 8, as the deployer |
| Pods wait for secrets, or show 403 from Key Vault | The cluster's outbound addresses changed or are wrong | Update `workload_egress_ip_ranges` and apply step 9 again |
| Pods cannot reach Postgres | The same | The same |
| `temporal-frontend-public` stays `<pending>` | The IP is not in the node resource group, or is not Standard and static | Do step 5 again |
| The runner log shows no connection to Temporal | The NSG blocks the runner | Do step 10 |

## Upgrade

The cluster owner does not have to give new permissions.

- With Terragrunt: set the two new numbers, then apply step 9 and step 11
  again. The command also points the `source` lines at the release tag:

  ```bash
  export NEW_INFRA_VERSION="<new autoheal-byoc-infra version, for example 2.2.1>"
  export NEW_CHART_VERSION="<new chart version>"
  cd "$WORK_DIR/acme-autoheal/prod"
  perl -pi -e 's/^(\s*infra_version\s*=\s*)"[^"]*"/$1"$ENV{NEW_INFRA_VERSION}"/;
               s/^(\s*chart_version\s*=\s*)"[^"]*"/$1"$ENV{NEW_CHART_VERSION}"/' versions.hcl
  perl -pi -e 's/\?ref=[^"]*"/?ref=v\$\{local.v.infra_version}"/' infra/terragrunt.hcl app/terragrunt.hcl
  grep -n 'version' versions.hcl; grep -n 'source =' infra/terragrunt.hcl app/terragrunt.hcl
  ```
- With Terraform Enterprise: move the workspace branch to the new release and
  set `autoheal_version` to the new chart version. Apply step 9 again. Save the
  new `values-infra.yaml`, then run the `helm upgrade` of step 11 with the new
  `--version`.

## Remove

With Terragrunt:

```bash
cd "$WORK_DIR/acme-autoheal/prod/app" && terragrunt destroy
cd "$WORK_DIR/acme-autoheal/prod/infra" && terragrunt destroy
```

With Terraform Enterprise:

```bash
kubectl delete -n "$K8S_NAMESPACE" service/temporal-frontend-public service/api-server-go-public \
  networkpolicy/temporal-frontend-public networkpolicy/api-server-go-public
helm uninstall autoheal -n "$K8S_NAMESPACE"
```

Then, in the workspace, queue a destroy run: **Settings**, **Destruction and
Deletion**, **Queue destroy plan**.

For both, as the cluster owner, remove the static IP, the NSG rules and the
deployer's roles:

```bash
az account set --subscription "$CLUSTER_SUB"
az network public-ip delete -g "$NODE_RG" -n pip-autoheal-temporal
if [ -n "$NSG_ID" ]; then
  az network nsg rule delete -g "$NSG_RG" --nsg-name "$NSG_NAME" -n allow-autoheal-runner
  az network nsg rule delete -g "$NSG_RG" --nsg-name "$NSG_NAME" -n deny-others-to-autoheal-temporal
fi
for grant in \
  "Azure Kubernetes Service Cluster User Role|$AKS_ID" \
  "Azure Kubernetes Service RBAC Admin|$AKS_ID/namespaces/$K8S_NAMESPACE" \
  "Reader|$AKS_SUBNET_ID" \
  "Network Contributor|$AKS_SUBNET_ID"; do
  az role assignment delete --assignee "$DEPLOYER_ID" --role "${grant%%|*}" --scope "${grant#*|}"
done
```

Only if step 4 made the namespace for Autoheal:

```bash
kubectl delete namespace "$K8S_NAMESPACE"
```

Only if no other workload on the AKS subnet uses the `Microsoft.Storage`
service endpoint:

```bash
OTHER_ENDPOINTS=$(az network vnet subnet show --ids "$AKS_SUBNET_ID" --query "serviceEndpoints[].service" -o tsv | grep -vx Microsoft.Storage)
if [ -n "$OTHER_ENDPOINTS" ]; then
  az network vnet subnet update --ids "$AKS_SUBNET_ID" --service-endpoints $(echo "$OTHER_ENDPOINTS") -o none
else
  az network vnet subnet update --ids "$AKS_SUBNET_ID" --remove serviceEndpoints -o none
fi
```

## Edge cases and references

The steps above cover the usual cluster. These cases need one more action.

### Entra ID or Azure RBAC is off

`kubelogin` needs Entra ID, and the namespace role in step 6 needs Azure RBAC.
On a cluster with Entra ID, turn on Azure RBAC:

```bash
az aks update -g "$AKS_RG" -n "$AKS_NAME" --enable-azure-rbac
```

A cluster without Entra ID needs it first. That change cannot be undone, so
agree it with the cluster owner.

- [Microsoft Entra ID authentication for AKS](https://learn.microsoft.com/azure/aks/enable-authentication-microsoft-entra-id)
- [Azure RBAC for Kubernetes authorization](https://learn.microsoft.com/azure/aks/manage-azure-rbac)

### Your machine cannot reach the API server

The API server is the front door of the cluster: `kubectl` and Helm send every
request to it. When it does not answer, `kubectl` waits, then shows
`dial tcp <address>:443: i/o timeout`. There are two causes.

**Authorized IP ranges.** The API server drops connections from addresses that
are not in `authorizedIpRanges`. This command shows the list and your address,
then adds your address and keeps the others. It changes nothing when the list
is empty, because then every address may connect, or when your address is in
it already:

```bash
export MY_IP=$(curl -s https://api.ipify.org)
export RANGES=$(az aks show -g "$AKS_RG" -n "$AKS_NAME" \
  --query "apiServerAccessProfile.authorizedIpRanges" -o tsv | paste -sd, -)
echo "Allowed: ${RANGES:-every address}. Your address: $MY_IP"
if [ -n "$RANGES" ] && ! echo ",$RANGES," | grep -q ",$MY_IP/32,"; then
  az aks update -g "$AKS_RG" -n "$AKS_NAME" \
    --api-server-authorized-ip-ranges "$RANGES,$MY_IP/32"
fi
```

The update takes a few minutes. The public address of a home or mobile
connection can change; when `kubectl` times out again, run the command again.
A pipeline that runs step 11 needs its own address in the list.

**Private cluster.** `privateCluster` is `true`: the API server has no public
address. Run step 4 and step 11 from a machine on the cluster's network, for
example over a VPN or from a VM in a connected VNet.

- [Authorized IP address ranges for the AKS API server](https://learn.microsoft.com/azure/aks/api-server-authorized-ip-ranges)
- [Private AKS clusters](https://learn.microsoft.com/azure/aks/private-clusters)

### You cannot make the namespace

`kubectl` shows `Error from server (Forbidden): namespaces is forbidden ...
User does not have access to the resource in Azure`. The cluster uses Azure
RBAC for Kubernetes. Owner on the subscription lets you manage the cluster as
an Azure resource, but gives no rights in Kubernetes. Give yourself Azure
Kubernetes Service RBAC Cluster Admin on the cluster:

```bash
az role assignment create \
  --assignee-object-id "$(az ad signed-in-user show --query id -o tsv)" \
  --assignee-principal-type User \
  --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --scope "$(az aks show -g "$AKS_RG" -n "$AKS_NAME" --query id -o tsv)"
```

The grant can take up to 10 minutes to take effect. Then run the namespace
command of step 4 again. Membership in an admin group of the cluster
(`aadProfile.adminGroupObjectIDs`) also gives these rights.

- [Azure RBAC for Kubernetes authorization](https://learn.microsoft.com/azure/aks/manage-azure-rbac)

### The cluster uses the VNet that AKS made

`subnet` in step 2 is empty. The cluster runs on a VNet that AKS made and
manages. This runbook changes the AKS subnet (step 4) and its NSG (step 10),
which you cannot do on that VNet. Use a cluster on a subnet of a VNet that you
manage.

- [Azure CNI networking in AKS](https://learn.microsoft.com/azure/aks/configure-azure-cni)

### Key Vault service endpoint on the subnet

The `Microsoft.KeyVault` service endpoint sends the cluster's Key Vault traffic
over the subnet, not from its public addresses. The Key Vault firewall of this
layout lets in public addresses only, so it cannot let the pods in. Use the
[connected VNets](azure-two-subscriptions.md) layout instead.

- [Virtual network service endpoints](https://learn.microsoft.com/azure/virtual-network/virtual-network-service-endpoints-overview)
- [Key Vault network security](https://learn.microsoft.com/azure/key-vault/general/network-security)

### The namespace holds another install

The check in step 4 shows a Helm release named `autoheal` from a different
install. Two installs in one namespace overwrite each other. Remove the other
install first, or use a different namespace and start again from step 4:

```bash
export K8S_NAMESPACE="autoheal-public"
```

### Other outbound types

Step 6 finds the outbound addresses for the `outboundType` `loadBalancer`. For
`managedNATGateway`:

```bash
export EGRESS_IPS=$(az aks show -g "$AKS_RG" -n "$AKS_NAME" \
  --query "networkProfile.natGatewayProfile.effectiveOutboundIPs[].id" -o tsv |
  xargs -n1 az network public-ip show --query ipAddress -o tsv --ids |
  sed 's|$|/32|' | paste -sd' ' -)
```

For `userDefinedRouting` or `userAssignedNATGateway`, the traffic leaves through
your own firewall or NAT gateway. Set its public addresses:

```bash
export EGRESS_IPS="<address>/32"   # several: separate them with spaces
```

If that firewall serves other workloads, they share these addresses, and the
firewalls of Postgres and the Key Vaults let them in too.

- [Outbound types in AKS](https://learn.microsoft.com/azure/aks/egress-outboundtype)

### The DNS zone is not in the data subscription

Terraform makes the DNS records only in an Azure DNS zone in the data
subscription. For a zone in another place, keep `DNS_ZONE_ID` empty in step 1,
and make the three records after step 9. Each record is an A record with the
value `$PROXY_IP`.

For an Azure DNS zone in another subscription, for example the cluster
subscription:

```bash
export RECORDS_ZONE_ID="<ID of the Azure DNS zone that holds AUTOHEAL_HOSTNAME>"
export ZONE_SUB=$(echo "$RECORDS_ZONE_ID" | cut -d/ -f3) ZONE_RG=$(echo "$RECORDS_ZONE_ID" | cut -d/ -f5) \
  ZONE_NAME=$(echo "$RECORDS_ZONE_ID" | cut -d/ -f9)
for h in "$AUTOHEAL_HOSTNAME" "auth.$AUTOHEAL_HOSTNAME" "auth-app.$AUTOHEAL_HOSTNAME"; do
  az network dns record-set a add-record --subscription "$ZONE_SUB" -g "$ZONE_RG" -z "$ZONE_NAME" \
    -n "${h%.$ZONE_NAME}" -a "$PROXY_IP" -o none
done
```

`AUTOHEAL_HOSTNAME` must be a name below that zone.

For DNS outside Azure, make the three records by hand in your DNS provider:
`AUTOHEAL_HOSTNAME`, `auth.` and `auth-app.` before it, each an A record with
the value `$PROXY_IP`. If the provider can proxy traffic, turn that off for
these records, because the address is private.

To find the zone of a name, ask for its name servers:
`dig +short NS <zone>`. Azure DNS name servers end in `azure-dns.com`,
`azure-dns.net`, `azure-dns.org` or `azure-dns.info`.

### A Portkey gateway

With `LLM_GATEWAY_URL` set, agents-py sends every model and embeddings call to
the gateway, and the gateway calls the provider with its own keys. The gateway
is not part of this install:

- Run it where the agents-py pods reach it, for example as a service in its own
  namespace of the cluster:
  `http://portkey-gateway.llm-gateway.svc.cluster.local:8787/v1`. Portkey OSS
  is the `portkeyai/gateway` image, on port 8787.
- The gateway must route the embedding model `text-embedding-3-large` to a model
  that returns 1024 dimensions.
- For Portkey OSS, the config in `PORTKEY_CONFIG_FILE` holds the routing and
  the provider keys. Hosted Portkey takes its config from the API key instead,
  so leave `PORTKEY_CONFIG_FILE` empty.

"Optional: an LLM gateway" in [getting-started.md](getting-started.md) has an
example Portkey config for Azure OpenAI and Azure AI Foundry, and the other
gateway kinds.

### Get a TLS certificate

The Autoheal proxy serves one certificate for the three names:
`$AUTOHEAL_HOSTNAME`, `auth.$AUTOHEAL_HOSTNAME` and `auth-app.$AUTOHEAL_HOSTNAME`.
Use the certificate of your organization when you have one. Otherwise, make one
of these two.

**Let's Encrypt.** A free certificate that browsers trust, valid for 90 days.
To prove that you own the name, you add two TXT records in the DNS zone of the
name while the command runs. It works for a private address too:

```bash
python3 -m venv "$WORK_DIR/certbot"
PIP_USER=false "$WORK_DIR/certbot/bin/python3" -m pip install -q --upgrade pip
PIP_USER=false "$WORK_DIR/certbot/bin/pip" install -q certbot "urllib3<2"
"$WORK_DIR/certbot/bin/certbot" --version
"$WORK_DIR/certbot/bin/certbot" certonly --manual --preferred-challenges dns \
  -d "$AUTOHEAL_HOSTNAME" -d "*.$AUTOHEAL_HOSTNAME" \
  --config-dir "$WORK_DIR/certbot/conf" --work-dir "$WORK_DIR/certbot/work" --logs-dir "$WORK_DIR/certbot/logs"
export TLS_CERT_FILE="$WORK_DIR/certbot/conf/live/$AUTOHEAL_HOSTNAME/fullchain.pem"
export TLS_KEY_FILE="$WORK_DIR/certbot/conf/live/$AUTOHEAL_HOSTNAME/privkey.pem"
```

certbot installs into its own Python environment in `$WORK_DIR`. `PIP_USER=false`
overrides a pip setting that installs to your user folder, which a Python
environment does not allow. `urllib3<2` suits the older SSL library of the
macOS Python.

certbot shows each TXT record to add, at `_acme-challenge.$AUTOHEAL_HOSTNAME`,
and waits. Add it in your DNS provider, wait a minute, then press Enter. To
renew, run the `certbot` command again before the 90 days end, then apply
step 9.

**Your own test CA.** Works at once, with nothing to prove. Browsers warn until
you trust `ca.pem` on your machine. Autoheal trusts it through
`TF_VAR_edge_ca_certificate`:

```bash
mkdir -p "$WORK_DIR/certs" && cd "$WORK_DIR/certs"
openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes -keyout ca.key -out ca.pem -subj "/CN=Autoheal test CA"
openssl req -newkey rsa:2048 -nodes -keyout privkey.pem -out server.csr -subj "/CN=$AUTOHEAL_HOSTNAME"
printf 'subjectAltName=DNS:%s,DNS:auth.%s,DNS:auth-app.%s\nextendedKeyUsage=serverAuth\n' \
  "$AUTOHEAL_HOSTNAME" "$AUTOHEAL_HOSTNAME" "$AUTOHEAL_HOSTNAME" > san.ext
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 365 -sha256 \
  -extfile san.ext -out server.pem
cat server.pem ca.pem > fullchain.pem
export TLS_CERT_FILE="$WORK_DIR/certs/fullchain.pem" TLS_KEY_FILE="$WORK_DIR/certs/privkey.pem"
export TF_VAR_edge_ca_certificate="$(cat ca.pem)"
```

With Terraform Enterprise, add `edge_ca_certificate` as a Terraform variable
with the text of `ca.pem`.

### A certificate from a private CA

When a private CA signed your certificate, also give the CA certificate, so that
Autoheal trusts it. With Terragrunt:

```bash
export TF_VAR_edge_ca_certificate="$(cat ca.pem)"
```

With Terraform Enterprise: a Terraform variable `edge_ca_certificate` with the
PEM text.

### References

- [Sign in with the Azure CLI](https://learn.microsoft.com/cli/azure/authenticate-azure-cli-interactively): the tenant and subscription questions of `az login`
- [kubelogin](https://azure.github.io/kubelogin/): how `kubectl` signs in with Entra ID
- [Workload identity on AKS](https://learn.microsoft.com/azure/aks/workload-identity-deploy-cluster): the OIDC issuer and workload identity of step 3
- [Key Vault provider for the Secrets Store CSI Driver](https://learn.microsoft.com/azure/aks/csi-secrets-store-driver): the add-on of step 3
- [Static public IP for an AKS load balancer](https://learn.microsoft.com/azure/aks/static-ip): the Temporal address of step 5
- [Standard load balancer in AKS](https://learn.microsoft.com/azure/aks/load-balancer-standard): `loadBalancerSourceRanges`, which lets only the runner reach Temporal
- [Network security groups](https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview): the rules of step 10
- [Storage network security limitations](https://learn.microsoft.com/azure/storage/common/storage-network-security-limitations): why storage uses a subnet rule, not IP rules
- [Dynamic credentials with the Azure provider](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/azure-configuration): how Terraform Enterprise signs in to Azure with OIDC
