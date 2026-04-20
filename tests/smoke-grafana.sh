#!/usr/bin/env bash

set -euo pipefail

DOCKER=${DOCKER:-docker}
GRAFANA_IMAGE=${GRAFANA_IMAGE:-grafana/grafana:12.2.0}
CONTAINER_NAME=${CONTAINER_NAME:-resource-review-mixin-grafana-smoke}
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if "$DOCKER" ps --all --format '{{.Names}}' | grep --fixed-strings --line-regexp --quiet "$CONTAINER_NAME"; then
  echo "Refusing to replace existing container: $CONTAINER_NAME" >&2
  exit 1
fi

cleanup() {
  "$DOCKER" stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

"$DOCKER" run --rm --detach \
  --name "$CONTAINER_NAME" \
  --env GF_AUTH_ANONYMOUS_ENABLED=true \
  --env GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer \
  --volume "$ROOT_DIR/tests/grafana/provisioning:/etc/grafana/provisioning:ro" \
  --volume "$ROOT_DIR/generated:/var/lib/grafana/dashboards:ro" \
  "$GRAFANA_IMAGE" >/dev/null

dashboard_url=http://127.0.0.1:3000/api/dashboards/uid/learnk8s-resource-review

for _ in $(seq 1 60); do
  if "$DOCKER" exec "$CONTAINER_NAME" wget --quiet --output-document=- "$dashboard_url" 2>/dev/null | grep --quiet '"uid":"learnk8s-resource-review"'; then
    break
  fi
  sleep 1
done

health=$("$DOCKER" exec "$CONTAINER_NAME" wget --quiet --output-document=- http://127.0.0.1:3000/api/health)
dashboard=$("$DOCKER" exec "$CONTAINER_NAME" wget --quiet --output-document=- "$dashboard_url")

grep --quiet '"database": "ok"' <<<"$health"
grep --quiet '"uid":"learnk8s-resource-review"' <<<"$dashboard"
grep --quiet '"title":"Kubernetes Resource Review"' <<<"$dashboard"

echo "Grafana provisioned Kubernetes Resource Review successfully from $GRAFANA_IMAGE"
