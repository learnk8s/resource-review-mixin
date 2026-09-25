#!/usr/bin/env bash

set -euo pipefail

KIND=${KIND:-kind}
KUBECTL=${KUBECTL:-kubectl}
HELM=${HELM:-helm}
CURL=${CURL:-curl}
CLUSTER_NAME=${CLUSTER_NAME:-resource-review-mixin}
KIND_NODE_IMAGE=${KIND_NODE_IMAGE:-kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5}
KUBE_PROMETHEUS_STACK_VERSION=${KUBE_PROMETHEUS_STACK_VERSION:-91.4.0}
KUBE_PROMETHEUS_STACK_SHA256=${KUBE_PROMETHEUS_STACK_SHA256:-10d54f6984e5f97b2e96e64440c7c0c37af2ed1b17c1521fa6c0da3529bdeec1}
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONTEXT="kind-$CLUSTER_NAME"
chart_dir=''
cluster_created=false

cleanup() {
  if [[ -n "$chart_dir" ]]; then
    rm -f "$chart_dir/kube-prometheus-stack-$KUBE_PROMETHEUS_STACK_VERSION.tgz"
    rmdir "$chart_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

for command in "$KIND" "$KUBECTL" "$HELM" "$CURL"; do
  require_command "$command"
done

if "$KIND" get clusters | grep --fixed-strings --line-regexp --quiet "$CLUSTER_NAME"; then
  echo "♻️  Reusing kind cluster: $CLUSTER_NAME"
else
  echo "🚀 Creating kind cluster: $CLUSTER_NAME"
  "$KIND" create cluster \
    --quiet \
    --name "$CLUSTER_NAME" \
    --image "$KIND_NODE_IMAGE" \
    --config "$ROOT_DIR/scripts/kind-config.yaml" \
    --wait 120s
  cluster_created=true
fi

"$KUBECTL" config use-context "$CONTEXT" >/dev/null

if [[ "$cluster_created" == true ]]; then
  "$KUBECTL" --context "$CONTEXT" -n kube-system create configmap resource-review-dev-metadata \
    --from-literal="kind-node-image=$KIND_NODE_IMAGE" \
    >/dev/null
else
  installed_node_image=$("$KUBECTL" --context "$CONTEXT" -n kube-system \
    get configmap resource-review-dev-metadata \
    -o jsonpath='{.data.kind-node-image}' 2>/dev/null || true)
  if [[ "$installed_node_image" != "$KIND_NODE_IMAGE" ]]; then
    echo '🔒 The existing kind cluster was created with a different or unverified node image.' >&2
    echo 'Run make dev-down, then make dev to recreate it from the pinned digest.' >&2
    exit 1
  fi
fi

chart_dir=$(mktemp -d)
chart_archive="$chart_dir/kube-prometheus-stack-$KUBE_PROMETHEUS_STACK_VERSION.tgz"
echo "📦 Installing kube-prometheus-stack $KUBE_PROMETHEUS_STACK_VERSION"
"$HELM" pull \
  oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
  --version "$KUBE_PROMETHEUS_STACK_VERSION" \
  --destination "$chart_dir" \
  >/dev/null

if command -v sha256sum >/dev/null 2>&1; then
  actual_chart_sha256=$(sha256sum "$chart_archive" | awk '{ print $1 }')
else
  require_command shasum
  actual_chart_sha256=$(shasum -a 256 "$chart_archive" | awk '{ print $1 }')
fi
if [[ "$actual_chart_sha256" != "$KUBE_PROMETHEUS_STACK_SHA256" ]]; then
  echo "🔒 kube-prometheus-stack chart checksum mismatch" >&2
  echo "Expected: $KUBE_PROMETHEUS_STACK_SHA256" >&2
  echo "Actual:   $actual_chart_sha256" >&2
  exit 1
fi

"$HELM" upgrade --install kube-prometheus-stack \
  "$chart_archive" \
  --namespace monitoring \
  --create-namespace \
  --wait \
  --timeout 15m \
  --hide-notes \
  --set alertmanager.enabled=false \
  --set defaultRules.create=false \
  --set prometheus-node-exporter.enabled=false \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30000 \
  --set grafana.sidecar.dashboards.folderAnnotation=grafana_folder \
  --set grafana.sidecar.dashboards.provider.foldersFromFilesStructure=true \
  --set-string grafana.env.GF_AUTH_ANONYMOUS_ENABLED=true \
  --set-string grafana.env.GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer \
  --set prometheus.prometheusSpec.retention=31d \
  --set prometheus.prometheusSpec.scrapeInterval=15s \
  --set prometheus.prometheusSpec.evaluationInterval=15s \
  --set prometheus.service.type=NodePort \
  --set prometheus.service.nodePort=30090 \
  >/dev/null

echo '📊 Installing the mixin and sample workload'
"$KUBECTL" --context "$CONTEXT" apply -f "$ROOT_DIR/manifests/prometheus-rule.yaml" 2>&1 \
  | sed 's/^/   ↳ /'
"$KUBECTL" --context "$CONTEXT" apply -f "$ROOT_DIR/manifests/dashboard-configmap.yaml" 2>&1 \
  | sed 's/^/   ↳ /'
"$KUBECTL" --context "$CONTEXT" apply -f "$ROOT_DIR/tests/fixtures/review-workload.yaml" 2>&1 \
  | sed 's/^/   ↳ /'
"$KUBECTL" --context "$CONTEXT" -n resource-review-test \
  rollout status deployment/review-sample --timeout=3m 2>&1 \
  | sed 's/^/   ↳ /'

wait_for_url() {
  local url=$1
  local name=$2

  for _ in $(seq 1 60); do
    if "$CURL" --silent --fail "$url" >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done

  echo "Timed out waiting for $name at $url" >&2
  exit 1
}

wait_for_url 'http://127.0.0.1:3000/api/health' Grafana
wait_for_url 'http://127.0.0.1:9090/-/ready' Prometheus
wait_for_url 'http://127.0.0.1:3000/api/dashboards/uid/learnk8s-resource-review' dashboard

print_link() {
  local label=$1
  local url=$2

  if [[ -t 1 && "${TERM:-}" != dumb ]]; then
    printf '   %-11s \033]8;;%s\033\\%s\033]8;;\033\\\n' "$label" "$url" "$url"
  else
    printf '   %-11s %s\n' "$label" "$url"
  fi
}

cat <<EOF

✅ Development environment is ready.
EOF

print_link 'Grafana:' 'http://127.0.0.1:3000/d/learnk8s-resource-review/kubernetes-resource-review'
print_link 'Prometheus:' 'http://127.0.0.1:9090'

cat <<EOF
   Cluster:    $CLUSTER_NAME ($CONTEXT)

ℹ️  Data will appear after Prometheus has collected the first samples.
🧹 Remove everything with: make dev-down
EOF
