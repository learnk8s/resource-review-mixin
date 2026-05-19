# Compatibility and required metrics

The table below shows the versions covered by the project tests and gives you a tested starting point.

## Verified baseline

| Layer | Verified version | Check |
|---|---|---|
| Kubernetes API schema | 1.34.0 | Strict `kubeconform` validation for generated manifests |
| Kubernetes end to end | 1.36.1 on kind | Installation, workload rollout, server-side dry-run, and live Prometheus queries |
| `kube-prometheus-stack` | 91.4.0 | Pinned Helm chart and checksum-verified development installation |
| Prometheus | 3.14.0 | Rule syntax, rule-unit tests, dashboard PromQL, and live integration queries |
| kube-state-metrics | 2.20.0 | Live integration through kube-state-metrics chart 8.5.0 |
| Grafana | 12.2.0 and 13.2.1 | Standalone provisioning smoke test and sidecar integration |
| Jsonnet | go-jsonnet 0.22.0 | Rendering, formatting, and linting |
| Grafonnet | `v13.0.0`, commit `41e6bfcbe4ef1054298ffff8664f1354c897dd2d` | Vendored dashboard construction library |

## Check the identity metrics

After you choose the stack versions, check the metrics that tell the mixin where each sample came from. They identify the workload, revision, Pod execution, and container, so the mixin can attach the right CPU, memory, and event data to each one.

| Source | Metrics | What the mixin gets from them |
|---|---|---|
| kube-state-metrics | `kube_pod_info`, `kube_pod_container_info` | Pod UID, node, container, image, and immutable image ID |
| kube-state-metrics | `kube_pod_owner`, `kube_replicaset_owner`, `kube_job_owner` | Workload and revision owner paths |

## Check the CPU and memory metrics

Once the mixin knows which container a sample belongs to, it uses these cAdvisor metrics to show CPU and memory use.

| Source | Metrics | What the mixin gets from them |
|---|---|---|
| cAdvisor | `container_cpu_usage_seconds_total` | Five-minute CPU usage and sample coverage |
| cAdvisor | `container_memory_usage_bytes`, `container_memory_working_set_bytes` | Total memory and working-set evidence |

The mixin looks for kube-state-metrics with `job="kube-state-metrics"` and for cAdvisor with `job="kubelet", metrics_path="/metrics/cadvisor"`. If your monitoring stack uses different labels, set the matching selectors in `config.libsonnet`.

## Use the optional metrics

The following metrics add limits, throttling, pressure, failures, resource settings, and Pod age.

- **CPU limits and throttling:** `container_cpu_cfs_periods_total`, `container_cpu_cfs_throttled_periods_total`, and `container_cpu_cfs_throttled_seconds_total`. Some kubelet/cAdvisor versions omit the throttled-seconds counter while retaining the period counters; in that case the throttled-time value stays unavailable and the dashboard emits a warning.
- **CPU and memory PSI:** `container_pressure_cpu_waiting_seconds_total` and `container_pressure_memory_waiting_seconds_total`.
- **Memory detail:** `container_memory_rss` and `container_memory_cache`.
- **Failure evidence:** `container_oom_events_total`, `kube_pod_container_status_restarts_total`, `kube_pod_container_status_last_terminated_reason`, and `kube_pod_container_status_last_terminated_exitcode`.
- **Resource configuration:** `kube_pod_container_resource_requests`, `kube_pod_container_resource_limits`, and `kube_pod_status_qos_class`.
- **Pod age:** `kube_pod_created`.

When Prometheus has one of these metric families, the dashboard shows its values. When the family is absent, the value stays empty, while a measured zero still appears as `0`.

## Understand the 30-day window

As Prometheus collects these samples, retention controls how far back the dashboard can look. You can select a 30-day range in Grafana. CI parses dashboard queries with `$__range=30d`, and the integration test runs a live `[30d]` query against Prometheus with 31 days of retention.

## Check a monitoring-stack upgrade

The same checks matter when you change the monitoring stack. After an upgrade, use these steps to verify the new versions:

1. Update the pinned version and digest or checksum together.
2. Recreate the development cluster with `make dev-down && make dev`.
3. Run `make validate` and `make check-generated`.
4. Run `make integration-test` with the proposed versions.
5. Compare the raw metric labels with this document and `docs/metrics.md`.

To run the second step with different versions, pass all three values to `make dev` as in the following:

```sh
make dev-down && \
KIND_NODE_IMAGE='kindest/node:v1.35.0@sha256:<matching-kind-node-image-digest>' \
KUBE_PROMETHEUS_STACK_VERSION='<chosen-chart-version>' \
KUBE_PROMETHEUS_STACK_SHA256='<matching-chart-archive-sha256>' \
make dev
```

The image digest must match the kind node image, and the chart checksum must match the chosen `kube-prometheus-stack` version.
