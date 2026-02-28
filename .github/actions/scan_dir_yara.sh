#!/usr/bin/env bash
set -euo pipefail

scan_path="${SCAN_PATH:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_rules_dir="$(cd "${script_dir}/../../.security/yara" && pwd)"
rules_dir="${RULES_DIR:-${default_rules_dir}}"
scan_label="${SCAN_LABEL:-target}"
exclude_git="${EXCLUDE_GIT:-false}"
exclude_rules_dir="${EXCLUDE_RULES_DIR:-false}"
yara_image="${YARA_IMAGE:-alpine:3.20}"

if [[ -z "${scan_path}" || ! -d "${scan_path}" ]]; then
  echo "SCAN_PATH must point to an existing directory."
  exit 1
fi
if [[ -z "${rules_dir}" || ! -d "${rules_dir}" ]]; then
  echo "RULES_DIR must point to an existing directory."
  exit 1
fi

echo "Running YARA scan on ${scan_label}..."
docker run --rm \
  --entrypoint /bin/sh \
  -e EXCLUDE_GIT="${exclude_git}" \
  -e EXCLUDE_RULES_DIR="${exclude_rules_dir}" \
  -v "${scan_path}:/scan:ro" \
  -v "${rules_dir}:/rules:ro" \
  "${yara_image}" \
  -lc '
    set -e
    apk add --no-cache yara >/dev/null
    cat /rules/basic-malware.yar /rules/webshell-and-cryptominer.yar > /tmp/all-rules.yar

    if [ "${EXCLUDE_GIT}" = "true" ] && [ "${EXCLUDE_RULES_DIR}" = "true" ]; then
      find /scan -type f ! -path "/scan/.git/*" ! -path "/scan/.security/yara/*" -print0 > /tmp/yara-targets.txt
    elif [ "${EXCLUDE_GIT}" = "true" ]; then
      find /scan -type f ! -path "/scan/.git/*" -print0 > /tmp/yara-targets.txt
    elif [ "${EXCLUDE_RULES_DIR}" = "true" ]; then
      find /scan -type f ! -path "/scan/.security/yara/*" -print0 > /tmp/yara-targets.txt
    else
      find /scan -type f -print0 > /tmp/yara-targets.txt
    fi

    : > /tmp/yara-matches.txt
    while IFS= read -r -d "" target; do
      scan_out="$(yara /tmp/all-rules.yar "${target}" 2>/tmp/yara.err)" || {
        cat /tmp/yara.err
        exit 1
      }
      if [ -n "${scan_out}" ]; then
        printf "%s\n" "${scan_out}" >> /tmp/yara-matches.txt
      fi
    done < /tmp/yara-targets.txt

    if [ -s /tmp/yara-matches.txt ]; then
      cat /tmp/yara-matches.txt
      echo "YARA failed: suspicious pattern matches found."
      exit 1
    fi
  '
echo "YARA passed on ${scan_label}."
