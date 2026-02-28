#!/usr/bin/env bash
set -euo pipefail

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

canonical_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
  else
    readlink -f "$1"
  fi
}

helm_repo_name="${HELM_REPO_NAME:-}"
helm_repo_url="${HELM_REPO_URL:-}"
helm_chart_name="${HELM_CHART_NAME:-}"
helm_chart_version="${HELM_CHART_VERSION:-}"
helm_set="${HELM_SET:-}"
helm_values_file="${HELM_VALUES_FILE:-}"
helm_values_yaml="${HELM_VALUES_YAML:-}"
helm_release_name="${HELM_RELEASE_NAME:-ci-release}"
helm_namespace="${HELM_NAMESPACE:-default}"
helm_image="${HELM_IMAGE:-alpine/helm:3.17.1}"

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

workspace="${GITHUB_WORKSPACE:-${PWD}}"
if [[ ! -d "${workspace}" ]]; then
  echo "Workspace directory does not exist: ${workspace}"
  exit 1
fi
workspace="$(canonical_path "${workspace}")"
container_values_file=""
inline_values_file=""

if [[ -n "${helm_values_file}" && -n "${helm_values_yaml}" ]]; then
  echo "Provide either HELM_VALUES_FILE or HELM_VALUES_YAML, not both."
  exit 1
fi

host_values_file=""

if [[ -n "${helm_values_yaml}" ]]; then
  inline_values_file="$(mktemp "${workspace}/.helm-inline-values.XXXXXX.yaml")"
  printf '%s\n' "${helm_values_yaml}" > "${inline_values_file}"
  host_values_file="${inline_values_file}"
elif [[ -n "${helm_values_file}" ]]; then
  host_values_file="${helm_values_file}"
  if [[ "${helm_values_file}" != /* ]]; then
    host_values_file="${workspace}/${helm_values_file}"
  fi
fi

if [[ -n "${host_values_file}" ]]; then
  if [[ ! -f "${host_values_file}" ]]; then
    alternate_values_file=""
    if [[ "${host_values_file}" == *.yaml ]]; then
      alternate_values_file="${host_values_file%.yaml}.yml"
    elif [[ "${host_values_file}" == *.yml ]]; then
      alternate_values_file="${host_values_file%.yml}.yaml"
    fi

    if [[ -n "${alternate_values_file}" && -f "${alternate_values_file}" ]]; then
      echo "HELM_VALUES_FILE '${host_values_file}' not found, using '${alternate_values_file}' instead."
      host_values_file="${alternate_values_file}"
    else
      echo "HELM_VALUES_FILE does not exist: ${host_values_file}"
      exit 1
    fi
  fi

  host_values_file="$(canonical_path "${host_values_file}")"
  if [[ "${host_values_file}" != "${workspace}"/* && "${host_values_file}" != "${workspace}" ]]; then
    echo "HELM_VALUES_FILE must be inside workspace '${workspace}': ${host_values_file}"
    exit 1
  fi

  if [[ "${host_values_file}" == "${workspace}" ]]; then
    container_values_file="/work"
  else
    container_values_file="/work/${host_values_file#"${workspace}/"}"
  fi
fi

tmp_dir="$(mktemp -d)"
manifest_file="${tmp_dir}/rendered-manifests.yaml"

cleanup() {
  if [[ -n "${inline_values_file}" ]]; then
    rm -f "${inline_values_file}" >/dev/null 2>&1 || true
  fi
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

echo "Pulling and templating chart '${helm_repo_name}/${helm_chart_name}'..."

helm_pull_cmd=(helm pull "${helm_repo_name}/${helm_chart_name}" --destination /tmp/helm-chart)
helm_template_cmd=(helm template "${helm_release_name}" "${helm_repo_name}/${helm_chart_name}" --namespace "${helm_namespace}")

if [[ -n "${helm_chart_version}" ]]; then
  helm_pull_cmd+=(--version "${helm_chart_version}")
  helm_template_cmd+=(--version "${helm_chart_version}")
fi
if [[ -n "${container_values_file}" ]]; then
  helm_template_cmd+=(-f "${container_values_file}")
fi
if [[ -n "${helm_set}" ]]; then
  IFS=',' read -r -a helm_set_entries <<< "${helm_set}"
  for raw_set_entry in "${helm_set_entries[@]}"; do
    set_entry="$(trim "${raw_set_entry}")"
    if [[ -z "${set_entry}" ]]; then
      continue
    fi
    helm_template_cmd+=(--set "${set_entry}")
  done
fi

helm_script="set -euo pipefail; \
helm repo add $(printf '%q ' "${helm_repo_name}" "${helm_repo_url}") >/dev/null; \
helm repo update >/dev/null; \
mkdir -p /tmp/helm-chart; \
$(printf '%q ' "${helm_pull_cmd[@]}") >/dev/null; \
$(printf '%q ' "${helm_template_cmd[@]}")"

docker run --rm \
  --entrypoint /bin/sh \
  -v "${workspace}:/work" \
  -w /work \
  "${helm_image}" \
  -lc "${helm_script}" > "${manifest_file}"

if [[ ! -s "${manifest_file}" ]]; then
  echo "Rendered manifest is empty. Cannot resolve chart images."
  exit 1
fi

raw_images="$(sed -n -E 's/^[[:space:]]*image:[[:space:]]*//p' "${manifest_file}" | sed -E 's/[[:space:]]+#.*$//' || true)"

declare -A seen=()
declare -a image_refs=()

while IFS= read -r raw_image; do
  image_ref="$(trim "${raw_image}")"
  image_ref="${image_ref#\"}"
  image_ref="${image_ref%\"}"

  if [[ -z "${image_ref}" || "${image_ref}" == "null" ]]; then
    continue
  fi

  # Skip unresolved template fragments if any survive rendering.
  if [[ "${image_ref}" == *"{{"* || "${image_ref}" == *"}}"* ]]; then
    echo "Skipping unresolved image reference: ${image_ref}"
    continue
  fi

  if [[ -n "${seen[${image_ref}]:-}" ]]; then
    continue
  fi

  seen["${image_ref}"]=1
  image_refs+=("${image_ref}")
done <<< "${raw_images}"

if [[ "${#image_refs[@]}" -eq 0 ]]; then
  echo "No container images were discovered in chart manifests."
  exit 1
fi

{
  echo "image_refs<<EOF"
  printf '%s\n' "${image_refs[@]}"
  echo "EOF"
} >> "${GITHUB_OUTPUT}"

echo "Discovered ${#image_refs[@]} chart image reference(s)."
printf ' - %s\n' "${image_refs[@]}"
