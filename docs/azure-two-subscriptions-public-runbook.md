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
  steps 11 to 12).

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

> **Version.** This layout needs autoheal-byoc-infra **2.2.0 or later**. Until
> 2.2.0 is released, set `INFRA_REF` in step 1 to the branch
> `feat/azure-two-subscriptions`, and do the extra part of step 8. After the
> release, the runbook works as written.

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

Set your values:

```bash
export CLUSTER_SUB="<cluster subscription ID>"
export AKS_RG="<resource group of the cluster>"
export AKS_NAME="<cluster name>"
export DATA_SUB="<data subscription ID>"
export LOCATION="<region of the cluster, for example eastus2>"
export K8S_NAMESPACE="autoheal"   # the Kubernetes namespace that Autoheal runs in
export WORK_DIR="$HOME/autoheal-install"   # a new, empty folder for the files of this install
export INFRA_REF="v2.2.0"   # the autoheal-byoc-infra release; until 2.2.0 is released: feat/azure-two-subscriptions
```

`WORK_DIR` must not be inside a git checkout, for example a copy of
autoheal-byoc-infra. Step 7 makes it.

Use the namespace that the cluster owner gives you. Step 4 makes it.

Set the deployer: the identity that Terraform signs in as.

**With Terragrunt.** To deploy as yourself:

```bash
export DEPLOYER_ID=$(az ad signed-in-user show --query id -o tsv)
export DEPLOYER_TYPE=User
```

For a pipeline service principal, set `DEPLOYER_ID` to its object ID and
`DEPLOYER_TYPE=ServicePrincipal`.

**With Terraform Enterprise.** The deployer is the identity of the
workspace. Make it first: do Step 2 and Step 4 of Part A in
[terraform-enterprise.md](terraform-enterprise.md). That makes the app
registration `tfe-autoheal-byoc` and lets the workspace `autoheal-infra-prod`
sign in as it. Then:

```bash
export APP_ID=$(az ad app list --display-name "tfe-autoheal-byoc" --query "[0].appId" -o tsv)
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

Edit `root.hcl`: set the resource group, the storage account (3 to 24 lowercase
letters and digits, unique in Azure) and the container for the state. Then make
them, with the same names:

```bash
"$WORK_DIR/autoheal-byoc-infra/scripts/bootstrap-state-azure.sh" \
  --subscription "$DATA_SUB" --resource-group rg-acme-tfstate \
  --storage-account stacmetfstate --location "$LOCATION"
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

Find the public address of the apply host:

- With Terragrunt: your machine or your pipeline runner. On your machine:
  `curl -s https://api.ipify.org; echo`
- With Terraform Enterprise: the public egress addresses of the workers or
  agents.

```bash
export DEPLOYER_IPS="<address>/32"   # several: separate them with spaces
```

Print the inputs with your values:

```bash
cat <<EOF
namespace        = "acme"
environment      = "prod"
location         = "$LOCATION"
subscription_id  = "$DATA_SUB"
autoheal_version = "1.0.0-rc.8"

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
network_cidr              = "10.70.0.0/16"

hostname             = "autoheal.acme.example"
edge_mode            = "loadbalancer"
existing_dns_zone_id = "<ID of an Azure DNS zone in the data subscription that holds hostname>"
EOF
```

Change these values in the output:

| Input | Value |
|-------|-------|
| `namespace`, `environment` | Your short name and the environment, for example `acme` and `prod`. They start every Azure resource name. This `namespace` is not the Kubernetes namespace |
| `network_cidr` | A range for the runner VNet. It is never connected to your VNet |
| `hostname` | The name users open |
| `existing_dns_zone_id` | An Azure DNS zone in the data subscription that holds `hostname`. If you have none, remove this line and add `create_dns_records = false`. Step 9 then lists the records to make |


**With Terragrunt.** In `$WORK_DIR/acme-autoheal/prod/infra/terragrunt.hcl`,
put these values in the `inputs` block. Keep `autoheal_version` as the file has
it; it comes from `versions.hcl`.

Until 2.2.0 is released (`INFRA_REF` is the branch), point the `source` lines
of the infra and the app folders at the branch instead of the tag:

```bash
cd "$WORK_DIR/acme-autoheal/prod"
perl -pi -e 's/\?ref=v\$\{local\.v\.infra_version\}/?ref=feat\/azure-two-subscriptions/' infra/terragrunt.hcl app/terragrunt.hcl
grep -n 'source =' infra/terragrunt.hcl app/terragrunt.hcl
```

Both lines must end in `?ref=feat/azure-two-subscriptions"`. When 2.2.0 is
released, change them back to `?ref=v${local.v.infra_version}`.

Set the secrets as environment variables. They never go in a file:

```bash
export TF_VAR_llm_api_key="<your LLM provider key>"
export TF_VAR_tls_certificate=$(jq -n --rawfile c fullchain.pem --rawfile k privkey.pem \
  '{certificate: $c, private_key: $k}')
export TF_VAR_sso_client_secret="<only when SSO is on>"
```

**With Terraform Enterprise.** In the workspace, open **Variables**. Add each
input as a variable of the category **Terraform**: the key is the name before
`=`, the value is the part after it. For `existing_network`,
`service_accounts` and the two `_ranges` lists, tick **HCL**. Add the secrets
as **Sensitive** Terraform variables:

| Key | Value |
|-----|-------|
| `llm_api_key` | Your LLM provider key |
| `tls_certificate` | **HCL**. The output of `jq -n --rawfile c fullchain.pem --rawfile k privkey.pem '{certificate: $c, private_key: $k}'` |
| `sso_client_secret` | Only when SSO is on |

For both: `fullchain.pem` is the certificate chain and `privkey.pem` its key.
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
terragrunt output required_dns_records             # empty when Terraform made the records
export RUNNER_IP=$(terragrunt output -json temporal_public_endpoint | jq -r '.allowed_source_ranges[0]' | cut -d/ -f1)
```

**With Terraform Enterprise:** in the workspace, click **Actions**, then
**Start new run**. Read the plan, then click **Confirm & Apply**. Open the
**Outputs** tab, and keep the runner address and the chart values:

- `temporal_public_endpoint`: copy the address in `allowed_source_ranges`,
  without `/32`, into `export RUNNER_IP="<address>"`.
- `autoheal_values_yaml`: save the value as the file
  `$WORK_DIR/values-infra.yaml`. Step 11 uses it.
- `required_cluster_owner_actions` and `required_dns_records`: as with
  Terragrunt.

For both, when the plan stops with an error, the message names the
input to change. The apply takes 30 to 45 minutes; Postgres and Redis are the
slow parts.

## Step 10: Let the runner through the subnet NSG

```bash
az account set --subscription "$CLUSTER_SUB"
az network vnet subnet show --ids "$AKS_SUBNET_ID" --query networkSecurityGroup.id -o tsv
```

If the command shows no NSG, skip this step: AKS opens its own NSG for the load
balancers. If it shows an NSG, add two rules to it. Use priorities that the NSG
does not use yet:

```bash
export NSG_ID="<the NSG ID from the command above>"
export NSG_RG=$(echo "$NSG_ID" | cut -d/ -f5) NSG_NAME=$(echo "$NSG_ID" | cut -d/ -f9)
az network nsg rule create -g "$NSG_RG" --nsg-name "$NSG_NAME" \
  -n allow-autoheal-runner --priority 300 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "$RUNNER_IP" --destination-address-prefixes "$TEMPORAL_IP" \
  --destination-port-ranges 7233 8083
az network nsg rule create -g "$NSG_RG" --nsg-name "$NSG_NAME" \
  -n deny-others-to-autoheal-temporal --priority 310 --direction Inbound --access Deny --protocol '*' \
  --source-address-prefixes '*' --destination-address-prefixes "$TEMPORAL_IP" \
  --destination-port-ranges 7233 8083
```

## Step 11: Install the application

For both, edit `values-customer.yaml`. With Terragrunt, the file is
`$WORK_DIR/acme-autoheal/prod/app/values-customer.yaml`. With Terraform
Enterprise, copy it from the repository into `$WORK_DIR`:

```bash
mkdir -p "$WORK_DIR" && cd "$WORK_DIR"
[ -d autoheal-byoc-infra ] || git clone --branch "$INFRA_REF" https://github.com/autohealai/autoheal-byoc-infra.git
[ -e values-customer.yaml ] || cp autoheal-byoc-infra/examples/azure/split-public/app/values-customer.yaml .
```

- `global.adminEmail`: the first admin's email.
- `global.tenant.name`: your short name.
- `global.llm`: your provider, endpoint, model and
  `apiKeyVaultEntry: llm-api-key`. See Step 7 of
  [getting-started.md](getting-started.md) for Azure OpenAI.
- `global.sso`: your SSO application, or `enabled: false`.

Do not set `global.infra`.

**With Terragrunt.** Edit `$WORK_DIR/acme-autoheal/prod/app/terragrunt.hcl`:
set `namespace` to `$K8S_NAMESPACE`. It must be the same as
`service_accounts.namespace` in step 8. Then:

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
  -f values-infra.yaml -f values-customer.yaml --atomic --wait --timeout 20m
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
az vmss run-command invoke -g rg-acme-prod-autoheal -n acme-prod-autoheal-runner \
  --instance-id 0 --command-id RunShellScript --scripts "docker logs --tail 30 runner-go"
```

The log must show a connection to `$TEMPORAL_IP:7233`. Use your own
`namespace` and `environment` in the two names.

Only the runner can reach Temporal. From your own machine, this command must
time out:

```bash
nc -vz -w 5 "$TEMPORAL_IP" 7233
```

Open `https://<hostname>` from a machine on the cluster's network. The proxy
address `$PROXY_IP` is private.

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
| Pods wait for secrets, or show 403 from Key Vault | The cluster's outbound addresses changed or are wrong | Update `workload_egress_ip_ranges` and apply step 9 again |
| Pods cannot reach Postgres | The same | The same |
| `temporal-frontend-public` stays `<pending>` | The IP is not in the node resource group, or is not Standard and static | Do step 5 again |
| The runner log shows no connection to Temporal | The NSG blocks the runner | Do step 10 |

## Upgrade

The cluster owner does not have to give new permissions.

- With Terragrunt: change the two numbers in
  `$WORK_DIR/acme-autoheal/prod/versions.hcl`, then apply step 9 and step 11
  again.
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

For both, as the cluster owner: delete `pip-autoheal-temporal`, the NSG
rules from step 10 and the role grants. Delete the namespace only if step 4
made it for Autoheal. Remove `Microsoft.Storage` from the subnet only if
nothing else uses it.

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
install first, or set `K8S_NAMESPACE` to a different namespace in step 1 and
start again from step 4.

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
