# Runbook: Autoheal on an existing AKS cluster, public endpoints

This runbook installs Autoheal end to end on an AKS cluster that you already
have. The cluster stays in its subscription (the **cluster subscription**).
All the other Autoheal resources go in a second subscription (the **data
subscription**). The two VNets are not connected. The data services use public
endpoints with firewalls, and users and webhooks reach Autoheal on a public IP.
[The one-pager](azure-two-subscriptions-public.md) explains the layout, and
[the comparison](azure-subscription-options.md) shows its limits. The runbook
uses autoheal-byoc-infra **v4.1.0**.

The runbook has two roles. One person can do both:

- The **cluster owner** prepares the cluster (steps 1 to 6) and adds the
  storage network rule (step 9c).
- The **deployer** runs Terraform (steps 7 to 9b and steps 10 to 14). The infra
  apply of step 9a works in the data subscription only and does not read the
  cluster. Step 10 reads the cluster and connects the Autoheal identities to it.

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
- [Step 5: Make the public IP for the proxy](#step-5-make-the-public-ip-for-the-proxy)
  - [5a. Make the static public IP](#5a-make-the-static-public-ip)
  - [5b. Open the subnet NSG for the proxy](#5b-open-the-subnet-nsg-for-the-proxy)
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
  - [9c. Add the storage network rule](#9c-add-the-storage-network-rule)
- [Step 10: Connect the identities to the cluster](#step-10-connect-the-identities-to-the-cluster): [Terragrunt](#10-terragrunt), [Terraform Enterprise](#10-terraform-enterprise)
- [Step 11: Install the application](#step-11-install-the-application)
  - [11a. Write your chart settings](#11a-write-your-chart-settings): [Azure OpenAI](#11a-azure-openai), [Portkey](#11a-portkey)
  - [11b. Install the chart](#11b-install-the-chart): [Terragrunt](#11b-terragrunt), [Terraform Enterprise](#11b-terraform-enterprise)
- [Step 12: Check that it works](#step-12-check-that-it-works)
  - [12a. Check the pods](#12a-check-the-pods)
  - [12b. Check the federated credentials](#12b-check-the-federated-credentials)
  - [12c. Check that the pods signed in to Key Vault](#12c-check-that-the-pods-signed-in-to-key-vault)
  - [12d. Open Autoheal](#12d-open-autoheal)
  - [12e. Sign in as the first admin](#12e-sign-in-as-the-first-admin): [Terragrunt](#12e-terragrunt), [Terraform Enterprise](#12e-terraform-enterprise)
  - [12f. Check the model calls](#12f-check-the-model-calls): [Azure OpenAI](#12f-azure-openai), [Portkey](#12f-portkey)
- [Step 13 (optional): Turn on single sign-on](#step-13-optional-turn-on-single-sign-on)
  - [13a. Add your identity provider](#13a-add-your-identity-provider)
- [Step 14 (optional): Add the sandbox runner](#step-14-optional-add-the-sandbox-runner)
  - [14a. Make the DNS record for the runner host](#14a-make-the-dns-record-for-the-runner-host)
  - [14b. Check the certificate](#14b-check-the-certificate)
  - [14c. Turn on the runner route](#14c-turn-on-the-runner-route)
  - [14d. Make the runner](#14d-make-the-runner): [Terragrunt](#14d-terragrunt), [Terraform Enterprise](#14d-terraform-enterprise)
  - [14e. Check that the runner polls](#14e-check-that-the-runner-polls)
  - [14f. Turn on sandboxes](#14f-turn-on-sandboxes)
  - [14g. Change the runner key](#14g-change-the-runner-key)
- [Resume in a new shell](#resume-in-a-new-shell)
- [Troubleshooting](#troubleshooting)
- [Upgrade](#upgrade): [Terragrunt](#upgrade-with-terragrunt), [Terraform Enterprise](#upgrade-with-terraform-enterprise), [from 3.x](#upgrade-from-3x)
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
  - [A shared Istio gateway](#a-shared-istio-gateway)
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
| 9: apply the infra, storage rule     | 10 min                                | 30 to 45 min                                   |
| 10: connect the identities           | 5 min                                 |                                                |
| 11: install the application          | 10 min                                | 10 to 20 min                                   |
| 12: check                            | 10 min                                |                                                |
| 13 (optional): single sign-on        | 20 min                                |                                                |
| 14 (optional): sandbox runner        | 20 min                                | 10 to 20 min                                   |

These times are estimates. Plan half a day for a first install.

## Before you start

You must have:

- An AKS cluster on a subnet of a VNet that you manage. A cluster on the
  VNet that AKS makes for itself does not fit this runbook.
- A path from your machine to the cluster's API server on TCP 443. Step 4 and
  step 11 use it. Step 2 shows how to check it.
- A data subscription in the same Microsoft Entra tenant as the cluster.
- One Standard static public IP in the node resource group of the cluster.
  Step 5 makes it.
- Owner on the cluster subscription and Kubernetes admin rights in the
  cluster, or the cluster owner's help for steps 1 to 6 and step 9c. Owner on
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
  For the sandbox runner of step 14 it must cover `runner.<hostname>` too. A
  certificate for `hostname` and `*.<hostname>` covers all four.
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

## Step 1: Sign in and set your values

Open one shell and keep it open. Every later step uses the variables you set
here and in steps 4 to 9. Keep a copy of your filled-in blocks of step 1: in a
new shell, run them again, then [Resume in a new shell](#resume-in-a-new-shell).
Steps 1 to 6 work from any folder. From step 7, the commands go to the folders
that they need themselves.

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

# Autoheal
export AUTOHEAL_HOSTNAME="autoheal.acme.example"   # the name users open; also auth.<name> and auth-app.<name>
export DNS_ZONE_ID=""                  # ID of an Azure DNS zone in the data subscription that holds the name; empty: you make the records in step 9b
export ADMIN_EMAIL="<email of the first admin>"
export TLS_CERT_FILE="$HOME/certs/fullchain.pem"   # certificate chain for the three names; see "Get a TLS certificate" at the end
export TLS_KEY_FILE="$HOME/certs/privkey.pem"      # its private key

check_values WORK_DIR CLUSTER_SUB AKS_RG AKS_NAME K8S_NAMESPACE DATA_SUB LOCATION NAME_PREFIX ENVIRONMENT \
  AUTOHEAL_HOSTNAME ADMIN_EMAIL TLS_CERT_FILE TLS_KEY_FILE
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
export TFE_WORKSPACE="autoheal-infra-prod"             # the infra, step 9a
export TFE_CLUSTER_WORKSPACE="autoheal-cluster-prod"   # the identities on the cluster, step 10

# Your chart settings, written in step 11a
export VALUES_FILE="$WORK_DIR/values-customer.yaml"

check_values TFE_ISSUER TFE_ORG TFE_PROJECT TFE_WORKSPACE TFE_CLUSTER_WORKSPACE VALUES_FILE
```

The deployer is the identity of the two workspaces: an app registration that
both workspaces sign in as with OIDC. This makes it, or finds it when it
exists, and links it to each workspace:

```bash
export APP_ID=$(az ad app list --display-name "tfe-autoheal-byoc" --query "[0].appId" -o tsv)
[ -n "$APP_ID" ] || export APP_ID=$(az ad app create --display-name "tfe-autoheal-byoc" --query appId -o tsv)
az ad sp show --id "$APP_ID" -o none 2>/dev/null || az ad sp create --id "$APP_ID" -o none
for ws in "$TFE_WORKSPACE" "$TFE_CLUSTER_WORKSPACE"; do
  for phase in plan apply; do
    az ad app federated-credential show --id "$APP_ID" --federated-credential-id "tfe-${ws}-${phase}" -o none 2>/dev/null ||
      az ad app federated-credential create --id "$APP_ID" -o none --parameters "{
        \"name\": \"tfe-${ws}-${phase}\",
        \"issuer\": \"${TFE_ISSUER}\",
        \"subject\": \"organization:${TFE_ORG}:project:${TFE_PROJECT}:workspace:${ws}:run_phase:${phase}\",
        \"audiences\": [\"api://AzureADTokenExchange\"]
      }"
  done
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
az account set --subscription "$CLUSTER_SUB"
# oidcIssuer or workloadIdentity
az aks update -g "$AKS_RG" -n "$AKS_NAME" --enable-oidc-issuer --enable-workload-identity
# keyVaultAddon
az aks enable-addons -g "$AKS_RG" -n "$AKS_NAME" --addons azure-keyvault-secrets-provider
```

Each command takes 5 to 10 minutes.

## Step 4: Make the namespace and prepare the AKS subnet

### 4a. Connect to the cluster

```bash
az account set --subscription "$CLUSTER_SUB"
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

## Step 5: Make the public IP for the proxy

### 5a. Make the static public IP

Users and webhook senders reach Autoheal on this IP. The Autoheal proxy serves
the web app, the login and the webhooks over HTTPS on it. The DNS records for
`hostname`, `auth.<hostname>` and `auth-app.<hostname>` point to it.

The IP goes in the node resource group of the cluster, in the cluster
subscription. Azure may warn about a coming change to zones; it does not affect
this IP:

```bash
export NODE_RG=$(az aks show --subscription "$CLUSTER_SUB" -g "$AKS_RG" -n "$AKS_NAME" --query nodeResourceGroup -o tsv)
export PROXY_IP=$(az network public-ip create --subscription "$CLUSTER_SUB" -g "$NODE_RG" -n pip-autoheal-proxy \
  --location "$LOCATION" --sku Standard --allocation-method Static --query publicIp.ipAddress -o tsv)
echo "$PROXY_IP"
```

### 5b. Open the subnet NSG for the proxy

When the AKS subnet has an NSG, add a rule to it that lets everyone reach the
proxy IP on TCP 443 and 80. To let in only some sources, for example your users
and the webhook senders, put their ranges in place of `Internet`.

Without an NSG, AKS opens its own NSG for the load balancer, and the command
does nothing. The rule takes the first free priority from 300:

```bash
az account set --subscription "$CLUSTER_SUB"
export NSG_ID=$(az network vnet subnet show --ids "$AKS_SUBNET_ID" --query networkSecurityGroup.id -o tsv)
echo "NSG: ${NSG_ID:-none}"
if [ -n "$NSG_ID" ]; then
  export NSG_RG=$(echo "$NSG_ID" | cut -d/ -f5) NSG_NAME=$(echo "$NSG_ID" | cut -d/ -f9)
  USED=$(az network nsg rule list -g "$NSG_RG" --nsg-name "$NSG_NAME" \
    --query "[?name!='allow-autoheal-proxy'].priority" -o tsv)
  PROXY_PRIORITY=300; while echo "$USED" | grep -qx "$PROXY_PRIORITY"; do PROXY_PRIORITY=$((PROXY_PRIORITY+1)); done
  az network nsg rule create -g "$NSG_RG" --nsg-name "$NSG_NAME" -o none \
    -n allow-autoheal-proxy --priority "$PROXY_PRIORITY" --direction Inbound --access Allow --protocol Tcp \
    --source-address-prefixes Internet --destination-address-prefixes "$PROXY_IP" \
    --destination-port-ranges 443 80
  echo "Rule added at priority $PROXY_PRIORITY"
fi
```

## Step 6: Get the outbound addresses and give the deployer its roles

### 6a. Get the outbound addresses

The public outbound addresses of the cluster. Postgres and the Key Vaults let
in only these addresses, so they must stay fixed. For the `outboundType`
`loadBalancer` from step 2, this command finds them:

```bash
az account set --subscription "$CLUSTER_SUB"
export EGRESS_IPS=$(az aks show -g "$AKS_RG" -n "$AKS_NAME" \
  --query "networkProfile.loadBalancerProfile.effectiveOutboundIPs[].id" -o tsv |
  xargs -n1 az network public-ip show --query ipAddress -o tsv --ids |
  sed 's|$|/32|' | paste -sd' ' -)
echo "$EGRESS_IPS"
```

It must show one or more addresses. For another `outboundType`, see
[Other outbound types](#other-outbound-types).

### 6b. Give the deployer its roles

Cluster User Role lets the deployer read the cluster and its connection details
in step 10. RBAC Admin on the namespace lets the chart make its Roles and
RoleBindings there in step 11. The deployer needs no role on the AKS subnet:

```bash
export AKS_ID=$(az aks show -g "$AKS_RG" -n "$AKS_NAME" --query id -o tsv)
for grant in \
  "Azure Kubernetes Service Cluster User Role|$AKS_ID" \
  "Azure Kubernetes Service RBAC Admin|$AKS_ID/namespaces/$K8S_NAMESPACE"; do
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
          Microsoft.KeyVault Microsoft.Network Microsoft.ManagedIdentity; do
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
      cluster/terragrunt.hcl   reads the cluster and connects the identities to it (step 10)
      app/terragrunt.hcl       the app inputs (step 8c)
      app/values-customer.yaml your chart settings (step 11a)
```

**1. Copy the starter files.** You can run this again. It keeps a copy and
files that are there already, so it does not overwrite your edits:

```bash
mkdir -p "$WORK_DIR" && cd "$WORK_DIR"
[ -d autoheal-byoc-infra ] || git clone --branch v4.1.0 https://github.com/autohealai/autoheal-byoc-infra.git
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
  directory `compositions/azure`, on a branch of your copy at the tag v4.1.0. Set the workspace Terraform version to 1.7 or later.
- Add the four environment variables for the sign-in. `ARM_SUBSCRIPTION_ID`
  is `$DATA_SUB`. The composition does not read the cluster, so this workspace
  needs no access to the cluster subscription.

**3. Make the cluster workspace.** Do the same again for a second workspace,
`autoheal-cluster-prod` (`$TFE_CLUSTER_WORKSPACE`), with the Terraform working
directory `compositions/azure-cluster`, on the same branch, with Terraform 1.7
or later and the same four environment variables. `ARM_SUBSCRIPTION_ID` is
`$DATA_SUB` here too. Step 10 sets its inputs and runs it.

The workspaces keep the state. You do not make a storage account.

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
check_values AKS_ID AKS_SUBNET_ID PROXY_IP EGRESS_IPS DEPLOYER_IPS
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
  proxy_ip      = "$PROXY_IP"
}
service_accounts          = { namespace = "$K8S_NAMESPACE" }
workload_egress_ip_ranges = [$(echo "$EGRESS_IPS" | tr ' ' '\n' | sed 's/.*/"&"/' | paste -sd, -)]
deployer_ip_ranges        = [$(echo "$DEPLOYER_IPS" | tr ' ' '\n' | sed 's/.*/"&"/' | paste -sd, -)]

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
code at the tag `infra_version` in `versions.hcl`:

```bash
cd "$WORK_DIR/acme-autoheal/prod/infra"
{
  cat <<EOF
# The cloud resources in the data subscription. Written by step 8c of
# docs/azure-two-subscriptions-public-runbook.md.

locals { v = read_terragrunt_config(find_in_parent_folders("versions.hcl")).locals }

include "root" { path = find_in_parent_folders("root.hcl") }

terraform {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure?ref=v\${local.v.infra_version}"
}

inputs = {
EOF
  sed 's/^/  /; s/^  $//' "$WORK_DIR/inputs.hcl"
  echo "}"
} > terragrunt.hcl
cat terragrunt.hcl
```

**2. Set the namespace of the app folder:**

```bash
cd "$WORK_DIR/acme-autoheal/prod/app"
perl -pi -e 's/^(\s*namespace\s*=\s*)"[^"]*"/$1"$ENV{K8S_NAMESPACE}"/' terragrunt.hcl
grep -n '^ *namespace ' terragrunt.hcl
```

#### 8c: Terraform Enterprise

In the workspace, open **Variables**, and add each line of the output below as
a variable of the category **Terraform**. The key is the name before `=`; the
value is the part after it. For `existing_network`, `service_accounts` and the
two `_ranges` lists, tick **HCL**:

```bash
cat "$WORK_DIR/inputs.hcl"
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

Read the plan before you type `yes`. Then read the outputs, and keep the name
of the storage account for step 9c:

```bash
terragrunt output required_cluster_owner_actions   # the list from steps 2 to 6 and step 9c, with real values
terragrunt output required_dns_records             # the records for step 9b; empty when Terraform made them
export STORAGE_ACCOUNT=$(terragrunt output -json autoheal_values | jq -r .global.infra.objectStore.account)
echo "$STORAGE_ACCOUNT"
```

#### 9a: Terraform Enterprise

In the workspace, click **Actions**, then **Start new run**. Read the plan, then
click **Confirm & Apply**. Then open the **Outputs** tab.

Save the value of `autoheal_values_yaml` for step 11b. Run this command, paste
the value, then press Ctrl-D:

```bash
cat > "$WORK_DIR/values-infra.yaml"
```

Read `required_cluster_owner_actions` and `required_dns_records` there too.
Step 10 uses the `cluster` and `federation` outputs. Keep the name of the
storage account for step 9c:

```bash
export STORAGE_ACCOUNT=$(grep -A3 'objectStore:' "$WORK_DIR/values-infra.yaml" | sed -n 's/.*account: *//p')
echo "$STORAGE_ACCOUNT"
```

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

### 9c. Add the storage network rule

The cluster owner does this sub-step. Azure Storage does not apply IP rules to
clients in its own region. The pods reach the storage account from the AKS
subnet, through the service endpoint of step 4d, and the account lets them in
only with a network rule for that subnet. This is the
`az storage account network-rule add` line of `required_cluster_owner_actions`.
Terraform leaves the rule alone in later applies.

Whoever adds the rule needs two rights:

- `Microsoft.Network/virtualNetworks/subnets/joinViaServiceEndpoint/action` on
  the AKS subnet. The cluster owner has it.
- Write on the storage account, in the data subscription. The deployer has it.

Find the storage account:

```bash
export STORAGE_ID=$(az storage account show --subscription "$DATA_SUB" -n "$STORAGE_ACCOUNT" --query id -o tsv)
echo "$STORAGE_ID"
```

When the cluster owner and the deployer are two people, the deployer gives the
cluster owner Storage Account Contributor on the account. It can take a few
minutes to take effect. The deployer can remove it after this sub-step:

```bash
az role assignment create --assignee "<sign-in name or object ID of the cluster owner>" \
  --role "Storage Account Contributor" --scope "$STORAGE_ID" -o none
```

Then, as the cluster owner, add the rule and check it. The list must show the
AKS subnet with the state `Succeeded`:

```bash
az storage account network-rule add --subscription "$DATA_SUB" -g "$(echo "$STORAGE_ID" | cut -d/ -f5)" \
  --account-name "$STORAGE_ACCOUNT" --subnet "$AKS_SUBNET_ID" -o none
az storage account network-rule list --subscription "$DATA_SUB" -g "$(echo "$STORAGE_ID" | cut -d/ -f5)" \
  --account-name "$STORAGE_ACCOUNT" --query "virtualNetworkRules[].[virtualNetworkResourceId, state]" -o tsv
```

## Step 10: Connect the identities to the cluster

The pods sign in to Key Vault and storage as three managed identities in the
data subscription. Each identity trusts the cluster's OIDC issuer through one
federated credential for each chart service account. The infra apply of step 9a
does not read the cluster, so it makes no federated credentials. This step
reads the cluster, checks it, and makes them. It makes nothing in the cluster
subscription.

The deployer needs the Cluster User Role of step 6b. The plan stops when the
OIDC issuer of the cluster is off: do step 3. It warns when the Key Vault
secrets provider add-on is off. That is fine when the cluster has its own
Secrets Store CSI driver with the Azure Key Vault provider; otherwise do
step 3.

#### 10: Terragrunt

The `cluster` folder reads the outputs of the `infra` folder itself:

```bash
cd "$WORK_DIR/acme-autoheal/prod/cluster"
terragrunt plan
terragrunt apply
terragrunt output federated_credentials
```

The last command shows one line per credential: the identity, the credential
name and the subject. Each subject is
`system:serviceaccount:<namespace>:<service account>`, with your
`$K8S_NAMESPACE`.

#### 10: Terraform Enterprise

1. In the infra workspace, open the **Outputs** tab, and copy the values of
   `cluster` and `federation`.
2. In the cluster workspace, open **Variables**, and add two variables of the
   category **Terraform**, `cluster` and `federation`, with **HCL** ticked. The
   values are the ones from item 1.
3. Click **Actions**, then **Start new run**. Read the plan, then click
   **Confirm & Apply**.
4. Open the **Outputs** tab of the cluster workspace. `federated_credentials`
   shows one line per credential: the identity, the credential name and the
   subject. Each subject is
   `system:serviceaccount:<namespace>:<service account>`, with your
   `$K8S_NAMESPACE`.

## Step 11: Install the application

### 11a. Write your chart settings

Your chart settings go in `$VALUES_FILE` (step 1c). Single sign-on stays off
here; step 13 adds it after the install. The public proxy setting comes from
the infra, so the file does not set it. `offeredModels` lists the models that
agents may use, comma separated; the first is the default for an agent that
names no model.

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
    offeredModels: $LLM_MODEL
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
    offeredModels: $LLM_MODEL
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

The apply installs the chart in `$K8S_NAMESPACE`, with the load balancer of the
proxy on `$PROXY_IP`. It connects to the cluster with the endpoint and CA
certificate from the `cluster` folder of step 10.

#### 11b: Terraform Enterprise

The workers have no `kubelogin`, so you install the chart from your machine
with Helm. Helm signs in as you, with the access from step 4:

```bash
cd "$WORK_DIR"
helm upgrade --install autoheal oci://public.ecr.aws/e4h3h0d9/charts/autoheal \
  --version 1.0.0-rc.12 -n "$K8S_NAMESPACE" \
  -f values-infra.yaml -f "$VALUES_FILE" --atomic --wait --timeout 20m
```

## Step 12: Check that it works

### 12a. Check the pods

```bash
kubectl get pods -n "$K8S_NAMESPACE"      # all Running and ready
kubectl get svc -n "$K8S_NAMESPACE" autoheal-edge   # EXTERNAL-IP is $PROXY_IP
```

### 12b. Check the federated credentials

Step 10 made one federated credential for each chart service account. Each
subject must name `$K8S_NAMESPACE`. With Terragrunt:

```bash
cd "$WORK_DIR/acme-autoheal/prod/cluster" && terragrunt output federated_credentials
```

With Terraform Enterprise: `federated_credentials` in the **Outputs** tab of the
cluster workspace.

### 12c. Check that the pods signed in to Key Vault

The chart's secrets-sync hook Job and CronJob run as the `autoheal-hooks`
service account. They sign in to Key Vault with workload identity and copy the
secrets into Kubernetes Secrets. The Secrets must exist, and no secrets-sync
job may show `Failed`:

```bash
kubectl get secrets -n "$K8S_NAMESPACE"         # the secrets synced from Key Vault
kubectl get jobs,cronjobs -n "$K8S_NAMESPACE"   # the secrets-sync jobs
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

## Step 14 (optional): Add the sandbox runner

Sandboxes are where the agents run commands: shell commands, git and skill
scripts. Without them the agents answer and call your integrations, but run no
commands. Sandboxes run on runner VMs outside the cluster, in the data
subscription. A runner VM reaches Temporal, the workflow engine in the cluster,
through the same proxy as your users, on a hostname of its own,
`runner.$AUTOHEAL_HOSTNAME`. It dials out on TCP 443 over TLS and sends a key
with each call. The proxy passes a call on to Temporal only when it carries the
key, and answers 401 to anything else. Nothing connects in to the runner.

This step needs autoheal-byoc-infra 4.1.0 or later and chart 1.0.0-rc.12 or
later. For an install on 4.0.x, do [Upgrade](#upgrade) first: the infra plan
adds two resources, the runner key and its vault entry `runner-token`.

The deployer does every sub-step. The DNS records are for whoever owns the
zone, as in step 9b. With a shared Istio gateway instead of `$PROXY_IP`, see
[A shared Istio gateway](#a-shared-istio-gateway) for 14a and 14b.

### 14a. Make the DNS record for the runner host

Terraform does not make this record, even with `DNS_ZONE_ID`. Make one A
record, `$RUNNER_HOST`, with the value `$PROXY_IP`, as in step 9b:

```bash
export RUNNER_HOST="runner.$AUTOHEAL_HOSTNAME"
check_values RUNNER_HOST PROXY_IP
```

In an Azure DNS zone:

```bash
export RECORDS_ZONE_ID="${DNS_ZONE_ID:-<ID of the Azure DNS zone that holds AUTOHEAL_HOSTNAME>}"
export ZONE_SUB=$(echo "$RECORDS_ZONE_ID" | cut -d/ -f3) ZONE_RG=$(echo "$RECORDS_ZONE_ID" | cut -d/ -f5) \
  ZONE_NAME=$(echo "$RECORDS_ZONE_ID" | cut -d/ -f9)
az network dns record-set a add-record --subscription "$ZONE_SUB" -g "$ZONE_RG" -z "$ZONE_NAME" \
  -n "${RUNNER_HOST%.$ZONE_NAME}" -a "$PROXY_IP" -o none
```

Outside Azure, make the record by hand in your DNS provider, DNS only, as in
step 9b. Then check that the name shows `$PROXY_IP`:

```bash
dig +short A "$RUNNER_HOST" @1.1.1.1
```

### 14b. Check the certificate

The proxy serves the certificate of step 8d for the runner host too, so it must
cover `$RUNNER_HOST`. A wildcard for `*.$AUTOHEAL_HOSTNAME` covers it. This
shows the names in the certificate:

```bash
openssl x509 -in "$TLS_CERT_FILE" -noout -text | grep -A1 'Subject Alternative Name'
```

When it shows neither `$RUNNER_HOST` nor `*.$AUTOHEAL_HOSTNAME`, get a new
certificate that does ([Get a TLS certificate](#get-a-tls-certificate)), set
`tls_certificate` again as in step 8d, and apply step 9a.

### 14c. Turn on the runner route

Add the runner host under `edge` in your chart settings. Sandboxes stay off
until step 14f:

```bash
check_values VALUES_FILE RUNNER_HOST
grep -q '^    runner:' "$VALUES_FILE" ||
  perl -0pi -e 's/^(  edge:\n)/$1    runner:\n      host: $ENV{RUNNER_HOST}\n/m' "$VALUES_FILE"
grep -n -A1 '^    runner:' "$VALUES_FILE" ||
  echo "STOP: no runner under edge in $VALUES_FILE"
```

It must show `runner:` and `host: <your runner host>`. On `STOP`, the file has
no `edge:` line indented by two spaces under `global:`: add the two lines under
`edge:` by hand.

Then install the chart again, as in step 11b. The proxy now answers on the
runner host. Without the key it must show `401`:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' "https://$RUNNER_HOST"
```

`404` means the chart runs without the runner host: check `$VALUES_FILE` and
step 11b. A timeout means the DNS record of step 14a or the NSG rule of step
5b.

### 14d. Make the runner

The runner gets its own VNet in the data subscription, from `10.61.0.0/24`,
with a NAT gateway for its outbound traffic. It reaches `$PROXY_IP` over the
internet, so no VNet connection is needed. The VMs pull
`runner-go:chart-<chart_version>` from the public registry.

When step 5b let in only some sources, the cluster owner adds the runner's
outbound address to the rule after this apply: the `egress_ip` output. When a
private CA signed the certificate, the runner needs the CA: the commands below
copy it from `TF_VAR_edge_ca_certificate`.

#### 14d: Terragrunt

Copy the runner folder of the release, set your values in it, then apply:

```bash
git -C "$WORK_DIR/autoheal-byoc-infra" fetch --tags
git -C "$WORK_DIR/autoheal-byoc-infra" checkout "v$(sed -n 's/.*infra_version *= *"\([^"]*\)".*/\1/p' "$WORK_DIR/acme-autoheal/prod/versions.hcl")"
cd "$WORK_DIR/acme-autoheal/prod"
[ -e runner/terragrunt.hcl ] || { mkdir -p runner && cp "$WORK_DIR/autoheal-byoc-infra/examples/azure/split-public/runner/terragrunt.hcl" runner/; }
cd runner
perl -pi -e 's/^(\s*namespace\s*=\s*)"[^"]*"/$1"$ENV{NAME_PREFIX}"/;
             s/^(\s*environment\s*=\s*)"[^"]*"/$1"$ENV{ENVIRONMENT}"/;
             s/^(\s*location\s*=\s*)"[^"]*"/$1"$ENV{LOCATION}"/;
             s/^(\s*subscription_id\s*=\s*)"[^"]*"/$1"$ENV{DATA_SUB}"/;
             s/^(\s*runner_host\s*=\s*)"[^"]*"/$1"$ENV{RUNNER_HOST}"/' terragrunt.hcl
if [ -n "$TF_VAR_edge_ca_certificate" ]; then
  printf '%s\n' "$TF_VAR_edge_ca_certificate" > edge-ca.pem
  perl -pi -e 's/^(\s*)# (temporal_ca_certificate\s*=)/$1$2/' terragrunt.hcl
fi
grep -n 'namespace\|environment\|location\|subscription_id\|runner_host\|temporal_' terragrunt.hcl
terragrunt plan
terragrunt apply
terragrunt output egress_ip
```

The runner folder reads the key from the `infra` folder (the `runner_token`
output), so the key is never typed. The plan adds the runner's resource group,
network, identity and VM scale set. Keep `edge-ca.pem` in the folder: every
later apply reads it.

#### 14d: Terraform Enterprise

1. Make a third workspace, `autoheal-runner-prod`, as in step 7b, item 3: the
   Terraform working directory `compositions/azure-runner`, on the same branch,
   with Terraform 1.7 or later and the same four environment variables. Then
   link it to the workspace identity, as in step 1c:

   ```bash
   export TFE_RUNNER_WORKSPACE="autoheal-runner-prod"
   for phase in plan apply; do
     az ad app federated-credential show --id "$APP_ID" --federated-credential-id "tfe-${TFE_RUNNER_WORKSPACE}-${phase}" -o none 2>/dev/null ||
       az ad app federated-credential create --id "$APP_ID" -o none --parameters "{
         \"name\": \"tfe-${TFE_RUNNER_WORKSPACE}-${phase}\",
         \"issuer\": \"${TFE_ISSUER}\",
         \"subject\": \"organization:${TFE_ORG}:project:${TFE_PROJECT}:workspace:${TFE_RUNNER_WORKSPACE}:run_phase:${phase}\",
         \"audiences\": [\"api://AzureADTokenExchange\"]
       }"
   done
   ```

2. Add these variables of the category **Terraform**:

   | Key                       | Sensitive | Value                                                  |
   | ------------------------- | --------- | ------------------------------------------------------ |
   | `namespace`               | No        | `$NAME_PREFIX`                                         |
   | `environment`             | No        | `$ENVIRONMENT`                                         |
   | `location`                | No        | `$LOCATION`                                            |
   | `subscription_id`         | No        | `$DATA_SUB`                                            |
   | `temporal_address`        | No        | `$RUNNER_HOST:443`                                     |
   | `chart_version`           | No        | The chart version of step 11b                          |
   | `temporal_token`          | Yes       | The vault entry `runner-token`: the command below      |
   | `temporal_ca_certificate` | No        | Only with a private CA: the text of `ca.pem`           |

   On the machine of step 8a, with the read access of step 12e:

   ```bash
   az keyvault secret show --subscription "$DATA_SUB" --vault-name "$VAULT_NAME" --name runner-token --query value -o tsv
   ```

3. Start a run, read the plan, then click **Confirm & Apply**. The
   `egress_ip` output is the runner's outbound address.

### 14e. Check that the runner polls

A VM takes about 5 minutes to boot, install Docker and pull the image. Then
runner-go holds long polls open on Temporal through the proxy. The proxy logs
each poll when it ends, after up to a minute. This counts the polls of the last
10 minutes that carried the key and reached Temporal:

```bash
kubectl logs -n "$K8S_NAMESPACE" -l app.kubernetes.io/name=autoheal-proxy -c envoy --since=10m |
  grep -F "$RUNNER_HOST" | grep '"upstream":"temporal"' | grep -cE '"status":"?200'
```

It must show a number above 0. When it shows 0, read the runner's log on each
VM. The VM numbers change when VMs are replaced, so the loop looks them up:

```bash
RUNNER_RG="rg-$NAME_PREFIX-$ENVIRONMENT-autoheal-runner"
RUNNER_VMSS="$NAME_PREFIX-$ENVIRONMENT-autoheal-runner"
for id in $(az vmss list-instances --subscription "$DATA_SUB" -g "$RUNNER_RG" -n "$RUNNER_VMSS" --query '[].instanceId' -o tsv); do
  echo "== VM $id"
  az vmss run-command invoke --subscription "$DATA_SUB" -g "$RUNNER_RG" -n "$RUNNER_VMSS" \
    --command-id RunShellScript --instance-id "$id" \
    --scripts "systemctl is-active runner-go; journalctl -u runner-go -n 50 --no-pager" --query 'value[0].message' -o tsv
done
```

See [Troubleshooting](#troubleshooting) for the usual messages.

### 14f. Turn on sandboxes

Only after step 14e shows polls. With sandboxes on and no runner, every agent
run waits for a sandbox that never starts, then fails:

```bash
grep -q '^  sandbox:' "$VALUES_FILE" ||
  perl -0pi -e 's/^(  edge:\n)/  sandbox:\n    enabled: true\n$1/m' "$VALUES_FILE"
grep -n -A1 '^  sandbox:' "$VALUES_FILE" ||
  echo "STOP: no sandbox under global in $VALUES_FILE"
```

It must show `sandbox:` and `enabled: true`. On `STOP`, add the two lines under
`global:` by hand; on `enabled: false`, change it to `true`.

Then install the chart again, as in step 11b. To check, ask an agent in a new
chat to run `uname -a` in a sandbox. The answer shows the Linux kernel of the
sandbox.

To turn sandboxes off again, set `enabled: false` under `sandbox` and install
the chart again.

### 14g. Change the runner key

Change the key when it may have leaked, or when your policy says so. There is
one key at a time, so the runner gets `401` from when the proxy takes the new
key until the runner VMs boot with it, about 5 to 10 minutes. Agent runs that
need a sandbox in that time fail, and the runner apply restarts the VMs, which
ends the sandboxes on them. Pick a quiet time, and do the three parts one after
the other: within 15 minutes of the first, the proxy takes the new key by
itself.

1. Make a new key. With Terragrunt:

   ```bash
   cd "$WORK_DIR/acme-autoheal/prod/infra"
   terragrunt apply -replace=random_password.runner_token
   ```

   With Terraform Enterprise, start a run in the infra workspace that replaces
   `random_password.runner_token`. The plan replaces the key and updates its
   vault entry `runner-token`, and changes nothing else.

2. Give the proxy the new key now. The chart copies the vault into the cluster
   every 15 minutes and restarts the proxy when the key changed; this does it
   at once:

   ```bash
   JOB="autoheal-secrets-sync-$(date +%s)"
   kubectl create job -n "$K8S_NAMESPACE" --from=cronjob/autoheal-secrets-sync "$JOB"
   kubectl wait -n "$K8S_NAMESPACE" --for=condition=complete "job/$JOB" --timeout=5m
   kubectl rollout status -n "$K8S_NAMESPACE" deployment/autoheal-proxy --timeout=5m
   ```

3. Give the runner the new key. With Terragrunt, the runner folder reads it
   from the infra folder:

   ```bash
   cd "$WORK_DIR/acme-autoheal/prod/runner"
   terragrunt apply
   ```

   With Terraform Enterprise, set `temporal_token` in `autoheal-runner-prod` to
   the new value of the vault entry (the command in step 14d, item 2), then
   start a run. The plan updates the VM scale set in place, and the apply
   restarts each VM with the new key.

Then check that the runner polls, as in step 14e.

## Resume in a new shell

The steps keep their results in shell variables. In a new shell, run your
filled-in blocks of step 1 again, then this block. It reads the other values
back from Azure, so it is safe to run at any time after the step that makes
each value:

```bash
az account set --subscription "$CLUSTER_SUB"
export AKS_ID=$(az aks show -g "$AKS_RG" -n "$AKS_NAME" --query id -o tsv)
export AKS_SUBNET_ID=$(az aks show -g "$AKS_RG" -n "$AKS_NAME" --query "agentPoolProfiles[0].vnetSubnetId" -o tsv)
export NODE_RG=$(az aks show -g "$AKS_RG" -n "$AKS_NAME" --query nodeResourceGroup -o tsv)
export PROXY_IP=$(az network public-ip show -g "$NODE_RG" -n pip-autoheal-proxy --query ipAddress -o tsv)
export EGRESS_IPS=$(az aks show -g "$AKS_RG" -n "$AKS_NAME" \
  --query "networkProfile.loadBalancerProfile.effectiveOutboundIPs[].id" -o tsv |
  xargs -n1 az network public-ip show --query ipAddress -o tsv --ids |
  sed 's|$|/32|' | paste -sd' ' -)
export NSG_ID=$(az network vnet subnet show --ids "$AKS_SUBNET_ID" --query networkSecurityGroup.id -o tsv)
[ -z "$NSG_ID" ] || export NSG_RG=$(echo "$NSG_ID" | cut -d/ -f5) NSG_NAME=$(echo "$NSG_ID" | cut -d/ -f9)
export RUNNER_HOST="runner.$AUTOHEAL_HOSTNAME"   # step 14
check_values AKS_ID AKS_SUBNET_ID NODE_RG PROXY_IP EGRESS_IPS
```

For another `outboundType`, set `EGRESS_IPS` as in
[Other outbound types](#other-outbound-types). Then the values of steps 8a and
9a, for your option.

#### Resume: Terragrunt

```bash
export DEPLOYER_IPS="$(curl -s https://api.ipify.org)/32"
export STORAGE_ACCOUNT=$(cd "$WORK_DIR/acme-autoheal/prod/infra" && terragrunt output -json autoheal_values 2>/dev/null |
  jq -r '.global.infra.objectStore.account // empty')
echo "STORAGE_ACCOUNT=${STORAGE_ACCOUNT:-none yet: step 9a makes it}"
```

#### Resume: Terraform Enterprise

```bash
export DEPLOYER_IPS="<address of the workers>/32 $(curl -s https://api.ipify.org)/32"   # as in step 8a
export STORAGE_ACCOUNT=$(grep -A3 'objectStore:' "$WORK_DIR/values-infra.yaml" 2>/dev/null | sed -n 's/.*account: *//p')
echo "STORAGE_ACCOUNT=${STORAGE_ACCOUNT:-none yet: step 9a makes it}"
```

The secrets of step 8d are not kept anywhere on your machine: set them again
before you apply step 9a.

## Troubleshooting

| Symptom                                                                               | Cause                                                                                                   | Fix                                                                                                                    |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Step 4b shows `Error from server (Forbidden)`                                         | You have no Kubernetes rights in the cluster                                                            | See [You cannot make the namespace](#you-cannot-make-the-namespace)                                                    |
| Step 4a or step 11b times out with `dial tcp <address>:443: i/o timeout`              | Your machine cannot reach the API server                                                                | See [Your machine cannot reach the API server](#your-machine-cannot-reach-the-api-server)                              |
| Step 8d shows `Set TF_VAR_tls_certificate`                                            | `jq` did not find the certificate files                                                                 | Check `TLS_CERT_FILE` and `TLS_KEY_FILE` in step 1b. See [Get a TLS certificate](#get-a-tls-certificate)               |
| Step 9a fails with `registering resource provider ... connection may have been reset` | A network break while Terraform registered the resource providers                                       | Run the command again                                                                                                  |
| Step 9a stops on "workload_egress_ip_ranges"                                          | An input from step 8b is missing or private                                                             | Set it as the message says                                                                                             |
| Step 9a fails with 403 on Key Vault entries                                           | `deployer_ip_ranges` is not the address of the apply host                                               | Find the address again (step 8a) and update the input                                                                  |
| Step 9c fails with `AuthorizationFailed` or a service endpoint error                  | No `Microsoft.Storage` service endpoint on the subnet, or no right on the subnet or the storage account | Do step 4d, and check the two rights in step 9c                                                                        |
| Step 10 fails to read the cluster                                                     | The Cluster User Role is not in effect yet, or was given to another identity                            | Wait 10 minutes and apply again. With Terraform Enterprise: check that `DEPLOYER_ID` is the workspace identity         |
| Step 10 stops on "has no OIDC issuer"                                                 | The OIDC issuer or workload identity is off                                                             | Do step 3, then apply step 10 again                                                                                    |
| With Terraform Enterprise: the run fails to sign in to Azure                          | The OIDC links of step 1c or the environment variables of step 7b                                       | Check Step 4 of Part A and Step 8 of Part B in [terraform-enterprise.md](terraform-enterprise.md), for both workspaces |
| Step 11b fails with Forbidden                                                         | The namespace role is missing or not in effect yet, or the namespace is not `$K8S_NAMESPACE`            | Check step 6b and step 8c, wait, then try again                                                                        |
| The secrets-sync job fails to sign in to Key Vault                                    | `service_accounts.namespace` is not `$K8S_NAMESPACE`, or step 10 was not applied                        | Fix it in step 8b, then apply step 9a and step 10 again                                                                |
| The proxy pod waits for the Secret `autoheal-tls`                                     | `tls_certificate` was not set in step 8d                                                                | Set it and apply step 9a again                                                                                         |
| Step 12e shows `Forbidden` from Key Vault                                             | The vault firewall does not let in this machine, or you have no read access                             | Run it on the machine of step 8a. With Terraform Enterprise, wait a few minutes for the role grant                     |
| Pods wait for secrets, or show 403 from Key Vault                                     | The cluster's outbound addresses changed or are wrong                                                   | Update `workload_egress_ip_ranges` and apply step 9a again                                                             |
| Pods cannot reach Postgres                                                            | The same                                                                                                | The same                                                                                                               |
| Pods show 403 from the storage account                                                | The storage account has no network rule for the AKS subnet                                              | Do step 9c                                                                                                             |
| `autoheal-edge` stays `<pending>`                                                     | The proxy IP is not in the node resource group, or is not Standard and static                           | Do step 5a again                                                                                                       |
| Users or webhooks time out on `https://$AUTOHEAL_HOSTNAME`                            | The subnet NSG blocks TCP 443, or a DNS record points elsewhere                                         | Do step 5b, and check step 9b                                                                                          |
| An agent run fails with `this deployment offers no models`                            | `global.llm.offeredModels` is not set                                                                   | Add `offeredModels: $LLM_MODEL` under `llm` in `$VALUES_FILE` (step 11a), then do step 11b again                       |
| Step 9a stops on "edge_exposure" or "proxy_ip"                                        | `PROXY_IP` is a private address, or the DNS zone is private                                             | Do step 5a again, or see step 9b                                                                                       |
| Step 14c shows `404`                                                                  | The chart runs without the runner host                                                                  | Check `runner:` under `edge` in `$VALUES_FILE`, then do step 11b again                                                 |
| Step 14c times out                                                                    | The DNS record of step 14a points elsewhere, or the NSG of step 5b blocks this machine                  | Check step 14a and step 5b                                                                                             |
| Step 14e shows 0, and the runner log shows `Unauthenticated`                          | The runner sends no key, or a different key from the proxy                                              | Apply the runner folder again. With Terraform Enterprise, set `temporal_token` again from the vault                    |
| Step 14e shows 0, and the runner log shows a certificate error                        | The runner does not trust the certificate                                                               | With a private CA, do the CA part of step 14d. Check step 14b                                                          |
| Step 14e shows 0, and the runner log shows a timeout                                  | The runner cannot reach `$RUNNER_HOST` on TCP 443                                                       | Check step 14a, and let the `egress_ip` output in at the NSG of step 5b                                                |
| An agent run waits for a sandbox, then fails after about 11 minutes                   | Sandboxes are on, and no runner polls                                                                   | Do step 14e. Turn sandboxes off until it shows polls                                                                   |

## Upgrade

The cluster owner does not have to give new permissions. For an install from
autoheal-byoc-infra 3.x, follow [Upgrade from 3.x](#upgrade-from-3x) instead.

### Upgrade with Terragrunt

Set the two new numbers in `versions.hcl`, then apply step 9a, step 10 and
step 11b again. The three `source` lines follow `infra_version`:

```bash
export NEW_INFRA_VERSION="<new autoheal-byoc-infra version, for example 4.1.0>"
export NEW_CHART_VERSION="<new chart version>"
cd "$WORK_DIR/acme-autoheal/prod"
perl -pi -e 's/^(\s*infra_version\s*=\s*)"[^"]*"/$1"$ENV{NEW_INFRA_VERSION}"/;
             s/^(\s*chart_version\s*=\s*)"[^"]*"/$1"$ENV{NEW_CHART_VERSION}"/' versions.hcl
grep -n 'version' versions.hcl
```

### Upgrade with Terraform Enterprise

Move the branch of both workspaces to the new release. Apply step 9a, then run
the cluster workspace as in step 10. Save the new `values-infra.yaml`, then run
the `helm upgrade` of step 11b with the new `--version`.

### Upgrade from 3.x

In 3.x, the infra made runner VMs in the data subscription, and the cluster
owner opened a Temporal IP for them. 4.x has no runner: after the upgrade,
nothing runs sandboxes until a runner runs elsewhere. The 4.x infra also does
not read the cluster; step 10 makes the federated credentials.

Do these steps in order. The storage network rule of 3.x stays, so step 9c is
not needed.

1. **The new chart on the 3.x infra.** With Terragrunt: set only
   `chart_version` in `versions.hcl` to the new chart version, and apply step
   11b. With Terraform Enterprise: run the `helm upgrade` of step 11b with the
   new `--version` and the 3.x `values-infra.yaml`. The chart prints a warning
   while the infra values still hold runner settings; the 4.x values of item 2
   do not.

2. **The 4.x infra.** Remove the inputs that 4.x does not have:
   `autoheal_version`, `temporal_ip` in `existing_network`, and
   `network_cidr`. With Terragrunt, this sets the new `infra_version` and
   removes them:

   ```bash
   export NEW_INFRA_VERSION="<new autoheal-byoc-infra version>"
   cd "$WORK_DIR/acme-autoheal/prod"
   perl -pi -e 's/^(\s*infra_version\s*=\s*)"[^"]*"/$1"$ENV{NEW_INFRA_VERSION}"/' versions.hcl
   perl -ni -e 'print unless /^\s*(autoheal_version|temporal_ip|network_cidr)\s*=/' infra/terragrunt.hcl
   grep -n 'version' versions.hcl
   cat infra/terragrunt.hcl
   ```

   With Terraform Enterprise, move the infra workspace branch to the new
   release, and change the same variables in **Variables**.

   Then apply step 9a. The plan destroys the runner VMs, their VNet and NAT
   gateway, their SSH key and role grants, and the federated credentials of
   the three identities. Pods that sign in between this apply and item 3
   fail. To keep the credentials instead, see "Upgrading from 3.x" in
   `compositions/azure-cluster/README.md`: it moves them from the infra state
   to the cluster state.

3. **The cluster step.** With Terragrunt, copy the `cluster` folder and the new
   `app/terragrunt.hcl` of the release into your deployment repository, then
   set the namespace of the app folder again (step 8c, item 2):

   ```bash
   git -C "$WORK_DIR/autoheal-byoc-infra" fetch --tags
   git -C "$WORK_DIR/autoheal-byoc-infra" checkout "v$NEW_INFRA_VERSION"
   mkdir -p "$WORK_DIR/acme-autoheal/prod/cluster"
   cp "$WORK_DIR/autoheal-byoc-infra/examples/azure/split-public/cluster/terragrunt.hcl" "$WORK_DIR/acme-autoheal/prod/cluster/"
   cp "$WORK_DIR/autoheal-byoc-infra/examples/azure/split-public/app/terragrunt.hcl" "$WORK_DIR/acme-autoheal/prod/app/"
   ```

   With Terraform Enterprise, make the cluster workspace: its OIDC links in
   step 1c, and the workspace in step 7b, item 3.

   Then do step 10.

4. **The app.** With Terragrunt, apply step 11b again. It removes the two
   public load balancers that 3.x made for the runner. With Terraform
   Enterprise, save the new `values-infra.yaml`, run the `helm upgrade` of
   step 11b, and delete the objects that 3.x had you make for the runner:

   ```bash
   kubectl delete -n "$K8S_NAMESPACE" service/temporal-frontend-public service/api-server-go-public \
     networkpolicy/temporal-frontend-public networkpolicy/api-server-go-public
   ```

To run sandboxes again, add the runner of step 14: it needs no Temporal IP and
no NSG rules for Temporal.

Then the cluster owner can remove what only the 3.x runner used: the Temporal IP,
the two NSG rules for it, and the deployer's roles on the AKS subnet. With one
public IP in 3.x, the proxy still uses `pip-autoheal-temporal`: keep it, and in
a new shell read `PROXY_IP` from it instead of `pip-autoheal-proxy`.

```bash
az account set --subscription "$CLUSTER_SUB"
az network public-ip delete -g "$NODE_RG" -n pip-autoheal-temporal   # only with two public IPs in 3.x
if [ -n "$NSG_ID" ]; then
  az network nsg rule delete -g "$NSG_RG" --nsg-name "$NSG_NAME" -n allow-autoheal-runner
  az network nsg rule delete -g "$NSG_RG" --nsg-name "$NSG_NAME" -n deny-others-to-autoheal-temporal
fi
for grant in "Reader|$AKS_SUBNET_ID" "Network Contributor|$AKS_SUBNET_ID"; do
  az role assignment delete --assignee "$DEPLOYER_ID" --role "${grant%%|*}" --scope "${grant#*|}"
done
```

## Remove

### Remove with Terragrunt

```bash
[ ! -d "$WORK_DIR/acme-autoheal/prod/runner" ] || (cd "$WORK_DIR/acme-autoheal/prod/runner" && terragrunt destroy)
cd "$WORK_DIR/acme-autoheal/prod/app" && terragrunt destroy
cd "$WORK_DIR/acme-autoheal/prod/cluster" && terragrunt destroy
cd "$WORK_DIR/acme-autoheal/prod/infra" && terragrunt destroy
```

### Remove with Terraform Enterprise

```bash
helm uninstall autoheal -n "$K8S_NAMESPACE"
```

Then queue a destroy run in the runner workspace of step 14, when you made it,
then in the cluster workspace, then in the infra workspace: **Settings**,
**Destruction and Deletion**, **Queue destroy plan**.

### Remove the cluster owner's changes

As the cluster owner, remove the static IP, the NSG rule and the deployer's
roles:

```bash
az account set --subscription "$CLUSTER_SUB"
az network public-ip delete -g "$NODE_RG" -n pip-autoheal-proxy
if [ -n "$NSG_ID" ]; then
  az network nsg rule delete -g "$NSG_RG" --nsg-name "$NSG_NAME" -n allow-autoheal-proxy
fi
for grant in \
  "Azure Kubernetes Service Cluster User Role|$AKS_ID" \
  "Azure Kubernetes Service RBAC Admin|$AKS_ID/namespaces/$K8S_NAMESPACE"; do
  az role assignment delete --assignee "$DEPLOYER_ID" --role "${grant%%|*}" --scope "${grant#*|}"
done
```

The storage network rule of step 9c goes with the storage account. Remove the
DNS records of step 9b and step 14a too.

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
manages. This runbook changes the AKS subnet (step 4d) and its NSG (step 5b),
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
AKS subnet instead of the public IP of step 5a. Webhooks from outside your
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

Then skip step 5b, and in step 8b, write `edge_exposure = "internal"`. Your
users reach `$PROXY_IP` on TCP 443 over your network. In step 9b, a DNS provider that proxies traffic must not proxy these
records, because the address is private.

The runner of step 14 then needs a private path to `$PROXY_IP`. In the runner
folder, set `existing_subnet_id` to a subnet that reaches the AKS subnet, as in
`examples/azure/split/runner`, instead of the VNet and NAT gateway it makes.
The DNS record of step 14a points to the private address too.

### A shared Istio gateway

Some clusters take all outside traffic through one Istio ingress gateway that
another team owns. The chart can sit behind it, with `edge.mode: istio` and
`edge.istio.gateway: <namespace>/<name>` in `$VALUES_FILE`, instead of the load
balancer on `$PROXY_IP`. The gateway ends TLS, so its certificate is the one the
users and the runner see.

For the runner of step 14, the gateway owner does four things before step 14c:

- Adds `$RUNNER_HOST` to the `hosts` of the HTTPS server of the Gateway, and
  makes sure the gateway certificate covers it. A wildcard for
  `*.$AUTOHEAL_HOSTNAME` covers it.
- Makes sure the gateway offers TLS 1.3 on `$RUNNER_HOST` and passes the
  runner's gRPC through as HTTP/2. The runner refuses older TLS versions, and
  gRPC does not work over HTTP/1.1. A WAF or load balancer in front of the
  gateway that ends TLS must do the same. When it cannot, point the runner at
  an address of the gateway that skips it, such as a private one.
- Points the DNS record of step 14a at the address of the gateway instead of
  `$PROXY_IP`.
- Lets the runner's outbound address in on TCP 443, after step 14d shows it
  (the `egress_ip` output), when the gateway takes only some sources.

The chart then adds a VirtualService `autoheal-runner` for `$RUNNER_HOST` on
that Gateway, and the steps from 14c on are the same. When a private CA signed
the gateway certificate, give that CA to the runner in step 14d: write it to
`edge-ca.pem` in the runner folder, or set `temporal_ca_certificate` with
Terraform Enterprise.

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
`$AUTOHEAL_HOSTNAME`, `auth.$AUTOHEAL_HOSTNAME` and `auth-app.$AUTOHEAL_HOSTNAME`,
and for `runner.$AUTOHEAL_HOSTNAME` with the runner of step 14.
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
printf 'subjectAltName=DNS:%s,DNS:auth.%s,DNS:auth-app.%s,DNS:runner.%s\nextendedKeyUsage=serverAuth\n' \
  "$AUTOHEAL_HOSTNAME" "$AUTOHEAL_HOSTNAME" "$AUTOHEAL_HOSTNAME" "$AUTOHEAL_HOSTNAME" > san.ext
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 365 -sha256 \
  -extfile san.ext -out server.pem
cat server.pem ca.pem > fullchain.pem
export TLS_CERT_FILE="$WORK_DIR/certs/fullchain.pem" TLS_KEY_FILE="$WORK_DIR/certs/privkey.pem"
export TF_VAR_edge_ca_certificate="$(cat ca.pem)"
```

With Terraform Enterprise, add `edge_ca_certificate` as a Terraform variable
with the text of `ca.pem`. The runner of step 14 needs the same CA.

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
- [Workload identity on AKS](https://learn.microsoft.com/azure/aks/workload-identity-deploy-cluster): the OIDC issuer and workload identity of step 3, and the federated credentials of step 10
- [Key Vault provider for the Secrets Store CSI Driver](https://learn.microsoft.com/azure/aks/csi-secrets-store-driver): the add-on of step 3
- [Static public IP for an AKS load balancer](https://learn.microsoft.com/azure/aks/static-ip): the public IP of step 5a
- [Standard load balancer in AKS](https://learn.microsoft.com/azure/aks/load-balancer-standard): the load balancer that AKS makes for the proxy
- [Network security groups](https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview): the rule of step 5b
- [Storage network security limitations](https://learn.microsoft.com/azure/storage/common/storage-network-security-limitations): why storage uses the subnet rule of step 9c, not IP rules
- [Dynamic credentials with the Azure provider](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/azure-configuration): how Terraform Enterprise signs in to Azure with OIDC
