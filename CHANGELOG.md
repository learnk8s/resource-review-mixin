# Changelog

This file tells users what changed in each release. It follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), a simple format that groups changes by release, and [Semantic Versioning](https://semver.org/spec/v2.0.0.html), which uses version numbers such as `1.2.3` to show whether a release breaks old settings, adds a feature, or fixes a problem.

## Unreleased

### Added

- The first [Grafana dashboard](https://grafana.com/docs/grafana/latest/dashboards/) shows CPU, memory, restarts, out-of-memory events, and Kubernetes [resource requests and limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) for the Pods created by each Deployment update or Job run.
- [Prometheus recording rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/) save the dashboard's query results with the [Pod UID](https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#uids), the unique ID Kubernetes gives one Pod, along with the image, container, node, and workload that produced them.
- `make dev` creates a local [kind cluster](https://kind.sigs.k8s.io/), which runs Kubernetes nodes in containers, and `make dev-down` removes it.
- The repository uses [Jsonnet](https://jsonnet.org/), a language that creates the dashboard and Kubernetes files from reusable source files, then checks those files and their queries for mistakes.

### Changed

- The dashboard now shows missing measurements and warnings first, compares Pods next, and keeps the detailed CPU and memory tables collapsed until the reader needs them.
- Pod, node, and workload names now open the matching standard Kubernetes dashboards, and [Grafonnet](https://grafana.github.io/grafonnet/), a Jsonnet library for building Grafana dashboards, now creates the saved dashboard file.

### Fixed

- Old restart and out-of-memory events now stay with the Pod UID that produced them, even when Kubernetes later reuses the Pod name.
