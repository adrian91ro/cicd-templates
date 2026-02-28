#!/usr/bin/env bash
set -euo pipefail

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

read_output_value() {
  local key="$1"
  local output_file="$2"
  awk -F= -v requested_key="${key}" '$1 == requested_key {print substr($0, index($0, "=") + 1)}' "${output_file}" | tail -n 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
image_refs_input="${IMAGE_REFS:-}"
clamav_image="${CLAMAV_IMAGE:-clamav/clamav:stable}"
yara_image="${YARA_IMAGE:-alpine:3.20}"
trivy_image="${TRIVY_IMAGE:-aquasec/trivy:0.57.1}"
trivy_warm_db="${TRIVY_WARM_DB:-true}"
clamav_warm_db="${CLAMAV_WARM_DB:-true}"
trivy_cache_dir=""
clamav_db_dir=""
clamav_cache_ready="false"

if [[ -z "${image_refs_input}" ]]; then
  echo "IMAGE_REFS is required."
  exit 1
fi

current_tmp_dir=""
cleanup_current_tmp_dir() {
  if [[ -n "${current_tmp_dir}" ]]; then
    TMP_DIR="${current_tmp_dir}" bash "${script_dir}/cleanup_rootfs.sh" >/dev/null 2>&1 || true
    current_tmp_dir=""
  fi
}

cleanup_scan_caches() {
  if [[ -n "${trivy_cache_dir}" ]]; then
    rm -rf "${trivy_cache_dir}" >/dev/null 2>&1 || true
    trivy_cache_dir=""
  fi
  if [[ -n "${clamav_db_dir}" ]]; then
    rm -rf "${clamav_db_dir}" >/dev/null 2>&1 || true
    clamav_db_dir=""
  fi
}

cleanup_all() {
  cleanup_current_tmp_dir
  cleanup_scan_caches
}
trap cleanup_all EXIT

trivy_cache_dir="$(mktemp -d)"
if [[ "${trivy_warm_db,,}" == "true" ]]; then
  echo "Warming Trivy vulnerability database cache once..."
  docker run --rm \
    -v "${trivy_cache_dir}:/trivy-cache" \
    "${trivy_image}" \
    image \
    --cache-dir /trivy-cache \
    --download-db-only
fi

clamav_db_dir="$(mktemp -d)"
chmod 0777 "${clamav_db_dir}"
if [[ "${clamav_warm_db,,}" == "true" ]]; then
  echo "Warming ClamAV signature database cache once..."
  docker run --rm \
    --user 0:0 \
    --entrypoint /bin/sh \
    -v "${clamav_db_dir}:/var/lib/clamav" \
    "${clamav_image}" \
    -lc '
      set -e
      if [ -f /etc/clamav/freshclam.conf ]; then
        tmp_freshclam_conf="$(mktemp)"
        grep -Ev "^[[:space:]]*NotifyClamd([[:space:]]|$)" /etc/clamav/freshclam.conf > "${tmp_freshclam_conf}"
        freshclam --stdout --config-file="${tmp_freshclam_conf}" || true
        rm -f "${tmp_freshclam_conf}"
      else
        freshclam --stdout || true
      fi
    '

  if find "${clamav_db_dir}" -maxdepth 1 -type f \( -name '*.cvd' -o -name '*.cld' -o -name '*.cud' \) | grep -q .; then
    clamav_cache_ready="true"
    echo "ClamAV cache warm-up completed and signature files were found."
  else
    echo "ClamAV cache warm-up did not produce signature files; falling back to per-scan updates."
    rm -rf "${clamav_db_dir}" >/dev/null 2>&1 || true
    clamav_db_dir=""
  fi
fi

scan_count=0
while IFS= read -r raw_source_ref; do
  source_ref="$(trim "${raw_source_ref}")"
  if [[ -z "${source_ref}" ]]; then
    continue
  fi

  echo "Scanning image: ${source_ref}"
  IMAGE_REF="${source_ref}" \
  TRIVY_IMAGE="${trivy_image}" \
  TRIVY_CACHE_DIR="${trivy_cache_dir}" \
  TRIVY_SKIP_DB_UPDATE="${trivy_warm_db}" \
  bash "${script_dir}/scan_image_trivy.sh"

  prepare_output_file="$(mktemp)"
  IMAGE_REF="${source_ref}" \
  GITHUB_OUTPUT="${prepare_output_file}" \
  bash "${script_dir}/prepare_image_rootfs.sh"

  rootfs_dir="$(read_output_value "rootfs_dir" "${prepare_output_file}")"
  current_tmp_dir="$(read_output_value "tmp_dir" "${prepare_output_file}")"
  rm -f "${prepare_output_file}"

  if [[ -z "${rootfs_dir}" || -z "${current_tmp_dir}" ]]; then
    echo "Failed to prepare image root filesystem for: ${source_ref}"
    exit 1
  fi

  SCAN_PATH="${rootfs_dir}" \
  SCAN_LABEL="image filesystem (${source_ref})" \
  CLAMAV_IMAGE="${clamav_image}" \
  CLAMAV_DB_DIR="${clamav_db_dir}" \
  CLAMAV_SKIP_UPDATE="${clamav_cache_ready}" \
  bash "${script_dir}/scan_dir_clamav.sh"

  SCAN_PATH="${rootfs_dir}" \
  SCAN_LABEL="image filesystem (${source_ref})" \
  YARA_IMAGE="${yara_image}" \
  bash "${script_dir}/scan_dir_yara.sh"

  TMP_DIR="${current_tmp_dir}" bash "${script_dir}/cleanup_rootfs.sh"
  current_tmp_dir=""

  scan_count=$((scan_count + 1))
done <<< "${image_refs_input}"

if [[ "${scan_count}" -eq 0 ]]; then
  echo "No image references were provided to scan."
  exit 1
fi

echo "Scanned ${scan_count} image reference(s) with Trivy, ClamAV, and YARA."
