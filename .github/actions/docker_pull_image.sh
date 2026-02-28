#!/usr/bin/env bash
set -euo pipefail

image_ref="${IMAGE_REF:-}"
if [[ -z "${image_ref}" ]]; then
  echo "IMAGE_REF is required."
  exit 1
fi

echo "Pulling image: ${image_ref}"
docker pull "${image_ref}"
