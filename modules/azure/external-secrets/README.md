# Autoheal BYOC — External Secrets Operator identity

Dedicated, least-scoped Entra identity for the External Secrets Operator (ESO) on
AKS. Creates a user-assigned identity, federates it to the ESO controller
ServiceAccount (default `external-secrets/external-secrets`) via the AKS OIDC
issuer, and grants it **Key Vault Secrets User** on exactly this install's Key
Vault — so ESO can read the vault and nothing else, with no stored credentials.

Scope is **cloud primitives only**. It does NOT install the ESO operator, create
the `ClusterSecretStore`, or declare `ExternalSecret`s — those are in-cluster
objects owned by the app/install layer (`install-aks.sh` / the Helm chart), which
consumes this module's `client_id`, `tenant_id`, and the Key Vault `vault_uri`.
This repo is pure cloud-infra (no helm/kubernetes providers) shipped as one
composition per apply, so installing the operator here would mean configuring a
provider from the cluster resource's own output — deliberately avoided.

The AWS analogue is the IAM-role + Pod-Identity half of `modules/byoc-eso-install`.
Naming and tags follow the repo's null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

## How the app layer consumes this

```yaml
# ServiceAccount (ESO controller) — stamped by the installer
metadata:
  annotations:
    azure.workload.identity/client-id: <module output client_id>
  labels:
    azure.workload.identity/use: "true"
---
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: azure-keyvault
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity
      vaultUrl: <keyvault module output vault_uri>
      tenantId: <module output tenant_id>
      serviceAccountRef:
        name: external-secrets        # == eso_service_account
        namespace: external-secrets   # == eso_namespace
```

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs populates the providers / inputs / outputs tables here.
     The module-specific inputs are in variables.tf; label inputs (namespace,
     environment, name, attributes, tags, ...) come from label.tf. -->

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `resource_group_name` | RG the identity lands in (created by the composition) | — |
| `location` | Azure region | — |
| `oidc_issuer_url` | AKS OIDC issuer (`aks` output `oidc_issuer_url`) | — |
| `key_vault_id` | Key Vault the ESO identity may read (`keyvault` output `key_vault_id`) | — |
| `eso_namespace` | Namespace the ESO controller runs in | `external-secrets` |
| `eso_service_account` | ESO controller ServiceAccount federated to this identity | `external-secrets` |

### Key outputs

| Name | Description |
|------|-------------|
| `client_id` | stamp on the ESO SA `azure.workload.identity/client-id` annotation |
| `tenant_id` | ClusterSecretStore `provider.azurekv.tenantId` |
| `service_account` | `namespace/name` of the federated ESO SA |
| `principal_id`, `identity_id` | identity object id / resource id |
<!-- END_TF_DOCS -->
