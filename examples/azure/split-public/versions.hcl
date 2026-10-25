# Two numbers for the whole environment. Changing them is how you upgrade.
locals {
  infra_version = "4.1.1"       # autoheal-byoc-infra tag; 2.2.0 or later for public endpoints
  chart_version = "1.0.0-rc.13" # every service, Temporal, Zitadel and the proxy; 4.x needs 1.0.0-rc.11 or later, the runner 1.0.0-rc.12
}
