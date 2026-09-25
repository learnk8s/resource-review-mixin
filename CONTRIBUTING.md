# Contributing

Thank you for helping improve Kubernetes Resource Review Mixin.

## Before you change anything

The [Grafana dashboard](https://grafana.com/docs/grafana/latest/dashboards/), the page that shows the collected measurements, and the [Prometheus recording rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/), the saved queries that Prometheus repeats on a schedule, are written in [Jsonnet](https://jsonnet.org/). Jsonnet is a language that turns reusable source files into [JSON](https://www.json.org/json-en.html) and [YAML](https://yaml.org/spec/1.2.2/), two text formats that Grafana and Kubernetes can read. Change the Jsonnet source, tests, or documentation, but do not edit files in `generated/` or `manifests/` by hand because the Jsonnet source creates those files. When your change is ready, run:

```bash
make validate
make check-generated
```

`make validate` creates the JSON and YAML again, then checks the source, rules, dashboard, and Kubernetes files. `make check-generated` creates the same files in a temporary directory and confirms that they match the files in the repository. If either command finds a difference, update the Jsonnet source and run the commands again instead of fixing the created files by hand.

These commands use several command-line tools. [jsonnet](https://jsonnet.org/ref/command.html) turns Jsonnet into JSON or YAML, [jsonnetfmt](https://github.com/google/go-jsonnet/tree/master/cmd/jsonnetfmt) checks its formatting, and [jsonnet-lint](https://github.com/grafana/jsonnet-lint) finds mistakes in Jsonnet source. [promtool](https://prometheus.io/docs/prometheus/latest/command-line/promtool/) checks Prometheus rules, while [Pint](https://cloudflare.github.io/pint/) finds common mistakes in those rules. [dashboard-linter](https://github.com/grafana/dashboard-linter) checks the saved Grafana dashboard, [kubeconform](https://github.com/yannh/kubeconform) checks that the Kubernetes YAML uses allowed fields and values, and [jq](https://jqlang.org/) reads and checks JSON. [GNU Make](https://www.gnu.org/software/make/manual/make.html) connects these commands to the `make` names used above.

The repository already contains [Grafonnet](https://grafana.github.io/grafonnet/), the Jsonnet library used to build the Grafana dashboard, under `vendor/`. You only need [`jb`](https://github.com/jsonnet-bundler/jsonnet-bundler), the Jsonnet package manager, when you update Grafonnet or another library used by the project. Commit the matching changes to both `jsonnetfile.lock.json`, which records the exact library versions, and `vendor/`, which contains their source files. [GitHub Actions](https://docs.github.com/en/actions) runs the same commands automatically when someone pushes a change or opens a pull request, and [its file in this repository](.github/workflows/ci.yaml) lists the exact tool versions it uses.

Most changes only need the two checks above. A change that affects how a query connects a Pod to the Kubernetes object that created it, creates the Kubernetes YAML, loads the dashboard into Grafana, or chooses which measurements and time period to read must also pass:

```bash
make integration-test
```

This command creates a temporary [kind cluster](https://kind.sigs.k8s.io/), which is a Kubernetes cluster whose nodes run in local containers. It installs the exact [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) version listed in [Compatibility and required metrics](docs/compatibility.md). This package installs Prometheus, Grafana, and the tools that collect Kubernetes measurements. The command checks the rules and dashboard with data from that cluster, then removes the cluster when it finishes. If a check fails and you need to look inside the cluster, run it with `KEEP_CLUSTER=true` so the cluster stays available.

## When you change a Prometheus query or its labels

Before changing a query, read [How the mixin keeps each sample with the right Pod](docs/architecture.md). The dashboard uses [PromQL](https://prometheus.io/docs/prometheus/latest/querying/basics/), the Prometheus query language, to select and combine stored measurements. Prometheus stores each stream of measurements as a [time series](https://prometheus.io/docs/prometheus/latest/querying/basics/#time-series-selectors), and names and values called [labels](https://prometheus.io/docs/concepts/data_model/#metric-names-and-labels) say which cluster, Pod, container, or image produced it. Every query must keep enough of these labels to show exactly where each measurement came from.

Keep the cluster and [namespace](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/), the Kubernetes group that contains the workload. Keep the workload type and name too. The revision groups Pods from one Deployment update or one Job run, while the revision source says which Kubernetes field supplied that revision, so keep both labels. Also keep the Pod name, Pod UID, and node, along with the container name, configured image, and exact image ID. A [Pod UID](https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#uids) is the unique ID Kubernetes gives one Pod object, so it prevents a replacement Pod with the same name from receiving the old Pod's measurements.

The query must also keep missing, zero, and unconfigured values separate. A missing value means Prometheus did not receive a measurement, zero means it received a measurement whose value was `0`, and unconfigured means the Kubernetes object did not set a resource [request or limit](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/). A request tells Kubernetes how much CPU or memory to reserve for a container, while a limit caps how much the container may use. Treating these cases as the same value can make the dashboard tell the wrong story.

Add a [`promtool` rule test](https://prometheus.io/docs/prometheus/latest/configuration/unit_testing_rules/) whenever a change follows a new chain from a Pod to the Kubernetes object that owns it, adds a recording rule, matches an event to another measurement, or combines several time series into one result. If `dashboard-linter` cannot check an important panel rule, add that check to `tests/check-dashboard-structure.sh`. Every query used by a dashboard panel must also pass the test that asks Prometheus to read the query and reject invalid PromQL.

These checks protect the facts shown in the dashboard, but the wording matters too. A panel may explain the collected measurements and what they do not cover. It must not treat low use as proof that a request or limit should be reduced, and it must not tell the reader that a change is safe.

## Commit the files created from Jsonnet

Because `make validate` creates fresh output from the Jsonnet source, include its changes to these files in the same commit:

- `generated/resource-review.json`
- `generated/prometheus-rules.yaml`
- `manifests/prometheus-rule.yaml`
- `manifests/dashboard-configmap.yaml`

After you commit those files, `make check-generated` should finish without showing a difference. This confirms that someone can create the committed files from the current source.

## Open the pull request

In the pull request, describe the problem a user or operator could see, say whether the change could mix one Pod's data with another's or create more Prometheus time series, and list the commands or tests that passed. For a dashboard change, include before-and-after screenshots made from realistic sample data when you can. Leave out created files or formatting changes that do not belong to the change, because they make the useful difference harder to review.

If you add code from another project, check its license first and add the project, source link, copyright, and license to [Third-party licenses](THIRD_PARTY_LICENSES.md).

If you find a security problem, do not open a public issue. Follow the private reporting steps in [SECURITY.md](SECURITY.md) instead.
