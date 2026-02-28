#!/usr/bin/env bash
set -euo pipefail

registry_host="${REGISTRY_HOST:-}"
image_ref="${IMAGE_REF:-}"
artifactory_username="${ARTIFACTORY_USERNAME:-}"
artifactory_token="${ARTIFACTORY_TOKEN:-}"

if [[ -z "${registry_host}" ]]; then
  echo "REGISTRY_HOST is required."
  exit 1
fi
if [[ -z "${image_ref}" ]]; then
  echo "IMAGE_REF is required."
  exit 1
fi
if [[ -z "${artifactory_username}" ]]; then
  echo "ARTIFACTORY_USERNAME is required."
  exit 1
fi
if [[ -z "${artifactory_token}" ]]; then
  echo "ARTIFACTORY_TOKEN is required."
  exit 1
fi

cleanup() {
  if [[ -n "${docker_config_dir:-}" && -d "${docker_config_dir}" ]]; then
    rm -rf "${docker_config_dir}"
  fi
  unset DOCKER_CONFIG || true
}
trap cleanup EXIT

docker_config_dir="$(mktemp -d)"
chmod 700 "${docker_config_dir}"
export DOCKER_CONFIG="${docker_config_dir}"

auth_b64="$(printf '%s' "${artifactory_username}:${artifactory_token}" | base64 | tr -d '\n')"
cat > "${DOCKER_CONFIG}/config.json" <<EOF
{
  "auths": {
    "${registry_host}": {
      "auth": "${auth_b64}"
    }
  }
}
EOF

docker --config "${DOCKER_CONFIG}" push "${image_ref}"
echo "Pushed image: ${image_ref}"
