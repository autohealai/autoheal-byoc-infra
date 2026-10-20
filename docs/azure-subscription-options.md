# Choosing a subscription layout for Autoheal on Azure

Autoheal on Azure uses one AKS cluster and a set of data resources: Postgres,
Redis, a storage account, two Key Vaults, managed identities and runner VMs.
This document compares three layouts for these resources. Use it to select one
layout before the install.

| Layout | Where the resources are | How the cluster reaches the data resources |
|--------|-------------------------|--------------------------------------------|
| **One subscription** | The cluster and all data resources in one subscription | A private network in that subscription |
| **Two subscriptions, connected VNets** | The cluster in the cluster subscription. All data resources in the data subscription | VNet peering (or a hub) and private endpoints. [Details](azure-two-subscriptions.md) |
| **Two subscriptions, public endpoints** | As above | Public endpoints with firewalls. No VNet connection. [Details](azure-two-subscriptions-public.md), [runbook](azure-two-subscriptions-public-runbook.md) |

Our recommendation: use one subscription when the cluster owner lets us make
resources next to the cluster. Use connected VNets when the cluster must stay
in its own subscription. Use public endpoints only when the network team
cannot connect the two VNets.

## Security

| Item | One subscription | Connected VNets | Public endpoints |
|------|------------------|-----------------|------------------|
| Postgres | Private, in the VNet | Private, in the data VNet | Public endpoint. The firewall lets in only the cluster's outbound addresses |
| Key Vaults | Private endpoint, or public with an IP firewall | Private endpoint | Public endpoint. The firewall lets in only the cluster's outbound addresses and the deploy host |
| Storage | Private endpoint, or public with a firewall | Private endpoint | Public endpoint. The firewall lets in only the cluster's AKS subnet and the deploy host |
| Redis | Private endpoint | Private endpoint | Public endpoint. **No IP filter**: Azure Managed Redis has none. The access key and TLS protect it |
| Temporal and tool results (runner VMs to the cluster) | Private address. An NSG lets in only the runner subnet | Private address over the peering. An NSG lets in only the runner subnet | **Public IP.** The load balancer, the NSG and a network policy let in only the runner address |
| Encryption of Temporal and tool results | None, on the private network | None, on the private network | **None, on public addresses.** Azure keeps the traffic on the Microsoft network |
| Encryption of all other connections | TLS | TLS | TLS |
| Rights of our deployer in the cluster subscription | Contributor and role grants | Read only, admin in one namespace, and Network Contributor on the cluster VNet for the DNS links | Read only, admin in one namespace, and Network Contributor on the AKS subnet for the storage firewall |
| Separation of duties | Low. One team controls the cluster and the data | High. Each team controls its own subscription | High. Each team controls its own subscription |
| Effect of a mistake in one firewall rule | Small. The data stays private | Small. The data stays private | Large. A wrong rule can expose a data resource to the internet |

## Maintenance

| Item | One subscription | Connected VNets | Public endpoints |
|------|------------------|-----------------|------------------|
| Tasks for the cluster owner before the install | None, or roles only | Four roles, the namespace, two cluster features, two IP addresses, an address range | Four roles, the namespace, two cluster features, a service endpoint, a static public IP, one IP address, the outbound addresses |
| Tasks for the cluster owner after the first apply | None | VNet peering (both directions), one NSG rule | One NSG rule |
| Address planning | One VNet range | Two ranges that must not overlap | No overlap rule |
| Private DNS | We make and link the zones | We make the zones and link them to the cluster VNet, or you use your central zones | None |
| Recurring upkeep | None | Keep the peering connected | Keep the cluster's outbound addresses fixed. Tell us before they change, so that we update the firewalls first |
| Effect on other workloads on the cluster | None | None | The storage service endpoint changes how all workloads on the AKS subnet reach Azure Storage |
| Upgrades of Autoheal | Same for all layouts | Same for all layouts | Same for all layouts |
| Move to another layout later | A new install | To public endpoints: a new Postgres server and a data move | To connected VNets: a new Postgres server and a data move |
| Troubleshooting | One network | Two networks and the peering | Firewalls on Postgres, the vaults, storage and Temporal, and the outbound addresses |
| Extra Azure cost | Private endpoints | Private endpoints, private DNS zones, data through the peering | A static public IP |

## When to select each layout

- **One subscription**: the cluster owner lets us make resources in the
  cluster subscription, or we make the cluster too. This layout is the
  simplest and has the fewest moving parts.
- **Two subscriptions, connected VNets**: the cluster owner gives us one
  namespace and nothing else, and the network team can peer the VNets or
  connect them through a hub. All traffic stays private.
- **Two subscriptions, public endpoints**: the cluster owner gives us one
  namespace, and the network team cannot connect the VNets. You accept a
  public Redis endpoint without an IP filter, and Temporal traffic without
  encryption on public addresses.

All three layouts use the same Autoheal chart and the same Terraform code. Only
the inputs are different.
