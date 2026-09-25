{
  _config+:: import 'config.libsonnet',
  grafanaDashboards: {
    'resource-review.json': (import 'dashboards/resource-review.libsonnet')($._config),
  },
  prometheusRules: (import 'rules/resource-review.libsonnet')($._config),
}
