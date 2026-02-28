#!/usr/bin/env bash
set -euo pipefail

registry_host="${REGISTRY_HOST:-}"
registry_repository="${REGISTRY_REPOSITORY:-}"
image_name="${IMAGE_NAME:-}"
image_tag="${IMAGE_TAG:-}"
require_registry_repository="${REQUIRE_REGISTRY_REPOSITORY:-false}"

if [[ -z "${registry_host}" ]]; then
  echo "REGISTRY_HOST is required."
  exit 1
fi
if [[ -z "${image_name}" ]]; then
  echo "IMAGE_NAME is required."
  exit 1
fi
if [[ -z "${image_tag}" ]]; then
  image_tag="${GITHUB_SHA}"
fi

registry_repository="${registry_repository#/}"
registry_repository="${registry_repository%/}"

if [[ "${require_registry_repository}" == "true" ]] && [[ -z "${registry_repository}" ]]; then
  echo "REGISTRY_REPOSITORY is required for this workflow (example: docker-local or docker-local/my-team)."
  exit 1
fi

if [[ -n "${registry_repository}" ]]; then
  image_ref="${registry_host}/${registry_repository}/${image_name}:${image_tag}"
else
  image_ref="${registry_host}/${image_name}:${image_tag}"
fi

{
  echo "image_ref=${image_ref}"
} >> "${GITHUB_OUTPUT}"

echo "Resolved image reference: ${image_ref}"
