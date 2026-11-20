#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELM="${HELM:-helm}"
KUBE_VERSION="${KUBE_VERSION:-v1.25.0}"

# argo cd deletes passive hook resources before the hook job finishes (#17741),
# so only the job may be a hook; its serviceaccount and rbac must be release resources.
render="$("${HELM}" template kyverno "${ROOT_DIR}/charts/kyverno" \
  --namespace kyverno --kube-version "${KUBE_VERSION}" \
  --show-only templates/hooks/post-upgrade-migrate-resources.yaml)"

hooks="$(awk '
  /^---/ { kind = "" }
  /^kind: / { kind = $2 }
  /^    helm\.sh\/hook: / { print kind }
' <<< "${render}")"

if [[ "${hooks}" != "Job" ]]; then
  printf 'Unexpected helm hook resources in migrate-resources: %s\n' "${hooks//$'\n'/ }" >&2
  exit 1
fi
for kind in ServiceAccount ClusterRole ClusterRoleBinding Job; do
  if ! grep -q "^kind: ${kind}$" <<< "${render}"; then
    printf 'Missing %s in migrate-resources\n' "${kind}" >&2
    exit 1
  fi
done
printf 'Migrate-resources hook resources verified\n'
