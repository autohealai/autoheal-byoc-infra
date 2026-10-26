# Two numbers for the whole environment. Changing them is how you upgrade.
locals {
  infra_version = "4.1.2"       # autoheal-byoc-infra tag; the runner needs 4.1.0 or later
  chart_version = "1.0.0-rc.13" # every service, Temporal, Zitadel and the proxy; the runner needs 1.0.0-rc.12 or later
}
