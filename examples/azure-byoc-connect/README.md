# examples/azure-byoc-connect

A copyable starting config that points at `compositions/azure-byoc-connect` via
Terragrunt — the **connect-mode** install where the customer already built the
infrastructure and Autoheal connects the app to it.

**New to this? Read [docs/getting-started.md](../../docs/getting-started.md) first** for the
tools, permissions, and remote-state setup. The short version:

```bash
cp -r examples/azure-byoc-connect examples/azure-byoc-connect-mine
cd examples/azure-byoc-connect-mine
# edit terragrunt.hcl: subscription_id, location, resource_group_name, and the
# existing resource names (aks/postgres/keyvault/redis/acr/storage), plus remote_state
terragrunt init
terragrunt plan      # review; only the app identity (+ optional secrets) is created
terragrunt apply
terragrunt output -json > autoheal-infra-outputs.json
```

For a greenfield install where Autoheal provisions everything, use
[examples/azure-byoc](../azure-byoc) instead. See
[docs/getting-started.md](../../docs/getting-started.md).
