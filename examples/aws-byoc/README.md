# examples/aws-byoc

A copyable starting config that points at `compositions/aws-byoc` via Terragrunt.

**First time? Follow the full step-by-step tutorial in
[docs/getting-started.md](../../docs/getting-started.md)** — it covers the tools, permissions,
and remote-state setup this short version assumes. The short version:

```bash
cp -r examples/aws-byoc examples/aws-byoc-mine
cd examples/aws-byoc-mine
# edit terragrunt.hcl: namespace, environment, region, availability_zones, remote_state
terragrunt init
terragrunt plan      # review; nothing created yet
terragrunt apply
terragrunt output -json > autoheal-infra-outputs.json
```

After the app + Temporal are up, apply `modules/aws/runner-asg` separately, feeding
it this stack's `vpc_id` + `private_subnet_ids` and the discovered internal NLB host.

See [docs/getting-started.md](../../docs/getting-started.md) for the full flow and what the
outputs feed.
