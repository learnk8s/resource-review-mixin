function(config)
  local ownedIdentity(ownerKind, workloadType) = |||
    label_replace(
      label_replace(
        label_replace(
          label_replace(
            max by (%(clusterLabel)s, namespace, pod, owner_name) (
              kube_pod_owner{%(kubeStateMetricsSelector)s, owner_kind="%(ownerKind)s", owner_is_controller="true"}
            )
            * on (%(clusterLabel)s, namespace, pod) group_left(uid, node)
            max by (%(clusterLabel)s, namespace, pod, uid, node) (
              kube_pod_info{%(kubeStateMetricsSelector)s}
            ),
            "workload", "$1", "owner_name", "(.+)"
          ),
          "revision", "$1", "uid", "(.+)"
        ),
        "revision_source", "pod_uid", "uid", ".+"
      ),
      "workload_type", "%(workloadType)s", "owner_name", ".+"
    )
  ||| % (config { ownerKind: ownerKind, workloadType: workloadType });

  local deploymentIdentity = |||
    label_replace(
      label_replace(
        max by (%(clusterLabel)s, namespace, pod, uid, node, workload, revision) (
          max by (%(clusterLabel)s, namespace, pod, revision) (
            label_replace(
              kube_pod_owner{%(kubeStateMetricsSelector)s, owner_kind="ReplicaSet", owner_is_controller="true"},
              "revision", "$1", "owner_name", "(.+)"
            )
          )
          * on (%(clusterLabel)s, namespace, revision) group_left(workload)
          max by (%(clusterLabel)s, namespace, revision, workload) (
            label_replace(
              label_replace(
                kube_replicaset_owner{%(kubeStateMetricsSelector)s, owner_kind="Deployment", owner_is_controller="true"},
                "revision", "$1", "replicaset", "(.+)"
              ),
              "workload", "$1", "owner_name", "(.+)"
            )
          )
          * on (%(clusterLabel)s, namespace, pod) group_left(uid, node)
          max by (%(clusterLabel)s, namespace, pod, uid, node) (
            kube_pod_info{%(kubeStateMetricsSelector)s}
          )
        ),
        "revision_source", "replicaset", "revision", ".+"
      ),
      "workload_type", "deployment", "workload", ".+"
    )
  ||| % config;

  local directPodIdentity = |||
    label_replace(
      label_replace(
        label_replace(
          label_replace(
            max by (%(clusterLabel)s, namespace, pod, uid, node) (
              kube_pod_info{%(kubeStateMetricsSelector)s}
              unless on (%(clusterLabel)s, namespace, pod)
              kube_pod_owner{%(kubeStateMetricsSelector)s, owner_is_controller="true"}
            ),
            "workload", "$1", "pod", "(.+)"
          ),
          "revision", "$1", "uid", "(.+)"
        ),
        "revision_source", "pod_uid", "uid", ".+"
      ),
      "workload_type", "pod", "pod", ".+"
    )
  ||| % config;

  local standaloneReplicaSetIdentity = |||
    label_replace(
      label_replace(
        label_replace(
          max by (%(clusterLabel)s, namespace, pod, uid, node, workload) (
            max by (%(clusterLabel)s, namespace, pod, workload) (
              label_replace(
                kube_pod_owner{%(kubeStateMetricsSelector)s, owner_kind="ReplicaSet", owner_is_controller="true"},
                "workload", "$1", "owner_name", "(.+)"
              )
              unless on (%(clusterLabel)s, namespace, workload)
              label_replace(
                kube_replicaset_owner{%(kubeStateMetricsSelector)s, owner_kind!=""},
                "workload", "$1", "replicaset", "(.+)"
              )
            )
            * on (%(clusterLabel)s, namespace, pod) group_left(uid, node)
            max by (%(clusterLabel)s, namespace, pod, uid, node) (
              kube_pod_info{%(kubeStateMetricsSelector)s}
            )
          ),
          "revision", "$1", "workload", "(.+)"
        ),
        "revision_source", "replicaset_name", "revision", ".+"
      ),
      "workload_type", "replicaset", "workload", ".+"
    )
  ||| % config;

  // ReplicaSets controlled by operators (for example, Rollouts) retain the
  // top-level controller as workload and the ReplicaSet as revision.
  local nonDeploymentReplicaSetIdentity = |||
    label_replace(
      label_replace(
        label_replace(
          max by (%(clusterLabel)s, namespace, pod, uid, node, revision, owner_kind, owner_name) (
            max by (%(clusterLabel)s, namespace, pod, revision) (
              label_replace(
                kube_pod_owner{%(kubeStateMetricsSelector)s, owner_kind="ReplicaSet", owner_is_controller="true"},
                "revision", "$1", "owner_name", "(.+)"
              )
            )
            * on (%(clusterLabel)s, namespace, revision) group_left(owner_kind, owner_name)
            max by (%(clusterLabel)s, namespace, revision, owner_kind, owner_name) (
              label_replace(
                kube_replicaset_owner{%(kubeStateMetricsSelector)s, owner_kind!="Deployment", owner_kind!=""},
                "revision", "$1", "replicaset", "(.+)"
              )
            )
            * on (%(clusterLabel)s, namespace, pod) group_left(uid, node)
            max by (%(clusterLabel)s, namespace, pod, uid, node) (
              kube_pod_info{%(kubeStateMetricsSelector)s}
            )
          ),
          "workload", "$1", "owner_name", "(.+)"
        ),
        "revision_source", "replicaset", "revision", ".+"
      ),
      "workload_type", "$1", "owner_kind", "(.+)"
    )
  ||| % config;

  // Jobs controlled by CronJobs or custom controllers use the Job name as an
  // execution revision. This keeps parallel Pods together without crossing
  // separate scheduled executions.
  local controllerJobIdentity = |||
    label_replace(
      label_replace(
        label_replace(
          max by (%(clusterLabel)s, namespace, pod, uid, node, revision, owner_kind, owner_name) (
            max by (%(clusterLabel)s, namespace, pod, revision) (
              label_replace(
                kube_pod_owner{%(kubeStateMetricsSelector)s, owner_kind="Job", owner_is_controller="true"},
                "revision", "$1", "owner_name", "(.+)"
              )
            )
            * on (%(clusterLabel)s, namespace, revision) group_left(owner_kind, owner_name)
            max by (%(clusterLabel)s, namespace, revision, owner_kind, owner_name) (
              label_replace(
                kube_job_owner{%(kubeStateMetricsSelector)s, owner_kind!="Pod", owner_kind!=""},
                "revision", "$1", "job_name", "(.+)"
              )
            )
            * on (%(clusterLabel)s, namespace, pod) group_left(uid, node)
            max by (%(clusterLabel)s, namespace, pod, uid, node) (
              kube_pod_info{%(kubeStateMetricsSelector)s}
            )
          ),
          "workload", "$1", "owner_name", "(.+)"
        ),
        "revision_source", "job_name", "revision", ".+"
      ),
      "workload_type", "$1", "owner_kind", "(.+)"
    )
  ||| % config;

  local standaloneJobIdentity = |||
    label_replace(
      label_replace(
        label_replace(
          max by (%(clusterLabel)s, namespace, pod, uid, node, workload) (
            max by (%(clusterLabel)s, namespace, pod, workload) (
              label_replace(
                kube_pod_owner{%(kubeStateMetricsSelector)s, owner_kind="Job", owner_is_controller="true"},
                "workload", "$1", "owner_name", "(.+)"
              )
              unless on (%(clusterLabel)s, namespace, workload)
              label_replace(
                kube_job_owner{%(kubeStateMetricsSelector)s, owner_kind!="Pod", owner_kind!=""},
                "workload", "$1", "job_name", "(.+)"
              )
            )
            * on (%(clusterLabel)s, namespace, pod) group_left(uid, node)
            max by (%(clusterLabel)s, namespace, pod, uid, node) (
              kube_pod_info{%(kubeStateMetricsSelector)s}
            )
          ),
          "revision", "$1", "uid", "(.+)"
        ),
          "revision_source", "pod_uid", "revision", ".+"
        ),
        "workload_type", "job", "workload", ".+"
      )
  ||| % config;

  local staticPodIdentity = |||
    label_replace(
      label_replace(
        label_replace(
          label_replace(
            max by (%(clusterLabel)s, namespace, pod, uid, node) (
              kube_pod_owner{%(kubeStateMetricsSelector)s, owner_kind="Node", owner_is_controller="true"}
              * on (%(clusterLabel)s, namespace, pod) group_left(uid, node)
              max by (%(clusterLabel)s, namespace, pod, uid, node) (
                kube_pod_info{%(kubeStateMetricsSelector)s}
              )
            ),
            "workload", "$1", "pod", "(.+)"
          ),
          "revision", "$1", "uid", "(.+)"
        ),
        "revision_source", "pod_uid", "uid", ".+"
      ),
      "workload_type", "staticpod", "pod", ".+"
    )
  ||| % config;

  local genericControllerIdentity = |||
    label_replace(
      label_replace(
        label_replace(
          label_replace(
            max by (%(clusterLabel)s, namespace, pod, uid, node, owner_kind, owner_name) (
              kube_pod_owner{%(kubeStateMetricsSelector)s, owner_is_controller="true", owner_kind!~"ReplicaSet|StatefulSet|DaemonSet|Job|Node"}
              * on (%(clusterLabel)s, namespace, pod) group_left(uid, node)
              max by (%(clusterLabel)s, namespace, pod, uid, node) (
                kube_pod_info{%(kubeStateMetricsSelector)s}
              )
            ),
            "workload", "$1", "owner_name", "(.+)"
          ),
          "revision", "$1", "uid", "(.+)"
        ),
        "revision_source", "pod_uid", "uid", ".+"
      ),
      "workload_type", "$1", "owner_kind", "(.+)"
    )
  ||| % config;

  local identityLabels = '%(clusterLabel)s, namespace, workload_type, workload, revision, revision_source, pod, uid, node' % config;
  local containerLabels = '%(clusterLabel)s, namespace, workload_type, workload, revision, revision_source, pod, uid, node, container, image, image_id' % config;
  local identitySelector = 'resource_review:workload_revision_pod_container_info';

  // cAdvisor lacks a stable Kubernetes Pod UID label. Enrich its samples while
  // the matching Pod identity exists and retain that identity in the recording
  // series. Historical dashboard queries never join old counters to live Pods.
  local joinCadvisorIdentity(metric) = |||
    max by (%(containerLabels)s) (
      %(metric)s
      * on (%(clusterLabel)s, namespace, pod, container)
        group_left(workload_type, workload, revision, revision_source, uid, node, image, image_id)
        %(identitySelector)s
    )
  ||| % (config {
           containerLabels: containerLabels,
           metric: metric,
           identitySelector: identitySelector,
         });

  // kube-state-metrics exposes Pod UID on container metrics. Include it in the
  // match so reused StatefulSet and static Pod names cannot inherit old data.
  local joinKsmIdentity(metric) = |||
    max by (%(containerLabels)s) (
      %(metric)s
      * on (%(clusterLabel)s, namespace, pod, uid, container)
        group_left(workload_type, workload, revision, revision_source, node, image, image_id)
        %(identitySelector)s
    )
  ||| % (config {
           containerLabels: containerLabels,
           metric: metric,
           identitySelector: identitySelector,
         });

  {
    groups: [
      {
        // Dependent rules stay in one group. Prometheus evaluates them
        // sequentially at the same timestamp, so evidence always sees identity.
        name: 'resource-review',
        interval: '1m',
        rules: [
          {
            record: 'resource_review:workload_revision_pod_info',
            expr: 'max by (%s) (%s)' % [
              identityLabels,
              std.join(' or ', [
                deploymentIdentity,
                nonDeploymentReplicaSetIdentity,
                standaloneReplicaSetIdentity,
                ownedIdentity('StatefulSet', 'statefulset'),
                ownedIdentity('DaemonSet', 'daemonset'),
                controllerJobIdentity,
                standaloneJobIdentity,
                staticPodIdentity,
                genericControllerIdentity,
                directPodIdentity,
              ]),
            ],
          },
          {
            record: 'resource_review:workload_revision_pod_container_info',
            expr: |||
              max by (%(containerLabels)s) (
                max by (%(clusterLabel)s, namespace, pod, uid, container, image, image_id) (
                  kube_pod_container_info{%(kubeStateMetricsSelector)s, container!=""}
                )
                * on (%(clusterLabel)s, namespace, pod, uid)
                  group_left(workload_type, workload, revision, revision_source, node)
                  resource_review:workload_revision_pod_info
              )
            ||| % (config { containerLabels: containerLabels }),
          },
          {
            record: 'resource_review:workload_revision_pod_created_timestamp_seconds',
            expr: |||
              max by (%(identityLabels)s) (
                max by (%(clusterLabel)s, namespace, pod, uid) (
                  kube_pod_created{%(kubeStateMetricsSelector)s}
                )
                * on (%(clusterLabel)s, namespace, pod, uid)
                  group_left(workload_type, workload, revision, revision_source, node)
                  resource_review:workload_revision_pod_info
              )
            ||| % (config { identityLabels: identityLabels }),
          },
          {
            record: 'resource_review:container_cpu_usage_cores:rate5m',
            expr: joinCadvisorIdentity(|||
              sum by (%(clusterLabel)s, namespace, pod, container) (
                rate(container_cpu_usage_seconds_total{%(cadvisorSelector)s, container!="", container!="POD", image!=""}[5m])
              )
            ||| % config),
          },
          {
            record: 'resource_review:container_cpu_throttled_periods:ratio_rate5m',
            expr: joinCadvisorIdentity(|||
              sum by (%(clusterLabel)s, namespace, pod, container) (
                rate(container_cpu_cfs_throttled_periods_total{%(cadvisorSelector)s, container!="", container!="POD", image!=""}[5m])
              )
              /
              sum by (%(clusterLabel)s, namespace, pod, container) (
                rate(container_cpu_cfs_periods_total{%(cadvisorSelector)s, container!="", container!="POD", image!=""}[5m]) > 0
              )
            ||| % config),
          },
          {
            record: 'resource_review:container_cpu_throttled_seconds:rate5m',
            expr: joinCadvisorIdentity(|||
              sum by (%(clusterLabel)s, namespace, pod, container) (
                rate(container_cpu_cfs_throttled_seconds_total{%(cadvisorSelector)s, container!="", container!="POD", image!=""}[5m])
              )
            ||| % config),
          },
          {
            record: 'resource_review:container_cpu_pressure_waiting:ratio_rate5m',
            expr: joinCadvisorIdentity(|||
              sum by (%(clusterLabel)s, namespace, pod, container) (
                rate(container_pressure_cpu_waiting_seconds_total{%(cadvisorSelector)s, container!="", container!="POD"}[5m])
              )
            ||| % config),
          },
          {
            record: 'resource_review:container_memory_usage_bytes',
            expr: joinCadvisorIdentity(|||
              max by (%(clusterLabel)s, namespace, pod, container) (
                container_memory_usage_bytes{%(cadvisorSelector)s, container!="", container!="POD", image!=""}
              )
            ||| % config),
          },
          {
            record: 'resource_review:container_memory_working_set_bytes',
            expr: joinCadvisorIdentity(|||
              max by (%(clusterLabel)s, namespace, pod, container) (
                container_memory_working_set_bytes{%(cadvisorSelector)s, container!="", container!="POD", image!=""}
              )
            ||| % config),
          },
          {
            record: 'resource_review:container_memory_rss_bytes',
            expr: joinCadvisorIdentity(|||
              max by (%(clusterLabel)s, namespace, pod, container) (
                container_memory_rss{%(cadvisorSelector)s, container!="", container!="POD", image!=""}
              )
            ||| % config),
          },
          {
            record: 'resource_review:container_memory_cache_bytes',
            expr: joinCadvisorIdentity(|||
              max by (%(clusterLabel)s, namespace, pod, container) (
                container_memory_cache{%(cadvisorSelector)s, container!="", container!="POD", image!=""}
              )
            ||| % config),
          },
          {
            record: 'resource_review:container_memory_pressure_waiting:ratio_rate5m',
            expr: joinCadvisorIdentity(|||
              sum by (%(clusterLabel)s, namespace, pod, container) (
                rate(container_pressure_memory_waiting_seconds_total{%(cadvisorSelector)s, container!="", container!="POD"}[5m])
              )
            ||| % config),
          },
          {
            record: 'resource_review:container_cpu_request_cores',
            expr: joinKsmIdentity(|||
              max by (%(clusterLabel)s, namespace, pod, uid, container) (
                kube_pod_container_resource_requests{%(kubeStateMetricsSelector)s, resource="cpu", unit="core"}
              )
            ||| % config),
          },
          {
            record: 'resource_review:container_cpu_limit_cores',
            expr: joinKsmIdentity(|||
              max by (%(clusterLabel)s, namespace, pod, uid, container) (
                kube_pod_container_resource_limits{%(kubeStateMetricsSelector)s, resource="cpu", unit="core"}
              )
            ||| % config),
          },
          {
            record: 'resource_review:container_memory_request_bytes',
            expr: joinKsmIdentity(|||
              max by (%(clusterLabel)s, namespace, pod, uid, container) (
                kube_pod_container_resource_requests{%(kubeStateMetricsSelector)s, resource="memory", unit="byte"}
              )
            ||| % config),
          },
          {
            record: 'resource_review:container_memory_limit_bytes',
            expr: joinKsmIdentity(|||
              max by (%(clusterLabel)s, namespace, pod, uid, container) (
                kube_pod_container_resource_limits{%(kubeStateMetricsSelector)s, resource="memory", unit="byte"}
              )
            ||| % config),
          },
          {
            record: 'resource_review:container_restarts_total',
            expr: joinKsmIdentity(|||
              max by (%(clusterLabel)s, namespace, pod, uid, container) (
                kube_pod_container_status_restarts_total{%(kubeStateMetricsSelector)s}
              )
            ||| % config),
          },
          {
            record: 'resource_review:container_last_termination_oomkilled',
            expr: joinKsmIdentity(|||
              max by (%(clusterLabel)s, namespace, pod, uid, container) (
                kube_pod_container_status_last_terminated_reason{%(kubeStateMetricsSelector)s, reason="OOMKilled"} == 1
              )
            ||| % config),
          },
          {
            record: 'resource_review:container_oom_events_total',
            expr: joinCadvisorIdentity(|||
              max by (%(clusterLabel)s, namespace, pod, container) (
                container_oom_events_total{%(cadvisorSelector)s, container!="", container!="POD"}
              )
            ||| % config),
          },
          {
            // QoS class is a Pod-level fact (Guaranteed/Burstable/BestEffort)
            // derived by Kubernetes from whether requests equal limits. It is
            // broadcast onto every container row of the Pod so it can be
            // reviewed alongside container-level evidence without changing
            // the join grain of existing tables.
            record: 'resource_review:workload_revision_pod_container_qos_class',
            expr: |||
              max by (%(containerLabels)s, qos_class) (
                resource_review:workload_revision_pod_container_info
                * on (%(clusterLabel)s, namespace, pod, uid) group_left(qos_class)
                max by (%(clusterLabel)s, namespace, pod, uid, qos_class) (
                  kube_pod_status_qos_class{%(kubeStateMetricsSelector)s} == 1
                )
              )
            ||| % (config { containerLabels: containerLabels }),
          },
          {
            // Generalizes container_last_termination_oomkilled to every
            // reason kube-state-metrics reports (Error, Completed,
            // ContainerCannotRun, Evicted, OOMKilled, and so on).
            record: 'resource_review:container_last_terminated_reason',
            expr: |||
              max by (%(containerLabels)s, reason) (
                max by (%(clusterLabel)s, namespace, pod, uid, container, reason) (
                  kube_pod_container_status_last_terminated_reason{%(kubeStateMetricsSelector)s} == 1
                )
                * on (%(clusterLabel)s, namespace, pod, uid, container)
                  group_left(workload_type, workload, revision, revision_source, node, image, image_id)
                  %(identitySelector)s
              )
            ||| % (config { containerLabels: containerLabels, identitySelector: identitySelector }),
          },
          {
            record: 'resource_review:container_last_terminated_exit_code',
            expr: joinKsmIdentity(|||
              max by (%(clusterLabel)s, namespace, pod, uid, container) (
                kube_pod_container_status_last_terminated_exitcode{%(kubeStateMetricsSelector)s}
              )
            ||| % config),
          },
        ],
      },
    ],
  }
