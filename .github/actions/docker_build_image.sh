#!/usr/bin/env bash
set -euo pipefail

build_file="${BUILD_FILE:-}"
image_ref="${IMAGE_REF:-}"

if [[ -z "${build_file}" || ! -f "${build_file}" ]]; then
  echo "BUILD_FILE must point to an existing file."
  exit 1
fi
if [[ -z "${image_ref}" ]]; then
  echo "IMAGE_REF is required."
  exit 1
fi

echo "Building image: ${image_ref} (file: ${build_file})"
docker build -f "${build_file}" -t "${image_ref}" .
