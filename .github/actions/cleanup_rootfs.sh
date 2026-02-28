#!/usr/bin/env bash
set -euo pipefail

canonical_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
  else
    readlink -f "$1"
  fi
}

tmp_dir="${TMP_DIR:-}"
if [[ -z "${tmp_dir}" ]]; then
  echo "TMP_DIR is empty. Nothing to cleanup."
  exit 0
fi

if [[ ! -d "${tmp_dir}" ]]; then
  echo "TMP_DIR does not exist anymore: ${tmp_dir}"
  exit 0
fi

resolved_tmp="$(canonical_path "${tmp_dir}")"
if [[ "${resolved_tmp}" != /tmp/* ]]; then
  echo "Refusing to remove non-/tmp directory: ${resolved_tmp}"
  exit 1
fi

if rm -rf -- "${resolved_tmp}" 2>/dev/null; then
  echo "Removed temp directory: ${resolved_tmp}"
  exit 0
fi

echo "Direct cleanup failed for ${resolved_tmp}; attempting privileged Docker cleanup fallback."
docker run --rm \
  --user 0:0 \
  --entrypoint /bin/sh \
  -v "${resolved_tmp}:/cleanup" \
  alpine:3.20 \
  -lc '
    set -eu
    rm -rf /cleanup/* /cleanup/.[!.]* /cleanup/..?* 2>/dev/null || true
  ' >/dev/null 2>&1 || true

rmdir "${resolved_tmp}" 2>/dev/null || rm -rf -- "${resolved_tmp}" 2>/dev/null || true

if [[ -d "${resolved_tmp}" ]]; then
  echo "Warning: unable to fully remove temp directory: ${resolved_tmp}"
  exit 0
fi

echo "Removed temp directory: ${resolved_tmp}"
