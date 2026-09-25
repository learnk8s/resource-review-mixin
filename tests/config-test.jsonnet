local mixin = (import '../mixin.libsonnet') {
  _config+:: {
    name: 'Configured Resource Review',
    showMultiCluster: true,
    clusterLabel: 'tenant_cluster',
  },
};
local dashboard = mixin.grafanaDashboards['resource-review.json'];
local expressions = std.flattenArrays([
  if std.objectHas(panel, 'targets') then [target.expr for target in panel.targets] else []
  for panel in dashboard.panels
]);
local matchingExpressions = [
  expr
  for expr in expressions
  if std.length(std.findSubstr('tenant_cluster=~"$cluster"', expr)) > 0
];
local rulesJson = std.manifestJson(mixin.prometheusRules);

assert dashboard.title == 'Configured Resource Review';
assert std.length(matchingExpressions) > 0;
assert std.length(std.findSubstr('tenant_cluster, namespace', rulesJson)) > 0;

true
