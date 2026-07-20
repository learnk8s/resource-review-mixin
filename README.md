# Kubernetes Resource Review Mixin

This repository provides a [Grafana dashboard](https://grafana.com/docs/grafana/latest/dashboards/) and [Prometheus recording rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/). They follow the review process from the [Kubernetes Rightsizing book](https://learnkube.com/kubernetes-rightsizing).

The dashboard compares each [Pod](https://kubernetes.io/docs/concepts/workloads/pods/). It shows CPU and memory use, CPU slowdowns, restarts, out-of-memory events, and Kubernetes [resource requests and limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/). The dashboard shows what happened without choosing new values for you.

[Metric definitions and limitations](docs/metrics.md) explains what each value means and what it cannot tell you.

## Dashboard Filters

- Cluster.
- Namespace.
- Workload.
- Workload revision.
- Pod.
- Container.
- Observation window.

## Dashboard Sections

### Workload Context

- Workload kind and name.
- Current revision and image.
- Replica count.
- Revision age.
- CPU and memory requests.
- CPU and memory limits.
- Available observation history.

### CPU Evidence

- CPU usage over time.
- p95 and maximum CPU usage.
- CPU request and limit.
- Difference between the request and p95 usage.
- CPU throttled-period percentage.
- CPU throttled time.
- CPU pressure when PSI metrics exist.

### Memory Evidence

- Total container memory.
- Working-set memory.
- RSS and cache.
- Maximum values for the selected period.
- Memory request and limit.
- Memory pressure when PSI metrics exist.
- cAdvisor OOM events.
- Kubernetes `OOMKilled` state.
- Container restarts.

### Replica Comparison

- Keep each pod and node visible.
- Compare usage, throttling, pressure, memory, OOM events, and restarts.
- Do not hide replica differences behind one average.

### Review Table

Show one row for each workload revision and container:

- Current requests and limits.
- CPU p95 and maximum.
- Memory maximum.
- Absolute and percentage differences from requests.
- Replica count.
- Observation duration.
- OOM, restart, throttling, and pressure signals.
- Missing evidence warnings.

## Try it locally

`make dev` needs [Docker](https://docs.docker.com/get-started/docker-overview/), [kind](https://kind.sigs.k8s.io/), [Helm](https://helm.sh/docs/), [kubectl](https://kubernetes.io/docs/reference/kubectl/), [curl](https://curl.se/docs/), and [GNU Make](https://www.gnu.org/software/make/manual/make.html).

```bash
cd resource-review-mixin
make dev

🚀 Creating kind cluster: resource-review-mixin
📦 Installing kube-prometheus-stack 91.4.0
📊 Installing the mixin and sample workload
   ↳ prometheusrule.monitoring.coreos.com/resource-review-mixin created
   ↳ configmap/resource-review-dashboard created
   ↳ namespace/resource-review-test created
   ↳ deployment.apps/review-sample created
   ↳ deployment.apps/failure-sample created
   ↳ deployment.apps/unconfigured-sample created
   ↳ Waiting for deployment "review-sample" rollout to finish: 0 of 2 updated replicas are available...
   ↳ Waiting for deployment "review-sample" rollout to finish: 1 of 2 updated replicas are available...
   ↳ deployment "review-sample" successfully rolled out

✅ Development environment is ready.
   Grafana:    http://127.0.0.1:3000/d/learnk8s-resource-review/kubernetes-resource-review
   Prometheus: http://127.0.0.1:9090
   Cluster:    resource-review-mixin (kind-resource-review-mixin)

ℹ️  Data will appear after Prometheus has collected the first samples.
🧹 Remove everything with: make dev-down

The command creates a dedicated cluster, installs Prometheus and Grafana, adds the dashboard and rules, starts a sample workload, and prints links to Grafana and Prometheus. Open **Kubernetes Resource Review** in the **Kubernetes** folder.

Run `make dev` again to update the cluster. This command keeps the existing cluster and reapplies the generated recording rules and dashboard ConfigMap.

Use `make dev-open` to open Grafana in your browser:

```bash
make dev-open
🌐 Opening Grafana in your default browser...
```

And remove the cluster with:

```bash
make dev-down
```

## Install it in a cluster

`make dev` installs [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack), including the required Prometheus Operator `PrometheusRule` CRD, in the local cluster. Before installing this project in another cluster, make sure that cluster already has the same CRD. Prometheus must receive Kubernetes object details from [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics) and container CPU and memory measurements from [cAdvisor](https://github.com/google/cadvisor). Metrics Server is not required.

CPU and memory [Pressure Stall Information (PSI)](https://docs.kernel.org/accounting/psi.html) metrics are optional. When a node or cAdvisor version does not expose them, the dashboard continues to work and shows the pressure evidence as unavailable rather than zero. Check the tested versions and required measurements in [Compatibility and required metrics](docs/compatibility.md).

`make validate` checks which tools are already available. It downloads missing tools to `.tools/bin`; it does not change system directories. Each download uses a fixed version and must match the SHA-256 checksum stored in this repository. Downloads need `curl`, `tar`, and a SHA-256 command (`sha256sum` or `shasum`). The setup also needs [GNU Make](https://www.gnu.org/software/make/manual/make.html). It supports Linux and macOS on amd64 and arm64.

Review [config.libsonnet](config.libsonnet), then create and check the files:

```bash
make validate

🔧 Checking validation tools
   ↳ Jsonnet tools: found
   ↳ promtool: found
   ↳ Pint: found
   ↳ dashboard-linter: found
   ↳ kubeconform: found
   ↳ jq: found
✅ Validation tools are ready.
🔎 Validating source and generated files
   ↳ Generating the dashboard, rules, and Kubernetes files
   ↳ Checking Jsonnet formatting
   ↳ Checking Jsonnet source
   ↳ Checking configuration variants
   ↳ Checking Prometheus rules
   ↳ Checking the dashboard JSON, queries, and panels
   ↳ Checking Kubernetes files

✅ Validation passed.
```

`make validate` recreates the dashboard, Prometheus rules, and Kubernetes files, then checks their formatting, queries, tests, and Kubernetes fields. After it passes, confirm that the committed files match the current Jsonnet source. `make check-generated` uses the same tools because it creates the files again in a temporary directory before comparing them:

```bash
make check-generated

🔧 Checking validation tools
   ↳ Jsonnet tools: found
   ↳ promtool: found
   ↳ Pint: found
   ↳ dashboard-linter: found
   ↳ kubeconform: found
   ↳ jq: found
✅ Validation tools are ready.
🔄 Checking committed generated files
✅ Committed generated files match the source
```

`make validate` creates a [PrometheusRule](https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.PrometheusRule) and a [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/). Before saving them in the cluster, ask the [Kubernetes API server](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/) to check them:

```bash
make cluster-check

🔎 Checking Kubernetes files with the API server
   ↳ PrometheusRule passed
   ↳ Dashboard ConfigMap passed

✅ Kubernetes API server check passed.
```

The command checks the files without saving them. If both files pass, install the rules first and the dashboard second:

```bash
kubectl apply -f manifests/prometheus-rule.yaml
kubectl apply -f manifests/dashboard-configmap.yaml
```

The rules begin saving measurements after installation, so the dashboard cannot show earlier Pod history.

If `kube-prometheus-stack` loads dashboards from ConfigMaps, use these Grafana settings so the dashboard appears in the **Kubernetes** folder:

```yaml
grafana:
  sidecar:
    dashboards:
      enabled: true
      folderAnnotation: grafana_folder
      provider:
        foldersFromFilesStructure: true
```

Without both folder settings, Grafana may place the dashboard in **General**.

## Change the settings

Change [config.libsonnet](config.libsonnet) before running `make validate`. These are the settings most installations need:

[Kubernetes labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/) decide which rule or dashboard file a tool reads, while [Prometheus labels](https://prometheus.io/docs/concepts/data_model/#metric-names-and-labels) decide which measurements a query reads.

| Setting | Default | What it controls |
|---|---|---|
| `namespace` | `monitoring` | Where Kubernetes stores the rule and dashboard files |
| `prometheusRuleLabels.release` | `kube-prometheus-stack` | Which Prometheus installation reads the rules |
| `dashboardConfigMapLabels.grafana_dashboard` | `1` | Which Grafana installation reads the dashboard |
| `kubeStateMetricsSelector` | `job="kube-state-metrics"` | Which kube-state-metrics measurements the rules read |
| `cadvisorSelector` | `job="kubelet", metrics_path="/metrics/cadvisor"` | Which cAdvisor measurements the rules read |
| `defaultTimeRange` | `now-7d` | The time period shown when the dashboard opens |
| `showMultiCluster` | `false` | Whether Cluster is a metric-backed multi-cluster picker instead of a named single-cluster context value |
| `clusterLabel` | `cluster` | The label that names each cluster when the picker is enabled |
| `singleClusterName` | `current-cluster` | The Cluster value shown when source metrics do not carry a cluster label |

The time picker supports observation windows up to 30 days. Prometheus must retain at least 30 days of samples for the complete window to contain data; `make dev` configures 31 days of retention. The dashboard opens with the seven-day `defaultTimeRange`, and you can select **30d** from the time picker.

The same file contains the optional warning colors, book link, and links to the standard Kubernetes dashboards. A warning color only draws attention to a measured value; it does not recommend a change.

## How measurements stay with the right Pod

Kubernetes can reuse a Pod name after deleting the original Pod. Before the dashboard reads the history, the recording rules keep the namespace, workload, revision, Pod name and [Pod UID](https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#uids), node, container, image, and exact image ID. They also keep the cluster label when the source metrics provide it. In single-cluster mode, the dashboard uses the configured Cluster name when the metrics do not have that label. A revision groups the Pods created by one [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) update or one [Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/) run. These details stop an old measurement from moving to a new Pod with the same name.

The rules also keep missing, zero, and unconfigured values separate. A missing value means Prometheus received nothing, zero is a measured value, and unconfigured means the Kubernetes object did not set a request or limit. [How the mixin keeps each sample with the right Pod](docs/architecture.md) explains the queries and how each Pod is connected to the Kubernetes object that created it.

## Check a change

```bash
make validate
make check-generated
make integration-test
```

The first command creates the files and checks their format, queries, and Kubernetes fields. The second confirms that the committed files match the source.

`make integration-test` creates its own temporary kind cluster, installs `kube-prometheus-stack` and a sample workload, checks the Prometheus rules and Grafana dashboard with data from the running containers, and removes the cluster when the test finishes.

[Contributing](CONTRIBUTING.md) explains which commands each change needs. [Security](SECURITY.md) explains how to report a security problem without publishing its details.

## License

This project uses the [Apache License 2.0](LICENSE). [Third-party licenses](THIRD_PARTY_LICENSES.md) lists the libraries included under `vendor/`.

## Sponsor

Open-source development of this project is sponsored by [StormForge](https://stormforge.io/).
