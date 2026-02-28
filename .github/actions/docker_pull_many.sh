#!/usr/bin/env bash
set -euo pipefail

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
image_refs_input="${IMAGE_REFS:-}"

if [[ -z "${image_refs_input}" ]]; then
  echo "IMAGE_REFS is required."
  exit 1
fi

pull_count=0
while IFS= read -r raw_image_ref; do
  image_ref="$(trim "${raw_image_ref}")"
  if [[ -z "${image_ref}" ]]; then
    continue
  fi

  IMAGE_REF="${image_ref}" bash "${script_dir}/docker_pull_image.sh"
  pull_count=$((pull_count + 1))
done <<< "${image_refs_input}"

if [[ "${pull_count}" -eq 0 ]]; then
  echo "No image references were provided to pull."
  exit 1
fi

echo "Pulled ${pull_count} image reference(s)."
