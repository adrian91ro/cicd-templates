#!/usr/bin/env bash
set -euo pipefail

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

build_target_image_ref() {
  local source_image="$1"
  local registry_host="$2"
  local registry_repository="$3"
  local mirror_path_prefix="$4"

  local image_without_digest source_digest source_tag source_name first_component
  local source_registry source_repo source_registry_path target_tag target_ref

  image_without_digest="${source_image}"
  source_digest=""
  if [[ "${source_image}" == *@* ]]; then
    source_digest="${source_image#*@}"
    image_without_digest="${source_image%@*}"
  fi

  if [[ "${image_without_digest##*/}" == *:* ]]; then
    source_tag="${image_without_digest##*:}"
    source_name="${image_without_digest%:*}"
  else
    source_tag="latest"
    source_name="${image_without_digest}"
  fi

  first_component="${source_name%%/*}"
  if [[ "${source_name}" == */* ]] && { [[ "${first_component}" == *.* ]] || [[ "${first_component}" == *:* ]] || [[ "${first_component}" == "localhost" ]]; }; then
    source_registry="${first_component,,}"
    source_repo="${source_name#*/}"
  else
    source_registry="docker.io"
    source_repo="${source_name}"
    if [[ "${source_repo}" != */* ]]; then
      source_repo="library/${source_repo}"
    fi
  fi

  source_repo="${source_repo,,}"
  if [[ -n "${source_digest}" ]]; then
    target_tag="sha256-${source_digest#sha256:}"
  else
    target_tag="${source_tag}"
  fi

  source_registry_path="${source_registry//:/-}"
  source_registry_path="${source_registry_path//[^a-z0-9._-]/-}"
  source_repo="${source_repo//[^a-z0-9._\/-]/-}"
  target_tag="${target_tag//[^A-Za-z0-9_.-]/-}"

  target_ref="${registry_host}/${registry_repository}/${mirror_path_prefix}/${source_registry_path}/${source_repo}:${target_tag}"
  printf '%s' "${target_ref}"
}

image_refs_input="${IMAGE_REFS:-}"
registry_host="${REGISTRY_HOST:-}"
registry_repository="${REGISTRY_REPOSITORY:-}"
mirror_path_prefix="${MIRROR_PATH_PREFIX:-helm-chart-images}"

if [[ -z "${image_refs_input}" ]]; then
  echo "IMAGE_REFS is required."
  exit 1
fi
if [[ -z "${registry_host}" ]]; then
  echo "REGISTRY_HOST is required."
  exit 1
fi
if [[ -z "${registry_repository}" ]]; then
  echo "REGISTRY_REPOSITORY is required."
  exit 1
fi

mirror_path_prefix="${mirror_path_prefix#/}"
mirror_path_prefix="${mirror_path_prefix%/}"
mirror_path_prefix="${mirror_path_prefix,,}"
if [[ -z "${mirror_path_prefix}" ]]; then
  echo "MIRROR_PATH_PREFIX is empty after normalization."
  exit 1
fi

declare -A seen_source_refs=()
declare -A seen_target_refs=()
declare -a source_refs=()
declare -a target_refs=()
declare -a image_map=()

while IFS= read -r raw_source_ref; do
  source_ref="$(trim "${raw_source_ref}")"
  if [[ -z "${source_ref}" ]]; then
    continue
  fi
  if [[ -n "${seen_source_refs[${source_ref}]:-}" ]]; then
    continue
  fi
  seen_source_refs["${source_ref}"]=1
  source_refs+=("${source_ref}")
done <<< "${image_refs_input}"

if [[ "${#source_refs[@]}" -eq 0 ]]; then
  echo "No source image references were provided."
  exit 1
fi

for source_ref in "${source_refs[@]}"; do
  target_ref="$(build_target_image_ref "${source_ref}" "${registry_host}" "${registry_repository}" "${mirror_path_prefix}")"
  image_map+=("${source_ref}|${target_ref}")
  if [[ -z "${seen_target_refs[${target_ref}]:-}" ]]; then
    seen_target_refs["${target_ref}"]=1
    target_refs+=("${target_ref}")
  fi
done

{
  echo "source_image_refs<<EOF"
  printf '%s\n' "${source_refs[@]}"
  echo "EOF"
  echo "target_image_refs<<EOF"
  printf '%s\n' "${target_refs[@]}"
  echo "EOF"
  echo "image_map<<EOF"
  printf '%s\n' "${image_map[@]}"
  echo "EOF"
  echo "image_refs<<EOF"
  printf '%s\n' "${target_refs[@]}"
  echo "EOF"
} >> "${GITHUB_OUTPUT}"

echo "Resolved ${#source_refs[@]} source image reference(s) and ${#target_refs[@]} target mirror reference(s)."
