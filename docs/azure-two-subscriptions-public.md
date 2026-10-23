# Autoheal with AKS in a different Azure subscription, over public endpoints

In this document:

- **You** are the team that owns the AKS cluster.
- **We** are the team that installs Autoheal.
- The **cluster subscription** is the Azure subscription of your AKS cluster.
- The **data subscription** is the Azure subscription for all the other
  Autoheal resources.

[Choosing a subscription layout](azure-subscription-options.md) compares this
layout with the others. [The runbook](azure-two-subscriptions-public-runbook.md)
gives every command, end to end.

## What is this?

Autoheal runs in one namespace of your AKS cluster. All the other Azure
resources of Autoheal are in the data subscription. We make no Azure resources
in the cluster subscription. The two subscriptions have no network connection:
no VNet peering and no hub.

## Why is it necessary?

Your network team does not connect your VNet to other VNets. Autoheal can still
use your cluster. Each connection goes to a public endpoint that lets in only
known addresses.

## What does it do?

- The Autoheal services run as pods in one namespace of your cluster, for
  example `autoheal`.
- The pods connect to Postgres, Redis, storage and the Key Vaults on their
  public endpoints. Postgres lets in only the public outbound addresses of
  your cluster. The Key Vaults let in these addresses and our deploy host.
  Storage lets in your AKS subnet and our deploy host.
- Users and webhooks from your integrations reach the Autoheal proxy over HTTPS
  on a static public IP.
- The pods sign in to the Key Vaults and the storage account with workload
  identity.

## What goes where

| Item | Cluster subscription | Data subscription |
|------|----------------------|-------------------|
| AKS cluster | Yes (yours) | |
| The Autoheal namespace and the Autoheal pods | Yes | |
| Static public IP for the Autoheal proxy | Yes (you make it) | |
| PostgreSQL, Redis, storage account | | Yes |
| Two Key Vaults | | Yes |
| Managed identities for the pods, and their federated credentials | | Yes |
| DNS records for the Autoheal hostnames | | Yes |

The data subscription has no VNet in this layout.

The Autoheal chart makes no CRDs, no ClusterRoles and no other cluster-wide
objects. AKS makes the load balancer for the static public IP in the node
resource group of your cluster, as for any Service of type LoadBalancer.

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

   Cluster User Role lets us read the OIDC issuer and the connection details of
   the cluster. We need them to connect the pod identities to the cluster. The
   chart makes Roles and RoleBindings in the namespace. RBAC Admin lets it do
   this. RBAC Writer does not. We need no role on the AKS subnet.

5. Turn on the `Microsoft.Storage` service endpoint on the AKS subnet.
6. Make a Standard static public IP in the node resource group of the cluster
   (`MC_...`) for the Autoheal proxy.
7. If the AKS subnet has an NSG, let everyone reach the proxy IP on TCP 443 and
   80, or only the sources that you choose: your users and the webhook senders.
8. Send us the cluster resource ID, the AKS subnet resource ID, the static
   public IP, the public outbound addresses of the cluster and the name of the
   namespace.

After our first apply:

9. Add a network rule for the AKS subnet on our storage account. We send you
   the command. Azure Storage does not apply IP rules to clients in its own
   region, so the account lets the pods in by their subnet. You need the right
   to join the subnet through a service endpoint, which you have as the owner,
   and write on the storage account. We give you Storage Account Contributor on
   the account for this item, and remove it after.

Keep the outbound addresses of the cluster fixed. Tell us before they change.

Our `required_cluster_owner_actions` output shows each of these items with the
real names, IDs and addresses.

## What we do

1. Give our deployer Owner (or Contributor and User Access Administrator) on
   the data subscription.
2. Copy `examples/azure/split-public` into our deployment repository. It has
   three folders, applied in this order: `infra`, `cluster` and `app`.
3. Write your cluster ID, AKS subnet ID, static public IP and outbound
   addresses into `split-public/infra/terragrunt.hcl`, and the namespace into
   `split-public/infra/terragrunt.hcl` and `split-public/app/terragrunt.hcl`.
4. Apply `split-public/infra`. It makes the resources in the data subscription
   only. It does not read your cluster.
5. Send you the `required_cluster_owner_actions` output, with the command for
   the storage network rule.
6. Apply `split-public/cluster`. It reads your cluster, checks that the OIDC
   issuer is on, and connects the pod identities to the OIDC issuer of the
   cluster. It makes nothing in the cluster subscription.
7. Apply `split-public/app` after you add the storage network rule. It installs
   the Autoheal chart in the Autoheal namespace, with the load balancer for the
   proxy on the static public IP.
8. Make sure that all the pods are ready.

## Deploy steps

| Step | Who | Action |
|------|-----|--------|
| 1 | You | Do items 1 to 8 of "What you do". |
| 2 | We | Do items 1 to 6 of "What we do". |
| 3 | You | Do item 9 of "What you do". |
| 4 | We | Do items 7 and 8 of "What we do". |

For an upgrade, we do items 4, 6 and 7 of "What we do" again. You do not have
to give new permissions. To upgrade an install of infra 3.x, see
[Upgrade from 3.x](azure-two-subscriptions-public-runbook.md#upgrade-from-3x)
in the runbook.

## Limits

- The two subscriptions must be in the same Microsoft Entra tenant.
- We put the data resources in the region of your cluster. Storage lets in your
  AKS subnet only from the same region.
- Azure Managed Redis has no IP firewall. Its public endpoint accepts
  connections from all addresses. The access key and TLS protect it.
- The Autoheal proxy is open to the internet on TCP 443 and 80, unless the NSG
  lets in only some sources. TLS and the Autoheal login protect it. To keep it
  on your network only, see
  [Keep Autoheal private](azure-two-subscriptions-public-runbook.md#keep-autoheal-private)
  in the runbook.
- The `Microsoft.Storage` service endpoint applies to all workloads on the AKS
  subnet. Make sure that your other workloads still reach their storage
  accounts.
- To move to connected VNets later, we make a new Postgres server and move the
  data. Azure does not change the network mode of a Postgres server.
- The DNS zone for the Autoheal hostnames must be in the data subscription. If
  your DNS zone is in a different place, we give you the records to make.
