# Changelog

This file tells users what changed in each release. It follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- The first [Grafana dashboard](https://grafana.com/docs/grafana/latest/dashboards/) shows CPU, memory, restarts, out-of-memory events, and Kubernetes [resource requests and limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) for the Pods created by each Deployment update or Job run.
- [Prometheus recording rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/) save the dashboard's query results with the [Pod UID](https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#uids), image, container, node, and workload that produced them.
- `make dev` creates a local [kind cluster](https://kind.sigs.k8s.io/), and `make dev-down` removes it.
- The repository uses [Jsonnet](https://jsonnet.org/) and then checks the dashboard, Kubernetes files, and their queries for mistakes.
- The dashboard includes a Cluster context control for single-cluster installations and a metric-backed Cluster picker when multi-cluster labels are configured.
- The revision review table includes throttled time, CPU and memory pressure, Kubernetes `OOMKilled` state, and observed revision age.
- The Workload Context section now shows current revision and image, replica count, revision age, requests, limits, and observation history together instead of requiring the reader to infer current rows from the historical summary.
- StormForge sponsorship is attributed in the dashboard and project documentation.

### Changed

- The dashboard now shows missing measurements and warnings first, compares Pods next, and keeps the detailed CPU and memory tables collapsed until the reader needs them.
- Pod, node, and workload names now open the matching standard Kubernetes dashboards, and [Grafonnet](https://grafana.github.io/grafonnet/) now creates the saved dashboard file.
- Missing throttled-period, throttled-time, total-memory, RSS, and cache evidence now produces explicit warnings instead of an ambiguous empty result.

### Fixed

- Old restart and out-of-memory events now stay with the Pod UID that produced them, even when Kubernetes later reuses the Pod name.
