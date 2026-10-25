# Two numbers for the whole environment. Changing them is how you upgrade.
locals {
  infra_version = "4.0.0"       # autoheal-byoc-infra tag; 2.2.0 or later for a cluster in another subscription
  chart_version = "1.0.0-rc.11" # every service, Temporal, Zitadel and the proxy; 4.0.0 needs 1.0.0-rc.11 or later
}
