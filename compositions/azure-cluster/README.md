# compositions/azure-cluster

The cluster step for an AKS cluster you bring. Run it after `compositions/azure`
and before `compositions/app`, only when `compositions/azure` has
`existing_aks_cluster_id` set. A cluster that `compositions/azure` creates needs
no cluster step: it is federated in the same apply.

`compositions/azure` never reads a brought cluster, so the data subscription
does not depend on the cluster. This composition is where the cluster comes in.
It:

1. reads the cluster in its own subscription, which may differ from the data
   subscription;
2. stops when the OIDC issuer is off, and warns when the Key Vault secrets
   provider add-on is off (a CSI driver you install yourself also works, so
   that is a warning, not an error);
3. creates one federated credential per chart service account on the three
   workload identities, trusting the cluster's OIDC issuer, so pods in the
   Autoheal namespace can sign in as them;
4. outputs `cluster`, with the endpoint and CA certificate, for
   `compositions/app`.

It creates nothing in the cluster's subscription. The federated credentials are
child resources of the identities, in the data subscription.

## Inputs

| Input | Contents |
|-------|----------|
| `cluster` | The `cluster` output of `compositions/azure`. Only `name`, `resource_group` and `subscription_id` are read. |
| `federation` | The `federation` output of `compositions/azure`: the data subscription, and per identity its resource ID and the service accounts it trusts. It is null for a cluster `compositions/azure` created, and the plan stops. |
| `import_federated_credentials` | Default `false`. Set `true` for one apply when upgrading from 3.x without a sign-in gap (below). |

## Outputs

| Output | Contents |
|--------|----------|
| `cluster` | `cloud`, `name`, `resource_group`, `subscription_id`, `endpoint`, base64 `ca_certificate`. Pass to `compositions/app`. No credential. |
| `oidc_issuer_url` | The issuer the federated credentials trust. |
| `federated_credentials` | One line per credential: identity, credential name and subject. |

None of the outputs holds a secret.

## Who runs it

The deployer is whoever runs the apply: the person after `az login`, or the
pipeline's identity. It needs:

- Azure Kubernetes Service Cluster User Role on the cluster, to read it and its
  connection details. The `required_cluster_owner_actions` output of
  `compositions/azure` lists this grant for the cluster owner.
- Write on the federated credentials of the three workload identities
  (`Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/write`),
  which Managed Identity Contributor or Contributor on the data resource group
  gives. The identity that applied `compositions/azure` has it already.

Usually one identity runs all three steps. The provider registers no resource
providers, so no subscription-level right is needed for that.

## With Terragrunt

A `cluster` folder between `infra` and `app`, as in `examples/azure/split`:

```hcl
dependency "infra" {
  config_path = "../infra"
}

inputs = {
  cluster    = dependency.infra.outputs.cluster
  federation = dependency.infra.outputs.federation
}
```

The `app` folder takes `cluster = dependency.cluster.outputs.cluster`, and
`infra_values` from the `infra` folder as before.

## Upgrading from 3.x

In 3.x `compositions/azure` read the cluster and made the federated credentials
itself. In 4.x it makes none for a brought cluster, so its first 4.x apply
deletes them, and this composition creates them again. Pods whose tokens are
exchanged between the two applies fail to sign in. For a short gap, run the two
applies one after the other.

To keep the credentials, move them instead of deleting them:

1. Before the 4.x apply of `compositions/azure`, remove the credentials from
   its state. In its folder:

   ```bash
   terragrunt state rm 'module.secrets_identity.azurerm_federated_identity_credential.sa'
   terragrunt state rm 'module.api_server_identity.azurerm_federated_identity_credential.sa'
   terragrunt state rm 'module.agents_worker_identity.azurerm_federated_identity_credential.sa'
   ```

   This changes only the state; the credentials stay in Azure. The 4.x plan of
   `compositions/azure` then shows no change to them.

2. Apply `compositions/azure`.

3. Apply this composition once with `import_federated_credentials = true`. The
   plan shows each credential as imported. The names are the same as 3.x made
   (`<namespace>-<service account>`), so each import finds its credential.

4. Remove `import_federated_credentials`, or set it back to `false`.

If step 1 was skipped, the credentials are gone after step 2 and the import
fails with "Cannot import non-existent remote object". Apply without
`import_federated_credentials` instead.

## Tests

```bash
terraform init -backend=false
terraform test
```

`tests/cluster.tftest.hcl` plans against mocked providers: one credential per
service account, a namespace other than `autoheal`, a cluster without the OIDC
issuer (stops), a cluster without the CSI add-on (warns), a null `federation`
and a malformed identity ID (both stop). They pass on Terraform 1.9 and
OpenTofu 1.11.
