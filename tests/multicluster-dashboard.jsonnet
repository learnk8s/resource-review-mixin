local mixin = (import '../mixin.libsonnet') {
  _config+:: {
    showMultiCluster: true,
    clusterLabel: 'tenant_cluster',
  },
};

mixin.grafanaDashboards['resource-review.json']
