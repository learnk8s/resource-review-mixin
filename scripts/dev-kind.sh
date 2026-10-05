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
COMMAND_OUTPUT=''

cleanup() {
  if [[ -n "$chart_dir" ]]; then
    rm -f "$chart_dir/kube-prometheus-stack-$KUBE_PROMETHEUS_STACK_VERSION.tgz"
    rmdir "$chart_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

fail() {
  local message=$1
  local hint=${2:-}
  local output=${3:-}
  local status=${4:-1}
  local detail=''

  printf '❌ %s\n' "$message" >&2

  case "$output" in
    *'response status code 401'*|*'response status code 403'*|*'denied: denied'*)
      detail='The remote package source denied the request.'
      ;;
    *'permission denied while trying to connect to the Docker daemon'*|*'docker.sock: connect: permission denied'*)
      detail='Docker is running, but the current user cannot access the Docker socket.'
      ;;
    *'Cannot connect to the Docker daemon'*|*'Is the docker daemon running?'*)
      detail='The Docker daemon is not available.'
      ;;
    *'Could not resolve host'*|*'no such host'*|*'Temporary failure in name resolution'*)
      detail='DNS resolution failed.'
      ;;
    *'i/o timeout'*|*'context deadline exceeded'*|*'Client.Timeout exceeded'*)
      detail='The request timed out.'
      ;;
    *'connection refused'*|*'connect: connection refused'*)
      detail='The remote service refused the connection.'
      ;;
    *'x509:'*|*'certificate signed by unknown authority'*)
      detail='TLS certificate verification failed.'
      ;;
  esac

  if [[ -n "$detail" ]]; then
    printf '   %s\n' "$detail" >&2
  elif [[ -n "$output" ]]; then
    detail=$(printf '%s\n' "$output" | awk 'NF { line=$0 } END { print line }')
    if [[ ${#detail} -gt 240 ]]; then
      detail="${detail:0:237}..."
    fi
    [[ -z "$detail" ]] || printf '   Details: %s\n' "$detail" >&2
  fi

  [[ -z "$hint" ]] || printf '   %s\n' "$hint" >&2
  exit "$status"
}

run_or_fail() {
  local message=$1
  local hint=$2
  local status
  shift 2

  if COMMAND_OUTPUT=$("$@" 2>&1); then
    return
  else
    status=$?
  fi

  fail "$message" "$hint" "$COMMAND_OUTPUT" "$status"
}

unexpected_error() {
  local status=$?
  trap - ERR
  fail 'Development environment setup failed unexpectedly.' 'Run the command again after checking the tools listed in README.md.' '' "$status"
}
trap unexpected_error ERR

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Required command not found: $1." 'Install it and ensure it is available on PATH.'
  fi
}

for command in "$KIND" "$KUBECTL" "$HELM" "$CURL"; do
  require_command "$command"
done

run_or_fail \
  'Could not inspect local kind clusters.' \
  'Start Docker and verify that your user can access it, then retry.' \
  "$KIND" get clusters
if grep --fixed-strings --line-regexp --quiet "$CLUSTER_NAME" <<<"$COMMAND_OUTPUT"; then
  echo "♻️  Reusing kind cluster: $CLUSTER_NAME"
else
  echo "🚀 Creating kind cluster: $CLUSTER_NAME"
  run_or_fail \
    "Could not create kind cluster: $CLUSTER_NAME." \
    'Check Docker capacity and the kind node image, then retry.' \
    "$KIND" create cluster \
    --quiet \
    --name "$CLUSTER_NAME" \
    --image "$KIND_NODE_IMAGE" \
    --config "$ROOT_DIR/scripts/kind-config.yaml" \
    --wait 120s
  cluster_created=true
fi

run_or_fail \
  "Could not export kubeconfig for kind cluster: $CLUSTER_NAME." \
  'Check that the kind cluster is running and retry.' \
  "$KIND" export kubeconfig --name "$CLUSTER_NAME"

run_or_fail \
  "Could not select Kubernetes context: $CONTEXT." \
  'Check the generated kubeconfig and retry.' \
  "$KUBECTL" config use-context "$CONTEXT"

if [[ "$cluster_created" == true ]]; then
  run_or_fail \
    'Could not save development cluster metadata.' \
    'Check Kubernetes API access and retry.' \
    "$KUBECTL" --context "$CONTEXT" -n kube-system create configmap resource-review-dev-metadata \
    --from-literal="kind-node-image=$KIND_NODE_IMAGE"
else
  run_or_fail \
    'Could not verify the existing development cluster.' \
    'Check Kubernetes API access or recreate the cluster with make dev-down.' \
    "$KUBECTL" --context "$CONTEXT" -n kube-system \
    get configmap resource-review-dev-metadata \
    --ignore-not-found \
    -o jsonpath='{.data.kind-node-image}'
  installed_node_image=$COMMAND_OUTPUT
  if [[ "$installed_node_image" != "$KIND_NODE_IMAGE" ]]; then
    fail \
      'The existing kind cluster uses a different or unverified node image.' \
      'Run make dev-down, then make dev to recreate it from the pinned digest.'
  fi
fi

chart_dir=$(mktemp -d)
chart_archive="$chart_dir/kube-prometheus-stack-$KUBE_PROMETHEUS_STACK_VERSION.tgz"
echo "📦 Installing kube-prometheus-stack $KUBE_PROMETHEUS_STACK_VERSION"
run_or_fail \
  "Could not download kube-prometheus-stack $KUBE_PROMETHEUS_STACK_VERSION." \
  'Check access to the Prometheus Community Helm repository, or retry later.' \
  "$HELM" pull kube-prometheus-stack \
  --repo https://prometheus-community.github.io/helm-charts \
  --version "$KUBE_PROMETHEUS_STACK_VERSION" \
  --destination "$chart_dir"

if command -v sha256sum >/dev/null 2>&1; then
  actual_chart_sha256=$(sha256sum "$chart_archive" | awk '{ print $1 }')
else
  require_command shasum
  actual_chart_sha256=$(shasum -a 256 "$chart_archive" | awk '{ print $1 }')
fi
if [[ "$actual_chart_sha256" != "$KUBE_PROMETHEUS_STACK_SHA256" ]]; then
  fail \
    'The kube-prometheus-stack chart checksum does not match the pinned value.' \
    'Do not use the downloaded chart. Verify the configured version and checksum before retrying.' \
    "Expected $KUBE_PROMETHEUS_STACK_SHA256, received $actual_chart_sha256."
fi

run_or_fail \
  'Could not install kube-prometheus-stack.' \
  'Inspect the monitoring namespace and Helm release, then retry.' \
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
  --set prometheus.service.nodePort=30090

echo '📊 Installing the mixin and sample workload'
run_or_fail 'Could not install the Prometheus recording rules.' 'Check the PrometheusRule CRD and monitoring namespace.' \
  "$KUBECTL" --context "$CONTEXT" apply -f "$ROOT_DIR/manifests/prometheus-rule.yaml"
printf '%s\n' "$COMMAND_OUTPUT" | sed 's/^/   ↳ /'
run_or_fail 'Could not install the Grafana dashboard.' 'Check ConfigMap permissions in the monitoring namespace.' \
  "$KUBECTL" --context "$CONTEXT" apply -f "$ROOT_DIR/manifests/dashboard-configmap.yaml"
printf '%s\n' "$COMMAND_OUTPUT" | sed 's/^/   ↳ /'
run_or_fail 'Could not install the sample workload.' 'Check Kubernetes API access and the resource-review-test namespace.' \
  "$KUBECTL" --context "$CONTEXT" apply -f "$ROOT_DIR/tests/fixtures/review-workload.yaml"
printf '%s\n' "$COMMAND_OUTPUT" | sed 's/^/   ↳ /'
run_or_fail 'The sample workload did not become ready.' 'Inspect the resource-review-test Pods with kubectl.' \
  "$KUBECTL" --context "$CONTEXT" -n resource-review-test rollout status deployment/review-sample --timeout=3m
printf '%s\n' "$COMMAND_OUTPUT" | sed 's/^/   ↳ /'

wait_for_url() {
  local url=$1
  local name=$2

  for _ in $(seq 1 60); do
    if "$CURL" --silent --fail "$url" >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done

  fail \
    "Timed out waiting for $name." \
    'Inspect the monitoring Pods and services, then retry.' \
    "$url did not become ready within 60 seconds."
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
