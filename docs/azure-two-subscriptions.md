# Autoheal with AKS in a different Azure subscription, over connected VNets

In this document:

- **You** are the team that owns the AKS cluster.
- **We** are the team that installs Autoheal.
- The **cluster subscription** is the Azure subscription of your AKS cluster.
- The **data subscription** is the Azure subscription for all the other
  Autoheal resources.

[Choosing a subscription layout](azure-subscription-options.md) compares this
layout with the others.

## What is this?

Autoheal runs in one namespace of your AKS cluster. All the other Azure
resources of Autoheal are in the data subscription. We make no Azure
resources in the cluster subscription.

## Why is it necessary?

Your cluster has other applications on it. You keep control of the cluster
subscription, and we keep control of the data subscription. Each team
changes only its own subscription.

## What does it do?

- The Autoheal services run as pods in one namespace of your cluster, for
  example `autoheal`.
- The databases, storage and vaults are in the data subscription. Postgres and
  the private endpoints are in a VNet in that subscription.
- Your VNet and the Autoheal VNet connect through VNet peering.
- Users reach the Autoheal proxy on a private address in your AKS subnet.
- The pods sign in to the Key Vaults and the storage account with workload
  identity.

## What goes where

| Item | Cluster subscription | Data subscription |
|------|----------------------|-----------------------|
| AKS cluster | Yes (yours) | |
| The Autoheal namespace and the Autoheal pods | Yes | |
| VNet for Postgres and private endpoints | | Yes |
| PostgreSQL, Redis, storage account | | Yes |
| Two Key Vaults | | Yes |
| Managed identities for the pods, and their federated credentials | | Yes |
| Private endpoints and private DNS zones | | Yes |
| DNS records for the Autoheal hostnames | | Yes |
| VNet peering | Yes | Yes |

The Autoheal chart makes no CRDs, no ClusterRoles and no other cluster-wide
objects.

## What you do

1. Turn on the OIDC issuer and workload identity on the cluster.
2. Turn on the Key Vault secrets provider add-on on the cluster, or install the
   Secrets Store CSI driver with the Azure Key Vault provider yourself.
3. Make a namespace for Autoheal, for example `autoheal`.
4. Give our deployer these roles:

   | Role | Scope |
   |------|-------|
   | Azure Kubernetes Service Cluster User Role | The cluster |
   | Azure Kubernetes Service RBAC Admin | The Autoheal namespace only |
   | Network Contributor | The cluster VNet |

   Cluster User Role lets us read the OIDC issuer and the connection details of
   the cluster. We need them to connect the pod identities to the cluster. The
   chart makes Roles and RoleBindings in the namespace. RBAC Admin lets it do
   this. RBAC Writer does not. We use Network Contributor only to link our
   private DNS zones to your VNet. If your own DNS resolves these zones for
   your VNet, we do not link them and do not need this role.

5. Pick a free IP address in the AKS subnet for the Autoheal proxy.
6. Send us the cluster resource ID, the AKS subnet resource ID, the IP address
   and the name of the namespace.
7. Agree with us on an address range for the Autoheal VNet. It must not overlap
   your VNet.

After our first apply:

8. Peer your VNet with the Autoheal VNet in both directions. Or connect the two
   VNets through your hub.
9. Let your users reach the proxy address on TCP 443.

Our `required_cluster_owner_actions` output shows each of these items with the
real names, IDs and addresses.

## What we do

1. Give our deployer Owner (or Contributor and User Access Administrator) on
   the data subscription.
2. Copy `examples/azure/split` into our deployment repository. It has three
   folders, applied in this order: `infra`, `cluster` and `app`.
3. Write your cluster ID, AKS subnet ID, IP address and the agreed address
   range into `split/infra/terragrunt.hcl`, and the namespace into
   `split/infra/terragrunt.hcl` and `split/app/terragrunt.hcl`.
4. Apply `split/infra`. It makes the resources in the data subscription
   only. It does not read your cluster.
5. Send you the `required_cluster_owner_actions` and `network` outputs.
6. Apply `split/cluster`. It reads your cluster, checks that the OIDC issuer is
   on, and connects the pod identities to the OIDC issuer of the cluster. It
   makes nothing in the cluster subscription.
7. Apply `split/app` after you connect the VNets. It installs the Autoheal
   chart in the Autoheal namespace.
8. Make sure that all the pods are ready.

## Deploy steps

| Step | Who | Action |
|------|-----|--------|
| 1 | You | Do items 1 to 7 of "What you do". |
| 2 | We | Do items 1 to 6 of "What we do". |
| 3 | You | Do items 8 and 9 of "What you do". |
| 4 | We | Do items 7 and 8 of "What we do". |

For an upgrade, we do items 4, 6 and 7 of "What we do" again. You do not have
to give new permissions. To upgrade an install of infra 3.x, see
[Upgrading from 3.x](../compositions/azure-cluster/README.md#upgrading-from-3x)
in `compositions/azure-cluster`.

## Limits

- The two subscriptions must be in the same Microsoft Entra tenant.
- Put the two VNets in the same Azure region.
- The address ranges of the two VNets must not overlap.
- The DNS zone for the Autoheal hostnames must be in the data subscription.
  If your DNS zone is in a different place, we give you the records to make.
- Azure does not let two private DNS zones with the same name link to one
  VNet. If your VNet already uses central zones such as
  `privatelink.blob.core.windows.net`, tell us before our first apply. We then
  use your zones and do not link our zones.
