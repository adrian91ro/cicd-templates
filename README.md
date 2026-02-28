# cicd-templates

Reusable GitHub Actions templates for container CI/CD and security.

## Reusable workflows

- `.github/workflows/reusable-container-security-scan.yml`
  Purpose: scans source and image with Hadolint, ClamAV, YARA, and Trivy.
- `.github/workflows/reusable-build-and-push-artifactory.yml`
  Purpose: builds an image from `Containerfile`/`Dockerfile` and pushes one or more tags to Artifactory.
- `.github/workflows/reusable-build-and-push-from-release-tag.yml`
  Purpose: thin reusable wrapper that builds and pushes from a semantic release tag.
- `.github/workflows/reusable-helm-chart-mirror-scan-and-push.yml`
  Purpose: pulls a Helm chart, resolves required container images, scans them (Trivy + ClamAV + YARA), and mirrors them to Artifactory.
- `.github/workflows/reusable-create-semantic-version-release.yml`
  Purpose: calculates semantic version from PR template checkboxes, creates a tag, creates a GitHub release, and marks it as latest.
- `.github/workflows/reusable-create-release-and-dispatch-container-build.yml`
  Purpose: creates semantic release and dispatches a tag-scoped container build workflow in the consumer repository.
- `.github/workflows/create-semantic-version-release.yml`
  Purpose: repository workflow for `cicd-templates` that automatically creates semantic version tags/releases on `main` branch pushes.

## Shared action scripts

- `.github/actions/*`: shell helpers and a composite action wrapper used by reusable workflows.
- `.security/yara/*`: YARA rule set used by malware stages.

## Quality gate

- `.github/workflows/template-quality-gate.yml`
  - Validates workflow syntax (`actionlint`)
  - Validates shell syntax and best practices (`bash -n`, `shellcheck`)
  - Validates YARA rule syntax

## Runner requirements

- Linux runner
- Docker daemon access (`/var/run/docker.sock`)

## Consumer repository variables

Recommended repo/org variables for reusable workflows:

- `ARTIFACTORY_CONTAINER_REPO` (example: `docker-local/my-team`)
- `ARTIFACTORY_CONTAINER_REGISTRY_HOST` (example: `artifactory.example.com`)
- `ARTIFACTORY_HELM_REPO` (example: `helm-local/my-team`)
- `ARTIFACTORY_HELM_REGISTRY_HOST` (example: `artifactory.example.com`)
- `CI_CONTAINER_IMAGE_NAME` (example: `my-service`)
- `CI_IMAGE_TAG` (optional, defaults to `github.sha`)
- `CI_PREBUILT_IMAGE_REF` (optional, security scan pull mode)
- `CI_HADOLINT_IMAGE` (optional)
- `CI_HELM_IMAGE` (optional)
- `CI_CLAMAV_IMAGE` (optional)
- `CI_YARA_IMAGE` (optional)
- `CI_TRIVY_IMAGE` (optional)

Security image defaults when variables are unset:

- Hadolint: `hadolint/hadolint:v2.12.0`
- Helm: `alpine/helm:3.17.1`
- ClamAV: `clamav/clamav:stable`
- YARA runtime: `alpine:3.20`
- Trivy: `aquasec/trivy:0.57.1`

## Consumer repository secrets

Required for Artifactory push workflow:

- `ARTIFACTORY_CONTAINER_REGISTRY_HOST` (or `ARTIFACTORY_HELM_REGISTRY_HOST` for Helm mirror)
- `ARTIFACTORY_USERNAME`
- `ARTIFACTORY_TOKEN`

For reliability across repositories, map required secrets explicitly in consumer wrappers:
- semantic release wrapper: `release_api_token: ${{ secrets.RELEASE_API_TOKEN }}`
- build/push wrapper: `artifactory_registry_host`, `artifactory_username`, `artifactory_token`

`ARTIFACTORY_CONTAINER_REPO` is required for container push workflows (for example `docker-local` or `docker-local/my-team`).
`ARTIFACTORY_HELM_REPO` is required for Helm mirror workflows.
Registry host and repository are split by design:
- host example: `artifactory.apopx.online`
- repo example: `docker-local`

When calling the reusable workflow, map them to:

- `artifactory_registry_host`
- `artifactory_registry_repository`
- `artifactory_username`
- `artifactory_token`

Optional for semantic release workflows:

- `RELEASE_API_TOKEN` (falls back to `GITHUB_TOKEN` when unset)

Use `RELEASE_API_TOKEN` (PAT) when downstream workflow dispatch must always trigger.

## Environment mapping (development vs production)

You can set `deployment_environment` when calling the reusable push workflow.
Recommended mapping:

- `main` -> `production`
- non-`main` branches -> `development`

This allows environment protection rules, reviewers, and environment-level variables in the consumer repository.
For reusable workflows, pass secrets explicitly from the caller workflow.

## Example: non-main security scan

```yaml
name: Container Security CI

on:
  push:
    branches-ignore: [main]
    tags-ignore: ["*"]
    paths: ["Containerfile", "Dockerfile"]

permissions:
  contents: read

jobs:
  container_security_scan:
    uses: adrian91ro/cicd-templates/.github/workflows/reusable-container-security-scan.yml@latest
```

## Example: create release and dispatch tag build

```yaml
name: Create New Release

on:
  push:
    branches: [main]

permissions:
  actions: write
  contents: write
  pull-requests: read

jobs:
  create_new_release:
    uses: adrian91ro/cicd-templates/.github/workflows/reusable-create-release-and-dispatch-container-build.yml@latest
    secrets:
      release_api_token: ${{ secrets.RELEASE_API_TOKEN }}
```

## Example: build and push from release tag (dispatched, no inputs)

```yaml
name: Build and Push Container Image

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build_and_push:
    uses: adrian91ro/cicd-templates/.github/workflows/reusable-build-and-push-from-release-tag.yml@latest
    secrets:
      artifactory_registry_host: ${{ secrets.ARTIFACTORY_CONTAINER_REGISTRY_HOST }}
      artifactory_registry_repository: ${{ secrets.ARTIFACTORY_CONTAINER_REPO }}
      artifactory_username: ${{ secrets.ARTIFACTORY_USERNAME }}
      artifactory_token: ${{ secrets.ARTIFACTORY_TOKEN }}
```

The build workflow resolves the release tag from `github.ref_name`. When dispatched by the release workflow, it automatically runs on the created semantic tag.

## Example: mirror Helm chart images to Artifactory

```yaml
name: Helm Chart Mirror

on:
  push:
    branches: [master]

permissions:
  contents: read

jobs:
  helm_chart_mirror:
    uses: adrian91ro/cicd-templates/.github/workflows/reusable-helm-chart-mirror-scan-and-push.yml@latest
    with:
      helm_repo_name: bitnami
      helm_repo_url: https://charts.bitnami.com/bitnami
      helm_chart_name: nginx
      mirror_path_prefix: helm-chart-images
      deployment_environment: production
    secrets:
      artifactory_registry_host: ${{ secrets.ARTIFACTORY_HELM_REGISTRY_HOST }}
      artifactory_registry_repository: ${{ secrets.ARTIFACTORY_HELM_REPO }}
      artifactory_username: ${{ secrets.ARTIFACTORY_USERNAME }}
      artifactory_token: ${{ secrets.ARTIFACTORY_TOKEN }}
```

This workflow renders chart manifests, resolves all `image:` references, scans each image, and pushes mirrored tags to Artifactory.

Note: trigger definitions (`on:`) must stay in each consumer repository; reusable workflows cannot define caller triggers.

## Latest template tag

`cicd-templates` maintains a moving Git tag named `latest` on each semantic release created from the `main` branch.
Consumer repositories can reference reusable workflows using `@latest`.

## Version pinning recommendation

For stronger supply-chain control, pin `uses:` references to immutable commit SHAs instead of a moving branch.
