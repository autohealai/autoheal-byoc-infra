# Two numbers for the whole environment. Changing them is how you upgrade.
locals {
  infra_version = "2.1.0"      # autoheal-byoc-infra tag
  chart_version = "1.0.0-rc.7" # every service, Temporal, Zitadel, the proxy, runner-go
}
