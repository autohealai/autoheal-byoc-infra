# Security policy

## Reporting a vulnerability

If you find a security issue in this repository or in the infrastructure it
provisions, please report it privately. **Do not open a public GitHub issue or
pull request for a security problem.**

- Email: security@accelos.com
- Or use GitHub's private vulnerability reporting (the **Security** tab →
  **Report a vulnerability**) on this repository.

Please include:

- what the issue is and where (file, module, or composition),
- how to reproduce it, and
- the impact you think it has.

We will acknowledge your report, investigate, and keep you updated on the fix.

## Supported versions

Fixes land on `main` and ship in the next tagged release. Consumers should pin a
released tag (`?ref=vX.Y.Z`) and upgrade to pick up security fixes. See
[CHANGELOG.md](CHANGELOG.md) for what each release changes.

## Handling secrets

This repository must never contain secrets. Secrets live in the cloud secret
store (Azure Key Vault / AWS Secrets Manager), never in variables or state.
`detect-secrets` runs in pre-commit and secret-scanning push protection is
enabled on the repository. If you believe a secret was committed, treat it as
compromised: rotate it immediately and report as above.
