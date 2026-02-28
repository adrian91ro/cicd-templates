#!/usr/bin/env bash
set -euo pipefail

build_file="${BUILD_FILE:-}"
hadolint_image="${HADOLINT_IMAGE:-hadolint/hadolint:v2.12.0}"
if [[ -z "${build_file}" || ! -f "${build_file}" ]]; then
  echo "BUILD_FILE must point to an existing file."
  exit 1
fi

echo "Running hadolint on ${build_file}..."
if docker run --rm -i "${hadolint_image}" < "${build_file}"; then
  echo "Hadolint passed: no issues found."
else
  echo "Hadolint failed: issues found."
  exit 1
fi
