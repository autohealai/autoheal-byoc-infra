# examples/azure/cop-standin

**Not for customers.** An internal stand-in for a customer's cluster
subscription, to test `examples/azure/split` (peering) and
`examples/azure/split-public` (public endpoints) in two of our own
subscriptions: COP-test for the cluster, SRE-test for everything else. It does
what the customer's cluster owner does, and nothing more:

- a resource group, a VNet and an AKS cluster with the OIDC issuer, workload
  identity, the Key Vault secrets provider add-on, Entra ID with Azure RBAC and
  no local accounts (`modules/azure/aks`);
- the `autoheal` namespace;
- for our deployer: Azure Kubernetes Service Cluster User Role on the cluster,
  Reader on the AKS subnet, Azure Kubernetes Service RBAC Admin on the
  namespace only, and Network Contributor on the VNet (for the DNS zone links
  or the storage subnet rule);
- the NSG rule on the AKS subnet for the Temporal address;
- `network_path = "private"`: after the infra apply, both sides of the peering;
- `network_path = "public"`: the static public IP for Temporal in the node
  resource group and the `Microsoft.Storage` service endpoint on the AKS
  subnet; no peering.

It is a plain Terraform root with local state. Run it as someone with Owner on
COP-test, Network Contributor on SRE-test (for our side of the peering), and
membership of one of `admin_group_object_ids`.

## Test run: peering (`examples/azure/split`)

1. Apply the stand-in:

   ```bash
   az login
   terraform init
   terraform apply \
     -var subscription_id=<COP-test> -var sre_subscription_id=<SRE-test> \
     -var deployer_object_id=<deployer object ID> \
     -var 'admin_group_object_ids=["<group object ID>"]'
   ```

   If the namespace step fails with Forbidden right after the cluster is
   created, run the apply again.

2. In `../split/infra/terragrunt.hcl`, set `subscription_id` to SRE-test and
   `existing_aks_cluster_id` and `existing_network` to the stand-in's outputs.
   Point `source` at your checkout. Apply it as the deployer, which has
   Contributor and User Access Administrator on SRE-test and only the grants
   above on COP-test: `cd ../split/infra && terragrunt apply`.

3. Apply the stand-in again with `-var sre_vnet_id=<network.vnet_id output of
   ../split/infra>` to create the peering.

4. Apply the chart: `cd ../split/app && terragrunt apply`.

## Test run: public endpoints (`examples/azure/split-public`)

1. Apply the stand-in as above, with `-var network_path=public`.

2. Look up the cluster's outbound addresses:

   ```bash
   az aks show -g rg-cop-standin -n cop-standin-aks \
     --query 'networkProfile.loadBalancerProfile.effectiveOutboundIPs[].id' -o tsv |
     xargs -n1 az network public-ip show --query ipAddress -o tsv --ids
   ```

3. In `../split-public/infra/terragrunt.hcl`, set `subscription_id`,
   `existing_aks_cluster_id` and `existing_network` from the stand-in's outputs,
   and `workload_egress_ip_ranges` to the addresses from step 2. Apply it as the
   deployer.

4. Apply the stand-in again with `-var network_path=public -var
   runner_egress_ip=<the address in the temporal_public_endpoint output of
   ../split-public/infra>`, to let the runner through the NSG.

5. Apply the chart: `cd ../split-public/app && terragrunt apply`.

## Pass criteria

- The infra apply created nothing in COP-test:
  `az resource list --subscription <COP-test> -o table` shows only the
  stand-in's resources and the load balancer objects AKS manages in the node
  resource group, and the activity log of COP-test shows no write by the
  deployer.
- `helm status autoheal -n autoheal` shows `deployed`, and every pod in
  `autoheal` is ready.
- The `autoheal-hooks` job completed and the Kubernetes Secrets it syncs from
  the vault exist (workload identity works across the two subscriptions).
- The runner VM logs show a connection to Temporal at `temporal_ip:7233`.
- Public path only: from any address other than the runner's,
  `nc -vz <temporal_ip> 7233` times out.

## Clean up

1. Destroy the `app` folder.
2. Peering: apply the stand-in with `sre_vnet_id` empty, to remove the peering.
3. Destroy the `infra` folder, then this stand-in.
