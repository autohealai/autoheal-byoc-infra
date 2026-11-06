# compositions/aws-runner

The runner step: EC2 instances outside the cluster that run sandboxes, where the
agents run commands. It is optional. Without it Autoheal runs with sandboxes
off: the agents answer and call integrations but run no commands.

The runner instances run runner-go on an EC2 Auto Scaling group
(`modules/aws/runner-asg`). Each pulls `runner-go:chart-<chart_version>` and
polls Temporal at `temporal_address`, namespace `runners`, task queue
`runner-task-queue`.

The runner connects the way Autoheal's hosted runners do. `compositions/aws`
makes an internal network load balancer for it (`runner_lb_enabled`) that
fronts two listeners of the chart: the Temporal frontend on TCP 7233 and
api-server-go's tool-result listener on TCP 8083. The runner dials them in
plain gRPC and HTTP, with no TLS and no key, and the load balancer's security
group decides who may connect. Nothing runs at the edge for the runner, and
there is no key to make, store or rotate.

Since nothing else guards those listeners, the addresses must be private. The
plan stops on a public IPv4 address, on a load balancer that is not internal,
and on any other name that could resolve to a public address. It accepts:

- a private IPv4 address (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 or
  100.64.0.0/10);
- the DNS name of an internal load balancer in `account_id` and `region`,
  such as the `runner_load_balancer` output of `compositions/aws`. The plan
  looks it up by name and checks it is internal and has that DNS name;
- a name under `private_dns_domains`, such as a Route 53 private zone record
  that points at the load balancer. Use this for a load balancer in another
  account or region, which the plan cannot look up.

The runner only dials out; nothing connects into it. This composition never
reads the cluster: the addresses are inputs, like the cluster name is for
`compositions/app`. It creates, in `account_id`:

1. an IAM role and instance profile, unless `existing_instance_profile_arn` is
   set;
2. a security group that lets the instances out, unless
   `existing_security_group_id` is set;
3. a launch template and the Auto Scaling group, in `subnet_ids`, with
   cloud-init that installs Docker and runs runner-go under systemd.

It has no helm or kubernetes provider. The only provider is aws.

The instances run the runner-go image on a stock Amazon Linux 2023 AMI, or a
company image built from it (`ami_id`, `ami_name_filter`). Nothing is baked
into the AMI, so one image works in every account and region, and a new chart
version is a new image tag.

On the instances, runner-go runs sandboxes only. Its lambda drivers are off
(`DISABLED_DRIVERS`), since a lambda would run inside the runner container, on
its network. The launch template requires IMDSv2 with a hop limit of 1. A
firewall script, run before each runner-go start and every 5 minutes, keeps
containers in Docker's `DOCKER-USER` chain:

- off the instance metadata address, so only the host can use the instance
  role;
- for sandboxes, off the hosts of `temporal_address` and `tool_response_url`
  and off `sandbox_blocked_destinations`. Sandboxes run untrusted code, and
  the runner load balancer takes no key, so only runner-go may use it.
  runner-go runs on a Docker network of its own (`runner-go`) and starts the
  sandboxes on Docker's default bridge, where the rule applies.

Names are looked up each time, so the rule follows a load balancer whose
addresses change. runner-go does not start without the rules, and a name that
does not resolve stops it until it does.

The cloud-init is gzipped into the user data. EC2 takes at most 16 KB; with a
proxy and a long block list the plain cloud-init can be larger, gzipped it is
far smaller. The plan stops if even the gzipped one does not fit.

## Order

| Step | Composition | Needs |
|------|-------------|-------|
| 1 infra | `compositions/aws`, 4.6.0 or later, with `runner_lb_enabled = true` | makes the runner load balancer and the `runner_load_balancer` output, and turns on its two listeners in the chart values |
| 2 app | `compositions/app` | step 1: the chart binds the Temporal frontend and the tool-result listener to the load balancer |
| 3 runner | this composition, `temporal_address` and `tool_response_url` from the `runner_load_balancer` output | step 2, and the network owner's part |
| 4 app again | `compositions/app`, with `global.sandbox.enabled: true` in the chart values | the runner polling Temporal |

Sandboxes stay off until step 4. Until the network owner opens the path, the
runner keeps retrying; nothing fails.

Do step 4 only after the runner polls Temporal. With sandboxes on and no runner,
every agent run waits for a sandbox that never starts, then fails after about
11 minutes. To check, look in the Temporal web UI that the chart runs in the
cluster (reach it with `kubectl port-forward`) for a poller on task queue
`runner-task-queue` in namespace `runners`, or on a runner instance:

```bash
sudo systemctl is-active runner-go
sudo journalctl -u runner-go -n 50 --no-pager
sudo iptables -S AUTOHEAL-SANDBOX
```

Reach an instance with SSM Session Manager (`ssm_enabled`), or with SSH as
`ec2-user` (`key_name`). To list the instances:

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$(terragrunt output -raw autoscaling_group_name)" \
  --query 'AutoScalingGroups[0].Instances[].[InstanceId,LifecycleState,HealthStatus]' --output table
```

To stop sandboxes, set `global.sandbox.enabled: false` and apply the app.

## The network owner's part

`required_network_owner_actions` lists it in plain sentences. In short:

- Give the runner subnets a route to the runner load balancer and allow them
  there on TCP 7233 and 8083. The load balancer lets its own VPC in by
  default. From another VPC, connect the two (peering, a transit gateway) and
  add the runner subnets' ranges (`subnet_cidrs`) to
  `runner_lb_allowed_cidr_blocks` of `compositions/aws`. To let in only the
  runner, set `runner_lb_allowed_security_group_ids` to its security group
  (a brought one, or this composition's `security_group_id` after a second
  infra apply).
- Give the runner subnets outbound access, directly or through `http_proxy`,
  to the image registry (`public.ecr.aws`, or `ecr_registry_host`), the SSM
  endpoints with `ssm_enabled`, the git hosts and the endpoints the tools call.

Never put 7233 or 8083 on the internet: the load balancer's security group is
all that keeps others off Temporal, and the traffic carries git tokens and
command output in the clear inside the VPC.

The instances get no public address. The subnets' routes give the way out: the
NAT gateways of the VPC that `compositions/aws` creates, or your own. Where the
way out is a proxy, set `http_proxy`; dnf, Docker's image pulls, the ECR login
and runner-go use it, except for `no_proxy`. The hosts of `temporal_address`
and `tool_response_url`, the metadata address and localhost never go through
it. Sandboxes do not get the proxy: commands that reach the internet from a
sandbox need a direct way out. With VPC interface endpoints for ECR or SSM, add
their names (such as `api.ecr.us-west-2.amazonaws.com`) to `no_proxy`, or the
calls go to the proxy instead of the endpoint.

When the registry, or a proxy that inspects TLS, has a certificate from a
private CA, give that CA in `trusted_ca_certificates`. cloud-init adds it to
the system trust store before dnf installs packages and before Docker starts,
so the image pulls trust it without turning off TLS checks.

The security group we create lets the instances out to `egress_cidr_blocks` and
lets nothing in, apart from `ssh_ingress_cidr_blocks` on TCP 22. With
`existing_security_group_id` we add no rule, and
`required_network_owner_actions` lists what the brought group must allow.

## Inputs

| Input | Default | Contents |
|-------|---------|----------|
| `account_id` | required | Account to deploy into, usually the `account_id` of `compositions/aws`. The provider refuses credentials for any other account. |
| `region` | required | Region of `subnet_ids`. |
| `namespace`, `environment`, `name` | `name` = `autoheal` | Naming, as in `compositions/aws`. Resources are `<namespace>-<environment>-<name>-runner...`. |
| `tags` | `{}` | Tags on everything we create, such as those a company's policies require on instances. |
| `temporal_address` | required | `<host>:<port>`: the `temporal_address` of the `runner_load_balancer` output of `compositions/aws`, such as `acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com:7233`. Must be private (see above). |
| `tool_response_url` | `""` | Where the runner posts sandbox tool results: the `tool_response_url` of the same output, `http://<load balancer>:8083/api/v1/internal/sandbox-tool-responses`, as on Autoheal's hosted runners. Empty sends them through Temporal. An `http://` URL must be private like `temporal_address`; `https://` may be any host. |
| `private_dns_domains` | `[]` | Domains whose names resolve only to private addresses, such as a Route 53 private zone (`acme.internal`). `temporal_address` and `tool_response_url` may use names under them. |
| `sandbox_blocked_destinations` | `[]` | More destinations sandboxes may not reach over TCP, such as the VPC CIDR or the cluster API endpoint: IPv4 addresses, IPv4 CIDRs or DNS names. The hosts of `temporal_address` and `tool_response_url` are always blocked. |
| `chart_version` | required | The chart version of the app step. The image tag is `chart-<chart_version>`. |
| `runner_image` | `public.ecr.aws/e4h3h0d9/app/runner-go` | Repository, without a tag or digest. For a copy in your registry, its repository. |
| `runner_image_tag` | `""` | Overrides `chart-<chart_version>`, for a registry that keeps other tags. |
| `sandbox_image` | `""` | One sandbox image reference, to pre-pull at boot. |
| `ecr_registry_host` | `""` | A private ECR registry the images come from, such as the pull-through cache of `compositions/aws`: the role gets the inline policy `ecr-pull` on it, and the instances log in to it. runner-go pulls the sandbox image from the chart's `global.imageRegistry`, so set it when that is ECR, even with a public `runner_image`. |
| `ecr_repository_prefix` | `""` | Limits `ecr-pull` to `<prefix>/*`, such as the `registry_repository_prefix` of `compositions/aws`. Needs `ecr_registry_host`. |
| `subnet_ids` | required | Private subnets of one VPC, ideally one per zone: usually the `network.private_subnet_ids` output of `compositions/aws`. |
| `existing_security_group_id` | `""` | A security group to use instead of ours. We add no rule to it. |
| `additional_security_group_ids` | `[]` | More groups on the instances, such as one a company requires everywhere. |
| `egress_cidr_blocks` | `["0.0.0.0/0"]` | Where our group lets the instances out, on any port. |
| `ssh_ingress_cidr_blocks` | `[]` | Who our group lets in on TCP 22, with `key_name`. Never `0.0.0.0/0`. |
| `http_proxy` | `""` | Outbound proxy, such as `http://proxy.acme.example:8080`. Sandboxes do not get it. |
| `no_proxy` | `[]` | Hosts, `.domains` and CIDRs reached without the proxy. |
| `trusted_ca_certificates` | `[]` | PEM CA certificates added to the instances' trust store, such as `file("nexus-ca.pem")`: for a registry or a TLS-inspecting proxy whose certificate a private CA signs. dnf, Docker's image pulls and the ECR login trust them; runner-go and sandboxes do not. |
| `existing_instance_profile_arn` | `""` | An instance profile to use instead of ours, for accounts where a central team owns IAM. Its role needs `required_role_policies`. |
| `additional_iam_policy_arns` | `{}` | More managed policies for our role, keyed by a stable name. |
| `iam_permissions_boundary_arn` | `""` | Permissions boundary on our role. |
| `ssm_enabled` | `true` | `AmazonSSMManagedInstanceCore` on the role, for Session Manager. `false` where SSM is not used; then use `key_name`. |
| `key_name` | `""` | EC2 key pair for SSH as `ec2-user`. |
| `instance_type` | `m7i.xlarge` | Must support `architecture`. 4 vCPU and 16 GiB, the size of Autoheal's hosted runners. |
| `architecture` | `x86_64` | `x86_64` or `arm64`. The images must be built for it. |
| `ami_id` | `""` | An AMI to pin. |
| `ami_name_filter`, `ami_owners` | `""`, `[]` | A company image built from Amazon Linux 2023, such as `*golden-amzn-linux-2023-v*`, and the accounts that publish it. The newest match wins, so a new image rolls the instances at the next apply. With neither `ami_id` nor a filter, the latest Amazon Linux 2023. |
| `instance_count` | `1` | Runner instances. Each is an independent Temporal worker. `0` stops them all. |
| `instance_refresh_min_healthy_percentage`, `instance_refresh_max_healthy_percentage` | `100`, `200` | How a change replaces the instances. The defaults start each new instance before its old one stops. |
| `root_volume_size_gb` | `200` | Encrypted gp3. Holds Docker layers, sandbox directories and git caches. |
| `root_volume_kms_key_arn` | `""` | Empty uses the account's default EBS key. A customer managed key must let the Auto Scaling service-linked role use it. |
| `max_concurrent_activities` | `20` | Activities per instance at once. |

## Outputs

| Output | Contents |
|--------|----------|
| `autoscaling_group_name`, `launch_template_id` | The Auto Scaling group and its launch template. |
| `ami_id` | The AMI the instances run. |
| `security_group_id` | Our group, or `existing_security_group_id`. |
| `instance_profile_arn`, `iam_role_arn` | The instance profile, ours or brought, and our role (empty when brought). |
| `subnet_cidrs` | The runner subnets' ranges, the source of the network rules. |
| `required_network_owner_actions` | What the network owner must do, as readable lines. |
| `required_role_policies` | What the instance role needs: `trust_policy`, `inline_policies` (`ecr-pull` pulls from `ecr_registry_host`) and `managed_policy_arns` (`ssm`, and `additional_iam_policy_arns`). |

None of the outputs holds a secret, and neither does the state: the runner uses
no key.

## Who runs it

The deployer needs, in `account_id`, the rights to create launch templates,
Auto Scaling groups and security groups, and to read subnets, AMIs, SSM
parameters and load balancers (`elasticloadbalancing:DescribeLoadBalancers`,
for the private-address check). With our role it also needs the IAM rights to create roles,
policies and instance profiles, and `iam:PassRole` on the role. With
`existing_instance_profile_arn` it needs only `iam:PassRole` on the brought
profile's role, and the team that owns IAM creates that role from
`required_role_policies`:

```bash
terragrunt output -json required_role_policies
```

The output is filled on every plan, so a plan gives the list before the role
exists. The role must trust `ec2.amazonaws.com`. Nothing is needed on the
cluster.

## With Terragrunt

A `runner` folder after `app`, as in `examples/aws/prod`. It reads the runner
load balancer and the subnets from the `infra` folder and nothing from the
cluster:

```hcl
dependency "infra" {
  config_path = "../infra"
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs = {
    runner_load_balancer = {
      temporal_address  = "10.255.255.254:7233"
      tool_response_url = "http://10.255.255.254:8083/api/v1/internal/sandbox-tool-responses"
    }
    network = { private_subnet_ids = ["subnet-00000000000000000"] }
  }
}

inputs = {
  namespace         = "acme"
  environment       = "prod"
  account_id        = "111111111111"
  region            = "us-west-2"
  temporal_address  = dependency.infra.outputs.runner_load_balancer.temporal_address
  tool_response_url = dependency.infra.outputs.runner_load_balancer.tool_response_url
  subnet_ids        = dependency.infra.outputs.network.private_subnet_ids
  chart_version     = local.v.chart_version
}
```

`shallow` matters on an upgrade from 4.5.x: the `infra` state has outputs but
no `runner_load_balancer` until the 4.6.0 infra apply with `runner_lb_enabled`,
and without it the runner plan fails. The placeholders are private addresses so
that plan passes its checks; the apply never uses them. With
`runner_lb_enabled = false` the output is null and the runner plan stops.

## Upgrading

Bump `chart_version` with the app's. A new image tag, AMI or setting changes
the launch template, and the apply starts an instance refresh: with the
defaults the group launches each new instance, waits for it, then stops the
old one. A sandbox running on an old instance when it stops fails. The apply
does not wait for the refresh; follow it with
`aws autoscaling describe-instance-refreshes`.

A new runner load balancer (another name, so another DNS name) changes the
launch template and rolls the instances. The firewall follows address changes
of the same load balancer on its own, within 5 minutes.

## Tests

```bash
terraform init -backend=false
terraform test
```

`tests/runner.tftest.hcl` plans against a mocked provider: the runner load
balancer, a brought instance profile, security group and AMI filter, a private
ECR registry, private addresses and a private DNS domain, the network owner's
lines, and the input checks (address, private domains, blocked destinations,
images, subnets in two VPCs, a public address or name, an internet-facing load
balancer, a load balancer of the same name elsewhere, an `http://` tool-result
URL that is not private, a repository prefix without a registry).

`tests/cloudinit.tftest.hcl` plans `modules/aws/runner-asg` against a mocked
provider and compares its cloud-init with `tests/fixtures/`, once with the
defaults and once with every option. The user data must be the gzipped
cloud-init, it must set no TLS and an empty key, the block list must hold the
runner load balancer, and a block list of 600 ranges with every option must
still fit.
