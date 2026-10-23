# Two numbers for the whole environment. Changing them is how you upgrade.
locals {
  infra_version = "3.0.1"       # autoheal-byoc-infra tag; 2.2.0 or later for a cluster in another subscription
  chart_version = "1.0.0-rc.10" # every service, Temporal, Zitadel, the proxy, runner-go
}
