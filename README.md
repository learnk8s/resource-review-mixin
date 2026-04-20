# Kubernetes Resource Review Mixin

This repository provides a [Grafana dashboard](https://grafana.com/docs/grafana/latest/dashboards/), a page that shows collected measurements, and [Prometheus recording rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/), saved queries that Prometheus runs every minute. They follow the review process from the [Kubernetes Rightsizing book](https://learnkube.com/kubernetes-rightsizing).

The dashboard compares each [Pod](https://kubernetes.io/docs/concepts/workloads/pods/), the smallest Kubernetes unit that runs one or more [containers](https://kubernetes.io/docs/concepts/containers/), which package an application with the files it needs. It shows CPU and memory use, CPU slowdowns, restarts, out-of-memory events, and Kubernetes [resource requests and limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/), which reserve CPU or memory for a container and cap how much it may use. The dashboard shows what happened without choosing new values for you.

[Metric definitions and limitations](docs/metrics.md) explains what each value means and what it cannot tell you.

## Try it locally

`make dev` needs [Docker](https://docs.docker.com/get-started/docker-overview/), which runs containers; [kind](https://kind.sigs.k8s.io/), which creates a local Kubernetes cluster from those containers; [Helm](https://helm.sh/docs/), which installs applications in the cluster; [kubectl](https://kubernetes.io/docs/reference/kubectl/), which sends commands to Kubernetes; [curl](https://curl.se/docs/), which downloads files; and [GNU Make](https://www.gnu.org/software/make/manual/make.html), which runs the commands defined by this repository.

```bash
make dev
```

The command creates a dedicated cluster, installs Prometheus and Grafana, adds the dashboard and rules, starts a sample workload, and prints links to Grafana and Prometheus. Open **Kubernetes Resource Review** in the **Kubernetes** folder.

Run `make dev` again to update the cluster, use `make dev-open` to open Grafana in your browser, and remove the cluster with:

```bash
make dev-down
```

## Install it in a cluster

The project is tested with [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack), a Helm package that installs Prometheus, Grafana, and Kubernetes measurement collectors. Prometheus must receive Kubernetes object details from [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics) and container CPU and memory measurements from [cAdvisor](https://github.com/google/cadvisor). Check the tested versions and required measurements in [Compatibility and required metrics](docs/compatibility.md).

Review [config.libsonnet](config.libsonnet), then create and check the files:

```bash
make validate
make check-generated
```

`make validate` creates a [PrometheusRule](https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.PrometheusRule), which tells Prometheus which saved queries to run, and a [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/), which stores the dashboard for Grafana. Before saving them in the cluster, ask the [Kubernetes API server](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/), the part of Kubernetes that checks and stores cluster objects, to check them:

```bash
kubectl apply --server-side --dry-run=server -f manifests/prometheus-rule.yaml
kubectl apply --server-side --dry-run=server -f manifests/dashboard-configmap.yaml
```

The `--dry-run=server` option checks the files without saving them. If both commands pass, install the rules first and the dashboard second:

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
| `showMultiCluster` | `false` | Whether the dashboard shows a cluster picker |
| `clusterLabel` | `cluster` | The label that names each cluster when the picker is enabled |

The same file contains the optional warning colors, book link, and links to the standard Kubernetes dashboards. A warning color only draws attention to a measured value; it does not recommend a change.

## How measurements stay with the right Pod

Kubernetes can reuse a Pod name after deleting the original Pod. Before the dashboard reads the history, the recording rules add the [Pod UID](https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#uids), the unique ID Kubernetes gives one Pod, along with its workload, revision, node, container, image, and exact image ID. A revision groups the Pods created by one [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) update or one [Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/) run. These details stop an old measurement from moving to a new Pod with the same name.

The rules also keep missing, zero, and unconfigured values separate. A missing value means Prometheus received nothing, zero is a measured value, and unconfigured means the Kubernetes object did not set a request or limit. [How the mixin keeps each sample with the right Pod](docs/architecture.md) explains the queries and how each Pod is connected to the Kubernetes object that created it.

## Check a change

```bash
make validate
make check-generated
make integration-test
```

The first command creates the files and checks their format, queries, and Kubernetes fields. The second confirms that the committed files match the source. The third creates a temporary kind cluster and checks the rules and dashboard with measurements from running containers.

[Contributing](CONTRIBUTING.md) explains which commands each change needs. [Security](SECURITY.md) explains how to report a security problem without publishing its details.

## License

This project uses the [Apache License 2.0](LICENSE). [Third-party licenses](THIRD_PARTY_LICENSES.md) lists the libraries included under `vendor/`.
