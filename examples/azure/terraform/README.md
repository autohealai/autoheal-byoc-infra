# examples/azure/terraform

The same deployment as `../prod`, run with Terraform alone, without Terragrunt.
Use it when your pipeline runs plain Terraform, for example Azure DevOps.
Copy this folder into a repository you own, edit the values, and run it from
your pipeline.

```text
infra/                     cloud resources (compositions/azure)
  main.tf                  your inputs
  .terraform.lock.hcl      provider versions, the same as compositions/azure
  variables.tf             the chart version and the secrets, set by the pipeline
  outputs.tf               the composition's outputs, passed on
  versions.tf              Terraform version and an empty azurerm backend
app/                       the chart (compositions/app)
  main.tf                  reads the infra outputs from its state, installs the chart
  .terraform.lock.hcl      provider versions, the same as compositions/app
  values-customer.yaml     your chart settings
pipelines/
  azure-pipelines.yml      an Azure DevOps pipeline: plan and apply infra, then app
  terraform.yml            the steps for one folder
```

`docs/azure-devops.md` in autoheal-byoc-infra walks through the Azure DevOps
setup. `../README.md` lists the inputs, what you can bring and the secrets; they
are the same here.

## What replaces Terragrunt

| Terragrunt in `../prod` | Here |
|-------------------------|------|
| `root.hcl` writes `backend.tf` | `versions.tf` has an empty `backend "azurerm" {}`; the pipeline passes the names to `terraform init -backend-config=...` |
| `versions.hcl` holds the infra tag and the chart version | the tag is in the `source` line of `infra/main.tf` and `app/main.tf`; the chart version is a pipeline variable, `TF_VAR_autoheal_version` in both folders |
| `inputs = { ... }` | the inputs of the `module` block in `infra/main.tf` |
| `dependency "infra"` | `data "terraform_remote_state" "infra"` in `app/main.tf` |

The two folders keep separate state files, as with Terragrunt. The app folder
logs in to the cluster that the infra folder made, so the infra folder must be
applied first. Before that, the app folder cannot plan: there is no infra state
to read yet. Terragrunt plans it with placeholder outputs instead.

## Running it by hand

```bash
az login
export TF_VAR_autoheal_version=1.0.0-rc.8
export TF_VAR_llm_api_key=...   # and the other secrets you use

BACKEND="-backend-config=resource_group_name=rg-acme-tfstate
  -backend-config=storage_account_name=stacmetfstate
  -backend-config=container_name=tfstate
  -backend-config=use_azuread_auth=true"

cd infra
terraform init $BACKEND -backend-config=key=autoheal/prod/infra/terraform.tfstate
terraform apply

cd ../app
terraform init $BACKEND -backend-config=key=autoheal/prod/app/terraform.tfstate
terraform apply
```

Each folder has a `.terraform.lock.hcl`, a copy of the composition's lock file.
It pins the provider versions we test, so every run uses the same ones. Keep it
in your copy.

## Upgrading

Read the release notes in `CHANGELOG.md` of autoheal-byoc-infra first. Then
change the tag in the two `source` lines and the chart version in the pipeline,
run `terraform init -upgrade` on each folder, commit the lock files it updates,
and run both folders again.

## Moving from the Terragrunt example

Do not point this folder at the state of an install made with `../prod`.
Terragrunt runs the composition as the root module, so its state has addresses
such as `azurerm_key_vault.this`. Here the composition is a module, and the
same resource is `module.infra.azurerm_key_vault.this`. A plan against the old
state would create everything again. Pick one way per install. To run an
existing Terragrunt install with Terraform alone, run `compositions/azure`
itself as the root module with a `backend.tf`, as
`docs/terraform-enterprise.md` does.
