# examples/azure-byoc

A copyable starting config that points at `compositions/azure-byoc` via Terragrunt.

**First time? Follow the full step-by-step tutorial in
[docs/getting-started.md](../../docs/getting-started.md)** — it covers the tools, permissions,
and the one-time state bootstrap this short version assumes. The short version:

```bash
cp -r examples/azure-byoc examples/azure-byoc-mine
cd examples/azure-byoc-mine
# edit terragrunt.hcl: namespace, environment, location, subscription_id, remote_state
terragrunt init
terragrunt plan      # review; nothing created yet
terragrunt apply
terragrunt output -json > autoheal-infra-outputs.json
```

See [docs/getting-started.md](../../docs/getting-started.md) for the full flow and what the
outputs feed.
