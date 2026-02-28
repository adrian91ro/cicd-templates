#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

helm_repo_name="$(trim "${HELM_REPO_NAME:-}")"
helm_repo_url="$(trim "${HELM_REPO_URL:-}")"
helm_chart_name="$(trim "${HELM_CHART_NAME:-}")"
helm_chart_version="$(trim "${HELM_CHART_VERSION:-}")"
helm_image="$(trim "${HELM_IMAGE:-alpine/helm:3.17.1}")"
helm_registry_host_raw="$(trim "${HELM_REGISTRY_HOST:-}")"
helm_repository="$(trim "${HELM_REPOSITORY:-}")"
helm_push_mode="$(trim "${HELM_PUSH_MODE:-auto}")"
artifactory_username="$(trim "${ARTIFACTORY_USERNAME:-}")"
artifactory_token="$(trim "${ARTIFACTORY_TOKEN:-}")"

if [[ -z "${helm_repo_name}" ]]; then
  echo "HELM_REPO_NAME is required."
  exit 1
fi
if [[ -z "${helm_repo_url}" ]]; then
  echo "HELM_REPO_URL is required."
  exit 1
fi
if [[ -z "${helm_chart_name}" ]]; then
  echo "HELM_CHART_NAME is required."
  exit 1
fi
if [[ -z "${helm_registry_host_raw}" ]]; then
  echo "HELM_REGISTRY_HOST is required (for example: artifactory.example.com)."
  exit 1
fi
if [[ -z "${helm_repository}" ]]; then
  echo "HELM_REPOSITORY is required (for example: helm-local)."
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

helm_push_mode="${helm_push_mode,,}"
if [[ "${helm_push_mode}" != "auto" && "${helm_push_mode}" != "http" && "${helm_push_mode}" != "oci" ]]; then
  echo "HELM_PUSH_MODE must be one of: auto, http, oci."
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

pull_cmd=(helm pull "${helm_repo_name}/${helm_chart_name}" --destination /out)
if [[ -n "${helm_chart_version}" ]]; then
  pull_cmd+=(--version "${helm_chart_version}")
fi

helm_pull_script="set -euo pipefail; \
helm repo add $(printf '%q ' "${helm_repo_name}" "${helm_repo_url}") >/dev/null; \
helm repo update >/dev/null; \
mkdir -p /out; \
$(printf '%q ' "${pull_cmd[@]}") >/dev/null"

echo "Pulling Helm chart package '${helm_repo_name}/${helm_chart_name}'..."
docker run --rm \
  --entrypoint /bin/sh \
  -v "${tmp_dir}:/out" \
  "${helm_image}" \
  -lc "${helm_pull_script}"

chart_package_path="$(find "${tmp_dir}" -maxdepth 1 -type f -name "${helm_chart_name}-*.tgz" | sort | tail -n 1 || true)"
if [[ -z "${chart_package_path}" || ! -f "${chart_package_path}" ]]; then
  echo "Failed to locate Helm chart package after pull."
  exit 1
fi

chart_package_file="$(basename "${chart_package_path}")"
echo "Resolved chart package: ${chart_package_file}"

host_no_scheme="${helm_registry_host_raw#https://}"
host_no_scheme="${host_no_scheme#http://}"
host_no_scheme="${host_no_scheme%/}"
base_url="${helm_registry_host_raw%/}"
if [[ "${base_url}" != http://* && "${base_url}" != https://* ]]; then
  base_url="https://${base_url}"
fi
base_url="${base_url%/}"

if [[ "${base_url}" == */artifactory || "${base_url}" == */artifactory/* ]]; then
  artifactory_base_url="${base_url}"
else
  artifactory_base_url="${base_url}/artifactory"
fi

push_mode=""
push_location=""
oci_host="${host_no_scheme%%/*}"
resolved_push_mode="${helm_push_mode}"
repo_package_type=""

repo_info_url="${artifactory_base_url}/api/repositories/${helm_repository}"
repo_info_json="$(curl --silent --show-error --fail \
  --user "${artifactory_username}:${artifactory_token}" \
  "${repo_info_url}" 2>/dev/null || true)"
if [[ -n "${repo_info_json}" ]]; then
  repo_package_type="$(printf '%s' "${repo_info_json}" | sed -n -E 's/.*"packageType"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1)"
fi

if [[ "${resolved_push_mode}" == "auto" ]]; then
  case "${repo_package_type,,}" in
    helm)
      resolved_push_mode="http"
      ;;
    docker|oci)
      resolved_push_mode="oci"
      ;;
    *)
      resolved_push_mode="http"
      ;;
  esac
fi

if [[ "${resolved_push_mode}" == "oci" && "${host_no_scheme}" != "${oci_host}" ]]; then
  echo "HELM_REGISTRY_HOST contains a path, which is not supported for OCI login; using HTTP push instead."
  resolved_push_mode="http"
fi

if [[ "${resolved_push_mode}" == "oci" ]]; then
  echo "Pushing Helm chart package via OCI: oci://${oci_host}/${helm_repository}"
  oci_push_script='set -euo pipefail
printf "%s" "${ARTIFACTORY_TOKEN}" | helm registry login "${OCI_HOST}" --username "${ARTIFACTORY_USERNAME}" --password-stdin >/dev/null
helm push "/out/${CHART_PACKAGE_FILE}" "oci://${OCI_HOST}/${HELM_REPOSITORY}" >/dev/null'
  docker run --rm \
    --entrypoint /bin/sh \
    -e OCI_HOST="${oci_host}" \
    -e HELM_REPOSITORY="${helm_repository}" \
    -e CHART_PACKAGE_FILE="${chart_package_file}" \
    -e ARTIFACTORY_USERNAME="${artifactory_username}" \
    -e ARTIFACTORY_TOKEN="${artifactory_token}" \
    -v "${tmp_dir}:/out" \
    "${helm_image}" \
    -lc "${oci_push_script}"
  push_mode="oci"
  push_location="oci://${oci_host}/${helm_repository}/${chart_package_file}"
else
  target_url="${artifactory_base_url}/${helm_repository}/${chart_package_file}"
  echo "Pushing Helm chart package via HTTP: ${target_url}"
  response_file="${tmp_dir}/helm-upload-response.json"
  curl --silent --show-error --fail --location \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --user "${artifactory_username}:${artifactory_token}" \
    --upload-file "${chart_package_path}" \
    --output "${response_file}" \
    "${target_url}"

  download_uri="$(sed -n -E 's/.*"downloadUri"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "${response_file}" | head -n 1)"
  push_mode="http"
  if [[ -n "${download_uri}" ]]; then
    push_location="${download_uri}"
  else
    push_location="${target_url}"
  fi
fi

echo "Helm chart package pushed successfully via ${push_mode}: ${push_location}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "helm_chart_package=${chart_package_file}"
    echo "helm_chart_push_mode=${push_mode}"
    echo "helm_chart_push_location=${push_location}"
  } >> "${GITHUB_OUTPUT}"
fi
