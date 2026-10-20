# How the mixin keeps each sample with the right Pod

A resource review needs each CPU, memory, restart, and out-of-memory sample to stay with the Pod that produced it. Each Pod object has one lifetime, which this document calls a Pod execution. Kubernetes gives every Pod object a [Pod UID](https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#uids).

[Grafana](https://grafana.com/docs/grafana/latest/dashboards/) builds the dashboard from saved metrics. Before Grafana reads the history, the mixin stores each Pod UID with its workload details. [Prometheus recording rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/) use [PromQL](https://prometheus.io/docs/prometheus/latest/querying/basics/) at regular intervals to attach those details. Prometheus stores each result in a [time series](https://prometheus.io/docs/prometheus/latest/querying/basics/) with one metric name and a specific set of labels.

## Follow one sample from Kubernetes to Grafana

The mixin gets these details from two sources. [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics) reads Kubernetes objects and exposes their current fields as Prometheus metrics. [cAdvisor](https://github.com/google/cadvisor) measures CPU, memory, and out-of-memory events for containers. The [kubelet](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/) on each node exposes those container metrics. The recording rules combine the sources in this order:

```text
kube-state-metrics owners + Pod UID
                  │
                  ▼
resource_review:workload_revision_pod_info
                  │
      + container, image, and image_id
                  │
                  ▼
resource_review:workload_revision_pod_container_info
                  │
      ┌───────────┴───────────┐
      ▼                       ▼
kubelet/cAdvisor       kube-state-metrics
CPU, memory, OOM       requests, limits, events
      │                       │
      └── on(...) group_left(...) ──┘
                  │
                  ▼
       resource_review:* series
                  │
                  ▼
      Grafana range queries and tables
```

`resource_review:workload_revision_pod_info` comes first. It tracks the Kubernetes owners and records the workload, revision, Pod UID, and node. A revision groups Pods from one Deployment update or Job run. In the fallback cases described later, each Pod UID becomes its own revision. Next, `resource_review:workload_revision_pod_container_info` joins `kube_pod_container_info` and adds the container, configured image, and immutable `image_id`.

The other recording rules use [PromQL vector matching](https://prometheus.io/docs/prometheus/latest/querying/operators/#vector-matching-keywords) to attach the saved labels to CPU, memory, and event metrics. `on(...)` tells Prometheus which labels must match. `group_left(...)` copies extra labels from the saved Pod details. cAdvisor metrics match on the configured cluster label, [`namespace`](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/), `pod`, and `container`. They then receive `workload_type`, `workload`, `revision`, `revision_source`, `uid`, `node`, `image`, and `image_id`. kube-state-metrics container metrics already include the Pod UID, so those matches also use `uid`.

Prometheus evaluates these recording rules in order as one group every minute. Every rule uses the same evaluation timestamp. Each CPU, memory, or event rule can use the Pod and container labels saved just before it. Grafana reads the resulting `resource_review:*` series for the selected time range. The stored labels keep an old sample with its original Pod UID after Kubernetes replaces that Pod with another of the same name.

The restart counter joins directly to the Pod identity and keeps the container name. It omits `image` and `image_id` because Kubernetes counts restarts across image changes within the same Pod UID. Those changes must not split one cumulative counter into separate series.

## What each query must keep attached

Every dashboard query depends on these labels. After a query change, these results must still hold:

1. **Each revision stays separate.** When a query combines several series, it keeps `revision` or another label that distinguishes immutable Pod executions.
2. **Each event stays with its Pod UID.** Restart and out-of-memory metrics receive `uid` while the matching Pod details are available. A later Pod with the same name gets its own history.
3. **Each cluster stays separate.** Every multi-cluster join and summary keeps the configured cluster label.
4. **Each exact image remains identifiable.** Pod-level series and the current configuration table keep `image` and `image_id`. The final review combines a revision's images and marks that population as **Mixed images** when more than one known immutable image ID appears. Its maxima can come from different images.
5. **An empty value still means no data.** A missing series stays empty. A measured zero appears as `0`.
6. **A difference uses the values beside it.** The query subtracts the same request and usage values that the dashboard shows next to the difference.
7. **The query calculates each Pod first.** It finds percentiles and maxima for each immutable Pod execution before it summarizes a revision. For example, p95 is the value that 95 percent of samples stayed at or below.
8. **The panel shows what happened.** It explains the recorded values and lets the reviewer decide on requests and limits.

## Dashboard layout

All panels appear directly on the grid, without collapsible rows. A compact context strip comes first, followed by side-by-side CPU and memory graphs. Next come throttling, PSI, memory breakdown, and runtime activity. Tables for configuration, replica comparison, and revision review appear after the graphs.

Usage, requests, and limits keep each Pod's identity on the same axes. Memory breakdown lines overlap but are not stacked. The runtime chart uses `$__rate_interval` with a one-minute query step. This gives at least four minutes of counter history. The interval grows with the graph step so longer observation windows still capture short bursts of activity.

## How the mixin chooses a revision

Keeping revisions separate depends on how the mixin finds a revision. It starts with Kubernetes [owner references](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/). Different workload controllers connect their Pods through different owners, so the recording rule checks several patterns.

A [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) creates a [ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/). The mixin uses the ReplicaSet name as the revision. Pods from different Deployment updates therefore stay in separate rows.

For a [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) or another controller that creates [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/), the mixin uses the Job name as the revision. Pods from one Job stay together and separate from those of the next Job.

The table also includes [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/), [DaemonSets](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/), [static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/), and [custom controllers](https://kubernetes.io/docs/concepts/architecture/controller/).

For each owner chain, the table shows the revision and the `revision_source` label. That label identifies the owner or Pod field that supplied the revision:

| Pod owner path | Workload | Revision | `revision_source` |
|---|---|---|---|
| Deployment → ReplicaSet → Pod | Deployment | ReplicaSet name | `replicaset` |
| Custom controller → ReplicaSet → Pod | Custom controller | ReplicaSet name | `replicaset` |
| CronJob or custom controller → Job → Pod | Top-level controller | Job name | `job_name` |
| Standalone ReplicaSet → Pod | ReplicaSet | ReplicaSet name | `replicaset_name` |
| StatefulSet, DaemonSet, or standalone Job | Direct owner | Pod UID | `pod_uid` |
| Static Pod | Pod name | Pod UID | `pod_uid` |
| Other controller or direct Pod | Direct owner or Pod | Pod UID | `pod_uid` |

For fallback rows, the mixin uses the Pod UID as the revision. Each Pod object has its own UID, even if a replacement uses the same name. Samples from separate Pod executions therefore stay apart. As a result, one logical rollout can appear as several revision rows.

## Why the complete labels create more series

The different UIDs, revisions, clusters, and images also affect how many series Prometheus stores. Prometheus creates a separate series for each unique label set. Each container metric family therefore has this approximate upper bound:

```text
clusters × retained Pod executions × containers × immutable image identities
```

A longer [Prometheus retention period](https://prometheus.io/docs/prometheus/latest/storage/#operational-aspects) keeps more short-lived Job executions. Each one adds series with its own complete set of labels. Before you deploy the mixin across a fleet, count those series in a cluster similar to the intended production clusters.

At each evaluation timestamp, the rule group can produce up to 20 container-level series and two Pod-level identity series. Optional or unconfigured metric families produce fewer series. Retention keeps historical label sets from replaced Pods. Active-series counts alone therefore cannot estimate the complete 30-day storage cost of a cluster with frequent Pod replacements.

- Count the series produced by the recording rules at the workload scale you plan to use.
- Select one namespace and workload for each Grafana review.
- Keep Prometheus samples for the same length of time that you need to review.
- Store the metrics in a separate system that can answer Prometheus queries if you need a long history across several clusters.

Even with many series, historical event data still needs `uid`, `revision`, and the configured cluster label. OOM series also keep `image` and `image_id`. Restart counters keep one continuous series per Pod UID and container, even if the image changes. To store fewer series, shorten the retention period or deploy the mixin to fewer clusters.

## How the tests catch a broken join or dashboard

Every saved label affects the history, so a small query change can move data to the wrong Pod or combine two revisions. This project uses [Jsonnet](https://jsonnet.org/learning/tutorial.html) to define the recording rules and dashboard. `rules/resource-review.libsonnet` defines the recording rules, and `dashboards/resource-review.libsonnet` defines the Grafana dashboard.

`make validate` checks the source and generated files on the local machine. It checks Jsonnet formatting, tests changes to configuration values, runs the Prometheus rule tests, and parses the PromQL used by the dashboard. It also checks the panel layout, applies automated style checks to the dashboard, and validates each generated Kubernetes object against an [OpenAPI schema](https://kubernetes.io/docs/concepts/overview/kubernetes-api/#openapi-interface-definition). The command completes all of these checks without creating a Kubernetes cluster.

`make check-generated` renders the Jsonnet into a temporary directory and compares the result with the committed JSON and YAML. If the comparison finds a change, edit the Jsonnet source and regenerate the files.

`make integration-test` then checks the same work in a real Kubernetes cluster. It creates an isolated [kind](https://kind.sigs.k8s.io/) cluster. The command also installs the pinned [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) [Helm chart](https://helm.sh/docs/topics/charts/).

The test keeps two Deployment revisions active at the same time and uses real cAdvisor and kube-state-metrics data. It also runs a live 30-day query. The Grafana [sidecar](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/) [loads the dashboard](https://grafana.com/docs/grafana/latest/administration/provisioning/). The test confirms that the sidecar reads the dashboard JSON from a [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/).

The script removes the cluster after the test. Set `KEEP_CLUSTER=true` to keep it active when you need to inspect a failure.
