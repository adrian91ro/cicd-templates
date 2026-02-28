#!/usr/bin/env bash
set -euo pipefail

primary_image_ref="${PRIMARY_IMAGE_REF:-}"
registry_host="${REGISTRY_HOST:-}"
registry_repository="${REGISTRY_REPOSITORY:-}"
image_name="${IMAGE_NAME:-}"
additional_image_tags="${ADDITIONAL_IMAGE_TAGS:-}"

if [[ -z "${primary_image_ref}" ]]; then
  echo "PRIMARY_IMAGE_REF is required."
  exit 1
fi
if [[ -z "${registry_host}" ]]; then
  echo "REGISTRY_HOST is required."
  exit 1
fi
if [[ -z "${image_name}" ]]; then
  echo "IMAGE_NAME is required."
  exit 1
fi

registry_repository="${registry_repository#/}"
registry_repository="${registry_repository%/}"

if [[ -n "${registry_repository}" ]]; then
  base_ref="${registry_host}/${registry_repository}/${image_name}"
else
  base_ref="${registry_host}/${image_name}"
fi

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

primary_tag="${primary_image_ref##*:}"
declare -A seen=()
declare -a image_refs=()

seen["${primary_image_ref}"]=1
image_refs+=("${primary_image_ref}")

normalized_tags="$(printf '%s' "${additional_image_tags}" | tr ', ' '\n')"
while IFS= read -r raw_tag; do
  tag="$(trim "${raw_tag}")"
  if [[ -z "${tag}" ]]; then
    continue
  fi

  if [[ "${tag}" == "${primary_tag}" ]]; then
    continue
  fi

  if [[ ! "${tag}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
    echo "Invalid Docker image tag value: ${tag}"
    exit 1
  fi

  image_ref="${base_ref}:${tag}"
  if [[ -n "${seen[${image_ref}]:-}" ]]; then
    continue
  fi

  seen["${image_ref}"]=1
  image_refs+=("${image_ref}")
done <<< "${normalized_tags}"

{
  echo "image_refs<<EOF"
  printf '%s\n' "${image_refs[@]}"
  echo "EOF"
} >> "${GITHUB_OUTPUT}"

echo "Resolved image references:"
printf ' - %s\n' "${image_refs[@]}"
