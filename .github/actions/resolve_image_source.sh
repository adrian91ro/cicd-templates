#!/usr/bin/env bash
set -euo pipefail

scan_mode="build"
if [[ -n "${PREBUILT_IMAGE_REF:-}" ]]; then
  scan_mode="pull"
  selected_image_ref="${PREBUILT_IMAGE_REF}"
else
  if [[ -z "${CONTAINER_IMAGE_NAME:-}" ]]; then
    echo "CI_CONTAINER_IMAGE_NAME variable is required when build mode is selected."
    exit 1
  fi
  selected_image_ref="${CONTAINER_IMAGE_NAME}:${GITHUB_SHA}"
fi

{
  echo "mode=${scan_mode}"
  echo "image_ref=${selected_image_ref}"
} >> "${GITHUB_OUTPUT}"

echo "Selected mode: ${scan_mode}"
echo "Selected image: ${selected_image_ref}"
