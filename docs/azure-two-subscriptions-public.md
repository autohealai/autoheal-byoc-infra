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
- The runner VMs are in the data subscription. They connect to Temporal in your
  cluster on a static public IP. That IP lets in only the outbound address of
  the runner VMs. If a firewall carries the outbound traffic of your cluster,
  the firewall forwards this traffic to a private address instead (see below).
- Users and webhooks from your integrations reach the Autoheal proxy over HTTPS
  on a second static public IP. With only one public IP, the proxy and Temporal
  share it: their ports do not overlap.
- The pods sign in to the Key Vaults and the storage account with workload
  identity.

## What goes where

| Item | Cluster subscription | Data subscription |
|------|----------------------|-------------------|
| AKS cluster | Yes (yours) | |
| The Autoheal namespace and the Autoheal pods | Yes | |
| Static public IP for Temporal, or a forwarding rule on your firewall | Yes (you make it) | |
| Static public IP for the Autoheal proxy, or the Temporal IP for both | Yes (you make it) | |
| VNet for the runner VMs, with a NAT gateway | | Yes |
| Runner VMs | | Yes |
| PostgreSQL, Redis, storage account | | Yes |
| Two Key Vaults | | Yes |
| Managed identities for the pods | | Yes |
| DNS records for the Autoheal hostnames | | Yes |

The Autoheal chart makes no CRDs, no ClusterRoles and no other cluster-wide
objects. AKS makes the load balancer for the static public IP in the node
resource group of your cluster, as for any Service of type LoadBalancer.

## What you do

1. Turn on the OIDC issuer and workload identity on the cluster.
2. Run the Secrets Store CSI driver with the Azure Key Vault provider on the
   cluster: turn on the Key Vault secrets provider add-on, or keep your own
   install of them.
3. Make a namespace for Autoheal, for example `autoheal`.
4. Give our deployer these roles:

   | Role | Scope |
   |------|-------|
   | Azure Kubernetes Service Cluster User Role | The cluster |
   | Azure Kubernetes Service RBAC Admin | The Autoheal namespace only |
   | Reader | The AKS subnet |
   | Network Contributor | The AKS subnet |

   The chart makes Roles and RoleBindings in the namespace. RBAC Admin lets it
   do this. RBAC Writer does not. We use Network Contributor only to add your
   AKS subnet to the firewall of our storage account.

5. Turn on the `Microsoft.Storage` service endpoint on the AKS subnet.
6. Make two Standard static public IPs in the node resource group of the
   cluster (`MC_...`): one for Temporal and one for the Autoheal proxy. With
   only one IP, both use it. If a firewall carries the outbound traffic of the
   cluster, see "Temporal behind your firewall" below instead.
7. Send us the cluster resource ID, the AKS subnet resource ID, the static
   public IPs, the public outbound addresses of the cluster and the name of the
   namespace.

After our first apply:

8. Add NSG rules on the AKS subnet. Let only the runner address (we send it to
   you) reach the Temporal IP on TCP 7233 and 8083, and deny all other sources
   to that IP on these ports.
9. Let everyone reach the proxy IP on TCP 443 and 80, or only the sources that
   you choose: your users and the webhook senders.

Keep the outbound addresses of the cluster fixed. Tell us before they change.

Our `required_cluster_owner_actions` output shows each of these items with the
real names, IDs and addresses.

## What we do

1. Give our deployer Owner (or Contributor and User Access Administrator) on
   the data subscription.
2. Copy `examples/azure/split-public` into our deployment repository.
3. Write your cluster ID, AKS subnet ID, static public IPs and outbound
   addresses into `split-public/infra/terragrunt.hcl`, and the namespace into
   both `terragrunt.hcl` files.
4. Apply `split-public/infra`. It makes the resources in the data subscription
   only.
5. Send you the runner address from the `temporal_public_endpoint` output (or
   `temporal_forwarding`, with a firewall), and the
   `required_cluster_owner_actions` output.
6. Apply `split-public/app` after you add the NSG rules. It installs the
   Autoheal chart in the Autoheal namespace, with the load balancers for the
   proxy and for Temporal on the static public IPs.
7. Make sure that all the pods are ready and that the runner VMs connect to
   Temporal.

## Deploy steps

| Step | Who | Action |
|------|-----|--------|
| 1 | You | Do items 1 to 7 of "What you do". |
| 2 | We | Do items 1 to 5 of "What we do". |
| 3 | You | Do items 8 and 9 of "What you do". |
| 4 | We | Do items 6 and 7 of "What we do". |

For an upgrade, we do items 4 and 6 of "What we do" again. You do not have to
give new permissions.

## Temporal behind your firewall

Some clusters send all their outbound traffic to a firewall on a route
(`outboundType` `userDefinedRouting`). A public load balancer in such a cluster
does not work: its replies leave through the firewall, which drops them. Then:

- You pick a free private address in the AKS subnet for Temporal, in place of
  its static public IP. The chart puts its internal load balancers there.
- You send us a public address of your firewall, or a DNS name for it. The
  runner VMs connect to it.
- After our first apply, you add a rule on your firewall: forward TCP 7233 and
  8083 from that address to the private address, from the runner address only.
  Our `temporal_forwarding` output shows the rule with the real addresses.
- The proxy stays private, on a private address in the AKS subnet, for the same
  reason.

## Limits

- The two subscriptions must be in the same Microsoft Entra tenant.
- We put the data resources in the region of your cluster. Storage lets in your
  AKS subnet only from the same region.
- Azure Managed Redis has no IP firewall. Its public endpoint accepts
  connections from all addresses. The access key and TLS protect it.
- The runner VMs connect to Temporal and send tool results without encryption.
  Only the runner address can reach the Temporal IP on those ports.
- The Autoheal proxy is open to the internet on TCP 443 and 80, unless the NSG
  lets in only some sources. TLS and the Autoheal login protect it. To keep it
  on your network only, see "Keep Autoheal private" in the runbook.
- The `Microsoft.Storage` service endpoint applies to all workloads on the AKS
  subnet. Make sure that your other workloads still reach their storage
  accounts.
- To move to connected VNets later, we make a new Postgres server and move the
  data. Azure does not change the network mode of a Postgres server.
- The DNS zone for the Autoheal hostnames must be in the data subscription. If
  your DNS zone is in a different place, we give you the records to make.
