# examples/aws-byoc

A copyable starting config that points at `compositions/aws-byoc`. Lands once the
composition does. Consumers copy this directory, edit `terragrunt.hcl` (namespace,
environment, region), then `terragrunt init && plan && apply`.
See [docs/CONSUMING.md](../../docs/CONSUMING.md).
