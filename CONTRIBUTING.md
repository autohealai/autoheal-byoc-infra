# Contributing

Thanks for working on the Autoheal BYOC infrastructure. This repo has a small,
strict contract so that every module stays reusable and every release is safe to
pin. Read [docs/MODULE_STANDARD.md](docs/MODULE_STANDARD.md) first — it is the
bar every change must meet.

## The short version

1. **Branch off `main`.** You cannot push to `main` directly; it is protected.
2. **Make your change** following the module standard (naming via the shared
   label base, pinned providers, generated docs, example fixtures, no secrets).
3. **Run the checks locally** before you push (see below).
4. **Record the change** under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md).
5. **Open a pull request.** CI must pass and a code owner must approve before it
   merges. PRs are squash-merged and the branch is deleted on merge.

## Running the checks

CI runs the same gates described in `docs/MODULE_STANDARD.md` §10:

- `terraform fmt -check -recursive`
- `terraform validate` and `tflint` on modules and compositions
- a security scan (trivy)
- a docs check (terraform-docs — `README.yaml` is the source, `README.md` is
  generated; never hand-edit the generated tables)
- a `plan` on each example

Pre-commit wires most of these up:

```bash
pre-commit install
pre-commit run --all-files
```

## Versioning and releases

One semver version covers the whole repo (see `docs/MODULE_STANDARD.md` §12 and
the top of `CHANGELOG.md`):

- **MAJOR** — a breaking interface change (a consumer must edit their config).
- **MINOR** — a backward-compatible capability.
- **PATCH** — a bug fix with no interface change.

Put your entry under `## [Unreleased]`. A maintainer cuts a release by rolling
`[Unreleased]` into a dated `## [X.Y.Z]` heading and pushing the matching
`vX.Y.Z` git tag. Release tags are immutable — consumers pin them.

## Reporting security issues

Do not use issues or PRs for security problems. See [SECURITY.md](SECURITY.md).
