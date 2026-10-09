# examples/azure-byoc

A copyable starting config that points at `compositions/azure-byoc` via Terragrunt.

```bash
cp -r examples/azure-byoc examples/azure-byoc-mine
cd examples/azure-byoc-mine
# edit terragrunt.hcl: namespace, environment, location, subscription_id, remote_state
terragrunt init
terragrunt plan      # review; nothing created yet
terragrunt apply
terragrunt output -json > autoheal-infra-outputs.json
```

See [docs/CONSUMING.md](../../docs/CONSUMING.md) for the full flow and what the
outputs feed.
