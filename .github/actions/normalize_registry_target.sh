#!/usr/bin/env bash
set -euo pipefail

raw_registry_host="${REGISTRY_HOST:-}"
raw_registry_repository="${REGISTRY_REPOSITORY:-}"

if [[ -z "${raw_registry_host}" ]]; then
  echo "REGISTRY_HOST is required."
  exit 1
fi

registry_host="${raw_registry_host%/}"
registry_repository="${raw_registry_repository#/}"
registry_repository="${registry_repository%/}"

# Normalize optional URL scheme if provided.
registry_host="${registry_host#https://}"
registry_host="${registry_host#http://}"

if [[ "${registry_host}" == */* ]]; then
  host_part="${registry_host%%/*}"
  host_path="${registry_host#*/}"

  if [[ -z "${registry_repository}" ]]; then
    registry_repository="${host_path}"
    echo "Derived REGISTRY_REPOSITORY from REGISTRY_HOST path: ${registry_repository}"
  else
    echo "REGISTRY_REPOSITORY provided explicitly; ignoring REGISTRY_HOST path."
  fi

  registry_host="${host_part}"
fi

if [[ -z "${registry_host}" ]]; then
  echo "Normalized REGISTRY_HOST is empty."
  exit 1
fi

{
  echo "registry_host=${registry_host}"
  echo "registry_repository=${registry_repository}"
} >> "${GITHUB_OUTPUT}"

echo "Normalized registry host: ${registry_host}"
if [[ -n "${registry_repository}" ]]; then
  echo "Normalized registry repository: ${registry_repository}"
else
  echo "Normalized registry repository: <empty>"
fi
