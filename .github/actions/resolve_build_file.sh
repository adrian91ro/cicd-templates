#!/usr/bin/env bash
set -euo pipefail

if [[ -f Containerfile ]]; then
  build_file="Containerfile"
elif [[ -f Dockerfile ]]; then
  build_file="Dockerfile"
else
  echo "No Containerfile or Dockerfile found at repository root."
  exit 1
fi

echo "path=${build_file}" >> "${GITHUB_OUTPUT}"
echo "Selected build file: ${build_file}"
