# How the mixin keeps each sample with the right Pod

A resource review is useful when every CPU, memory, restart, and out-of-memory sample stays with the Pod that produced it. Each Pod object has one lifetime; this document calls that lifetime a Pod execution. Kubernetes gives every Pod object a [Pod UID](https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#uids), a unique ID that changes when a replacement Pod reuses the same name.

[Grafana](https://grafana.com/docs/grafana/latest/dashboards/) turns the saved metrics into the dashboard. Before Grafana reads the history, the mixin saves each Pod UID with its workload details. [Prometheus recording rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/) do this work by running [PromQL](https://prometheus.io/docs/prometheus/latest/querying/basics/), the Prometheus query language, at regular intervals. Each result becomes a new [time series](https://prometheus.io/docs/prometheus/latest/querying/basics/) with one metric name and one exact set of labels. Those labels are key-value details such as the Pod UID, container, and image ID.

## Follow one sample from Kubernetes to Grafana

To save those labels, the mixin reads two sources. [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics) reads Kubernetes objects and exposes their current fields as Prometheus metrics. [cAdvisor](https://github.com/google/cadvisor) measures CPU, memory, and out-of-memory events for running containers, and the [kubelet](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/) on each node exposes those container metrics. The recording rules bring the two sources together in this order:

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

`resource_review:workload_revision_pod_info` comes first. It follows the Kubernetes owners and records the workload, revision, Pod UID, and node. A revision groups the Pods from one Deployment update or one Job run. In the fallback cases described below, each Pod UID becomes its own revision. Next, `resource_review:workload_revision_pod_container_info` joins `kube_pod_container_info` and adds the container, configured image, and immutable `image_id`.

With the Pod and container labels saved, the other recording rules use [PromQL vector matching](https://prometheus.io/docs/prometheus/latest/querying/operators/#vector-matching-keywords) to attach them to CPU, memory, and event metrics. `on(...)` tells Prometheus which labels must match, and `group_left(...)` copies the extra labels from the saved Pod details. A [`namespace`](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) is the Kubernetes scope that contains the Pod. cAdvisor metrics match on the configured cluster label, `namespace`, `pod`, and `container`. They then receive `workload_type`, `workload`, `revision`, `revision_source`, `uid`, `node`, `image`, and `image_id`. kube-state-metrics container metrics already carry the Pod UID, so those matches also use `uid`.

Prometheus runs these dependent recording rules together in one rule group every minute. It evaluates them in order at the same timestamp, so each CPU, memory, or event rule can use the Pod and container labels recorded just before it. Grafana reads the resulting `resource_review:*` series across the selected time range. Because the labels are already stored, an old sample keeps its original Pod UID after Kubernetes removes that Pod and creates another one with the same name.

## What each query must keep attached

Once the recording rules attach these labels, every dashboard query depends on them. After a query change, these should still be the results:

1. **Each revision stays separate.** When a query combines several series, it keeps `revision` or another label that separates one immutable Pod execution from another.
2. **Each event stays with its Pod UID.** Restart and out-of-memory metrics receive `uid` while the matching Pod details are available, so a later Pod with the same name receives its own history.
3. **Each cluster stays separate.** Every multi-cluster join and summary keeps the configured cluster label.
4. **Each exact image stays separate.** Revision summaries keep both `image`, the configured image name, and `image_id`, the exact image content that the container used.
5. **An empty value still means no data.** A missing series stays empty, while a measured zero appears as `0`.
6. **A difference uses the values beside it.** The query subtracts the same request and usage values that the dashboard shows next to the difference.
7. **The query calculates each Pod first.** It finds the percentiles and maximums for each immutable Pod execution before it summarizes a revision. For example, p95 is the value that 95 percent of samples stayed at or below.
8. **The panel shows what happened.** It explains the recorded values and leaves the decision about requests and limits to the reviewer.

## How the mixin chooses a revision

The first item in that list depends on how the mixin finds a revision. It starts with Kubernetes [owner references](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/), fields that name the object managing a Pod or another Kubernetes object. Different workload controllers connect their Pods through different owners, so the recording rule checks several patterns.

A [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) creates a [ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/), which keeps the requested number of matching Pods running. The mixin uses the ReplicaSet name as the revision, so Pods from separate Deployment updates stay in separate rows.

A [Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/) runs Pods until a task completes, while a [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) creates Jobs on a schedule. For a CronJob or another controller that creates Jobs, the mixin uses the Job name as the revision. That choice keeps Pods from one Job together and separates them from the next Job.

The table also covers several other owners. A [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) gives its Pods stable names, a [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) places Pods on matching nodes, and a [static Pod](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/) is managed directly by the kubelet on one node. A [custom controller](https://kubernetes.io/docs/concepts/architecture/controller/) uses the Kubernetes API to manage its own kind of object.

For each owner chain, the table shows the revision and the `revision_source` label that tells you which owner or Pod field supplied it:

| Pod owner path | Workload | Revision | `revision_source` |
|---|---|---|---|
| Deployment → ReplicaSet → Pod | Deployment | ReplicaSet name | `replicaset` |
| Custom controller → ReplicaSet → Pod | Custom controller | ReplicaSet name | `replicaset` |
| CronJob or custom controller → Job → Pod | Top-level controller | Job name | `job_name` |
| Standalone ReplicaSet → Pod | ReplicaSet | ReplicaSet name | `replicaset_name` |
| StatefulSet, DaemonSet, or standalone Job | Direct owner | Pod UID | `pod_uid` |
| Static Pod | Pod name | Pod UID | `pod_uid` |
| Other controller or direct Pod | Direct owner or Pod | Pod UID | `pod_uid` |

For the fallback rows in the table, the mixin uses the Pod UID as the revision. Every Pod execution has its own UID, even when a later Pod reuses the same name, so samples from separate executions stay apart. One logical rollout may therefore appear as several revision rows.

## Why the complete labels create more series

Those separate UIDs, revisions, clusters, and images also determine how many series Prometheus stores. Prometheus creates a separate series for every distinct label set, so each container metric family has this approximate upper bound:

```text
clusters × retained Pod executions × containers × immutable image identities
```

The [Prometheus retention period](https://prometheus.io/docs/prometheus/latest/storage/#operational-aspects) tells Prometheus how long to keep samples. A longer period keeps more short-lived Job executions, and each one adds series with its own complete set of labels. Before you deploy the mixin across a fleet, count those series in a cluster that resembles the clusters where you plan to use it.

- Count the series produced by the recording rules at the workload scale you expect.
- Select one namespace and workload for each Grafana review.
- Keep Prometheus samples for the same length of time that you need to review.
- Store the metrics in a separate system that can answer Prometheus queries when you need a long history from many clusters.

Even when the count is high, historical event series still need `uid`, `revision`, the configured cluster label, `image`, and `image_id`. Those labels keep one Pod, cluster, revision, or image from receiving another one's data. To store fewer series, shorten the retention period or deploy the mixin to fewer clusters.

## How the tests catch a broken join or dashboard

Because every saved label affects the history, a small query change can move data to the wrong Pod or merge two revisions. This project writes the recording rules and dashboard in [Jsonnet](https://jsonnet.org/learning/tutorial.html), a configuration language that generates JSON and YAML from reusable code. `rules/resource-review.libsonnet` defines the recording rules, and `dashboards/resource-review.libsonnet` defines the Grafana dashboard.

`make validate` checks the source and generated files on the local machine. It checks Jsonnet formatting, tests changes to configuration values, runs the Prometheus rule tests, and parses the PromQL used by the dashboard. It also checks the panel layout, applies automated style checks to the dashboard, and validates each generated Kubernetes object against an [OpenAPI schema](https://kubernetes.io/docs/concepts/overview/kubernetes-api/#openapi-interface-definition), which lists its allowed fields and value types. The command completes all of these checks without creating a Kubernetes cluster.

`make check-generated` renders the Jsonnet into a temporary directory and compares the result with the committed JSON and YAML. If the comparison finds a change, edit the Jsonnet source and regenerate the files.

`make integration-test` then checks the same work in a real Kubernetes cluster. It creates an isolated [kind](https://kind.sigs.k8s.io/) cluster, which runs Kubernetes nodes in local containers. The command also installs the pinned [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) [Helm chart](https://helm.sh/docs/topics/charts/). A Helm chart packages the Prometheus, Grafana, and kube-state-metrics settings and Kubernetes resources that the test needs.

The test keeps two Deployment revisions alive at the same time, reads real cAdvisor and kube-state-metrics data, and runs a live 30-day query. The Grafana [sidecar](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/) is a container that runs beside Grafana and [loads the dashboard](https://grafana.com/docs/grafana/latest/administration/provisioning/). The test confirms that the sidecar reads the dashboard JSON from a [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/), a Kubernetes object that stores configuration data.

When the test finishes, the script removes the cluster. Set `KEEP_CLUSTER=true` to leave the cluster running when you need to inspect a failure.
