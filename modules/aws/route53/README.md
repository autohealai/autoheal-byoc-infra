# Autoheal BYOC - Route 53 records

DNS records for the Autoheal hostnames in a Route 53 hosted zone the customer
already has, public or private. The module never creates the zone. Each record
is an A record with addresses, an A alias for a load balancer, or a CNAME, keyed
by a stable key so alias targets created in the same apply can be passed in.
Record names are relative to the zone (empty for the apex) or fully qualified.
The Azure analogue is `modules/azure/dns`. Naming follows the repo's null-label
convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)); Route 53 records
take no tags.

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_this"></a> [this](#module\_this) | ../../_shared/label | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_route53_record.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_records"></a> [records](#input\_records) | Records keyed by a stable key. name is relative to the zone (auth for auth.<zone>, empty for the apex) or fully qualified. type is A or CNAME. An A record has either records (IPv4 addresses) or alias (a load balancer DNS name and its hosted zone ID); a CNAME has exactly one record. ttl is ignored for aliases. | <pre>map(object({<br/>    name    = string<br/>    type    = string<br/>    ttl     = optional(number, 300)<br/>    records = optional(list(string), [])<br/>    alias = optional(object({<br/>      name                   = string<br/>      zone_id                = string<br/>      evaluate_target_health = optional(bool, true)<br/>    }))<br/>  }))</pre> | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | ID of the existing public or private Route 53 hosted zone, e.g. Z0123456789ABCDEFGHIJ. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_fqdns"></a> [fqdns](#output\_fqdns) | Fully qualified names of the records (no trailing dot), keyed like var.records. |
<!-- END_TF_DOCS -->
