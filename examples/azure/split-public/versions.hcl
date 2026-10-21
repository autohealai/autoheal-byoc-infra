# Two numbers for the whole environment. Changing them is how you upgrade.
locals {
  infra_version = "3.0.0"      # autoheal-byoc-infra tag; 2.2.0 or later for public endpoints
  chart_version = "1.0.0-rc.8" # every service, Temporal, Zitadel, the proxy, runner-go
}
