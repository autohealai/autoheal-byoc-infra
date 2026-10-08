# compositions/azure-byoc

The Azure recipe: wires the `modules/azure/*` building blocks into the full
Autoheal BYOC stack and emits the shared output contract. This is what a consumer
runs (via an `examples/azure-byoc` config).

Wiring (planned, as modules land):

```
resource group
module "vnet"              modules/azure/vnet
module "postgres"          modules/azure/postgres-flexible  (subnet = vnet.subnet_db_id)
module "redis"             modules/azure/redis-premium      (subnet = vnet.subnet_redis_id)
module "blob"              modules/azure/blob
module "keyvault"          modules/azure/keyvault
module "acr"               modules/azure/acr
module "aks"               modules/azure/aks                (subnet = vnet.subnet_aks_id)
module "runner"            modules/azure/runner-vmss        (subnet = vnet.subnet_runner_id, acr = acr.id)
module "workload_identity" modules/azure/workload-identity
```

Outputs (shared contract — identical names in `aws-byoc`):
`cluster_name`, `postgres_host`, `redis_endpoint`, `object_store`,
`secret_store_uri`, `registry`, `runner_identity`.
