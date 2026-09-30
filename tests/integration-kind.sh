#!/usr/bin/env bash

set -euo pipefail

KIND=${KIND:-kind}
KUBECTL=${KUBECTL:-kubectl}
HELM=${HELM:-helm}
DOCKER=${DOCKER:-docker}
CURL=${CURL:-curl}
JQ=${JQ:-jq}
CLUSTER_NAME=${CLUSTER_NAME:-resource-review-mixin}
KIND_NODE_IMAGE=${KIND_NODE_IMAGE:-kindest/node:v1.36.1}
KUBE_PROMETHEUS_STACK_VERSION=${KUBE_PROMETHEUS_STACK_VERSION:-91.4.0}
KEEP_CLUSTER=${KEEP_CLUSTER:-false}
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
port_forward_pids=()

cleanup() {
  for pid in "${port_forward_pids[@]}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
  if [[ "$KEEP_CLUSTER" != true ]]; then
    "$KIND" delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if "$KIND" get clusters | grep --fixed-strings --line-regexp --quiet "$CLUSTER_NAME"; then
  echo "Refusing to replace existing kind cluster: $CLUSTER_NAME" >&2
  exit 1
fi

wait_for_query() {
  local query=$1
  local description=$2
  local minimum=$3
  local response value

  for _ in $(seq 1 90); do
    response=$("$CURL" --get --silent --show-error \
      --data-urlencode "query=$query" \
      http://127.0.0.1:19090/api/v1/query || true)
    value=$("$JQ" -r '.data.result[0].value[1] // "0"' <<<"$response" 2>/dev/null || printf '0')
    if awk -v value="$value" -v minimum="$minimum" 'BEGIN { exit !(value >= minimum) }'; then
      echo "Verified: $description ($value)"
      return 0
    fi
    sleep 10
  done

  echo "Timed out waiting for: $description" >&2
  return 1
}

wait_for_query_value() {
  local query=$1
  local description=$2
  local expected=$3
  local response value

  for _ in $(seq 1 90); do
    response=$("$CURL" --get --silent --show-error \
      --data-urlencode "query=$query" \
      http://127.0.0.1:19090/api/v1/query || true)
    value=$("$JQ" -r '.data.result[0].value[1] // ""' <<<"$response" 2>/dev/null || true)
    if awk -v value="$value" -v expected="$expected" 'BEGIN { exit !(value == expected) }'; then
      echo "Verified: $description ($value)"
      return 0
    fi
    sleep 10
  done

  echo "Timed out waiting for: $description (expected $expected, got ${value:-no result})" >&2
  return 1
}

wait_for_query_max() {
  local query=$1
  local description=$2
  local maximum=$3
  local response value

  for _ in $(seq 1 90); do
    response=$("$CURL" --get --silent --show-error \
      --data-urlencode "query=$query" \
      http://127.0.0.1:19090/api/v1/query || true)
    value=$("$JQ" -r '.data.result[0].value[1] // ""' <<<"$response" 2>/dev/null || true)
    if awk -v value="$value" -v maximum="$maximum" 'BEGIN { exit !(value != "" && value <= maximum) }'; then
      echo "Verified: $description ($value <= $maximum)"
      return 0
    fi
    sleep 10
  done

  echo "Timed out waiting for: $description (maximum $maximum, got ${value:-no result})" >&2
  return 1
}

if ! kind_output=$("$KIND" create cluster --name "$CLUSTER_NAME" --image "$KIND_NODE_IMAGE" --wait 120s --retain 2>&1); then
  printf '%s\n' "$kind_output" >&2
  node_logs=$("$DOCKER" logs "${CLUSTER_NAME}-control-plane" 2>&1 || true)
  if [[ "$node_logs" == *"Too many open files"* ]]; then
    cat >&2 <<'EOF'
kind could not start systemd because the host exhausted its inotify instances.
Increase fs.inotify.max_user_instances (for example to 512), then rerun the test.
EOF
  fi
  exit 1
fi
printf '%s\n' "$kind_output"
"$DOCKER" pull busybox:1.36
"$KIND" load docker-image busybox:1.36 --name "$CLUSTER_NAME"

"$HELM" upgrade --install kube-prometheus-stack \
  oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
  --version "$KUBE_PROMETHEUS_STACK_VERSION" \
  --namespace monitoring \
  --create-namespace \
  --wait \
  --timeout 15m \
  --set alertmanager.enabled=false \
  --set defaultRules.create=false \
  --set prometheus-node-exporter.enabled=false \
  --set grafana.sidecar.dashboards.folderAnnotation=grafana_folder \
  --set grafana.sidecar.dashboards.provider.foldersFromFilesStructure=true \
  --set-string grafana.env.GF_AUTH_ANONYMOUS_ENABLED=true \
  --set-string grafana.env.GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer \
  --set prometheus.prometheusSpec.retention=31d \
  --set prometheus.prometheusSpec.scrapeInterval=15s \
  --set prometheus.prometheusSpec.evaluationInterval=15s

"$KUBECTL" apply --server-side --dry-run=server -f "$ROOT_DIR/manifests/prometheus-rule.yaml"
"$KUBECTL" apply --server-side --dry-run=server -f "$ROOT_DIR/manifests/dashboard-configmap.yaml"
"$KUBECTL" apply -f "$ROOT_DIR/manifests/prometheus-rule.yaml"
"$KUBECTL" apply -f "$ROOT_DIR/manifests/dashboard-configmap.yaml"
"$KUBECTL" apply -f "$ROOT_DIR/tests/fixtures/review-workload.yaml"
"$KUBECTL" -n resource-review-test rollout status deployment/review-sample --timeout=3m

# A deliberately unready v2 Pod keeps the v1 ReplicaSet alive. The dashboard
# must preserve both ReplicaSet identities instead of merging the rollout.
"$KUBECTL" -n resource-review-test set env deployment/review-sample REVISION=v2
for _ in $(seq 1 60); do
  pod_count=$("$KUBECTL" -n resource-review-test get pods -l app=review-sample --no-headers 2>/dev/null | wc -l)
  if [[ "$pod_count" -ge 3 ]]; then
    break
  fi
  sleep 2
done
if [[ "${pod_count:-0}" -lt 3 ]]; then
  echo "Expected old and new ReplicaSets to run concurrently" >&2
  exit 1
fi

grafana_password=$("$KUBECTL" -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 --decode)
"$KUBECTL" -n monitoring port-forward service/kube-prometheus-stack-grafana 13000:80 \
  >"$ROOT_DIR/.integration-grafana-port-forward.log" 2>&1 &
port_forward_pids+=("$!")
for _ in $(seq 1 60); do
  if "$CURL" --silent --fail --user "admin:$grafana_password" \
    http://127.0.0.1:13000/api/dashboards/uid/learnk8s-resource-review 2>/dev/null \
    | grep --quiet '"uid":"learnk8s-resource-review"'; then
    break
  fi
  sleep 2
done
dashboard_response=$("$CURL" --silent --fail --user "admin:$grafana_password" \
  http://127.0.0.1:13000/api/dashboards/uid/learnk8s-resource-review)
"$JQ" -e '
  .dashboard.title == "Kubernetes Resource Review"
  and .meta.folderTitle == "Kubernetes"
' <<<"$dashboard_response" >/dev/null
echo 'Verified: Grafana sidecar provisioned the dashboard in the Kubernetes folder'

"$KUBECTL" -n monitoring port-forward service/kube-prometheus-stack-prometheus 19090:9090 \
  >"$ROOT_DIR/.integration-port-forward.log" 2>&1 &
port_forward_pids+=("$!")
for _ in $(seq 1 60); do
  if "$CURL" --silent --fail http://127.0.0.1:19090/-/ready >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
"$CURL" --silent --fail http://127.0.0.1:19090/-/ready >/dev/null

wait_for_query \
  'count(count by (revision) (resource_review:workload_revision_pod_container_info{namespace="resource-review-test",workload="review-sample"}))' \
  'two workload revisions remain distinct' \
  2
wait_for_query_value \
  'count(count by (revision) (resource_review:workload_revision_pod_container_info{namespace="resource-review-test",workload="review-sample"}) == 2)' \
  'the original revision retains both replicas' \
  1
wait_for_query_value \
  'count(count by (revision) (resource_review:workload_revision_pod_container_info{namespace="resource-review-test",workload="review-sample"}) == 1)' \
  'the unready revision remains a separate replica' \
  1
wait_for_query_value \
  'count(resource_review:container_cpu_usage_cores:rate5m{namespace="resource-review-test",workload="review-sample"})' \
  'five-minute CPU evidence exists for every concurrent Pod execution' \
  3
wait_for_query_value \
  'count(max_over_time(resource_review:container_cpu_usage_cores:rate5m{namespace="resource-review-test",workload="review-sample"}[30d]))' \
  'the 30-day observation query executes against retained evidence' \
  3
wait_for_query_value \
  'count(max_over_time(resource_review:container_cpu_throttled_periods:ratio_rate5m{namespace="resource-review-test",workload="review-sample"}[5m]) > 0)' \
  'CPU throttling is recorded for every constrained replica' \
  3
wait_for_query \
  'max(resource_review:container_restarts_total{namespace="resource-review-test",workload="failure-sample"})' \
  'the controlled failure causes a container restart' \
  1
wait_for_query_max \
  'count({__name__=~"resource_review:.*"}) / count(resource_review:workload_revision_pod_container_info)' \
  'the active recording-rule series budget stays bounded per container' \
  22

echo "Integration passed on Kubernetes ${KIND_NODE_IMAGE#*:} with kube-prometheus-stack $KUBE_PROMETHEUS_STACK_VERSION"
