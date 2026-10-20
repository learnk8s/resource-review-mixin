# Compatibility and required metrics

This table lists the versions covered by the project tests. These versions give you a tested starting point.

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

After you choose the stack versions, check the metrics that show where each sample comes from. They identify the workload, revision, Pod execution, and container. These details help the mixin attach the right CPU, memory, and event data to each sample.

| Source | Metrics | What the mixin gets from them |
|---|---|---|
| kube-state-metrics | `kube_pod_info`, `kube_pod_container_info` | Pod UID, node, container, image, and immutable image ID |
| kube-state-metrics | `kube_pod_owner`, `kube_replicaset_owner`, `kube_job_owner` | Workload and revision owner paths |

## Check the CPU and memory metrics

After the mixin identifies a sample's container, it uses these cAdvisor metrics to show CPU and memory use.

| Source | Metrics | What the mixin gets from them |
|---|---|---|
| cAdvisor | `container_cpu_usage_seconds_total` | Five-minute CPU usage and sample coverage |
| cAdvisor | `container_memory_usage_bytes`, `container_memory_working_set_bytes` | Total memory and working-set evidence |

The mixin finds kube-state-metrics with `job="kube-state-metrics"` and cAdvisor with `job="kubelet", metrics_path="/metrics/cadvisor"`. If your monitoring stack uses other labels, update the selectors in `config.libsonnet` to match.

## Use the optional metrics

These metrics add limits, throttling, pressure, failures, resource settings, and Pod age.

- **CPU limits and throttling:** `container_cpu_cfs_periods_total`, `container_cpu_cfs_throttled_periods_total`, and `container_cpu_cfs_throttled_seconds_total`. By default, the `kube-prometheus-stack` chart drops the throttled-seconds metric from its scrape, even when kubelet provides it. Use [the included Helm values](../kube-prometheus-stack-values.yaml) to keep it. If kubelet does not provide the metric, the graph stays empty and the dashboard shows a warning.
- **CPU and memory PSI:** `container_pressure_cpu_waiting_seconds_total` and `container_pressure_memory_waiting_seconds_total`.
- **Memory detail:** `container_memory_rss` and `container_memory_cache`.
- **Failure evidence:** `container_oom_events_total`, `kube_pod_container_status_restarts_total`, `kube_pod_container_status_last_terminated_reason`, and `kube_pod_container_status_last_terminated_exitcode`.
- **Resource configuration:** `kube_pod_container_resource_requests`, `kube_pod_container_resource_limits`, and `kube_pod_status_qos_class`.
- **Pod age:** `kube_pod_created`.

If Prometheus has one of these metric families, the dashboard shows its values. If the family is missing, the value stays empty. A measured zero still appears as `0`.

## Understand the 30-day window

Retention controls how far back the dashboard can show data. In Grafana, you can choose a 30-day range. CI parses dashboard queries with `$__range=30d`. The integration test runs a live `[30d]` query against Prometheus with 31 days of retention.

## Check a monitoring-stack upgrade

The same checks apply when you change the monitoring stack. After an upgrade, use these steps to verify the new versions:

1. Update the pinned version and its digest or checksum together.
2. Recreate the development cluster with `make dev-down && make dev`.
3. Run `make validate` and `make check-generated`.
4. Run `make integration-test` with the proposed versions.
5. Compare the raw metric labels with those in this document and `docs/metrics.md`.

To use different versions in step 2, pass all three values to `make dev`:

```sh
make dev-down && \
KIND_NODE_IMAGE='kindest/node:v1.35.0@sha256:<matching-kind-node-image-digest>' \
KUBE_PROMETHEUS_STACK_VERSION='<chosen-chart-version>' \
KUBE_PROMETHEUS_STACK_SHA256='<matching-chart-archive-sha256>' \
make dev
```

Make sure that the image digest matches the kind node image. Make sure that the chart checksum matches the chosen `kube-prometheus-stack` version.
