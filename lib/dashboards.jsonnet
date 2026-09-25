local dashboards = (import '../mixin.libsonnet').grafanaDashboards;

{
  [name]: std.manifestJsonEx(dashboards[name], '  ')
  for name in std.objectFields(dashboards)
}
