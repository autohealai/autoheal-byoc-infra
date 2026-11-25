# Two numbers for the whole environment. Changing them is how you upgrade.
locals {
  infra_version = "5.0.2"       # autoheal-byoc-infra tag
  chart_version = "1.0.0-rc.21" # every service, Temporal, Zitadel and the proxy; on AWS 5.0.0 and later need 1.0.0-rc.17 or later
}
