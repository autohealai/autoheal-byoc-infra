# Runbook: Autoheal on an existing AKS cluster, public endpoints

This runbook installs Autoheal end to end on an AKS cluster that you already
have. The cluster stays in its subscription (the **cluster subscription**).
All the other Autoheal resources go in a second subscription (the **data
subscription**). The two VNets are not connected. The data services use public
endpoints with firewalls. Users and webhooks reach Autoheal on a public IP. [The one-pager](azure-two-subscriptions-public.md)
explains the layout, and [the comparison](azure-subscription-options.md) shows
its limits.

The runbook has two roles. One person can do both:

- The **cluster owner** prepares the cluster (steps 1 to 6 and step 10).
- The **deployer** runs Terraform in the data subscription (steps 7 to 9 and
  steps 11 to 13).

## Contents

- [Choose your options](#choose-your-options)
- [Time](#time)
- [Before you start](#before-you-start)
- [Step 1: Sign in and set your values](#step-1-sign-in-and-set-your-values)
  - [1a. Sign in](#1a-sign-in)
  - [1b. Set the common values](#1b-set-the-common-values)
  - [1c. Set the Terraform values](#1c-set-the-terraform-values): [Terragrunt](#1c-terragrunt), [Terraform Enterprise](#1c-terraform-enterprise)
  - [1d. Set the model values](#1d-set-the-model-values): [Azure OpenAI](#1d-azure-openai), [Portkey](#1d-portkey)
- [Step 2: Check the cluster](#step-2-check-the-cluster)
- [Step 3 (optional): Turn on the cluster features](#step-3-optional-turn-on-the-cluster-features)
- [Step 4: Make the namespace and prepare the AKS subnet](#step-4-make-the-namespace-and-prepare-the-aks-subnet)
  - [4a. Connect to the cluster](#4a-connect-to-the-cluster)
  - [4b. Make the namespace](#4b-make-the-namespace)
  - [4c. Check that the namespace holds no other install](#4c-check-that-the-namespace-holds-no-other-install)
  - [4d. Add the storage service endpoint](#4d-add-the-storage-service-endpoint)
- [Step 5: Make the public IPs](#step-5-make-the-public-ips)
  - [5a. Make the static public IP for Temporal](#5a-make-the-static-public-ip-for-temporal)
  - [5b. Make the public IP for the proxy](#5b-make-the-public-ip-for-the-proxy): [Two public IPs](#5b-two-public-ips), [One public IP](#5b-one-public-ip)
- [Step 6: Get the outbound addresses and give the deployer its roles](#step-6-get-the-outbound-addresses-and-give-the-deployer-its-roles)
  - [6a. Get the outbound addresses](#6a-get-the-outbound-addresses)
  - [6b. Give the deployer its roles](#6b-give-the-deployer-its-roles)
- [Step 7: Prepare the data subscription](#step-7-prepare-the-data-subscription)
  - [7a. Register the resource providers](#7a-register-the-resource-providers)
  - [7b. Prepare Terraform](#7b-prepare-terraform): [Terragrunt](#7b-terragrunt), [Terraform Enterprise](#7b-terraform-enterprise)
- [Step 8: Set the inputs](#step-8-set-the-inputs)
  - [8a. Find the address of the apply host](#8a-find-the-address-of-the-apply-host): [Terragrunt](#8a-terragrunt), [Terraform Enterprise](#8a-terraform-enterprise)
  - [8b. Write the inputs](#8b-write-the-inputs)
  - [8c. Give the inputs to Terraform](#8c-give-the-inputs-to-terraform): [Terragrunt](#8c-terragrunt), [Terraform Enterprise](#8c-terraform-enterprise)
  - [8d. Set the secrets](#8d-set-the-secrets): [Terragrunt and Azure OpenAI](#8d-terragrunt-and-azure-openai), [Terragrunt and Portkey](#8d-terragrunt-and-portkey), [Terraform Enterprise and Azure OpenAI](#8d-terraform-enterprise-and-azure-openai), [Terraform Enterprise and Portkey](#8d-terraform-enterprise-and-portkey)
- [Step 9: Apply the infra](#step-9-apply-the-infra)
  - [9a. Apply and keep the outputs](#9a-apply-and-keep-the-outputs): [Terragrunt](#9a-terragrunt), [Terraform Enterprise](#9a-terraform-enterprise)
  - [9b. Make the DNS records](#9b-make-the-dns-records): [Azure DNS in another subscription](#9b-azure-dns-in-another-subscription), [DNS outside Azure](#9b-dns-outside-azure)
- [Step 10: Open the subnet NSG for the runner and the proxy](#step-10-open-the-subnet-nsg-for-the-runner-and-the-proxy)
- [Step 11: Install the application](#step-11-install-the-application)
  - [11a. Write your chart settings](#11a-write-your-chart-settings): [Azure OpenAI](#11a-azure-openai), [Portkey](#11a-portkey)
  - [11b. Install the chart](#11b-install-the-chart): [Terragrunt](#11b-terragrunt), [Terraform Enterprise](#11b-terraform-enterprise)
- [Step 12: Check that it works](#step-12-check-that-it-works)
  - [12a. Check the pods](#12a-check-the-pods)
  - [12b. Check the runner](#12b-check-the-runner)
  - [12c. Check that only the runner reaches Temporal](#12c-check-that-only-the-runner-reaches-temporal)
  - [12d. Open Autoheal](#12d-open-autoheal)
  - [12e. Sign in as the first admin](#12e-sign-in-as-the-first-admin): [Terragrunt](#12e-terragrunt), [Terraform Enterprise](#12e-terraform-enterprise)
  - [12f. Check the model calls](#12f-check-the-model-calls): [Azure OpenAI](#12f-azure-openai), [Portkey](#12f-portkey)
- [Step 13 (optional): Turn on single sign-on](#step-13-optional-turn-on-single-sign-on)
  - [13a. Add your identity provider](#13a-add-your-identity-provider)
- [Troubleshooting](#troubleshooting)
- [Upgrade](#upgrade): [Terragrunt](#upgrade-with-terragrunt), [Terraform Enterprise](#upgrade-with-terraform-enterprise)
- [Remove](#remove): [Terragrunt](#remove-with-terragrunt), [Terraform Enterprise](#remove-with-terraform-enterprise), [the cluster owner's changes](#remove-the-cluster-owners-changes)
- [Edge cases and references](#edge-cases-and-references)
  - [Entra ID or Azure RBAC is off](#entra-id-or-azure-rbac-is-off)
  - [Your machine cannot reach the API server](#your-machine-cannot-reach-the-api-server)
  - [You cannot make the namespace](#you-cannot-make-the-namespace)
  - [The cluster uses the VNet that AKS made](#the-cluster-uses-the-vnet-that-aks-made)
  - [Key Vault service endpoint on the subnet](#key-vault-service-endpoint-on-the-subnet)
  - [The namespace holds another install](#the-namespace-holds-another-install)
  - [Other outbound types](#other-outbound-types)
  - [Keep Autoheal private](#keep-autoheal-private)
  - [A Portkey gateway](#a-portkey-gateway)
  - [Get a TLS certificate](#get-a-tls-certificate)
  - [A certificate from a private CA](#a-certificate-from-a-private-ca)
  - [References](#references)

## Choose your options

Make two choices before you start.

**How you run Terraform:**

|                                 | Terragrunt                                  | Terraform Enterprise                              |
| ------------------------------- | ------------------------------------------- | ------------------------------------------------- |
| Where Terraform runs            | Your machine or your pipeline               | The Terraform Enterprise workers                  |
| Where the state is              | A storage account in the data subscription  | The Terraform Enterprise workspace                |
| How Terraform signs in to Azure | Your `az login`, or the pipeline's identity | The workspace identity, with OIDC and no password |
| How the chart is installed      | The app folder, with Terragrunt             | Helm, from your machine                           |

**How Autoheal reaches the model:**

|                           | Azure OpenAI                                                                             | Portkey                                                                    |
| ------------------------- | ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| What Autoheal calls       | Your Azure OpenAI resource, or the Azure OpenAI endpoint of an Azure AI Foundry resource | A Portkey gateway. The gateway calls the provider                          |
| Where the provider key is | The install vault, from step 8d                                                          | The gateway                                                                |
| What you need             | A chat model deployment, and an embedding deployment named `text-embedding-3-large`      | A gateway that the pods reach. See [A Portkey gateway](#a-portkey-gateway) |

A sub-step that depends on a choice has one part for each option, for example
**7b: Terragrunt** and **7b: Terraform Enterprise**. Do the part of your
option and skip the others. Sub-step 8d has one part for each pair of options.

## Time

| Step                                 | Hands-on                              | Waiting                                        |
| ------------------------------------ | ------------------------------------- | ---------------------------------------------- |
| 1 to 6: prepare the cluster          | 30 min                                | 10 to 15 min for step 3; none when you skip it |
| 7 to 8: state or workspace, settings | 30 min (Terraform Enterprise: 45 min) |                                                |
| 9: apply the infra                   | 5 min                                 | 30 to 45 min                                   |
| 10: NSG rule                         | 5 min                                 |                                                |
| 11: install the application          | 10 min                                | 10 to 20 min                                   |
| 12: check                            | 10 min                                |                                                |
| 13 (optional): single sign-on        | 20 min                                |                                                |

These times are estimates. Plan half a day for a first install.

## Before you start

You must have:

- An AKS cluster on a subnet of a VNet that you manage. A cluster on the
  VNet that AKS makes for itself does not fit this runbook.
- A path from your machine to the cluster's API server on TCP 443. Step 4 and
  step 11 use it. Step 2 shows how to check it.
- A data subscription in the same Microsoft Entra tenant as the cluster.
- One or two Standard static public IPs in the node resource group of the
  cluster. Step 5 makes them.
- Owner on the cluster subscription and Kubernetes admin rights in the
  cluster, or the cluster owner's help for steps 1 to 6 and step 10. Owner on
  the subscription does not give Kubernetes rights; step 4b shows how to get
  them.
- For the deployer: Owner, or Contributor and User Access Administrator, on the
  data subscription.
- With Terraform Enterprise: access to your organization, and its public
  egress addresses (the addresses of the Terraform Enterprise workers or
  agents).
- With Azure OpenAI: the endpoint and a key of the resource. With Portkey: a
  running gateway, and its API key or config.
- A TLS certificate, with its private key, that covers `hostname`,
  `auth.<hostname>` and `auth-app.<hostname>`. The Autoheal proxy serves it.
  [Get a TLS certificate](#get-a-tls-certificate) shows how to make one.

Install these tools:

| Tool                                | For                  | Install                                                                                                                                                                                    |
| ----------------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `az` CLI                            | both                 | https://learn.microsoft.com/cli/azure/install-azure-cli                                                                                                                                    |
| `kubectl` and `kubelogin`           | both                 | `az aks install-cli` installs both. It writes to `/usr/local/bin`, so it may need `sudo`: `sudo az aks install-cli`. On macOS, `brew install kubectl Azure/kubelogin/kubelogin` also works |
| `git`, `curl`, `jq`, `python3`      | both                 | any version                                                                                                                                                                                |
| Terraform 1.7 or later, or OpenTofu | Terragrunt           | Terragrunt runs `tofu` from your PATH. To use Terraform, `export TG_TF_PATH=terraform`                                                                                                     |
| Terragrunt                          | Terragrunt           | https://terragrunt.gruntwork.io/docs/getting-started/install/                                                                                                                              |
| Helm 3                              | Terraform Enterprise | https://helm.sh/docs/intro/install/                                                                                                                                                        |

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

> **Version.** This layout needs autoheal-byoc-infra **2.2.0 or later**. Step
> 1b sets `INFRA_REF` to the release tag `v2.2.0` when it exists, and to the
> branch `feat/azure-two-subscriptions` until then. The later steps use it, so
> you change nothing yourself.

## Step 1: Sign in and set your values

Open one shell and keep it open. Every later step uses the variables you set
here. When you open a new shell, run step 1 again. Steps 1 to 6 work from any
folder. From step 7, the commands go to the folders that they need themselves.

### 1a. Sign in

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

### 1b. Set the common values

Type your values in this block, then run it. The last command names each value
that is still empty or a `<...>` placeholder. It must show nothing:

```bash
# Shows each value that is empty or still a <placeholder>. Each values block ends with it.
check_values() { for v in "$@"; do eval "val=\${$v}"; case "$val" in ""|*"<"*) echo "Set $v";; esac; done; }

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

# Autoheal
export AUTOHEAL_HOSTNAME="autoheal.acme.example"   # the name users open; also auth.<name> and auth-app.<name>
export DNS_ZONE_ID=""                  # ID of an Azure DNS zone in the data subscription that holds the name; empty: you make the records in step 9b
export ADMIN_EMAIL="<email of the first admin>"
export TLS_CERT_FILE="$HOME/certs/fullchain.pem"   # certificate chain for the three names; see "Get a TLS certificate" at the end
export TLS_KEY_FILE="$HOME/certs/privkey.pem"      # its private key

# The autoheal-byoc-infra version: the release tag when it exists, the branch until then
export INFRA_REF=$(git ls-remote --tags https://github.com/autohealai/autoheal-byoc-infra.git refs/tags/v2.2.0 |
  grep -q . && echo v2.2.0 || echo feat/azure-two-subscriptions)
echo "INFRA_REF=$INFRA_REF"

check_values WORK_DIR CLUSTER_SUB AKS_RG AKS_NAME K8S_NAMESPACE DATA_SUB LOCATION NAME_PREFIX ENVIRONMENT \
  RUNNER_CIDR AUTOHEAL_HOSTNAME ADMIN_EMAIL TLS_CERT_FILE TLS_KEY_FILE INFRA_REF
```

### 1c. Set the Terraform values

The deployer is the identity that Terraform signs in as.

#### 1c: Terragrunt

```bash
# The Terraform state: a new storage account that step 7b makes.
# Its name is made for you, unique in Azure; a new shell reads it back from root.hcl.
export STATE_RG="rg-${NAME_PREFIX}-tfstate"
export STATE_ACCOUNT=$(sed -n 's/.*storage_account_name *= *"\([a-z0-9]*\)".*/\1/p' \
  "$WORK_DIR/acme-autoheal/root.hcl" 2>/dev/null | grep -vx stacmetfstate)
[ -n "$STATE_ACCOUNT" ] ||
  export STATE_ACCOUNT="st$(echo "$NAME_PREFIX" | tr -cd 'a-z0-9' | cut -c1-9)tfstate$(openssl rand -hex 3)"

# The deployer: you
export DEPLOYER_ID=$(az ad signed-in-user show --query id -o tsv)
export DEPLOYER_TYPE=User

# Your chart settings, written in step 11a
export VALUES_FILE="$WORK_DIR/acme-autoheal/prod/app/values-customer.yaml"

check_values STATE_RG STATE_ACCOUNT DEPLOYER_ID VALUES_FILE
```

For a pipeline service principal, set `DEPLOYER_ID` to its object ID and
`DEPLOYER_TYPE=ServicePrincipal`.

#### 1c: Terraform Enterprise

```bash
export TFE_ISSUER="https://app.terraform.io"   # or the address of your Terraform Enterprise, for example https://tfe.example.com
export TFE_ORG="<organization>"
export TFE_PROJECT="Default Project"
export TFE_WORKSPACE="autoheal-infra-prod"

# Your chart settings, written in step 11a
export VALUES_FILE="$WORK_DIR/values-customer.yaml"

check_values TFE_ISSUER TFE_ORG TFE_PROJECT TFE_WORKSPACE VALUES_FILE
```

The deployer is the identity of the workspace: an app registration that the
workspace signs in as with OIDC. This makes it, or finds it when it exists:

```bash
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

check_values APP_ID DEPLOYER_ID
```

### 1d. Set the model values

#### 1d: Azure OpenAI

```bash
export LLM_PROVIDER="azure-openai"
export LLM_ENDPOINT="https://<resource>.openai.azure.com/openai/v1/"   # the endpoint of the resource, with openai/v1/ at the end
export LLM_MODEL="gpt-5-mini"          # the name of the chat model deployment

check_values LLM_PROVIDER LLM_ENDPOINT LLM_MODEL
```

The resource also needs an embedding deployment named
`text-embedding-3-large`. This lists the deployments of the resource. It must
show `$LLM_MODEL` and `text-embedding-3-large`:

```bash
az cognitiveservices account deployment list --subscription "<subscription of the resource>" \
  -g "<resource group of the resource>" -n "<resource name>" --query "[].name" -o tsv
```

See Step 7 of [getting-started.md](getting-started.md) to make a deployment.

#### 1d: Portkey

```bash
export LLM_PROVIDER="azure-openai"     # the provider behind the gateway
export LLM_MODEL="gpt-5-mini"          # the model name that the gateway routes
export LLM_GATEWAY_URL="<gateway root, ending in /v1>"   # for example http://portkey-gateway.llm-gateway.svc.cluster.local:8787/v1
export PORTKEY_CONFIG_FILE=""          # Portkey OSS: path of its config JSON, with the routing and the provider keys, outside any repository. Hosted Portkey: empty

check_values LLM_PROVIDER LLM_MODEL LLM_GATEWAY_URL
```

See [A Portkey gateway](#a-portkey-gateway) for what the gateway must do.

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

### 4a. Connect to the cluster

```bash
az aks get-credentials -g "$AKS_RG" -n "$AKS_NAME" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
kubectl get --raw /readyz --request-timeout=20s; echo
```

The last command must show `ok`. A timeout means that your machine cannot
reach the API server. See
[Your machine cannot reach the API server](#your-machine-cannot-reach-the-api-server).

### 4b. Make the namespace

The command makes the namespace only when it does not exist, so it works for a
new namespace and for one you already have:

```bash
kubectl get namespace "$K8S_NAMESPACE" >/dev/null 2>&1 && echo "namespace $K8S_NAMESPACE exists" ||
  kubectl create namespace "$K8S_NAMESPACE"
```

It shows `namespace/<name> created` when it makes the namespace, and
`namespace <name> exists` when the namespace was there already.
`Error from server (Forbidden)` means that you have no Kubernetes rights in the
cluster. See [You cannot make the namespace](#you-cannot-make-the-namespace).

### 4c. Check that the namespace holds no other install

A namespace that exists already must not hold a different Autoheal install.
This command must show nothing, or only the release of this install when you
run the runbook again:

```bash
kubectl get secrets -n "$K8S_NAMESPACE" -l owner=helm,name=autoheal
```

If it shows a release from a different install, see
[The namespace holds another install](#the-namespace-holds-another-install).

### 4d. Add the storage service endpoint

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

## Step 5: Make the public IPs

### 5a. Make the static public IP for Temporal

The IP goes in the node resource group of the cluster, in the cluster
subscription. Azure may warn about a coming change to zones; it does not affect
this IP:

```bash
export NODE_RG=$(az aks show --subscription "$CLUSTER_SUB" -g "$AKS_RG" -n "$AKS_NAME" --query nodeResourceGroup -o tsv)
export TEMPORAL_IP=$(az network public-ip create --subscription "$CLUSTER_SUB" -g "$NODE_RG" -n pip-autoheal-temporal \
  --location "$LOCATION" --sku Standard --allocation-method Static --query publicIp.ipAddress -o tsv)
echo "$TEMPORAL_IP"
```

### 5b. Make the public IP for the proxy

Users and webhook senders reach Autoheal on this IP. The Autoheal proxy serves
the web app, the login and the webhooks over HTTPS on it. The DNS records for
`hostname`, `auth.<hostname>` and `auth-app.<hostname>` point to it.

#### 5b: Two public IPs

A second IP, apart from the Temporal IP. The proxy and Temporal then have
separate addresses and separate firewall rules:

```bash
export PROXY_IP=$(az network public-ip create --subscription "$CLUSTER_SUB" -g "$NODE_RG" -n pip-autoheal-proxy \
  --location "$LOCATION" --sku Standard --allocation-method Static --query publicIp.ipAddress -o tsv)
echo "$PROXY_IP"
```

#### 5b: One public IP

When you get only one public IP, the proxy uses the Temporal IP. Their ports do
not overlap: 443 and 80 for the proxy, 7233 and 8083 for the runner:

```bash
export PROXY_IP="$TEMPORAL_IP"
echo "$PROXY_IP"
```

## Step 6: Get the outbound addresses and give the deployer its roles

### 6a. Get the outbound addresses

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

### 6b. Give the deployer its roles

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

### 7a. Register the resource providers

```bash
az account set --subscription "$DATA_SUB"
for ns in Microsoft.DBforPostgreSQL Microsoft.Cache Microsoft.Storage \
          Microsoft.KeyVault Microsoft.Network Microsoft.ManagedIdentity Microsoft.Compute; do
  az provider register --namespace "$ns"
done
```

### 7b. Prepare Terraform

#### 7b: Terragrunt

Your deployment repository holds only settings, not our Terraform code. Each
`terragrunt.hcl` points at a tag of autoheal-byoc-infra, and Terragrunt
downloads the code at that tag on every run. The tag is `infra_version` in
`versions.hcl`. The layout is the same as for
[one subscription](getting-started.md). This sub-step makes these folders in
`$WORK_DIR`:

```text
$WORK_DIR/                     for example ~/autoheal-install
  autoheal-byoc-infra/         a copy, for the starter files and the state script; not your repository
  acme-autoheal/               your deployment repository
    root.hcl                   the state backend, for every environment
    prod/
      versions.hcl             the infra tag and the chart version
      infra/terragrunt.hcl     the infra inputs (step 8c)
      app/terragrunt.hcl       the app inputs (step 8c)
      app/values-customer.yaml your chart settings (step 11a)
```

**1. Copy the starter files.** You can run this again. It keeps a copy and
files that are there already, so it does not overwrite your edits:

```bash
mkdir -p "$WORK_DIR" && cd "$WORK_DIR"
[ -d autoheal-byoc-infra ] || git clone --branch "$INFRA_REF" https://github.com/autohealai/autoheal-byoc-infra.git
mkdir -p acme-autoheal
[ -e acme-autoheal/root.hcl ] || cp autoheal-byoc-infra/examples/azure/root.hcl acme-autoheal/
[ -e acme-autoheal/prod ] || cp -R autoheal-byoc-infra/examples/azure/split-public acme-autoheal/prod
cd "$WORK_DIR/acme-autoheal"
```

To keep your settings in git, make `acme-autoheal` a git repository of your
own (`git init`) and push it to your own remote. For a second environment, copy
`prod/` to `staging/` and change its inputs. Each environment folder has its
own state.

**2. Make the state storage account.** This puts the names of the state
storage in `root.hcl`, then makes the storage account and its container:

```bash
if [ -z "$STATE_RG" ] || [ -z "$STATE_ACCOUNT" ] || [ -z "${STATE_ACCOUNT##*<*}" ]; then
  echo "Set STATE_RG and STATE_ACCOUNT in step 1c first"
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

#### 7b: Terraform Enterprise

**1. Give the workspace identity its rights** in the data subscription:

```bash
az role assignment create --assignee "$APP_ID" --role "Contributor" --scope "/subscriptions/$DATA_SUB"
az role assignment create --assignee "$APP_ID" --role "User Access Administrator" --scope "/subscriptions/$DATA_SUB"
```

**2. Make the workspace.** In Terraform Enterprise, do Step 6 and Step 8 of
Part B in [terraform-enterprise.md](terraform-enterprise.md):

- Make the workspace `autoheal-infra-prod`, with the Terraform working
  directory `compositions/azure`, on a branch of your copy that has 2.2.0 or
  later. Set the workspace Terraform version to 1.7 or later.
- Add the four environment variables for the sign-in. `ARM_SUBSCRIPTION_ID`
  is `$DATA_SUB`. The composition reads the cluster in the cluster subscription
  with the same identity.

The workspace keeps the state. You do not make a storage account.

## Step 8: Set the inputs

### 8a. Find the address of the apply host

The Key Vaults let in the apply host, so that Terraform can write the vault
entries.

#### 8a: Terragrunt

The address of this machine:

```bash
export DEPLOYER_IPS="$(curl -s https://api.ipify.org)/32"
echo "$DEPLOYER_IPS"
```

#### 8a: Terraform Enterprise

The public egress addresses of the workers or agents, and the address of this
machine, which reads the admin password in step 12e:

```bash
export DEPLOYER_IPS="<address of the workers>/32 $(curl -s https://api.ipify.org)/32"   # several worker addresses: separate them with spaces
check_values DEPLOYER_IPS
echo "$DEPLOYER_IPS"
```

### 8b. Write the inputs

Make sure that the values from steps 4 to 8a are set. This must show nothing:

```bash
check_values AKS_ID AKS_SUBNET_ID TEMPORAL_IP PROXY_IP EGRESS_IPS DEPLOYER_IPS
```

This writes the inputs into `$WORK_DIR/inputs.hcl`:

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

hostname      = "$AUTOHEAL_HOSTNAME"
edge_mode     = "loadbalancer"
edge_exposure = "public"
$([ -n "$DNS_ZONE_ID" ] && echo "existing_dns_zone_id = \"$DNS_ZONE_ID\"" || echo "create_dns_records = false")
EOF
cat "$WORK_DIR/inputs.hcl"
```

Without `DNS_ZONE_ID`, Terraform makes no DNS records. You make them in
step 9b.

### 8c. Give the inputs to Terraform

#### 8c: Terragrunt

**1. Write the infra folder** from the inputs. Its `source` line downloads our
code at the release tag, or at the branch until the release:

```bash
cd "$WORK_DIR/acme-autoheal/prod/infra"
[ "$INFRA_REF" = "v2.2.0" ] && SOURCE_REF='v${local.v.infra_version}' || SOURCE_REF="$INFRA_REF"
{
  cat <<EOF
# The cloud resources in the data subscription. Written by step 8c of
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

**2. Set the namespace and the `source` line of the app folder:**

```bash
cd "$WORK_DIR/acme-autoheal/prod/app"
perl -pi -e 's/^(\s*namespace\s*=\s*)"[^"]*"/$1"$ENV{K8S_NAMESPACE}"/' terragrunt.hcl
[ "$INFRA_REF" = "v2.2.0" ] || perl -pi -e 's/\?ref=v\$\{local\.v\.infra_version\}/?ref=$ENV{INFRA_REF}/' terragrunt.hcl
grep -n 'source =\|^ *namespace ' terragrunt.hcl
```

#### 8c: Terraform Enterprise

In the workspace, open **Variables**, and add each line of the output below as
a variable of the category **Terraform**. The key is the name before `=`; the
value is the part after it. For `existing_network`, `service_accounts` and the
two `_ranges` lists, tick **HCL**:

```bash
cat "$WORK_DIR/inputs.hcl"
echo 'autoheal_version = "1.0.0-rc.8"'
```

### 8d. Set the secrets

The secrets never go in a file. Do the part for your two options. For a
certificate from a private CA, also see
[A certificate from a private CA](#a-certificate-from-a-private-ca).

#### 8d: Terragrunt and Azure OpenAI

```bash
export TF_VAR_tls_certificate=$(jq -n --rawfile c "$TLS_CERT_FILE" --rawfile k "$TLS_KEY_FILE" \
  '{certificate: $c, private_key: $k}')
export TF_VAR_llm_api_key="<key of your Azure OpenAI resource>"   # Azure portal: the resource, Keys and Endpoint

check_values TF_VAR_tls_certificate TF_VAR_llm_api_key
```

#### 8d: Terragrunt and Portkey

```bash
export TF_VAR_tls_certificate=$(jq -n --rawfile c "$TLS_CERT_FILE" --rawfile k "$TLS_KEY_FILE" \
  '{certificate: $c, private_key: $k}')
export TF_VAR_llm_gateway_api_key="<Portkey API key; Portkey OSS ignores it, so any value, for example unused>"
[ -z "$PORTKEY_CONFIG_FILE" ] ||
  export TF_VAR_llm_gateway_extra_headers="$(jq -cn --arg cfg "$(jq -c . "$PORTKEY_CONFIG_FILE")" '{"x-portkey-config": $cfg}')"

check_values TF_VAR_tls_certificate TF_VAR_llm_gateway_api_key
```

#### 8d: Terraform Enterprise and Azure OpenAI

In the workspace **Variables**, add these as **Sensitive** variables of the
category **Terraform**:

| Key               | HCL | Value                                 |
| ----------------- | --- | ------------------------------------- |
| `tls_certificate` | Yes | The output of the command below       |
| `llm_api_key`     | No  | The key of your Azure OpenAI resource |

```bash
jq -n --rawfile c "$TLS_CERT_FILE" --rawfile k "$TLS_KEY_FILE" '{certificate: $c, private_key: $k}'
```

#### 8d: Terraform Enterprise and Portkey

In the workspace **Variables**, add these as **Sensitive** variables of the
category **Terraform**:

| Key                         | HCL | Value                                                                        |
| --------------------------- | --- | ---------------------------------------------------------------------------- |
| `tls_certificate`           | Yes | The output of the first command below                                        |
| `llm_gateway_api_key`       | No  | The Portkey API key. Portkey OSS ignores it: any value, for example `unused` |
| `llm_gateway_extra_headers` | No  | Portkey OSS only: the output of the second command below                     |

```bash
jq -n --rawfile c "$TLS_CERT_FILE" --rawfile k "$TLS_KEY_FILE" '{certificate: $c, private_key: $k}'
```

```bash
jq -cn --arg cfg "$(jq -c . "$PORTKEY_CONFIG_FILE")" '{"x-portkey-config": $cfg}'
```

## Step 9: Apply the infra

### 9a. Apply and keep the outputs

The apply takes 30 to 45 minutes; Postgres and Redis are the slow parts. When
the plan stops with an error, the message names the input to change.

#### 9a: Terragrunt

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
terragrunt output required_dns_records             # the records for step 9b; empty when Terraform made them
export RUNNER_IP=$(terragrunt output -json temporal_public_endpoint | jq -r '.allowed_source_ranges[0]' | cut -d/ -f1)
echo "$RUNNER_IP"
```

#### 9a: Terraform Enterprise

In the workspace, click **Actions**, then **Start new run**. Read the plan, then
click **Confirm & Apply**. Then open the **Outputs** tab. Keep the address in
`temporal_public_endpoint.allowed_source_ranges`, without `/32`:

```bash
export RUNNER_IP="<the address>"
```

Save the value of `autoheal_values_yaml` for step 11b. Run this command, paste
the value, then press Ctrl-D:

```bash
cat > "$WORK_DIR/values-infra.yaml"
```

Read `required_cluster_owner_actions` and `required_dns_records` there too.

### 9b. Make the DNS records

Skip this sub-step when you set `DNS_ZONE_ID` in step 1b: Terraform made the
records. Otherwise, make three A records, each with the value `$PROXY_IP`:

```bash
printf '%s  A  %s\n' "$AUTOHEAL_HOSTNAME" "$PROXY_IP" "auth.$AUTOHEAL_HOSTNAME" "$PROXY_IP" \
  "auth-app.$AUTOHEAL_HOSTNAME" "$PROXY_IP"
```

To find the DNS zone of the name and its name servers:

```bash
dig +noall +answer +authority SOA "$AUTOHEAL_HOSTNAME"
```

The first word is the zone. Azure DNS name servers end in `azure-dns.com`,
`azure-dns.net`, `azure-dns.org` or `azure-dns.info`.

#### 9b: Azure DNS in another subscription

For example a zone in the cluster subscription. `AUTOHEAL_HOSTNAME` must be a
name below that zone:

```bash
export RECORDS_ZONE_ID="<ID of the Azure DNS zone that holds AUTOHEAL_HOSTNAME>"
export ZONE_SUB=$(echo "$RECORDS_ZONE_ID" | cut -d/ -f3) ZONE_RG=$(echo "$RECORDS_ZONE_ID" | cut -d/ -f5) \
  ZONE_NAME=$(echo "$RECORDS_ZONE_ID" | cut -d/ -f9)
for h in "$AUTOHEAL_HOSTNAME" "auth.$AUTOHEAL_HOSTNAME" "auth-app.$AUTOHEAL_HOSTNAME"; do
  az network dns record-set a add-record --subscription "$ZONE_SUB" -g "$ZONE_RG" -z "$ZONE_NAME" \
    -n "${h%.$ZONE_NAME}" -a "$PROXY_IP" -o none
done
```

#### 9b: DNS outside Azure

Make the three records by hand in your DNS provider. If the provider can proxy
traffic, for example Cloudflare, keep these records DNS only, so that users and
webhooks reach the Autoheal proxy and its certificate directly. Then check that
each name shows `$PROXY_IP`:

```bash
for h in "$AUTOHEAL_HOSTNAME" "auth.$AUTOHEAL_HOSTNAME" "auth-app.$AUTOHEAL_HOSTNAME"; do
  echo "$h $(dig +short A "$h" @1.1.1.1)"
done
```

## Step 10: Open the subnet NSG for the runner and the proxy

When the AKS subnet has an NSG, add three rules to it:

- Let only the runner reach the Temporal IP on TCP 7233 and 8083.
- Deny all other sources to the Temporal IP on these ports.
- Let everyone reach the proxy IP on TCP 443 and 80. To let in only some
  sources, put their ranges in place of `Internet`.

Without an NSG, AKS opens its own NSG for the load balancers, and the command
does nothing. The rules take the first free priorities from 300:

```bash
az account set --subscription "$CLUSTER_SUB"
export NSG_ID=$(az network vnet subnet show --ids "$AKS_SUBNET_ID" --query networkSecurityGroup.id -o tsv)
echo "NSG: ${NSG_ID:-none}"
if [ -n "$NSG_ID" ]; then
  export NSG_RG=$(echo "$NSG_ID" | cut -d/ -f5) NSG_NAME=$(echo "$NSG_ID" | cut -d/ -f9)
  USED=$(az network nsg rule list -g "$NSG_RG" --nsg-name "$NSG_NAME" \
    --query "[?name!='allow-autoheal-runner' && name!='deny-others-to-autoheal-temporal' && name!='allow-autoheal-proxy'].priority" -o tsv)
  ALLOW_PRIORITY=300; while echo "$USED" | grep -qx "$ALLOW_PRIORITY"; do ALLOW_PRIORITY=$((ALLOW_PRIORITY+1)); done
  DENY_PRIORITY=$((ALLOW_PRIORITY+1)); while echo "$USED" | grep -qx "$DENY_PRIORITY"; do DENY_PRIORITY=$((DENY_PRIORITY+1)); done
  PROXY_PRIORITY=$((DENY_PRIORITY+1)); while echo "$USED" | grep -qx "$PROXY_PRIORITY"; do PROXY_PRIORITY=$((PROXY_PRIORITY+1)); done
  az network nsg rule create -g "$NSG_RG" --nsg-name "$NSG_NAME" -o none \
    -n allow-autoheal-runner --priority "$ALLOW_PRIORITY" --direction Inbound --access Allow --protocol Tcp \
    --source-address-prefixes "$RUNNER_IP" --destination-address-prefixes "$TEMPORAL_IP" \
    --destination-port-ranges 7233 8083
  az network nsg rule create -g "$NSG_RG" --nsg-name "$NSG_NAME" -o none \
    -n deny-others-to-autoheal-temporal --priority "$DENY_PRIORITY" --direction Inbound --access Deny --protocol '*' \
    --source-address-prefixes '*' --destination-address-prefixes "$TEMPORAL_IP" \
    --destination-port-ranges 7233 8083
  az network nsg rule create -g "$NSG_RG" --nsg-name "$NSG_NAME" -o none \
    -n allow-autoheal-proxy --priority "$PROXY_PRIORITY" --direction Inbound --access Allow --protocol Tcp \
    --source-address-prefixes Internet --destination-address-prefixes "$PROXY_IP" \
    --destination-port-ranges 443 80
  echo "Rules added at priorities $ALLOW_PRIORITY, $DENY_PRIORITY and $PROXY_PRIORITY"
fi
```

## Step 11: Install the application

### 11a. Write your chart settings

Your chart settings go in `$VALUES_FILE` (step 1c). Single sign-on stays off
here; step 13 adds it after the install. The public proxy setting comes from
the infra, so the file does not set it.

#### 11a: Azure OpenAI

Make sure that the values from step 1 are set. This must show nothing:

```bash
check_values VALUES_FILE ADMIN_EMAIL NAME_PREFIX LLM_PROVIDER LLM_MODEL LLM_ENDPOINT
```

Then write the file:

```bash
mkdir -p "$(dirname "$VALUES_FILE")"
cat > "$VALUES_FILE" <<EOF
# Your chart settings. Written by step 11a of docs/azure-two-subscriptions-public-runbook.md.
# Do not set global.infra: those values come from the infra.
global:
  adminEmail: $ADMIN_EMAIL
  tenant:
    name: $NAME_PREFIX
  edge:
    mode: loadbalancer
    tls:
      secretName: autoheal-tls
  llm:
    provider: $LLM_PROVIDER
    model: $LLM_MODEL
    endpoint: $LLM_ENDPOINT
    apiKeyVaultEntry: llm-api-key
  sso:
    enabled: false
  imageRegistry: ""
EOF
cat "$VALUES_FILE"
```

#### 11a: Portkey

Make sure that the values from step 1 are set. This must show nothing:

```bash
check_values VALUES_FILE ADMIN_EMAIL NAME_PREFIX LLM_PROVIDER LLM_MODEL LLM_GATEWAY_URL
```

Then write the file:

```bash
mkdir -p "$(dirname "$VALUES_FILE")"
cat > "$VALUES_FILE" <<EOF
# Your chart settings. Written by step 11a of docs/azure-two-subscriptions-public-runbook.md.
# Do not set global.infra: those values come from the infra.
global:
  adminEmail: $ADMIN_EMAIL
  tenant:
    name: $NAME_PREFIX
  edge:
    mode: loadbalancer
    tls:
      secretName: autoheal-tls
  llm:
    provider: $LLM_PROVIDER
    model: $LLM_MODEL
    gateway:
      enabled: true
      kind: portkey
      baseUrl: $LLM_GATEWAY_URL
  sso:
    enabled: false
  imageRegistry: ""
EOF
cat "$VALUES_FILE"
```

### 11b. Install the chart

The install takes 10 to 20 minutes.

#### 11b: Terragrunt

```bash
cd "$WORK_DIR/acme-autoheal/prod/app"
terragrunt plan
terragrunt apply
```

The apply installs the chart in `$K8S_NAMESPACE` and makes the two public load
balancers on `$TEMPORAL_IP`.

#### 11b: Terraform Enterprise

The workers have no `kubelogin`, so you install the chart from your machine
with Helm. Helm signs in as you, with the access from step 4.

**1. Install the chart:**

```bash
cd "$WORK_DIR"
helm upgrade --install autoheal oci://public.ecr.aws/e4h3h0d9/charts/autoheal \
  --version 1.0.0-rc.8 -n "$K8S_NAMESPACE" \
  -f values-infra.yaml -f "$VALUES_FILE" --atomic --wait --timeout 20m
```

**2. Make the two public load balancers** on `$TEMPORAL_IP`, open only to the
runner, with a network policy for each. These are the same objects that the
app folder makes with Terragrunt:

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

## Step 12: Check that it works

### 12a. Check the pods

```bash
kubectl get pods -n "$K8S_NAMESPACE"      # all Running and ready
kubectl get svc -n "$K8S_NAMESPACE" temporal-frontend-public api-server-go-public   # EXTERNAL-IP is $TEMPORAL_IP
kubectl get svc -n "$K8S_NAMESPACE" autoheal-edge   # EXTERNAL-IP is $PROXY_IP
kubectl get secrets -n "$K8S_NAMESPACE"   # the secrets synced from Key Vault
```

### 12b. Check the runner

The runner VMs connect to Temporal:

```bash
az account set --subscription "$DATA_SUB"
az vmss run-command invoke -g "rg-$NAME_PREFIX-$ENVIRONMENT-autoheal" -n "$NAME_PREFIX-$ENVIRONMENT-autoheal-runner" \
  --instance-id 0 --command-id RunShellScript --scripts "docker logs --tail 30 runner-go"
```

The log must show a connection to `$TEMPORAL_IP:7233`.

### 12c. Check that only the runner reaches Temporal

From your own machine, this command must time out:

```bash
nc -vz -w 5 "$TEMPORAL_IP" 7233
```

### 12d. Open Autoheal

From any machine, this command must show `200` or `302`. Then open the address
it shows in a browser:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' "https://$AUTOHEAL_HOSTNAME"
echo "https://$AUTOHEAL_HOSTNAME"
```

### 12e. Sign in as the first admin

Terraform made a password for the first admin, `$ADMIN_EMAIL`, and keeps it in
the install vault as `first-admin-password`. Run the command on the machine of
step 8a, which the vault firewall lets in.

#### 12e: Terragrunt

```bash
export VAULT_NAME=$(cd "$WORK_DIR/acme-autoheal/prod/infra" && terragrunt output -json autoheal_values | jq -r .global.infra.keyVault.name)
az keyvault secret show --subscription "$DATA_SUB" --vault-name "$VAULT_NAME" --name first-admin-password --query value -o tsv
```

#### 12e: Terraform Enterprise

Only the workspace identity can read the vault, so the first command gives you
read access. It can take a few minutes to take effect:

```bash
export VAULT_NAME=$(grep -A2 'keyVault:' "$WORK_DIR/values-infra.yaml" | sed -n 's/.*name: *//p')
az role assignment create --assignee-object-id "$(az ad signed-in-user show --query id -o tsv)" \
  --assignee-principal-type User --role "Key Vault Secrets User" \
  --scope "$(az keyvault show --subscription "$DATA_SUB" -n "$VAULT_NAME" --query id -o tsv)" -o none
az keyvault secret show --subscription "$DATA_SUB" --vault-name "$VAULT_NAME" --name first-admin-password --query value -o tsv
```

Then open `https://$AUTOHEAL_HOSTNAME`, and sign in as `$ADMIN_EMAIL` with that
password. The login asks you for a new password. The vault keeps the first
password only; it does not learn the new one.

### 12f. Check the model calls

Start a chat in Autoheal, then look for the model calls in the agents-py logs.

#### 12f: Azure OpenAI

The command must show lines with your Azure OpenAI resource:

```bash
kubectl logs -n "$K8S_NAMESPACE" deploy/agents-py-worker --since=10m | grep 'HTTP Request: POST' |
  grep "$(echo "$LLM_ENDPOINT" | cut -d/ -f3)"
```

#### 12f: Portkey

The command must show lines with the gateway address. Calls go to the gateway,
not to the provider:

```bash
kubectl logs -n "$K8S_NAMESPACE" deploy/agents-py-worker --since=10m | grep 'HTTP Request: POST' |
  grep "$(echo "$LLM_GATEWAY_URL" | cut -d/ -f3)"
```

## Step 13 (optional): Turn on single sign-on

Single sign-on is set up after the install. The chart does not configure your
identity provider in this version: you add it in the Zitadel console, which
Autoheal uses for sign-in.

### 13a. Add your identity provider

1. Open the Zitadel console, and sign in as `$ADMIN_EMAIL` with the password
   that you set in step 12e:

   ```bash
   echo "https://auth.$AUTOHEAL_HOSTNAME/ui/console"
   ```

2. In your identity provider, for example Microsoft Entra ID, make an app
   registration for Autoheal, with a client secret.
3. In the Zitadel console, add the identity provider with the client ID and the
   secret of item 2. Zitadel shows the redirect URI; add it to the app
   registration of item 2.

Users then sign in to `https://$AUTOHEAL_HOSTNAME` with your identity provider.

## Troubleshooting

| Symptom                                                                               | Cause                                                                                        | Fix                                                                                                            |
| ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Step 4b shows `Error from server (Forbidden)`                                         | You have no Kubernetes rights in the cluster                                                 | See [You cannot make the namespace](#you-cannot-make-the-namespace)                                            |
| Step 4a or step 11b times out with `dial tcp <address>:443: i/o timeout`              | Your machine cannot reach the API server                                                     | See [Your machine cannot reach the API server](#your-machine-cannot-reach-the-api-server)                      |
| Step 8d shows `Set TF_VAR_tls_certificate`                                            | `jq` did not find the certificate files                                                      | Check `TLS_CERT_FILE` and `TLS_KEY_FILE` in step 1b. See [Get a TLS certificate](#get-a-tls-certificate)       |
| Step 9a fails with `registering resource provider ... connection may have been reset` | A network break while Terraform registered the resource providers                            | Run the command again                                                                                          |
| Step 9a stops on "workload_egress_ip_ranges" or "temporal_ip"                         | An input from step 8b is missing or private                                                  | Set it as the message says                                                                                     |
| Step 9a fails with 403 on Key Vault entries                                           | `deployer_ip_ranges` is not the address of the apply host                                    | Find the address again (step 8a) and update the input                                                          |
| Step 9a fails to add the subnet to the storage account                                | No service endpoint, or no Network Contributor on the subnet                                 | Do step 4d, or the last grant of step 6b                                                                       |
| Step 9a fails to read the cluster or the subnet                                       | Role grants not in effect yet, or given to another identity                                  | Wait 10 minutes and apply again. With Terraform Enterprise: check that `DEPLOYER_ID` is the workspace identity |
| With Terraform Enterprise: the run fails to sign in to Azure                          | The OIDC links of step 1c or the environment variables of step 7b                            | Check Step 4 of Part A and Step 8 of Part B in [terraform-enterprise.md](terraform-enterprise.md)              |
| Step 11b fails with Forbidden                                                         | The namespace role is missing or not in effect yet, or the namespace is not `$K8S_NAMESPACE` | Check step 6b and step 8c, wait, then try again                                                                |
| The secrets-sync job fails to sign in to Key Vault                                    | `service_accounts.namespace` is not `$K8S_NAMESPACE`                                         | Fix it in step 8b and apply step 9a again                                                                      |
| The proxy pod waits for the Secret `autoheal-tls`                                     | `tls_certificate` was not set in step 8d                                                     | Set it and apply step 9a again                                                                                 |
| Step 12e shows `Forbidden` from Key Vault | The vault firewall does not let in this machine, or you have no read access | Run it on the machine of step 8a. With Terraform Enterprise, wait a few minutes for the role grant |
| Pods wait for secrets, or show 403 from Key Vault                                     | The cluster's outbound addresses changed or are wrong                                        | Update `workload_egress_ip_ranges` and apply step 9a again                                                     |
| Pods cannot reach Postgres                                                            | The same                                                                                     | The same                                                                                                       |
| `temporal-frontend-public` stays `<pending>`                                          | The IP is not in the node resource group, or is not Standard and static                      | Do step 5a again                                                                                               |
| `autoheal-edge` stays `<pending>` | The proxy IP is not in the node resource group, or is not Standard and static | Do step 5b again |
| Users or webhooks time out on `https://$AUTOHEAL_HOSTNAME` | The subnet NSG blocks TCP 443, or a DNS record points elsewhere | Do step 10, and check step 9b |
| Step 9a stops on "edge_exposure" or "proxy_ip" | `PROXY_IP` is a private address, or the DNS zone is private | Do step 5b again, or see step 9b |
| The runner log shows no connection to Temporal                                        | The NSG blocks the runner                                                                    | Do step 10                                                                                                     |

## Upgrade

The cluster owner does not have to give new permissions.

### Upgrade with Terragrunt

Set the two new numbers, then apply step 9a and step 11b again. The command
also points the `source` lines at the release tag:

```bash
export NEW_INFRA_VERSION="<new autoheal-byoc-infra version, for example 2.2.1>"
export NEW_CHART_VERSION="<new chart version>"
cd "$WORK_DIR/acme-autoheal/prod"
perl -pi -e 's/^(\s*infra_version\s*=\s*)"[^"]*"/$1"$ENV{NEW_INFRA_VERSION}"/;
             s/^(\s*chart_version\s*=\s*)"[^"]*"/$1"$ENV{NEW_CHART_VERSION}"/' versions.hcl
perl -pi -e 's/\?ref=[^"]*"/?ref=v\$\{local.v.infra_version}"/' infra/terragrunt.hcl app/terragrunt.hcl
grep -n 'version' versions.hcl; grep -n 'source =' infra/terragrunt.hcl app/terragrunt.hcl
```

### Upgrade with Terraform Enterprise

Move the workspace branch to the new release and set `autoheal_version` to the
new chart version. Apply step 9a again. Save the new `values-infra.yaml`, then
run the `helm upgrade` of step 11b with the new `--version`.

## Remove

### Remove with Terragrunt

```bash
cd "$WORK_DIR/acme-autoheal/prod/app" && terragrunt destroy
cd "$WORK_DIR/acme-autoheal/prod/infra" && terragrunt destroy
```

### Remove with Terraform Enterprise

```bash
kubectl delete -n "$K8S_NAMESPACE" service/temporal-frontend-public service/api-server-go-public \
  networkpolicy/temporal-frontend-public networkpolicy/api-server-go-public
helm uninstall autoheal -n "$K8S_NAMESPACE"
```

Then, in the workspace, queue a destroy run: **Settings**, **Destruction and
Deletion**, **Queue destroy plan**.

### Remove the cluster owner's changes

As the cluster owner, remove the static IPs, the NSG rules and the deployer's
roles:

```bash
az account set --subscription "$CLUSTER_SUB"
az network public-ip delete -g "$NODE_RG" -n pip-autoheal-temporal
az network public-ip delete -g "$NODE_RG" -n pip-autoheal-proxy   # with two public IPs
if [ -n "$NSG_ID" ]; then
  az network nsg rule delete -g "$NSG_RG" --nsg-name "$NSG_NAME" -n allow-autoheal-runner
  az network nsg rule delete -g "$NSG_RG" --nsg-name "$NSG_NAME" -n deny-others-to-autoheal-temporal
  az network nsg rule delete -g "$NSG_RG" --nsg-name "$NSG_NAME" -n allow-autoheal-proxy
fi
for grant in \
  "Azure Kubernetes Service Cluster User Role|$AKS_ID" \
  "Azure Kubernetes Service RBAC Admin|$AKS_ID/namespaces/$K8S_NAMESPACE" \
  "Reader|$AKS_SUBNET_ID" \
  "Network Contributor|$AKS_SUBNET_ID"; do
  az role assignment delete --assignee "$DEPLOYER_ID" --role "${grant%%|*}" --scope "${grant#*|}"
done
```

Only if step 4b made the namespace for Autoheal:

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

`kubelogin` needs Entra ID, and the namespace role in step 6b needs Azure RBAC.
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
A pipeline that runs step 11b needs its own address in the list.

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

The grant can take up to 10 minutes to take effect. Then run step 4b again.
Membership in an admin group of the cluster (`aadProfile.adminGroupObjectIDs`)
also gives these rights.

- [Azure RBAC for Kubernetes authorization](https://learn.microsoft.com/azure/aks/manage-azure-rbac)

### The cluster uses the VNet that AKS made

`subnet` in step 2 is empty. The cluster runs on a VNet that AKS made and
manages. This runbook changes the AKS subnet (step 4d) and its NSG (step 10),
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

The check in step 4c shows a Helm release named `autoheal` from a different
install. Two installs in one namespace overwrite each other. Remove the other
install first, or use a different namespace: set it in step 1b, then start
again from step 4.

```bash
export K8S_NAMESPACE="autoheal-public"
```

### Other outbound types

Step 6a finds the outbound addresses for the `outboundType` `loadBalancer`. For
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

### Keep Autoheal private

For a proxy that only your network reaches, use a free private address in the
AKS subnet instead of the public IP of step 5b. Webhooks from outside your
network then cannot reach Autoheal. This command tries the addresses from the
end of the subnet, where AKS does not give out addresses, and keeps the first
one that Azure shows as free:

```bash
export SUBNET_PREFIX=$(az network vnet subnet show --ids "$AKS_SUBNET_ID" \
  --query "addressPrefix || addressPrefixes[0]" -o tsv)
unset PROXY_IP
for n in $(seq 2 20); do
  IP=$(python3 -c 'import ipaddress,sys; print(ipaddress.ip_network(sys.argv[1])[-int(sys.argv[2])])' "$SUBNET_PREFIX" "$n")
  if [ "$(az network vnet check-ip-address --subscription "$CLUSTER_SUB" -g "$(echo "$AKS_SUBNET_ID" | cut -d/ -f5)" \
        -n "$(echo "$AKS_SUBNET_ID" | cut -d/ -f9)" --ip-address "$IP" --query available -o tsv)" = "true" ]; then
    export PROXY_IP="$IP"; break
  fi
done
echo "PROXY_IP=${PROXY_IP:-none found}"
```

Then in step 8b, write `edge_exposure = "internal"`. In step 10, leave out the
`allow-autoheal-proxy` rule; your users reach `$PROXY_IP` on TCP 443 over your
network. In step 9b, a DNS provider that proxies traffic must not proxy these
records, because the address is private.

### A Portkey gateway

With Portkey, agents-py sends every model and embeddings call to the gateway,
and the gateway calls the provider with its own keys. The gateway is not part
of this install:

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
of these two. Then set `TLS_CERT_FILE` and `TLS_KEY_FILE` in step 1b to the
paths that the block shows, so that a new shell finds them.

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

certbot shows two TXT values, one at a time, both for the same name
`_acme-challenge.$AUTOHEAL_HOSTNAME`. Add each one as a separate TXT record in
your DNS provider. Do not edit the first record to hold the second value.
Before you press Enter after the second value, run this in a second terminal
until it shows both values:

```bash
dig +short TXT "_acme-challenge.$AUTOHEAL_HOSTNAME" @1.1.1.1
```

If certbot stops with `Incorrect TXT record`, run the `certbot certonly` command
again. It asks only for the value that failed. Add it as one more TXT record.

To renew, run the `certbot` command again before the 90 days end, then apply
step 9a.

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
- [Static public IP for an AKS load balancer](https://learn.microsoft.com/azure/aks/static-ip): the public IPs of step 5
- [Standard load balancer in AKS](https://learn.microsoft.com/azure/aks/load-balancer-standard): `loadBalancerSourceRanges`, which lets only the runner reach Temporal
- [Network security groups](https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview): the rules of step 10
- [Storage network security limitations](https://learn.microsoft.com/azure/storage/common/storage-network-security-limitations): why storage uses a subnet rule, not IP rules
- [Dynamic credentials with the Azure provider](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/azure-configuration): how Terraform Enterprise signs in to Azure with OIDC
