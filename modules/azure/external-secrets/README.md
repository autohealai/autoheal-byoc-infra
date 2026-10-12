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
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~> 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_this"></a> [this](#module\_this) | ../../_shared/label | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_federated_identity_credential.eso](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_role_assignment.kv_secrets_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.eso](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_eso_namespace"></a> [eso\_namespace](#input\_eso\_namespace) | Namespace the ESO controller runs in (the federated SA subject). | `string` | `"external-secrets"` | no |
| <a name="input_eso_service_account"></a> [eso\_service\_account](#input\_eso\_service\_account) | The ESO controller ServiceAccount federated to this identity. Must match the SA the operator install uses and the ClusterSecretStore serviceAccountRef. | `string` | `"external-secrets"` | no |
| <a name="input_key_vault_id"></a> [key\_vault\_id](#input\_key\_vault\_id) | Key Vault the ESO controller may read (Key Vault Secrets User). The app/install layer points the ClusterSecretStore at this vault's URI. | `string` | n/a | yes |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'avid'. | `string` | `null` | no |
| <a name="input_oidc_issuer_url"></a> [oidc\_issuer\_url](#input\_oidc\_issuer\_url) | AKS OIDC issuer URL the federated credential trusts (modules/azure/aks output oidc\_issuer\_url). | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the identity lands in (created by the composition). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_client_id"></a> [client\_id](#output\_client\_id) | Client id of the ESO identity. The app/install layer stamps this on the ESO controller ServiceAccount (azure.workload.identity/client-id annotation). |
| <a name="output_identity_id"></a> [identity\_id](#output\_identity\_id) | Resource ID of the ESO user-assigned identity. |
| <a name="output_principal_id"></a> [principal\_id](#output\_principal\_id) | Principal (object) id of the ESO identity, for additional role assignments if needed. |
| <a name="output_service_account"></a> [service\_account](#output\_service\_account) | namespace/name of the federated ESO ServiceAccount, so the app layer wires the ClusterSecretStore serviceAccountRef consistently. |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Entra tenant id of the ESO identity. Feeds the ClusterSecretStore provider.azurekv.tenantId. |
<!-- END_TF_DOCS -->
