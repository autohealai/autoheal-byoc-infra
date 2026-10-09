# Autoheal BYOC — Azure Container Registry

Container registry for BYOC images in a BYOC-on-AKS Autoheal install. Pulls are
keyless via managed identity (AcrPull granted to the AKS kubelet identity and the
runner identity), so admin access stays disabled and no static registry
credentials exist.

The AWS analogue is `modules/aws/ecr`. Registry names reject dashes and allow 5-50
alphanumeric chars, so the module derives a sanitized name from the label id
(override available). Naming and tags follow the repo's null-label convention (see
`label.tf` and [docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `resource_group_name` | RG the registry lands in | — |
| `location` | Azure region | — |
| `sku` | `Basic` / `Standard` / `Premium` (PE + geo-rep need Premium) | `Standard` |
| `name_override` | force an exact registry name (else sanitized from label id) | `""` |
| `georeplication_locations` | extra regions (Premium only) | `[]` |

### Key outputs

| Name | Description |
|------|-------------|
| `login_server` | login server — maps to the contract `registry` |
| `acr_id` | registry resource id (grant AcrPull on this) |
| `acr_name` | registry name (for `az acr login -n`) |
<!-- END_TF_DOCS -->
