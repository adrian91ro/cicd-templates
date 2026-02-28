#!/usr/bin/env bash
set -euo pipefail

image_ref="${IMAGE_REF:-}"
trivy_image="${TRIVY_IMAGE:-aquasec/trivy:0.57.1}"
trivy_scanners="${TRIVY_SCANNERS:-vuln,secret,misconfig}"
trivy_pkg_types="${TRIVY_PKG_TYPES:-os,library}"
trivy_severity="${TRIVY_SEVERITY:-CRITICAL,HIGH}"
trivy_ignore_unfixed="${TRIVY_IGNORE_UNFIXED:-true}"
trivy_ignore_statuses="${TRIVY_IGNORE_STATUSES:-fixed}"
trivy_cache_dir="${TRIVY_CACHE_DIR:-}"
trivy_skip_db_update="${TRIVY_SKIP_DB_UPDATE:-false}"
trivy_skip_check_update="${TRIVY_SKIP_CHECK_UPDATE:-false}"

if [[ -z "${image_ref}" ]]; then
  echo "IMAGE_REF is required."
  exit 1
fi

echo "Running Trivy scan for image: ${image_ref}"
trivy_cmd=(
  docker run --rm
  -v /var/run/docker.sock:/var/run/docker.sock
)

if [[ -n "${trivy_cache_dir}" ]]; then
  mkdir -p "${trivy_cache_dir}"
  trivy_cmd+=(-v "${trivy_cache_dir}:/trivy-cache")
fi

trivy_cmd+=(
  "${trivy_image}"
  image
  --format table
  --exit-code 1
  --scanners "${trivy_scanners}"
  --pkg-types "${trivy_pkg_types}"
  --severity "${trivy_severity}"
)

if [[ -n "${trivy_cache_dir}" ]]; then
  trivy_cmd+=(--cache-dir /trivy-cache)
fi

if [[ "${trivy_skip_db_update,,}" == "true" ]]; then
  trivy_cmd+=(--skip-db-update)
fi

if [[ "${trivy_skip_check_update,,}" == "true" ]]; then
  trivy_cmd+=(--skip-check-update)
fi

if [[ "${trivy_ignore_unfixed,,}" == "true" && -z "${trivy_ignore_statuses}" ]]; then
  trivy_cmd+=(--ignore-unfixed)
fi

if [[ -n "${trivy_ignore_statuses}" ]]; then
  IFS=',' read -r -a ignore_status_list <<< "${trivy_ignore_statuses}"
  for raw_status in "${ignore_status_list[@]}"; do
    ignore_status="${raw_status//[[:space:]]/}"
    if [[ -z "${ignore_status}" ]]; then
      continue
    fi
    trivy_cmd+=(--ignore-status "${ignore_status}")
  done
fi

trivy_cmd+=("${image_ref}")
"${trivy_cmd[@]}"
