#!/usr/bin/env bash
# Build, smoke-test and (optionally) push the NaC execution environment.
#
#   ./build.sh                       # build nac-ee:<VERSION> locally and run the smoke test
#   ./build.sh push                  # ...then push to $REGISTRY (needs 'podman login' first)
#
# Env overrides:
#   VERSION   image tag              (default: contents of ./VERSION)
#   REGISTRY  e.g. ghcr.io/<github-user-or-org>   or   <name>.azurecr.io
#   RUNTIME   podman | docker        (default: podman)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-$(cat VERSION)}"
REGISTRY="${REGISTRY:-ghcr.io/CHANGE-ME}"
RUNTIME="${RUNTIME:-podman}"
IMAGE="nac-ee"
VCS_REF="$(git rev-parse --short HEAD 2>/dev/null || echo local)"

echo ">> Building ${IMAGE}:${VERSION} ($(uname -m)) with ${RUNTIME}"
ansible-builder build \
  --file execution-environment.yml \
  --context ./context \
  --container-runtime "${RUNTIME}" \
  --tag "${IMAGE}:${VERSION}" \
  --build-arg EE_VERSION="${VERSION}" \
  --build-arg VCS_REF="${VCS_REF}" \
  --verbosity 3

echo ">> Smoke test"
"${RUNTIME}" run --rm "${IMAGE}:${VERSION}" ee-smoke-test

echo ">> Saving build manifest to ./manifests/${VERSION}/"
mkdir -p "manifests/${VERSION}"
for f in pip-freeze.txt collections.yml tools.txt; do
  "${RUNTIME}" run --rm "${IMAGE}:${VERSION}" cat "/opt/ee-manifest/${f}" > "manifests/${VERSION}/${f}"
done

if [[ "${1:-}" == "push" ]]; then
  [[ "${REGISTRY}" == *CHANGE-ME* ]] && { echo "Set REGISTRY first, e.g. REGISTRY=ghcr.io/youruser"; exit 1; }
  arch="$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')"
  for t in "${VERSION}" "${VERSION}-${arch}"; do
    "${RUNTIME}" tag "${IMAGE}:${VERSION}" "${REGISTRY}/${IMAGE}:${t}"
    "${RUNTIME}" push "${REGISTRY}/${IMAGE}:${t}"
  done
  echo ">> Pushed ${REGISTRY}/${IMAGE}:${VERSION}"
  echo "   Note: a local push is single-arch (${arch}). Use the GitHub Actions workflow for the multi-arch release tag."
fi
