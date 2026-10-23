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
- for our deployer: Azure Kubernetes Service Cluster User Role on the cluster
  and Azure Kubernetes Service RBAC Admin on the namespace only, plus, on the
  private path, Network Contributor on the VNet for the DNS zone links;
- `network_path = "private"`: after the infra apply, both sides of the peering;
- `network_path = "public"`: the static public IP for the proxy in the node
  resource group, an NSG rule that lets everyone reach it on 443 and 80, and
  the `Microsoft.Storage` service endpoint on the AKS subnet; no peering. After
  the infra apply, you add the storage account's network rule for the AKS
  subnet by hand, as the cluster owner would.

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

4. Federate the workload identities to the cluster, as the deployer:
   `cd ../split/cluster && terragrunt apply`.

5. Apply the chart: `cd ../split/app && terragrunt apply`.

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
   deployer. It needs no grant on COP-test.

4. As the stand-in's operator, run the `az storage account network-rule add`
   command from the `required_cluster_owner_actions` output of
   `../split-public/infra`, so pods reach storage from the AKS subnet.

5. Federate the workload identities to the cluster, as the deployer:
   `cd ../split-public/cluster && terragrunt apply`.

6. Apply the chart: `cd ../split-public/app && terragrunt apply`.

## Pass criteria

- The infra and cluster applies created nothing in COP-test:
  `az resource list --subscription <COP-test> -o table` shows only the
  stand-in's resources and the load balancer objects AKS manages in the node
  resource group, and the activity log of COP-test shows no write by the
  deployer. On the private path the DNS zone links are the one exception: they
  are created in SRE-test, but join the COP-test VNet.
- The `federated_credentials` output of the cluster folder lists the three
  workload identities.
- `helm status autoheal -n autoheal` shows `deployed`, and every pod in
  `autoheal` is ready.
- The `autoheal-hooks` job completed and the Kubernetes Secrets it syncs from
  the vault exist (workload identity works across the two subscriptions).

## Clean up

1. Destroy the `app` folder, then the `cluster` folder.
2. Peering: apply the stand-in with `sre_vnet_id` empty, to remove the peering.
3. Destroy the `infra` folder, then this stand-in.
