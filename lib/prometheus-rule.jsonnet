local mixin = import '../mixin.libsonnet';
local config = mixin._config;

std.manifestYamlDoc({
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    labels: config.prometheusRuleLabels,
    name: config.prometheusRuleName,
    namespace: config.namespace,
  },
  spec: mixin.prometheusRules,
})
