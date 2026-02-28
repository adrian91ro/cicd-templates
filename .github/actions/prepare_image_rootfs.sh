#!/usr/bin/env bash
set -euo pipefail

canonical_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
  else
    readlink -f "$1"
  fi
}

image_ref="${IMAGE_REF:-}"
if [[ -z "${image_ref}" ]]; then
  echo "IMAGE_REF is required."
  exit 1
fi

tmp_dir="$(mktemp -d)"
tmp_dir="$(canonical_path "${tmp_dir}")"
rootfs_dir="${tmp_dir}/rootfs"
container_id=""

cleanup() {
  if [[ -n "${container_id:-}" ]]; then
    docker rm -f "${container_id}" >/dev/null 2>&1 || true
  fi
  if [[ "${tmp_dir}" == /tmp/* ]]; then
    rm -rf "${tmp_dir}"
  fi
}
trap cleanup EXIT

mkdir -p "${rootfs_dir}"
container_id="$(docker create "${image_ref}")"
docker export "${container_id}" | tar -xf - -C "${rootfs_dir}"
docker rm "${container_id}" >/dev/null 2>&1 || true
container_id=""

{
  echo "rootfs_dir=${rootfs_dir}"
  echo "tmp_dir=${tmp_dir}"
} >> "${GITHUB_OUTPUT}"

trap - EXIT
