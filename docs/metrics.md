# How to read the dashboard

Imagine that you open the dashboard for a Deployment called `checkout`. Three Pods are running now, but the dashboard says it observed five Pod executions during the selected week. The other two may have been replaced during a rollout, restart, or node change, and their CPU, memory, and failure history still belongs to the review.

The mixin records each Pod UID separately before it calculates revision and workload summaries.

## Check how much data you have

Before comparing CPU or memory, check the current Pod count, observed execution count, selected revision count, observed node count, shortest CPU history, and minimum sample coverage.

- **Current Pods** is the number of Pod UIDs that Kubernetes exposes now. It answers “how many Pod executions can I find at this moment?” rather than “how many replicas should exist?”

- **Observed executions** includes every immutable Pod UID found in the selected time range. Suppose `Current Pods` is 3 and `Observed executions` is 5. Two older Pod executions contributed evidence during the range but no longer exist. Keeping those executions separate prevents an old Pod's history from moving to its replacement.

- **Selected revisions** counts the revision identities in the current filter. A Deployment revision usually maps to a ReplicaSet. If two old Pods belong to `checkout-7d8f` and one new Pod belongs to `checkout-6bc4`, the dashboard reports two revisions and keeps their evidence separate.
- **Observed nodes** counts the nodes that ran the selected Pod executions. If one replica differs and it is the only row on `worker-2`, inspect CPU and memory pressure on `worker-2` and compare the other containers running there. The node count alone does not identify the cause.

- **Shortest CPU evidence** is the smallest amount of CPU history among the selected Pod executions. If the value is 20 minutes, the CPU statistics for at least one selected Pod cover only 20 minutes even when the dashboard range is seven days.

- **Minimum coverage** compares recorded samples with the one-minute samples expected during the selected window.

```text
observed duration = sample count × 60 seconds
coverage          = min(sample count / expected one-minute samples, 1)
```

If the window expects 60 samples and the least-observed replica has 45, minimum coverage is 75 percent. One quarter of the expected samples are missing. The Pod may have started late, Prometheus may have missed scrapes, a rule evaluation may have been delayed, or the backend may have downsampled the data.

## Compare Pods before reading the summary

Consider three Pods with average CPU usage of `0.10`, `0.12`, and `0.80` cores. A workload average of `0.34` cores hides the third replica. The main tables keep all three rows visible and retain the Pod, revision, node, and container that produced each value. The revision summary is calculated after these per-Pod statistics exist. When the summary needs one value, it keeps `0.80` rather than averaging the three replicas together.

## Check CPU usage, limits, and throttling

CPU usage is measured in cores, and one core means one CPU-second used during one wall-clock second. The recording rule starts with the five-minute [`rate()`](https://prometheus.io/docs/prometheus/latest/querying/functions/#rate) of cumulative CPU time:

```promql
rate(container_cpu_usage_seconds_total[5m])
```

If CPU usage spikes for a few seconds, the five-minute average makes that spike look smaller.

- **Average CPU** is the arithmetic mean of the CPU samples in the selected range. If the samples are `0.10`, `0.20`, and `0.45` cores, the average is `0.25` cores. This value does not contain the highest individual sample; read p95 and maximum CPU for that value.

- **p95 CPU** is the value that 95 percent of the recorded samples stayed at or below. If average CPU is `0.25` and p95 is `0.70`, 95 percent of the samples are at or below `0.70` cores. The highest 5 percent of samples are excluded from p95 and remain visible in Maximum CPU.

- **Maximum CPU** is the highest sampled five-minute rate in the selected range. It cannot reconstruct a shorter burst that happened between scrapes.

- **CPU request** is the amount Kubernetes uses when it schedules the Pod. The value comes from the Pod specification rather than CPU measurements. If maximum CPU is `0.60` cores and the request is `0.50` cores, the difference is `-0.10` because usage exceeded the request by one tenth of a core.

```text
difference       = request - usage statistic
difference ratio = difference / request
```

The ratio disappears when the request is missing or configured as zero.

- **CPU limit** is the container's CPU quota. The “CPU maximum / limit” bar divides the highest sampled usage by that configured value. A bar at 80 percent means the highest sampled five-minute rate reached 80 percent of the limit. It does not promise 20 percent of safe headroom because a shorter burst may be absent from the samples.

- **Throttled periods** measures how many CPU quota periods included throttling. A value of 20 percent means the Linux CPU controller stopped the container in 20 percent of the observed quota periods. A 20 percent throttled-period ratio and a 20 percent latency increase describe unrelated measurements.

- **Throttled time** measures accumulated task time stopped by the quota. Several tasks can wait at once, which can raise the rate above one second per second. Both throttling metrics prove that the quota was active, while latency, throughput, or another service-level signal must show the application impact.

- **CPU pressure** uses Pressure Stall Information, or PSI, to measure time that runnable tasks spent waiting for CPU. The [Linux PSI interface](https://docs.kernel.org/accounting/psi.html) reports waiting time without assigning a cause. Compare the same time window with CPU throttling, the CPU limit, node pressure, and application latency.

An empty panel means Prometheus received no `container_pressure_cpu_waiting_seconds_total` series matching the selected labels; run the raw query to confirm whether the source metric exists.

## Check memory usage and limits

The mixin records four separate cgroup memory values: total usage, working set, RSS, and cache. Compare them for the same Pod, container, and time range; they measure different parts of cgroup memory accounting.

- **Total memory** is everything charged to the container cgroup. It can include anonymous memory, file cache, and other kernel-accounted memory.

- **Working set** is commonly cAdvisor's total usage minus inactive file cache. It estimates recently active memory rather than “memory the application can never release.”

- **RSS** mainly represents resident anonymous memory. Application heaps and stacks often contribute here, but RSS is still a cgroup value rather than a language-runtime heap measurement.

- **Cache** represents file content retained for reuse, and the kernel may reclaim some of it when the node needs memory. RSS plus cache does not always equal total usage because these values come from different parts of cgroup accounting.

- **Memory request** affects scheduling, while **memory limit** is the cgroup ceiling that can lead to an OOM event when memory cannot be reclaimed. The “Memory maximum / limit” bar compares the highest sampled total memory with the configured limit. An absent bar means the limit or memory evidence is unavailable.

## Check restarts and OOM kills

If `Last terminated reason` is `OOMKilled`, the most recent recorded termination happened because the container ran out of memory. This value only describes the latest termination, and a newer termination replaces it.

`Restarts` tells you how many times the container restarted during the selected period, but it does not record the cause of each restart. `OOM events` shows how many out-of-memory events cAdvisor recorded during the same period. Check the Pod events and application logs when you need the cause of earlier restarts.

## Understand zero and empty values

`0` and an empty cell mean different things. If the throttling table shows `0`, Prometheus received the metric and measured no throttling during the selected time range. If the cell is empty, Prometheus has no matching data for that Pod and time range.

The data may be missing because the node does not expose the metric, Prometheus missed the scrape, or the Pod did not run during that period. The dashboard leaves missing data empty instead of displaying a false `0`.

The warning table explains what is missing or why a value could not be calculated:

- **CPU or memory usage unavailable:** Prometheus has no usage samples.
- **CPU or memory pressure unavailable:** the node does not expose the optional pressure metric.
- **Request or limit not configured:** the container does not have that value in its resource configuration.
- **OOM or restart counter unavailable:** Prometheus has no matching counter for the container.
- **Request is zero:** the dashboard cannot divide by zero to calculate the ratio.
- **Revision falls back to Pod UID:** the mixin could not find a shared controller revision.
- **Multiple immutable images:** one revision contains more than one image ID.
- **CPU sample coverage below 80 percent:** Prometheus collected fewer than 80 percent of the expected samples.

## Find the Pod behind each value

Every value keeps the labels that show where it came from. If one CPU or memory value looks unusual, these labels identify the exact workload, revision, Pod execution, node, container, and image:

```text
cluster
namespace
workload_type
workload
revision
revision_source
pod
uid
node
container
image
image_id
```

For example, one `checkout` container can have these labels:

```text
namespace       = shop
workload_type   = deployment
workload        = checkout
revision        = checkout-7d8f
revision_source = replicaset
pod             = checkout-7d8f-k9m2p
uid             = 2cb4...
node            = worker-2
container       = app
image           = registry.example/checkout:2.4
image_id        = registry.example/checkout@sha256:8ad1...
```

- **`cluster` and `namespace`** locate the workload in Kubernetes.
- **`workload_type` and `workload`** identify the controller, such as the `checkout` Deployment.
- **`revision`** identifies the rollout. For a Deployment, this is usually the ReplicaSet name.
- **`revision_source`** tells you how the mixin found the revision.
- **`pod` and `uid`** identify the Pod. The name is easy to read, while the UID identifies that exact Pod execution.
- **`node` and `container`** show where the container ran and which container produced the value.
- **`image` and `image_id`** show the configured image and the exact image content used by the container. Two Pods can use the same tag and still have different image IDs.

If `revision_source` is `pod_uid`, the mixin could not find a shared controller revision and used the Pod UID instead. Three Pod UIDs then appear as three revision rows, even when they belong to the same workload.

## Find the same value in Prometheus

Grafana reads the values in this dashboard from the recording rules below. You can copy a rule name into Prometheus when you want to inspect its series and add the same labels shown in Grafana to narrow the result:

```promql
resource_review:container_cpu_usage_cores:rate5m{
  namespace="shop",
  workload="checkout"
}
```

| Recording rule | Unit | What it records |
|---|---:|---|
| `resource_review:workload_revision_pod_info` | labels | Workload, revision, Pod UID, and node |
| `resource_review:workload_revision_pod_container_info` | labels | Pod labels plus container, image, and immutable image ID |
| `resource_review:workload_revision_pod_created_timestamp_seconds` | Unix seconds | Pod creation time |
| `resource_review:container_cpu_usage_cores:rate5m` | CPU cores | Average CPU use over five minutes |
| `resource_review:container_cpu_throttled_periods:ratio_rate5m` | ratio | Fraction of CPU quota periods that included throttling |
| `resource_review:container_cpu_throttled_seconds:rate5m` | seconds/second | Throttled task time per wall-clock second |
| `resource_review:container_cpu_pressure_waiting:ratio_rate5m` | ratio | Optional CPU waiting time from PSI |
| `resource_review:container_memory_usage_bytes` | bytes | Total cgroup memory |
| `resource_review:container_memory_working_set_bytes` | bytes | cAdvisor working set |
| `resource_review:container_memory_rss_bytes` | bytes | Resident anonymous memory |
| `resource_review:container_memory_cache_bytes` | bytes | File cache charged to the cgroup |
| `resource_review:container_memory_pressure_waiting:ratio_rate5m` | ratio | Optional memory waiting time from PSI |
| `resource_review:container_cpu_request_cores` | CPU cores | Configured CPU request |
| `resource_review:container_cpu_limit_cores` | CPU cores | Configured CPU limit |
| `resource_review:container_memory_request_bytes` | bytes | Configured memory request |
| `resource_review:container_memory_limit_bytes` | bytes | Configured memory limit |
| `resource_review:container_restarts_total` | counter | Restart count for the exact Pod UID and container |
| `resource_review:container_last_termination_oomkilled` | flag | Whether the latest termination reason was `OOMKilled` |
| `resource_review:container_oom_events_total` | counter | cAdvisor OOM count for the exact Pod UID and container |
| `resource_review:workload_revision_pod_container_qos_class` | label | [Kubernetes QoS class](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/) for the Pod |
| `resource_review:container_last_terminated_reason` | label | Latest known termination reason |
| `resource_review:container_last_terminated_exit_code` | exit code | Latest known terminated exit code |

The first rules identify the Pod and container. Prometheus then [evaluates the remaining rules in order](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/) and adds the same labels to the CPU, memory, restart, and OOM values.

## Check application metrics before changing resources

A low CPU or memory value does not automatically mean that you should lower the request or limit. This dashboard shows how the container used its resources.

Before changing a request or limit, note the Pod, revision, node, and time range that produced the value. Run the same workload in a load test, change one value at a time, and compare latency, throughput, and error rate before and after the change.