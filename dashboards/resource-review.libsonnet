function(config)
  local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';
  local prometheus = g.query.prometheus;
  local variable = g.dashboard.variable;
  local ds = { type: 'prometheus', uid: '${datasource}' };
  local clusterLabel = config.clusterLabel;
  local clusterSelector = if config.showMultiCluster then '%s=~"$cluster", ' % clusterLabel else '';
  local selector = '%snamespace=~"$namespace", workload_type=~"$workload_type", workload=~"$workload", revision=~"$revision", pod=~"$pod", container=~"$container"' % clusterSelector;
  local podSelector = '%snamespace=~"$namespace", workload_type=~"$workload_type", workload=~"$workload", revision=~"$revision", pod=~"$pod"' % clusterSelector;
  local identityMetric = 'resource_review:workload_revision_pod_container_info{%s}' % selector;
  local fallbackIdentityMetric = 'resource_review:workload_revision_pod_container_info{%s, revision_source="pod_uid"}' % selector;
  local identity = 'max_over_time(%s[$__range])' % identityMetric;
  local created = 'resource_review:workload_revision_pod_created_timestamp_seconds{%s}' % podSelector;
  local cpuUsage = 'resource_review:container_cpu_usage_cores:rate5m{%s}' % selector;
  local cpuRequest = 'resource_review:container_cpu_request_cores{%s}' % selector;
  local cpuLimit = 'resource_review:container_cpu_limit_cores{%s}' % selector;
  local cpuThrottled = 'resource_review:container_cpu_throttled_periods:ratio_rate5m{%s}' % selector;
  local cpuThrottledTime = 'resource_review:container_cpu_throttled_seconds:rate5m{%s}' % selector;
  local cpuPressure = 'resource_review:container_cpu_pressure_waiting:ratio_rate5m{%s}' % selector;
  local memoryUsage = 'resource_review:container_memory_usage_bytes{%s}' % selector;
  local memoryWss = 'resource_review:container_memory_working_set_bytes{%s}' % selector;
  local memoryRss = 'resource_review:container_memory_rss_bytes{%s}' % selector;
  local memoryCache = 'resource_review:container_memory_cache_bytes{%s}' % selector;
  local memoryRequest = 'resource_review:container_memory_request_bytes{%s}' % selector;
  local memoryLimit = 'resource_review:container_memory_limit_bytes{%s}' % selector;
  local memoryPressure = 'resource_review:container_memory_pressure_waiting:ratio_rate5m{%s}' % selector;
  local oomCounter = 'resource_review:container_oom_events_total{%s}' % selector;
  local restartCounter = 'resource_review:container_restarts_total{%s}' % selector;
  local oomKilledMetric = 'resource_review:container_last_termination_oomkilled{%s}' % selector;
  local oomEvents = 'increase(%s[$__range])' % oomCounter;
  local restarts = 'increase(%s[$__range])' % restartCounter;
  local oomKilled = 'max_over_time(%s[$__range])' % oomKilledMetric;
  local matchLabels = '%s, namespace, pod, uid, container' % clusterLabel;
  local revisionContainerLabels = '%s, namespace, workload_type, workload, revision, revision_source, container' % clusterLabel;
  local summaryLabels = revisionContainerLabels + ', image, image_id';
  local currentContextLabels = summaryLabels;

  local last(metric) = 'last_over_time(%s[$__range])' % metric;
  local minimum(metric) = 'min_over_time(%s[$__range])' % metric;
  local average(metric) = 'avg_over_time(%s[$__range])' % metric;
  local maximum(metric) = 'max_over_time(%s[$__range])' % metric;
  local p95(metric) = 'quantile_over_time(0.95, %s[$__range])' % metric;
  local lastTerminatedReason = 'resource_review:container_last_terminated_reason{%s}' % selector;
  local lastTerminatedExitCode = 'resource_review:container_last_terminated_exit_code{%s}' % selector;

  local summarize(expr) = 'max by (%s) (%s)' % [summaryLabels, expr];
  local summaryCpuRequest = summarize(cpuRequest);
  local summaryCpuLimit = summarize(cpuLimit);
  local summaryCpuP95 = summarize(p95(cpuUsage));
  local summaryCpuMax = summarize(maximum(cpuUsage));
  local summaryCpuThrottled = summarize(maximum(cpuThrottled));
  local summaryCpuThrottledTime = summarize(maximum(cpuThrottledTime));
  local summaryCpuPressure = summarize(maximum(cpuPressure));
  local summaryMemoryRequest = summarize(memoryRequest);
  local summaryMemoryLimit = summarize(memoryLimit);
  local summaryMemoryMax = summarize(maximum(memoryUsage));
  local summaryMemoryPressure = summarize(maximum(memoryPressure));
  local summaryOomKilled = summarize(oomKilled);
  local currentReplicaCount = 'count by (%s) (count by (%s, pod, uid) (%s))' % [currentContextLabels, currentContextLabels, identityMetric];
  local currentRevisionAge = 'time() - min by (%s) (%s * on (%s, namespace, pod, uid) group_left() %s)' % [
    currentContextLabels,
    identityMetric,
    clusterLabel,
    created,
  ];
  local currentCpuRequest = 'max by (%s) (%s)' % [currentContextLabels, cpuRequest];
  local currentCpuLimit = 'max by (%s) (%s)' % [currentContextLabels, cpuLimit];
  local currentMemoryRequest = 'max by (%s) (%s)' % [currentContextLabels, memoryRequest];
  local currentMemoryLimit = 'max by (%s) (%s)' % [currentContextLabels, memoryLimit];
  local currentObservationHistory = '(min by (%s) (count_over_time(%s[$__range]) * 60)) and on (%s) (%s)' % [
    currentContextLabels,
    cpuUsage,
    currentContextLabels,
    currentReplicaCount,
  ];
  local summaryCpuDifference = '(%s) - (%s)' % [summaryCpuRequest, summaryCpuP95];
  local summaryMemoryDifference = '(%s) - (%s)' % [summaryMemoryRequest, summaryMemoryMax];
  local warning(expr, message) = 'label_replace((%s), "warning", "%s", "container", ".*")' % [expr, message];
  local missingEvidence(metric, message) = warning(
    '%s unless on (%s) %s' % [identity, matchLabels, metric],
    message
  );
  local warnings = std.join(' or ', [
    missingEvidence(maximum(cpuUsage), 'CPU usage unavailable'),
    missingEvidence(maximum(cpuThrottled), 'CPU throttled-period evidence unavailable'),
    missingEvidence(maximum(cpuThrottledTime), 'CPU throttled-time evidence unavailable'),
    missingEvidence(maximum(memoryUsage), 'Total memory unavailable'),
    missingEvidence(maximum(memoryWss), 'Memory working set unavailable'),
    missingEvidence(maximum(memoryRss), 'Memory RSS unavailable'),
    missingEvidence(maximum(memoryCache), 'Memory cache unavailable'),
    missingEvidence(maximum(cpuPressure), 'CPU PSI unavailable (optional)'),
    missingEvidence(maximum(memoryPressure), 'Memory PSI unavailable (optional)'),
    missingEvidence(last(cpuRequest), 'CPU request not configured'),
    missingEvidence(last(cpuLimit), 'CPU limit not configured'),
    missingEvidence(last(memoryRequest), 'Memory request not configured'),
    missingEvidence(last(memoryLimit), 'Memory limit not configured'),
    missingEvidence('max_over_time(%s[$__range])' % oomCounter, 'cAdvisor OOM counter unavailable'),
    missingEvidence('max_over_time(%s[$__range])' % restartCounter, 'Restart counter unavailable'),
    warning(last(cpuRequest) + ' == 0', 'CPU request is zero; ratio omitted'),
    warning(last(memoryRequest) + ' == 0', 'Memory request is zero; ratio omitted'),
    warning('max_over_time(%s[$__range])' % fallbackIdentityMetric, 'Revision falls back to Pod UID'),
    warning('(count by (%s) (count by (%s) (%s)) > 1) * on (%s) group_right() count by (%s) (%s)' % [revisionContainerLabels, summaryLabels, identity, revisionContainerLabels, summaryLabels, identity], 'Multiple immutable images in one revision'),
    warning('clamp_max(count_over_time(%s[$__range]) / ($__range_s / 60), 1) < 0.8' % cpuUsage, 'CPU sample coverage below 80%'),
  ]);
  local summaryWarningCount = 'count by (%s) (%s) or on (%s) (0 * count by (%s) (%s))' % [
    summaryLabels,
    warnings,
    summaryLabels,
    summaryLabels,
    identity,
  ];
  local timeFields = { Time: true } + {
    ['Time ' + std.toString(i)]: true
    for i in std.range(1, 24)
  };

  local target(refId, expr, legend='', instant=false, format='time_series') =
    prometheus.new('${datasource}', expr)
    + prometheus.withRefId(refId)
    + prometheus.withLegendFormat(legend)
    + prometheus.withInstant(instant)
    + prometheus.withRange(!instant)
    + prometheus.withFormat(format);

  local grid(x, y, w=12, h=8) = { x: x, y: y, w: w, h: h };
  // overrides lets a caller style specific query refIds differently (for
  // example, dashed request/limit lines). thresholds, when set, colors the
  // single-series panel by a 0-1 ratio threshold (used for CPU throttling).
  local timeSeries(id, title, description, pos, targets, unit='short', overrides=[], thresholds=null) =
    g.panel.timeSeries.new(title)
    + g.panel.timeSeries.panelOptions.withDescription(description)
    + g.panel.timeSeries.panelOptions.withGridPos(pos.h, pos.w, pos.x, pos.y)
    + g.panel.timeSeries.queryOptions.withDatasource(ds.type, ds.uid)
    + g.panel.timeSeries.queryOptions.withTargets(targets)
    + g.panel.timeSeries.standardOptions.withUnit(unit)
    + g.panel.timeSeries.standardOptions.withOverrides(overrides)
    + g.panel.timeSeries.fieldConfig.defaults.custom.withDrawStyle('line')
    + g.panel.timeSeries.fieldConfig.defaults.custom.withLineInterpolation('smooth')
    + g.panel.timeSeries.fieldConfig.defaults.custom.withLineWidth(2)
    + g.panel.timeSeries.fieldConfig.defaults.custom.withFillOpacity(10)
    + g.panel.timeSeries.fieldConfig.defaults.custom.withGradientMode('opacity')
    + g.panel.timeSeries.fieldConfig.defaults.custom.withShowPoints('never')
    + g.panel.timeSeries.fieldConfig.defaults.custom.withSpanNulls(false)
    + g.panel.timeSeries.options.legend.withDisplayMode('table')
    + g.panel.timeSeries.options.legend.withPlacement('bottom')
    + g.panel.timeSeries.options.legend.withShowLegend(true)
    + g.panel.timeSeries.options.legend.withCalcs(['lastNotNull', 'max'])
    + g.panel.timeSeries.options.tooltip.withMode('multi')
    + g.panel.timeSeries.options.tooltip.withSort('desc')
    + { id: id }
    + if thresholds != null then {
      fieldConfig+: {
        defaults+: {
          custom+: { thresholdsStyle: { mode: 'dashed+area' } },
          thresholds: { mode: 'absolute', steps: thresholds },
          color: { mode: 'thresholds', seriesBy: 'lastNotNull' },
          min: 0,
          max: 1,
        },
      },
    } else {};

  local stat(id, title, description, pos, targets, unit='short') =
    g.panel.stat.new(title)
    + g.panel.stat.panelOptions.withDescription(description)
    + g.panel.stat.panelOptions.withGridPos(pos.h, pos.w, pos.x, pos.y)
    + g.panel.stat.queryOptions.withDatasource(ds.type, ds.uid)
    + g.panel.stat.queryOptions.withTargets(targets)
    + g.panel.stat.standardOptions.withUnit(unit)
    + g.panel.stat.standardOptions.withMappings([
      { type: 'special', options: { match: 'null', result: { text: 'No evidence', color: 'orange' } } },
    ])
    + g.panel.stat.standardOptions.withOverrides([])
    + g.panel.stat.options.withColorMode('value')
    + g.panel.stat.options.withGraphMode('none')
    + g.panel.stat.options.withJustifyMode('auto')
    + g.panel.stat.options.withOrientation('auto')
    + g.panel.stat.options.withReduceOptions({ calcs: ['lastNotNull'], fields: '', values: false })
    + g.panel.stat.options.withTextMode('auto')
    + {
      id: id,
      fieldConfig+: {
        defaults+: { thresholds: { mode: 'absolute', steps: [{ color: 'blue', value: null }] } },
      },
    };

  // A compact, at-a-glance complement to the detailed evidence tables: one
  // horizontal bar per series (typically per Pod/container), scaled 0-1.
  // Used only for ratios already computed elsewhere on the dashboard (for
  // example maximum usage as a share of the last observed limit), so it adds
  // no new PromQL semantics, only a faster way to scan them.
  local bargauge(id, title, description, pos, targets, unit='percentunit') =
    g.panel.barGauge.new(title)
    + g.panel.barGauge.panelOptions.withDescription(description)
    + g.panel.barGauge.panelOptions.withGridPos(pos.h, pos.w, pos.x, pos.y)
    + g.panel.barGauge.queryOptions.withDatasource(ds.type, ds.uid)
    + g.panel.barGauge.queryOptions.withTargets(targets)
    + g.panel.barGauge.standardOptions.withUnit(unit)
    + g.panel.barGauge.standardOptions.withMin(0)
    + g.panel.barGauge.standardOptions.withMax(1)
    + g.panel.barGauge.standardOptions.withMappings([
      { type: 'special', options: { match: 'null', result: { text: 'No limit or evidence', color: 'orange' } } },
    ])
    + g.panel.barGauge.standardOptions.withOverrides([])
    + g.panel.barGauge.standardOptions.color.withMode('thresholds')
    + g.panel.barGauge.options.withDisplayMode('gradient')
    + g.panel.barGauge.options.withOrientation('horizontal')
    + g.panel.barGauge.options.withShowUnfilled(true)
    + g.panel.barGauge.options.withReduceOptions({ calcs: ['lastNotNull'], fields: '', values: false })
    + {
      id: id,
      fieldConfig+: {
        defaults+: {
          thresholds: {
            mode: 'absolute',
            steps: [
              { color: 'green', value: null },
              { color: 'red', value: config.limitHeadroomWarningRatio },
            ],
          },
        },
      },
    };

  local clusterQueryParam = if config.showMultiCluster then '&var-cluster=$cluster' else '';
  local podLink = {
    title: 'Open the Kubernetes mixin Pod dashboard',
    url: '%s/d/%s?${datasource:queryparam}%s&var-namespace=$namespace&var-pod=${__data.fields.Pod}' % [
      config.kubernetesMixinLinkPrefix,
      config.kubernetesMixinDashboardUids.pod,
      clusterQueryParam,
    ],
  };
  local nodeLink = {
    title: 'Open the Kubernetes mixin Node dashboard',
    url: '%s/d/%s?${datasource:queryparam}%s&var-node=${__data.fields.Node}' % [
      config.kubernetesMixinLinkPrefix,
      config.kubernetesMixinDashboardUids.node,
      clusterQueryParam,
    ],
  };
  local workloadLink = {
    title: 'Open the Kubernetes mixin Workload dashboard',
    url: '%s/d/%s?${datasource:queryparam}%s&var-namespace=$namespace&var-type=${__data.fields.Workload kind}&var-workload=${__data.fields.Workload}' % [
      config.kubernetesMixinLinkPrefix,
      config.kubernetesMixinDashboardUids.workload,
      clusterQueryParam,
    ],
  };
  local identityRenames = {
    [clusterLabel]: 'Cluster',
    namespace: 'Namespace',
    workload_type: 'Workload kind',
    workload: 'Workload',
    revision: 'Revision',
    revision_source: 'Revision source',
    image: 'Image',
    image_id: 'Image ID',
    pod: 'Pod',
    uid: 'Pod UID',
    container: 'Container',
    node: 'Node',
    warning: 'Warning',
    reason: 'Reason',
    qos_class: 'QoS class',
  };
  local identityOverrides = [
    {
      matcher: { id: 'byName', options: 'Pod' },
      properties: [
        { id: 'custom.width', value: 220 },
        { id: 'links', value: [podLink] },
      ],
    },
    {
      matcher: { id: 'byName', options: 'Node' },
      properties: [
        { id: 'custom.width', value: 180 },
        { id: 'links', value: [nodeLink] },
      ],
    },
    {
      matcher: { id: 'byName', options: 'Workload' },
      properties: [
        { id: 'custom.width', value: 200 },
        { id: 'links', value: [workloadLink] },
      ],
    },
    {
      matcher: { id: 'byName', options: 'Container' },
      properties: [{ id: 'custom.width', value: 150 }],
    },
    {
      matcher: { id: 'byName', options: 'Revision' },
      properties: [{ id: 'custom.width', value: 220 }],
    },
    {
      matcher: { id: 'byName', options: 'Warning' },
      properties: [{ id: 'custom.width', value: 280 }],
    },
  ];
  // The two primary comparison tables carry six evidence columns alongside
  // replica identity. Keep links intact, but use narrower identity columns so
  // the complete comparison is readable without horizontal scrolling at a
  // normal desktop width.
  local compactIdentityOverrides = [
    {
      matcher: { id: 'byName', options: 'Pod' },
      properties: [
        { id: 'custom.width', value: 160 },
        { id: 'links', value: [podLink] },
      ],
    },
    {
      matcher: { id: 'byName', options: 'Node' },
      properties: [
        { id: 'custom.width', value: 110 },
        { id: 'links', value: [nodeLink] },
      ],
    },
    {
      matcher: { id: 'byName', options: 'Workload' },
      properties: [
        { id: 'custom.width', value: 170 },
        { id: 'links', value: [workloadLink] },
      ],
    },
    {
      matcher: { id: 'byName', options: 'Container' },
      properties: [{ id: 'custom.width', value: 75 }],
    },
    {
      matcher: { id: 'byName', options: 'Revision' },
      properties: [{ id: 'custom.width', value: 145 }],
    },
    {
      matcher: { id: 'byName', options: 'Warning' },
      properties: [{ id: 'custom.width', value: 220 }],
    },
  ];

  local table(id, title, description, pos, targets, columns=[], extraExclude=[], extraRename={}, compact=false) =
    local renames = identityRenames + std.foldl(
      function(acc, column) acc { ['Value #' + column.ref]: column.name },
      columns,
      {}
    ) + (if std.length(columns) == 1 then { Value: columns[0].name } else {}) + extraRename;
    local overrides = (if compact then compactIdentityOverrides else identityOverrides) + [
      {
        matcher: { id: 'byName', options: column.name },
        properties: [{ id: 'unit', value: column.unit }]
                    + (if std.objectHas(column, 'width') then [{ id: 'custom.width', value: column.width }] else []),
      }
      for column in columns
    ];
    g.panel.table.new(title)
    + g.panel.table.panelOptions.withDescription(description)
    + g.panel.table.panelOptions.withGridPos(pos.h, pos.w, pos.x, pos.y)
    + g.panel.table.queryOptions.withDatasource(ds.type, ds.uid)
    + g.panel.table.queryOptions.withTargets(targets)
    + g.panel.table.queryOptions.withTransformations([
      { id: 'merge', options: {} },
      {
        id: 'organize',
        options: {
          excludeByName: timeFields + { [name]: true for name in extraExclude },
          indexByName: {},
          renameByName: renames,
        },
      },
    ])
    + g.panel.table.standardOptions.withUnit('short')
    + g.panel.table.standardOptions.withOverrides(overrides)
    + g.panel.table.fieldConfig.defaults.custom.withAlign('auto')
    + g.panel.table.fieldConfig.defaults.custom.withCellOptions({ type: 'auto' })
    + g.panel.table.fieldConfig.defaults.custom.withInspect(false)
    + g.panel.table.options.withShowHeader(true)
    + g.panel.table.options.withCellHeight('sm')
    + g.panel.table.options.withSortBy([])
    + g.panel.table.options.withFooter({ show: false, reducer: ['sum'] })
    + {
      id: id,
    };

  local row(id, title, y, collapsed=false, panels=[]) =
    g.panel.row.new(title)
    + g.panel.row.withId(id)
    + g.panel.row.withCollapsed(collapsed)
    + g.panel.row.withGridPos(y)
    + g.panel.row.withPanels(panels);

  // Styles a request or limit overlay line on a multi-target timeSeries panel
  // so usage, request, and limit are visually distinct instead of identical
  // solid lines.
  local dashedOverride(refId, color) = {
    matcher: { id: 'byFrameRefID', options: refId },
    properties: [
      { id: 'custom.lineStyle', value: { fill: 'dash', dash: [10, 10] } },
      { id: 'custom.fillOpacity', value: 0 },
      { id: 'custom.lineWidth', value: 2 },
      { id: 'color', value: { mode: 'fixed', fixedColor: color } },
    ],
  };

  local queryVariable(name, label, query, includeAll=true) =
    variable.query.new(name)
    + variable.query.withDatasource(ds.type, ds.uid)
    + variable.query.generalOptions.withLabel(label)
    + variable.query.generalOptions.showOnDashboard.withLabelAndValue()
    + variable.query.refresh.onTime()
    + variable.query.withSort(i=1)
    + variable.query.selectionOptions.withIncludeAll(includeAll, if includeAll then '.*' else null)
    + variable.query.selectionOptions.withMulti(false)
    + {
      definition: query,
      query: { query: query, refId: 'variable-' + name },
      allValue: if includeAll then '.*' else null,
      options: [],
      current: if includeAll then { selected: true, text: 'All', value: '$__all' } else {},
    };

  g.dashboard.new(config.name)
  + g.dashboard.withUid(config.dashboardUid)
  + g.dashboard.withDescription('Revision-safe evidence for the Kubernetes Rightsizing review process. This dashboard does not make resource recommendations.')
  + g.dashboard.withTags(config.dashboardTags)
  + g.dashboard.withTimezone('browser')
  + g.dashboard.withSchemaVersion(39)
  + g.dashboard.withEditable(false)
  + g.dashboard.withRefresh('1m')
  + g.dashboard.time.withFrom(config.defaultTimeRange)
  + g.dashboard.time.withTo('now')
  + g.dashboard.timepicker.withRefreshIntervals(['30s', '1m', '5m'])
  + { timepicker+: { time_options: ['1h', '6h', '24h', '7d', '14d', '30d'] } }
  + g.dashboard.withLinks([
    {
      title: 'Kubernetes Rightsizing book — review process this dashboard implements',
      type: 'link',
      icon: 'external link',
      url: config.bookUrl,
      targetBlank: true,
    },
    {
      title: 'Metric definitions and limitations',
      type: 'link',
      icon: 'doc',
      url: 'https://github.com/learnk8s/resource-review-mixin/blob/main/docs/metrics.md',
      targetBlank: true,
    },
    {
      title: 'Open-source project sponsored by StormForge',
      type: 'link',
      icon: 'external link',
      url: 'https://stormforge.io/',
      targetBlank: true,
    },
  ])
  + g.dashboard.withAnnotations([])
  + g.dashboard.withVariables(
    [
      variable.datasource.new('datasource', 'prometheus')
      + variable.datasource.generalOptions.withLabel('Data source')
      + variable.datasource.withRegex('')
      + {
        refresh: 1,
        options: [],
        current: { selected: true, text: config.datasourceName, value: config.datasourceName },
      },
    ]
    + (if config.showMultiCluster then [
         queryVariable('cluster', 'Cluster', 'label_values(resource_review:workload_revision_pod_container_info, %s)' % clusterLabel),
       ] else [
         variable.constant.new('cluster', config.singleClusterName)
         + variable.constant.generalOptions.withLabel('Cluster')
         + variable.constant.generalOptions.withCurrent(config.singleClusterName)
         + variable.constant.generalOptions.showOnDashboard.withLabelAndValue(),
       ])
    + [
      queryVariable('namespace', 'Namespace', 'label_values(resource_review:workload_revision_pod_container_info{%s}, namespace)' % (if config.showMultiCluster then '%s=~"$cluster"' % clusterLabel else ''), false),
      queryVariable('workload_type', 'Workload kind', 'label_values(resource_review:workload_revision_pod_container_info{%snamespace=~"$namespace"}, workload_type)' % clusterSelector, false),
      queryVariable('workload', 'Workload', 'label_values(resource_review:workload_revision_pod_container_info{%snamespace=~"$namespace", workload_type=~"$workload_type"}, workload)' % clusterSelector, false),
      queryVariable('revision', 'Workload revision', 'label_values(resource_review:workload_revision_pod_container_info{%snamespace=~"$namespace", workload_type=~"$workload_type", workload=~"$workload"}, revision)' % clusterSelector),
      queryVariable('pod', 'Pod', 'label_values(resource_review:workload_revision_pod_container_info{%snamespace=~"$namespace", workload_type=~"$workload_type", workload=~"$workload", revision=~"$revision"}, pod)' % clusterSelector),
      queryVariable('container', 'Container', 'label_values(resource_review:workload_revision_pod_container_info{%snamespace=~"$namespace", workload_type=~"$workload_type", workload=~"$workload", revision=~"$revision", pod=~"$pod"}, container)' % clusterSelector),
    ]
  )
  + g.dashboard.withPanels(std.sort([
    row(10, 'Workload Context', 0),
    stat(19, 'Current Pods', 'Pod UIDs currently reported for the selected revisions. This is not the desired or Ready replica count.', grid(0, 1, 4, 5), [
      target('A', 'count(count by (%s, namespace, pod, uid) (%s))' % [clusterLabel, identityMetric], 'Current Pods', true),
    ]),
    stat(12, 'Pod executions', 'Distinct Pod UIDs seen during the selected time window, including Pods that have since been replaced.', grid(4, 1, 4, 5), [
      target('A', 'count(count by (%s, namespace, pod, uid) (%s))' % [clusterLabel, identity], 'Pod executions', true),
    ]),
    stat(18, 'Revisions', 'Distinct workload revisions seen during the selected time window. The detailed revision table shows how each revision was identified.', grid(8, 1, 4, 5), [
      target('A', 'count(count by (%s, namespace, workload_type, workload, revision, revision_source) (%s))' % [clusterLabel, identity], 'Revisions', true),
    ]),
    stat(17, 'Nodes', 'Nodes that ran the selected Pod executions during the time window. One node cannot reveal host-dependent differences.', grid(12, 1, 4, 5), [
      target('A', 'count(count by (%s, namespace, node) (%s))' % [clusterLabel, identity], 'Nodes', true),
    ]),
    stat(14, 'Shortest history', 'CPU history available for the least-observed selected replica. Missing one-minute rule samples shorten this value.', grid(16, 1, 4, 5), [
      target('A', 'min(count_over_time(%s[$__range])) * 60' % cpuUsage, 'History', true),
    ], 's'),
    stat(15, 'CPU coverage', 'Lowest share of expected one-minute CPU samples available for any selected replica in the time window.', grid(20, 1, 4, 5), [
      target('A', 'clamp_max(min(count_over_time(%s[$__range])) / ($__range_s / 60), 1)' % cpuUsage, 'Coverage', true),
    ], 'percentunit'),

    table(9, 'Current workload revisions and configuration', 'One row per currently reported workload revision, container, and immutable image. It keeps workload kind and name, replica count, observed revision age, current requests and limits, and the shortest available CPU observation history together.', grid(0, 6, 24, 8), [
      target('A', currentReplicaCount, 'Replica count', true, 'table'),
      target('B', currentRevisionAge, 'Revision age', true, 'table'),
      target('C', currentCpuRequest, 'CPU request', true, 'table'),
      target('D', currentCpuLimit, 'CPU limit', true, 'table'),
      target('E', currentMemoryRequest, 'Memory request', true, 'table'),
      target('F', currentMemoryLimit, 'Memory limit', true, 'table'),
      target('G', currentObservationHistory, 'Available observation history', true, 'table'),
    ], [
      { ref: 'A', name: 'Replica count', unit: 'short', width: 100 },
      { ref: 'B', name: 'Revision age', unit: 's', width: 130 },
      { ref: 'C', name: 'CPU request', unit: 'short', width: 95 },
      { ref: 'D', name: 'CPU limit', unit: 'short', width: 90 },
      { ref: 'E', name: 'Memory request', unit: 'bytes', width: 110 },
      { ref: 'F', name: 'Memory limit', unit: 'bytes', width: 105 },
      { ref: 'G', name: 'Available observation history', unit: 's', width: 170 },
    ], extraExclude=['revision_source'], compact=true),

    row(40, 'Replica Comparison', 16),
    table(41, 'CPU by Pod execution', 'Average, p95, and maximum are calculated independently for every immutable Pod execution. History and coverage keep short-lived or poorly observed replicas visible.', grid(0, 17, 24, 8), [
      target('A', average(cpuUsage), 'Avg CPU', true, 'table'),
      target('B', p95(cpuUsage), 'p95 CPU', true, 'table'),
      target('C', maximum(cpuUsage), 'Max CPU', true, 'table'),
      target('D', maximum(cpuThrottled), 'Max throttling', true, 'table'),
      target('E', maximum(cpuThrottledTime), 'Max throttled time', true, 'table'),
      target('F', maximum(cpuPressure), 'Max CPU pressure', true, 'table'),
      target('G', 'count_over_time(' + cpuUsage + '[$__range]) * 60', 'History', true, 'table'),
      target('H', 'clamp_max(count_over_time(' + cpuUsage + '[$__range]) / ($__range_s / 60), 1)', 'Coverage', true, 'table'),
    ], [
      { ref: 'A', name: 'Avg CPU', unit: 'short', width: 90 },
      { ref: 'B', name: 'p95 CPU', unit: 'short', width: 80 },
      { ref: 'C', name: 'Max CPU', unit: 'short', width: 90 },
      { ref: 'D', name: 'Max throttling', unit: 'percentunit', width: 110 },
      { ref: 'E', name: 'Max throttled time', unit: 's', width: 125 },
      { ref: 'F', name: 'Max CPU pressure', unit: 'percentunit', width: 120 },
      { ref: 'G', name: 'History', unit: 's', width: 90 },
      { ref: 'H', name: 'Coverage', unit: 'percentunit', width: 90 },
    ], extraExclude=[clusterLabel, 'namespace', 'workload_type', 'workload', 'revision_source', 'uid', 'image', 'image_id'], compact=true),
    table(42, 'Memory and failures by Pod execution', 'Average and maximum working set remain per replica. Total maximum, pressure, OOM events, and restarts are separate signals and do not identify application impact by themselves.', grid(0, 25, 24, 8), [
      target('A', average(memoryWss), 'Avg working set', true, 'table'),
      target('B', maximum(memoryWss), 'Max working set', true, 'table'),
      target('C', maximum(memoryUsage), 'Max total', true, 'table'),
      target('D', maximum(memoryPressure), 'Max pressure', true, 'table'),
      target('E', oomEvents, 'OOM', true, 'table'),
      target('F', restarts, 'Restarts', true, 'table'),
      target('G', oomKilled, 'OOMKilled', true, 'table'),
    ], [
      { ref: 'A', name: 'Avg working set', unit: 'bytes', width: 115 },
      { ref: 'B', name: 'Max working set', unit: 'bytes', width: 115 },
      { ref: 'C', name: 'Max total', unit: 'bytes', width: 85 },
      { ref: 'D', name: 'Max pressure', unit: 'percentunit', width: 105 },
      { ref: 'E', name: 'OOM', unit: 'short', width: 65 },
      { ref: 'F', name: 'Restarts', unit: 'short', width: 75 },
      { ref: 'G', name: 'OOMKilled', unit: 'bool', width: 90 },
    ], extraExclude=[clusterLabel, 'namespace', 'workload_type', 'workload', 'revision_source', 'uid', 'image', 'image_id'], compact=true),

    row(50, 'Review Table', 33, true, [
      table(51, 'Evidence by workload revision, container, and immutable image', 'One row per workload revision, container, and immutable image. It combines current requests and limits with selected-window usage, replica count, observation duration, failure signals, and missing-evidence warnings without merging evidence from different images.', grid(0, 34, 24, 13), [
        target('A', summaryCpuRequest, 'CPU request', true, 'table'),
        target('B', summaryCpuLimit, 'CPU limit', true, 'table'),
        target('D', summaryCpuP95, 'Highest replica CPU p95', true, 'table'),
        target('E', summaryCpuMax, 'Highest replica CPU maximum', true, 'table'),
        target('F', summaryMemoryRequest, 'Memory request', true, 'table'),
        target('G', summaryMemoryLimit, 'Memory limit', true, 'table'),
        target('I', summaryMemoryMax, 'Highest replica memory maximum', true, 'table'),
        target('V', 'count by (' + summaryLabels + ') (count by (' + summaryLabels + ', pod, uid) (' + identityMetric + '))', 'Replica count', true, 'table'),
        target('K', 'min by (' + summaryLabels + ') (count_over_time(' + cpuUsage + '[$__range]) * 60)', 'Observation duration', true, 'table'),
        target('M', 'sum by (' + summaryLabels + ') (' + oomEvents + ')', 'OOM events', true, 'table'),
        target('N', 'sum by (' + summaryLabels + ') (' + restarts + ')', 'Restarts', true, 'table'),
        target('O', summaryCpuThrottled, 'Maximum throttling', true, 'table'),
        target('R', summaryCpuDifference, 'CPU request minus p95', true, 'table'),
        target('S', '((' + summaryCpuDifference + ') / (' + summaryCpuRequest + ')) and on (' + summaryLabels + ') (' + summaryCpuRequest + ' > 0)', 'CPU difference ratio', true, 'table'),
        target('T', summaryMemoryDifference, 'Memory request minus maximum', true, 'table'),
        target('U', '((' + summaryMemoryDifference + ') / (' + summaryMemoryRequest + ')) and on (' + summaryLabels + ') (' + summaryMemoryRequest + ' > 0)', 'Memory difference ratio', true, 'table'),
        target('W', summaryCpuThrottledTime, 'Maximum throttled time', true, 'table'),
        target('X', summaryCpuPressure, 'Maximum CPU pressure', true, 'table'),
        target('Y', summaryMemoryPressure, 'Maximum memory pressure', true, 'table'),
        target('Z', summaryOomKilled, 'OOMKilled', true, 'table'),
        target('AA', summaryWarningCount, 'Missing evidence warnings', true, 'table'),
      ], [
        { ref: 'A', name: 'CPU request', unit: 'short' },
        { ref: 'B', name: 'CPU limit', unit: 'short' },
        { ref: 'D', name: 'Highest replica CPU p95', unit: 'short' },
        { ref: 'E', name: 'Highest replica CPU maximum', unit: 'short' },
        { ref: 'F', name: 'Memory request', unit: 'bytes' },
        { ref: 'G', name: 'Memory limit', unit: 'bytes' },
        { ref: 'I', name: 'Highest replica memory maximum', unit: 'bytes' },
        { ref: 'V', name: 'Replica count', unit: 'short' },
        { ref: 'K', name: 'Observation duration', unit: 's' },
        { ref: 'M', name: 'OOM events', unit: 'short' },
        { ref: 'N', name: 'Restarts', unit: 'short' },
        { ref: 'O', name: 'Maximum throttling', unit: 'percentunit' },
        { ref: 'R', name: 'CPU request minus p95', unit: 'short' },
        { ref: 'S', name: 'CPU difference ratio', unit: 'percentunit' },
        { ref: 'T', name: 'Memory request minus maximum', unit: 'bytes' },
        { ref: 'U', name: 'Memory difference ratio', unit: 'percentunit' },
        { ref: 'W', name: 'Maximum throttled time', unit: 's' },
        { ref: 'X', name: 'Maximum CPU pressure', unit: 'percentunit' },
        { ref: 'Y', name: 'Maximum memory pressure', unit: 'percentunit' },
        { ref: 'Z', name: 'OOMKilled', unit: 'bool' },
        { ref: 'AA', name: 'Missing evidence warnings', unit: 'short' },
      ]),
    ]),

    row(20, 'CPU Evidence', 14, true, [
      bargauge(61, 'Peak CPU as % of limit', 'Highest sampled five-minute CPU usage in the selected time window as a percentage of the configured limit for each Pod and container. Omitted when no limit is configured. This is evidence about the configured ceiling, not a sizing recommendation.', grid(0, 15, 24, 5), [
        target('A', '(' + maximum(cpuUsage) + ') / (' + last(cpuLimit) + ') and on (' + matchLabels + ') (' + last(cpuLimit) + ' > 0)', '{{pod}} / {{container}}', true),
      ]),
      timeSeries(21, 'CPU usage, request, and limit', 'CPU usage is a five-minute rate in cores. Request and limit lines retain Pod UID and revision identity. Request is dashed orange; limit is dashed red.', grid(0, 20, 24, 9), [
        target('A', cpuUsage, '{{pod}} / {{container}} usage'),
        target('B', cpuRequest, '{{pod}} / {{container}} request'),
        target('C', cpuLimit, '{{pod}} / {{container}} limit'),
      ], overrides=[dashedOverride('B', 'orange'), dashedOverride('C', 'red')]),
      table(22, 'CPU distribution by Pod execution', 'Minimum, average, p95, and maximum describe different parts of the selected history and are calculated independently per Pod UID. Difference arithmetic uses the same displayed p95 and request.', grid(0, 29, 24, 9), [
        target('A', minimum(cpuUsage), 'CPU minimum', true, 'table'),
        target('B', average(cpuUsage), 'CPU average', true, 'table'),
        target('C', p95(cpuUsage), 'CPU p95', true, 'table'),
        target('D', maximum(cpuUsage), 'CPU maximum', true, 'table'),
        target('E', '(' + last(cpuRequest) + ' - ' + p95(cpuUsage) + ') and on (' + matchLabels + ') (' + last(cpuRequest) + ' > 0)', 'Request minus p95', true, 'table'),
        target('F', '((' + last(cpuRequest) + ' - ' + p95(cpuUsage) + ') / ' + last(cpuRequest) + ') and on (' + matchLabels + ') (' + last(cpuRequest) + ' > 0)', 'Difference ratio', true, 'table'),
        target('G', '(' + maximum(cpuUsage) + ') / (' + last(cpuLimit) + ') and on (' + matchLabels + ') (' + last(cpuLimit) + ' > 0)', 'CPU max as % of limit', true, 'table'),
      ], [
        { ref: 'A', name: 'CPU minimum', unit: 'short' },
        { ref: 'B', name: 'CPU average', unit: 'short' },
        { ref: 'C', name: 'CPU p95', unit: 'short' },
        { ref: 'D', name: 'CPU maximum', unit: 'short' },
        { ref: 'E', name: 'Request minus p95', unit: 'short' },
        { ref: 'F', name: 'Difference ratio', unit: 'percentunit' },
        { ref: 'G', name: 'CPU max as % of limit', unit: 'percentunit' },
      ], extraExclude=[clusterLabel, 'namespace', 'workload_type', 'workload', 'revision_source', 'uid', 'image', 'image_id']),
      timeSeries(23, 'CPU throttled-period ratio', 'Share of CPU quota periods containing throttling. It proves quota enforcement, not application impact. The threshold is a visual highlight, not a verdict.', grid(0, 38, 12, 8), [
        target('A', cpuThrottled, '{{pod}} / {{container}}'),
      ], 'percentunit', thresholds=[
        { color: 'green', value: null },
        { color: 'red', value: config.cpuThrottledWarningRatio },
      ]),
      timeSeries(24, 'CPU throttled time rate', 'Seconds of throttled task time per wall-clock second. Parallel tasks can make this value exceed one.', grid(12, 38, 12, 8), [
        target('A', cpuThrottledTime, '{{pod}} / {{container}}'),
      ], 's'),
      timeSeries(25, 'CPU pressure (optional PSI)', 'Fraction of time with at least one runnable task waiting for CPU. No data means unavailable, not zero; PSI does not identify whether quota or node contention caused the wait.', grid(0, 46, 24, 8), [
        target('A', cpuPressure, '{{pod}} / {{node}} / {{container}}'),
      ], 'percentunit'),
    ]),

    row(30, 'Memory Evidence', 15, true, [
      bargauge(62, 'Peak memory as % of limit', 'Highest sampled total memory in the selected time window as a percentage of the configured limit for each Pod and container. Omitted when no limit is configured. This does not explain the cause of a large percentage.', grid(0, 16, 24, 5), [
        target('A', '(' + maximum(memoryUsage) + ') / (' + last(memoryLimit) + ') and on (' + matchLabels + ') (' + last(memoryLimit) + ' > 0)', '{{pod}} / {{container}}', true),
      ]),
      timeSeries(31, 'Total and working-set memory', 'Total is memory charged to the cgroup. Working set subtracts inactive file cache and is not equivalent to application memory. Request is dashed orange; limit is dashed red.', grid(0, 21, 24, 9), [
        target('A', memoryUsage, '{{pod}} / {{container}} total'),
        target('B', memoryWss, '{{pod}} / {{container}} working set'),
        target('C', memoryRequest, '{{pod}} / {{container}} request'),
        target('D', memoryLimit, '{{pod}} / {{container}} limit'),
      ], 'bytes', overrides=[dashedOverride('C', 'orange'), dashedOverride('D', 'red')]),
      timeSeries(32, 'RSS and cache', 'RSS primarily reflects resident anonymous memory; cache reflects file content retained for reuse. They do not partition every charged byte.', grid(0, 30, 24, 8), [
        target('A', memoryRss, '{{pod}} / {{container}} RSS'),
        target('B', memoryCache, '{{pod}} / {{container}} cache'),
      ], 'bytes'),
      table(33, 'Memory distribution by Pod execution', 'Average and maximum remain per Pod UID. Peaks between scrapes can still be missed. The limit ratio uses total memory because the cgroup limit applies to total charged usage.', grid(0, 38, 24, 8), [
        target('A', average(memoryUsage), 'Total average', true, 'table'),
        target('B', maximum(memoryUsage), 'Total maximum', true, 'table'),
        target('C', average(memoryWss), 'Working-set average', true, 'table'),
        target('D', maximum(memoryWss), 'Working-set maximum', true, 'table'),
        target('E', maximum(memoryRss), 'RSS maximum', true, 'table'),
        target('F', maximum(memoryCache), 'Cache maximum', true, 'table'),
        target('G', '(' + maximum(memoryUsage) + ') / (' + last(memoryLimit) + ') and on (' + matchLabels + ') (' + last(memoryLimit) + ' > 0)', 'Memory max as % of limit', true, 'table'),
      ], [
        { ref: 'A', name: 'Total average', unit: 'bytes' },
        { ref: 'B', name: 'Total maximum', unit: 'bytes' },
        { ref: 'C', name: 'Working-set average', unit: 'bytes' },
        { ref: 'D', name: 'Working-set maximum', unit: 'bytes' },
        { ref: 'E', name: 'RSS maximum', unit: 'bytes' },
        { ref: 'F', name: 'Cache maximum', unit: 'bytes' },
        { ref: 'G', name: 'Memory max as % of limit', unit: 'percentunit' },
      ], extraExclude=[clusterLabel, 'namespace', 'workload_type', 'workload', 'revision_source', 'uid', 'image', 'image_id']),
      timeSeries(34, 'Memory pressure (optional PSI)', 'Fraction of time tasks could not make progress while the kernel reclaimed memory. No data means unavailable, not zero.', grid(0, 46, 24, 8), [
        target('A', memoryPressure, '{{pod}} / {{node}} / {{container}}'),
      ], 'percentunit'),
      table(35, 'OOM and restart evidence', 'Counters were enriched with revision, Pod UID, node, and image at recording time; reused Pod names cannot inherit old evidence. Termination reason and exit code cover every cause, not only OOM.', grid(0, 54, 24, 9), [
        target('A', oomEvents, 'cAdvisor OOM events', true, 'table'),
        target('B', oomKilled, 'OOMKilled last-state seen', true, 'table'),
        target('C', restarts, 'Restarts', true, 'table'),
        target('D', last(lastTerminatedReason), 'Last terminated reason', true, 'table'),
        target('E', last(lastTerminatedExitCode), 'Last exit code', true, 'table'),
      ], [
        { ref: 'A', name: 'OOM events', unit: 'short' },
        { ref: 'B', name: 'OOMKilled seen', unit: 'bool' },
        { ref: 'C', name: 'Restarts', unit: 'short' },
        { ref: 'E', name: 'Last exit code', unit: 'short' },
      ], extraExclude=[clusterLabel, 'namespace', 'workload_type', 'workload', 'revision_source', 'uid', 'image', 'image_id', 'Value #D']),
    ]),

  ], function(panel) panel.gridPos.y), setPanelIDs=false)
  + { version: 8 }
