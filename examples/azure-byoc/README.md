# examples/azure-byoc

A copyable starting config that points at `compositions/azure-byoc`. Lands once
the composition does. Consumers copy this directory, edit `terragrunt.hcl`
(namespace, environment, location, subscription, resource group), then
`terragrunt init && plan && apply`. See [docs/CONSUMING.md](../../docs/CONSUMING.md).
