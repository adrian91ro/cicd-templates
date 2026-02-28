#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

scan_path="${SCAN_PATH:-}"
scan_label="${SCAN_LABEL:-target}"
clamav_image="${CLAMAV_IMAGE:-clamav/clamav:stable}"
clamav_db_dir="${CLAMAV_DB_DIR:-}"
clamav_skip_update="${CLAMAV_SKIP_UPDATE:-false}"

if [[ -z "${scan_path}" || ! -d "${scan_path}" ]]; then
  echo "SCAN_PATH must point to an existing directory."
  exit 1
fi

echo "Running ClamAV scan on ${scan_label}..."
docker_cmd=(
  docker run --rm
  --user 0:0
  --entrypoint /bin/sh
  -v "${scan_path}:/scan:ro"
)

if [[ -n "${clamav_db_dir}" ]]; then
  mkdir -p "${clamav_db_dir}"
  chmod 0777 "${clamav_db_dir}"
  docker_cmd+=(-v "${clamav_db_dir}:/var/lib/clamav")
fi

docker_cmd+=(
  -e "CLAMAV_SKIP_UPDATE=${clamav_skip_update}"
  "${clamav_image}"
  -lc '
    set -e
    if [ "${CLAMAV_SKIP_UPDATE:-false}" = "true" ]; then
      has_db="$(find /var/lib/clamav -maxdepth 1 -type f \( -name "*.cvd" -o -name "*.cld" -o -name "*.cud" \) | head -n 1 || true)"
      if [ -z "${has_db}" ]; then
        echo "ClamAV cache is empty; falling back to freshclam update."
        CLAMAV_SKIP_UPDATE="false"
      fi
    fi

    if [ "${CLAMAV_SKIP_UPDATE:-false}" != "true" ]; then
      if [ -f /etc/clamav/freshclam.conf ]; then
        tmp_freshclam_conf="$(mktemp)"
        grep -Ev "^[[:space:]]*NotifyClamd([[:space:]]|$)" /etc/clamav/freshclam.conf > "${tmp_freshclam_conf}"
        freshclam --stdout --config-file="${tmp_freshclam_conf}" || true
        rm -f "${tmp_freshclam_conf}"
      else
        freshclam --stdout || true
      fi
    fi
    clamscan -r --infected --no-summary /scan
  '
)

"${docker_cmd[@]}"
echo "ClamAV passed on ${scan_label}."
