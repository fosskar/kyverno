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
if ! grep -q '^  name: kyverno-migrate-resources$' <<< "${render##*kind: Job}"; then
  printf 'Migrate-resources Job must have a fixed name by default\n' >&2
  exit 1
fi
printf 'Migrate-resources hook resources verified\n'

# opt-in for argo cd, which can read the status of the previous same-named job (#17741)
render="$("${HELM}" template kyverno "${ROOT_DIR}/charts/kyverno" \
  --namespace kyverno --kube-version "${KUBE_VERSION}" \
  --set crds.migration.generateName=true --set crds.migration.ttlSecondsAfterFinished=300 \
  --show-only templates/hooks/post-upgrade-migrate-resources.yaml)"
job="${render##*kind: Job}"
if ! grep -q '^  generateName: kyverno-migrate-resources-$' <<< "${job}" ||
   grep -q '^  name: ' <<< "${job}" ||
   ! grep -q '^  ttlSecondsAfterFinished: 300$' <<< "${job}"; then
  printf 'Unexpected migrate-resources Job metadata with generateName enabled\n' >&2
  exit 1
fi
printf 'Migrate-resources generateName opt-in verified\n'
