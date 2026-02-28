#!/usr/bin/env bash
set -euo pipefail

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

image_map_input="${IMAGE_MAP:-}"

if [[ -z "${image_map_input}" ]]; then
  echo "IMAGE_MAP is required."
  exit 1
fi

declare -A seen_targets=()
declare -a target_refs=()
tag_count=0

while IFS= read -r raw_mapping; do
  mapping="$(trim "${raw_mapping}")"
  if [[ -z "${mapping}" ]]; then
    continue
  fi

  if [[ "${mapping}" != *"|"* ]]; then
    echo "Invalid mapping format (expected source|target): ${mapping}"
    exit 1
  fi

  source_ref="${mapping%%|*}"
  target_ref="${mapping#*|}"
  source_ref="$(trim "${source_ref}")"
  target_ref="$(trim "${target_ref}")"

  if [[ -z "${source_ref}" || -z "${target_ref}" ]]; then
    echo "Invalid mapping with empty source or target: ${mapping}"
    exit 1
  fi

  echo "Tagging mirrored image: ${source_ref} -> ${target_ref}"
  docker tag "${source_ref}" "${target_ref}"
  tag_count=$((tag_count + 1))

  if [[ -z "${seen_targets[${target_ref}]:-}" ]]; then
    seen_targets["${target_ref}"]=1
    target_refs+=("${target_ref}")
  fi
done <<< "${image_map_input}"

if [[ "${tag_count}" -eq 0 ]]; then
  echo "No image mappings were provided to tag."
  exit 1
fi

{
  echo "target_image_refs<<EOF"
  printf '%s\n' "${target_refs[@]}"
  echo "EOF"
  echo "image_refs<<EOF"
  printf '%s\n' "${target_refs[@]}"
  echo "EOF"
} >> "${GITHUB_OUTPUT}"

echo "Tagged ${tag_count} source-to-target mapping(s)."
