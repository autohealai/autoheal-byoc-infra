# Installing the Autoheal app on the infra you just provisioned

This picks up exactly where [CONSUMING.md](./CONSUMING.md) ends. At that point you
have run:

```bash
terragrunt apply
terragrunt output -json > autoheal-infra-outputs.json
```

`autoheal-infra-outputs.json` is the complete contract between the infrastructure
(hop 1, this repo) and the application install (hop 2, the Autoheal Helm chart).
Nothing else needs to be copied by hand — every value the install consumes is in
that file.

This document covers the Azure / AKS path produced by `compositions/azure-byoc`.
The AWS field names are identical (that is the point of the shared contract), so an
EKS reader can follow the same mapping; only the secret backend differs.

---

## 1. What the outputs mean, field by field

Pretty-print the file to see what you have:

```bash
jq . autoheal-infra-outputs.json
```

Every value below is nested under `.<name>.value` in the raw JSON (Terraform output
format). The table maps each field to where it goes in the install.

| Output field | Example value | Where it goes in the install |
|---|---|---|
| `cluster_name` | `avid-play-autoheal` | `az aks get-credentials` target — the cluster you point `kubectl`/`helm` at. |
| `resource_group_name` | `rg-avid-play-autoheal` | `-g` for `az aks get-credentials` and any `az` lookups below. |
| `registry` | `avidplayautoheal.azurecr.io` | Chart image registry: `*.image.registry` (prefix the `/release` repo path). Mirror the release images here first. |
| `acr_id` | `.../registries/avidplayautoheal` | Grant the AKS kubelet identity (and the runner VMSS) `AcrPull` on this id, so pods can pull. |
| `postgres_host` | `avid-play-autoheal-db.postgres.database.azure.com` | `byoc.data.postgres.host` in the chart values. |
| `object_store` | `avidplayautoheal/attachments` | Split on `/`: account → Blob workload-identity target; container → `byoc.storage.bucket` (and the per-service `ATTACHMENTS_BUCKET` / `PROMPTS_CONFIG__BASE_BUCKET`). |
| `runner_identity` | `<app WI client id>` | `byoc.platform.appServiceAccountAnnotations."azure.workload.identity/client-id"` — binds the app ServiceAccounts to the app workload identity (Blob access). |
| `secret_store_uri` | `https://avid-play-autoheal.vault.azure.net/` | Key Vault URL for the ESO `ClusterSecretStore` (`provider.azurekv.vaultUrl`). See §3. |
| `eso_identity_client_id` | `f94d409d-…` | Annotate the **ESO controller** ServiceAccount with `azure.workload.identity/client-id`. See §3. |
| `eso_tenant_id` | `b4dab56c-…` | `provider.azurekv.tenantId` on the `ClusterSecretStore`. |
| `eso_service_account` | `external-secrets/external-secrets` | `provider.azurekv.serviceAccountRef` (namespace/name) on the `ClusterSecretStore`. |
| `oidc_issuer_url` | `https://centralus.oic.prod-aks.azure.com/…/…/` | AKS OIDC issuer — already federated to both identities by this repo; needed only if you add further workload-identity federations by hand. |
| `runner_subnet_id` | `.../subnets/snet-runner` | Fed to the **separate** runner-VMSS apply (not part of the app install). |
| `kube_host` (sensitive) | `https://…azmk8s.io:443` | K8s API host. Normally you let `az aks get-credentials` write this into your kubeconfig rather than reading it. |

> **Not in the file, by design:** there is no `redis_endpoint` on Azure. The
> `azure-byoc` composition runs Redis in-cluster (a StatefulSet shipped by the app
> Helm chart) at a fixed in-cluster DNS name, so the app does not learn it from
> infra. If you brought your own managed Redis you used `azure-byoc-connect`, which
> *does* emit `redis_endpoint`; wire it into `byoc.data.redis.host/port`.

---

## 2. Point kubectl at the cluster

```bash
az aks get-credentials \
  --resource-group "$(jq -r .resource_group_name.value autoheal-infra-outputs.json)" \
  --name          "$(jq -r .cluster_name.value        autoheal-infra-outputs.json)"

kubectl get nodes          # expect your node count Ready
```

Grant the cluster pull rights on the registry (idempotent):

```bash
az role assignment create \
  --assignee-object-id "$(az aks show -g <rg> -n <cluster> --query identityProfile.kubeletidentity.objectId -o tsv)" \
  --assignee-principal-type ServicePrincipal \
  --role AcrPull \
  --scope "$(jq -r .acr_id.value autoheal-infra-outputs.json)"
```

Mirror the release images and chart into the ACR named by `registry` before the
`helm upgrade` below (same tags as the AWS release; see the app repo's release
notes for the image set).

---

## 3. Secrets: ESO + Key Vault (the Azure path)

### 3.1 How it is meant to work

This repo already provisioned the **cloud half** of the ESO wiring:

- A dedicated, least-privilege user-assigned managed identity for ESO
  (`eso_identity_client_id`), federated to the ESO controller ServiceAccount
  `external-secrets/external-secrets`, and granted **Key Vault Secrets User** on the
  Key Vault at `secret_store_uri`.
- The Key Vault itself, seeded by the apply with the Postgres admin material:
  `postgres-host`, `postgres-user`, `postgres-password`.

The **in-cluster half** (ESO operator, `ClusterSecretStore`, `ExternalSecret`
objects) belongs to the app/install layer — this repo is pure cloud infra and
installs no Helm/Kubernetes resources. Wire it as follows.

**a. Install the ESO operator** (once per cluster):

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
```

**b. Annotate the ESO controller ServiceAccount** with the ESO identity so its pods
get an Entra token via AKS workload identity, and label it for the webhook:

```yaml
# external-secrets/external-secrets ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: <eso_identity_client_id>
  labels:
    azure.workload.identity/use: "true"
```

(Set this through the ESO chart's `serviceAccount.annotations`, or patch it, then
restart the controller so the pod picks up the projected token.)

**c. Create the `ClusterSecretStore` pointing at Key Vault:**

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: azure-key-vault
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity
      vaultUrl: <secret_store_uri>            # https://avid-play-autoheal.vault.azure.net/
      tenantId: <eso_tenant_id>
      serviceAccountRef:
        name: external-secrets                # from eso_service_account (namespace/name)
        namespace: external-secrets
```

**d. `ExternalSecret`s materialize the in-cluster Secrets** the app's DB-migration
hooks expect (`api-server-db-credentials`, `agents-py-http-db-credentials`,
`agents-py-worker-db-credentials`), reading the `postgres-*` keys from Key Vault via
`secretStoreRef: { name: azure-key-vault, kind: ClusterSecretStore }`. Model these
on the existing AWS `ExternalSecret`s in the chart's `templates/platform.yaml`,
swapping `dataFrom.extract` for per-key `data[].remoteRef.key` (`postgres-host`,
`postgres-user`, `postgres-password`).

**e. Flip the chart's secret source to the Key Vault path:**

```yaml
byoc:
  platform:
    secretSource: azurekeyvault
```

### 3.2 Honest status — the chart gap (hop-2 work)

> The app chart at `infra/helm-charts/autoheal-byoc/` does **not** yet recognize
> `secretSource: azurekeyvault`. As of today its `templates/platform.yaml` creates a
> `ClusterSecretStore` + `ExternalSecret`s only under
> `{{- if eq $p.secretSource "awssecretsmanager" }}`, and its Azure override
> (`values-aks.yaml`) ships `secretSource: vault` — i.e. the current AKS path uses
> **in-cluster Vault**, with the installer seeding the target Secrets before
> `helm upgrade`. There is no `azurekv` branch in the template yet.
>
> So steps (c)–(e) above describe the *target* Path A. Landing it is the hop-2
> implementation task:
> 1. Add an `{{- if eq $p.secretSource "azurekeyvault" }}` branch to
>    `templates/platform.yaml` that emits the `azurekv` `ClusterSecretStore` and the
>    three DB-credential `ExternalSecret`s (keyed on `postgres-host/-user/-password`).
> 2. Change `values-aks.yaml` `secretSource: vault` → `azurekeyvault` and drop the
>    installer's Vault-seeding step.
> 3. Thread `secret_store_uri`, `eso_tenant_id`, and `eso_service_account` into the
>    chart values (e.g. `byoc.azure.keyVault.*`), and the ESO-SA annotation of
>    `eso_identity_client_id`.
>
> Until that lands, you have two working options: **(Path A, recommended)** do steps
> (a)–(d) by hand and run the app with the Secrets ESO materialized; or **(Path B,
> fastest today)** keep `secretSource: vault` and let the installer seed the Secrets
> from in-cluster Vault — functional, but it leaves the provisioned ESO identity and
> Key Vault unused and diverges from the EKS path. Path A is the one worth finishing.

---

## 4. Install the app

With kubeconfig set (§2), images mirrored, and secrets wired (§3), install the
umbrella chart, layering the Azure overrides on the neutral base:

```bash
helm upgrade --install autoheal oci://<registry>/autoheal-byoc \
  --namespace autoheal --create-namespace \
  -f values-aks.yaml \
  --set byoc.namespace=autoheal \
  --set byoc.data.postgres.host="$(jq -r .postgres_host.value autoheal-infra-outputs.json)" \
  --set byoc.storage.bucket="$(jq -r '.object_store.value | split("/")[1]' autoheal-infra-outputs.json)" \
  --set 'byoc.platform.appServiceAccountAnnotations.azure\.workload\.identity/client-id'="$(jq -r .runner_identity.value autoheal-infra-outputs.json)"
```

(Image registries, hostnames, and model-provider wiring come from `values-aks.yaml`;
adjust that file for your domain and ACR rather than passing dozens of `--set`
flags.)

The chart's platform hooks (negative-weight pre-install) create the app
ServiceAccounts and, on the ESO path, the `ClusterSecretStore`/`ExternalSecret`s
before the DB-migration hooks fire. ESO materializes the target Secrets within
seconds; migration pods retry until they appear.

Verify:

```bash
kubectl -n autoheal get pods
kubectl -n external-secrets get clustersecretstore,externalsecret -A
kubectl -n autoheal get secret api-server-db-credentials   # should exist once ESO syncs
```

---

## 5. After the app is up

- **Runner VMSS** is a separate `terragrunt apply` (it needs `temporal_host` from the
  running app); feed it `runner_subnet_id` and grant its identity `AcrPull` on
  `acr_id`.
- **Edge / TLS**: the AKS path fronts Envoy with an internal LoadBalancer and a
  brought-in TLS cert (`autoheal-edge-tls`); create that Secret and point DNS at the
  LB address.

---

## Quick reference: field → destination

```
cluster_name          -> az aks get-credentials --name
resource_group_name   -> az aks get-credentials -g ; az lookups
registry              -> chart *.image.registry  (mirror images here)
acr_id                -> AcrPull role assignment (kubelet + runner)
postgres_host         -> byoc.data.postgres.host
object_store          -> <acct>/<container> ; container -> byoc.storage.bucket
runner_identity       -> app SA azure.workload.identity/client-id
secret_store_uri      -> ClusterSecretStore provider.azurekv.vaultUrl
eso_identity_client_id-> ESO controller SA azure.workload.identity/client-id
eso_tenant_id         -> ClusterSecretStore provider.azurekv.tenantId
eso_service_account   -> ClusterSecretStore provider.azurekv.serviceAccountRef
oidc_issuer_url       -> (already federated; manual extra federations only)
runner_subnet_id      -> separate runner-vmss apply
kube_host             -> K8s API host (prefer get-credentials)
(no redis_endpoint)   -> Redis in-cluster; azure-byoc-connect emits it if BYO
```
