# examples/aws-byoc

A copyable starting config that points at `compositions/aws-byoc` via Terragrunt.

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

See [docs/CONSUMING.md](../../docs/CONSUMING.md) for the full flow and what the
outputs feed.
