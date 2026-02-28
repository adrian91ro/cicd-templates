#!/usr/bin/env bash
set -euo pipefail

primary_image_ref="${PRIMARY_IMAGE_REF:-}"
image_refs="${IMAGE_REFS:-}"

if [[ -z "${primary_image_ref}" ]]; then
  echo "PRIMARY_IMAGE_REF is required."
  exit 1
fi
if [[ -z "${image_refs}" ]]; then
  echo "IMAGE_REFS is required."
  exit 1
fi

while IFS= read -r image_ref; do
  if [[ -z "${image_ref}" ]]; then
    continue
  fi

  if [[ "${image_ref}" == "${primary_image_ref}" ]]; then
    continue
  fi

  echo "Tagging local image: ${primary_image_ref} -> ${image_ref}"
  docker tag "${primary_image_ref}" "${image_ref}"
done <<< "${image_refs}"
