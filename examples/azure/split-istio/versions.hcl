# Two numbers for the whole environment. Changing them is how you upgrade.
locals {
  infra_version = "4.3.1"       # autoheal-byoc-infra tag; the runner needs 4.1.0 or later, the temporal unit 4.3.1
  chart_version = "1.0.0-rc.14" # every service, Temporal, Zitadel and the proxy; the runner needs 1.0.0-rc.12 or later, the temporal unit 1.0.0-rc.14
}
