local mixin = import '../mixin.libsonnet';
local config = mixin._config;

std.manifestYamlDoc({
  apiVersion: 'v1',
  data: {
    'resource-review.json': std.manifestJsonEx(
      mixin.grafanaDashboards['resource-review.json'],
      '  '
    ),
  },
  kind: 'ConfigMap',
  metadata: {
    annotations: {
      grafana_folder: config.dashboardFolder,
    },
    labels: config.dashboardConfigMapLabels,
    name: config.dashboardConfigMapName,
    namespace: config.namespace,
  },
})
