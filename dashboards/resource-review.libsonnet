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
  // Combine legacy image-labelled series with the stable Pod/container
  // counter after each series' increase, without combining different UIDs.
  local restarts = 'sum without (image, image_id) (increase(%s[$__range]))' % restartCounter;
  local oomKilled = 'max_over_time(%s[$__range])' % oomKilledMetric;
  local matchLabels = '%s, namespace, pod, uid, container' % clusterLabel;
  local revisionContainerLabels = '%s, namespace, workload_type, workload, revision, revision_source, container' % clusterLabel;
  // The final review has exactly one row for a workload revision and
  // container. Image identity remains on the Pod-level rules, and the image
  // population column makes combined immutable images visible.
  local summaryLabels = revisionContainerLabels;
  local imageLabels = revisionContainerLabels + ', image, image_id';
  local currentContextLabels = imageLabels;
  local knownImageIdentity = 'max_over_time(resource_review:workload_revision_pod_container_info{%s, image_id!=""}[$__range])' % selector;
  local summaryImageCount = 'count by (%s) (count by (%s, image_id) (%s)) or on (%s) (0 * count by (%s) (%s))' % [
    summaryLabels,
    summaryLabels,
    knownImageIdentity,
    summaryLabels,
    summaryLabels,
    identity,
  ];

  local last(metric) = 'last_over_time(%s[$__range])' % metric;
  local average(metric) = 'avg_over_time(%s[$__range])' % metric;
  local maximum(metric) = 'max_over_time(%s[$__range])' % metric;
  local p95(metric) = 'quantile_over_time(0.95, %s[$__range])' % metric;

  local summarize(expr) = 'max by (%s) (%s)' % [summaryLabels, expr];
  local summaryCpuRequest = summarize(last(cpuRequest));
  local summaryCpuLimit = summarize(last(cpuLimit));
  local summaryCpuP95 = summarize(p95(cpuUsage));
  local summaryCpuMax = summarize(maximum(cpuUsage));
  local summaryCpuThrottled = summarize(maximum(cpuThrottled));
  local summaryCpuThrottledTime = summarize(maximum(cpuThrottledTime));
  local summaryCpuPressure = summarize(maximum(cpuPressure));
  local summaryMemoryRequest = summarize(last(memoryRequest));
  local summaryMemoryLimit = summarize(last(memoryLimit));
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
  // Include every known Pod/container identity, even when it has no CPU
  // samples.
  local cpuSampleCount = '(count_over_time(%s[$__range]) or (0 * %s))' % [cpuUsage, identity];
  local cpuHistory = '%s * 60' % cpuSampleCount;
  local cpuCoverage = 'clamp_max(%s / ($__range_s / 60), 1)' % cpuSampleCount;
  local currentObservationHistory = '(min by (%s) (%s)) and on (%s) (%s)' % [
    currentContextLabels,
    cpuHistory,
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
    warning('(%s) > 1' % summaryImageCount, 'Multiple immutable images in one revision'),
    warning('clamp_max(count_over_time(%s[$__range]) / ($__range_s / 60), 1) < 0.8' % cpuUsage, 'CPU sample coverage below 80%'),
  ]);
  local summaryWarningCount = 'count by (%s) (count by (%s, warning) (%s)) or on (%s) (0 * count by (%s) (%s))' % [
    summaryLabels,
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

  local graphSeries(expr) = 'label_replace(label_replace(%s, "pod_execution", "$1", "uid", "(.{1,8}).*"), "image_digest", "$1", "image_id", ".*sha256:([a-zA-Z0-9]{1,8}).*")' % expr;
  local podLegend = (if config.showMultiCluster then '{{%s}} / ' % clusterLabel else '') + '{{pod}} / {{container}} [{{pod_execution}} / {{image_digest}}]';
  local visibleClusterFields = if config.showMultiCluster then [clusterLabel] else [];
  local hiddenClusterFields = if config.showMultiCluster then [] else [clusterLabel];

  local target(refId, expr, legend='', instant=false, format='time_series') =
    prometheus.new('${datasource}', if instant then expr else graphSeries(expr))
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
        { id: 'custom.width', value: 160 },
        { id: 'links', value: [podLink] },
      ],
    },
    {
      matcher: { id: 'byName', options: 'Node' },
      properties: [
        { id: 'custom.width', value: 100 },
        { id: 'links', value: [nodeLink] },
      ],
    },
    {
      matcher: { id: 'byName', options: 'Workload' },
      properties: [
        { id: 'custom.width', value: 120 },
        { id: 'links', value: [workloadLink] },
      ],
    },
    {
      matcher: { id: 'byName', options: 'Container' },
      properties: [{ id: 'custom.width', value: 85 }],
    },
    {
      matcher: { id: 'byName', options: 'Revision' },
      properties: [{ id: 'custom.width', value: 145 }],
    },
    {
      matcher: { id: 'byName', options: 'Warning' },
      properties: [{ id: 'custom.width', value: 280 }],
    },
  ];
  // Shorter identity columns leave more room for per-Pod evidence.
  local compactIdentityOverrides = [
    {
      matcher: { id: 'byName', options: 'Pod' },
      properties: [
        { id: 'custom.width', value: 145 },
        { id: 'links', value: [podLink] },
      ],
    },
    {
      matcher: { id: 'byName', options: 'Node' },
      properties: [
        { id: 'custom.width', value: 90 },
        { id: 'links', value: [nodeLink] },
      ],
    },
    {
      matcher: { id: 'byName', options: 'Workload' },
      properties: [
        { id: 'custom.width', value: 110 },
        { id: 'links', value: [workloadLink] },
      ],
    },
    {
      matcher: { id: 'byName', options: 'Container' },
      properties: [{ id: 'custom.width', value: 90 }],
    },
    {
      matcher: { id: 'byName', options: 'Revision' },
      properties: [{ id: 'custom.width', value: 120 }],
    },
    {
      matcher: { id: 'byName', options: 'Warning' },
      properties: [{ id: 'custom.width', value: 220 }],
    },
    {
      matcher: { id: 'byName', options: 'Image' },
      properties: [{ id: 'custom.width', value: 170 }],
    },
    {
      matcher: { id: 'byName', options: 'Image ID' },
      properties: [{ id: 'custom.width', value: 140 }],
    },
    {
      matcher: { id: 'byName', options: 'Workload kind' },
      properties: [{ id: 'custom.width', value: 90 }],
    },
    {
      matcher: { id: 'byName', options: 'Cluster' },
      properties: [{ id: 'custom.width', value: 110 }],
    },
  ];

  local table(id, title, description, pos, targets, columns=[], extraExclude=[], extraRename={}, compact=false, extraOverrides=[], fieldOrder=[]) =
    local renames = identityRenames + std.foldl(
      function(acc, column) acc { ['Value #' + column.ref]: column.name },
      columns,
      {}
    ) + (if std.length(columns) == 1 then { Value: columns[0].name } else {}) + extraRename;
    local orderedFields = fieldOrder + ['Value #' + column.ref for column in columns];
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
          indexByName: if std.length(fieldOrder) == 0 then {} else {
            [orderedFields[i]]: i
            for i in std.range(0, std.length(orderedFields) - 1)
          },
          renameByName: renames,
        },
      },
    ])
    + g.panel.table.standardOptions.withUnit('short')
    + g.panel.table.standardOptions.withOverrides(overrides + extraOverrides)
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
      title: 'Read the Kubernetes Rightsizing guide',
      type: 'link',
      icon: 'external link',
      url: config.bookUrl,
      targetBlank: true,
    },
    {
      title: 'Metric definitions and limitations',
      type: 'link',
      icon: 'doc',
      url: 'https://github.com/learnk8s/resource-review-mixin/blob/master/docs/metrics.md',
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
         variable.custom.new('cluster', [config.singleClusterName])
         + variable.custom.generalOptions.withLabel('Cluster')
         + variable.custom.generalOptions.showOnDashboard.withLabelAndValue(),
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
    stat(14, 'Shortest history', 'CPU history available for the least-observed selected replica. A known replica without CPU samples has zero history.', grid(16, 1, 4, 5), [
      target('A', 'min(%s)' % cpuHistory, 'History', true),
    ], 's'),
    stat(15, 'CPU coverage', 'Lowest share of expected one-minute CPU samples available for any selected replica in the time window. Known replicas without CPU samples count as zero coverage.', grid(20, 1, 4, 5), [
      target('A', 'min(%s)' % cpuCoverage, 'Coverage', true),
    ], 'percentunit'),

    table(9, 'Current workload revisions and configuration', 'One row per currently reported workload revision, container, and immutable image. The filters identify the workload. Each row shows replica count, revision age, requests, limits, and the shortest available CPU history.', grid(0, 6, 24, 8), [
      target('A', currentReplicaCount, 'Replica count', true, 'table'),
      target('B', currentRevisionAge, 'Revision age', true, 'table'),
      target('C', currentCpuRequest, 'CPU request', true, 'table'),
      target('D', currentCpuLimit, 'CPU limit', true, 'table'),
      target('E', currentMemoryRequest, 'Memory request', true, 'table'),
      target('F', currentMemoryLimit, 'Memory limit', true, 'table'),
      target('G', currentObservationHistory, 'Available observation history', true, 'table'),
    ], [
      { ref: 'A', name: 'Replicas', unit: 'short', width: 85 },
      { ref: 'B', name: 'Revision age', unit: 's', width: 105 },
      { ref: 'C', name: 'CPU request', unit: 'short', width: 105 },
      { ref: 'D', name: 'CPU limit', unit: 'short', width: 90 },
      { ref: 'E', name: 'Memory request', unit: 'bytes', width: 130 },
      { ref: 'F', name: 'Memory limit', unit: 'bytes', width: 110 },
      { ref: 'G', name: 'CPU history', unit: 's', width: 105 },
    ], extraExclude=['namespace', 'workload_type', 'workload', 'revision_source'] + hiddenClusterFields, compact=true, fieldOrder=visibleClusterFields + ['revision', 'container', 'image_id']),

    row(40, 'Replica Comparison', 16),
    table(41, 'CPU usage, throttling, and pressure by Pod and node', 'Each row keeps one Pod and node visible. Average, p95, maximum, throttling, pressure, history, and coverage are calculated for that Pod UID before any workload-level summary.', grid(0, 17, 24, 8), [
      target('A', average(cpuUsage), 'Average CPU', true, 'table'),
      target('B', p95(cpuUsage), 'p95 CPU', true, 'table'),
      target('C', maximum(cpuUsage), 'Maximum CPU', true, 'table'),
      target('D', maximum(cpuThrottled), 'Maximum throttled-period percentage', true, 'table'),
      target('E', maximum(cpuThrottledTime), 'Maximum throttled-time rate', true, 'table'),
      target('F', maximum(cpuPressure), 'Maximum CPU pressure', true, 'table'),
      target('G', cpuHistory, 'History', true, 'table'),
      target('H', cpuCoverage, 'Coverage', true, 'table'),
    ], [
      { ref: 'A', name: 'Average CPU', unit: 'short', width: 110 },
      { ref: 'B', name: 'CPU p95', unit: 'short', width: 80 },
      { ref: 'C', name: 'CPU max', unit: 'short', width: 80 },
      { ref: 'D', name: 'Throttled periods', unit: 'percentunit', width: 135 },
      { ref: 'E', name: 'Throttled time', unit: 'short', width: 110 },
      { ref: 'F', name: 'CPU pressure', unit: 'percentunit', width: 115 },
      { ref: 'G', name: 'History', unit: 's', width: 80 },
      { ref: 'H', name: 'Coverage', unit: 'percentunit', width: 80 },
    ], extraExclude=['namespace', 'workload_type', 'workload', 'revision_source', 'uid', 'image', 'image_id'] + hiddenClusterFields, compact=true, fieldOrder=visibleClusterFields + ['revision', 'pod', 'container', 'node']),
    table(42, 'Memory, OOM events, and restarts by Pod and node', 'Each row keeps one Pod and node visible. Working set, total memory, pressure, OOM events, OOMKilled state, and restarts stay separate so one replica cannot disappear inside a workload average.', grid(0, 25, 24, 8), [
      target('A', average(memoryWss), 'Average working set', true, 'table'),
      target('B', maximum(memoryWss), 'Maximum working set', true, 'table'),
      target('C', maximum(memoryUsage), 'Maximum total memory', true, 'table'),
      target('D', maximum(memoryPressure), 'Maximum memory pressure', true, 'table'),
      target('E', oomEvents, 'OOM events', true, 'table'),
      target('F', restarts, 'Restarts', true, 'table'),
      target('G', oomKilled, 'OOMKilled', true, 'table'),
    ], [
      { ref: 'A', name: 'Average working set', unit: 'bytes', width: 125 },
      { ref: 'B', name: 'Max working set', unit: 'bytes', width: 115 },
      { ref: 'C', name: 'Max total memory', unit: 'bytes', width: 120 },
      { ref: 'D', name: 'Memory pressure', unit: 'percentunit', width: 115 },
      { ref: 'E', name: 'OOM events', unit: 'short', width: 80 },
      { ref: 'F', name: 'Restarts', unit: 'short', width: 70 },
      { ref: 'G', name: 'OOMKilled', unit: 'bool', width: 85 },
    ], extraExclude=['namespace', 'workload_type', 'workload', 'revision_source', 'uid', 'image', 'image_id'] + hiddenClusterFields, compact=true, fieldOrder=visibleClusterFields + ['revision', 'pod', 'container', 'node']),

    row(50, 'Review Table', 33, true, [
      table(51, 'Workload revision and container review', 'One row per workload revision and container. Image population identifies revisions with multiple known immutable images. Values in a Mixed images row can come from different images. The row includes requests, usage, resource differences, replica count, history, runtime signals, and warnings.', grid(0, 34, 24, 13), [
        target('AB', summaryImageCount, 'Image population', true, 'table'),
        target('A', summaryCpuRequest, 'Current CPU request', true, 'table'),
        target('B', summaryCpuLimit, 'Current CPU limit', true, 'table'),
        target('D', summaryCpuP95, 'CPU p95', true, 'table'),
        target('E', summaryCpuMax, 'CPU maximum', true, 'table'),
        target('F', summaryMemoryRequest, 'Current memory request', true, 'table'),
        target('G', summaryMemoryLimit, 'Current memory limit', true, 'table'),
        target('I', summaryMemoryMax, 'Memory maximum', true, 'table'),
        target('R', summaryCpuDifference, 'CPU absolute difference from request', true, 'table'),
        target('S', '((' + summaryCpuDifference + ') / (' + summaryCpuRequest + ')) and on (' + summaryLabels + ') (' + summaryCpuRequest + ' > 0)', 'CPU percentage difference from request', true, 'table'),
        target('T', summaryMemoryDifference, 'Memory absolute difference from request', true, 'table'),
        target('U', '((' + summaryMemoryDifference + ') / (' + summaryMemoryRequest + ')) and on (' + summaryLabels + ') (' + summaryMemoryRequest + ' > 0)', 'Memory percentage difference from request', true, 'table'),
        target('V', 'count by (' + summaryLabels + ') (count by (' + summaryLabels + ', pod, uid) (' + identity + '))', 'Replica count', true, 'table'),
        target('K', 'min by (' + summaryLabels + ') (' + cpuHistory + ')', 'Observation duration', true, 'table'),
        target('M', 'sum by (' + summaryLabels + ') (' + oomEvents + ')', 'OOM events', true, 'table'),
        target('N', 'sum by (' + summaryLabels + ') (' + restarts + ')', 'Restarts', true, 'table'),
        target('O', summaryCpuThrottled, 'Throttled-period percentage', true, 'table'),
        target('W', summaryCpuThrottledTime, 'Throttled-time rate', true, 'table'),
        target('X', summaryCpuPressure, 'CPU pressure', true, 'table'),
        target('Y', summaryMemoryPressure, 'Memory pressure', true, 'table'),
        target('Z', summaryOomKilled, 'OOMKilled', true, 'table'),
        target('AA', summaryWarningCount, 'Missing evidence warnings', true, 'table'),
      ], [
        { ref: 'AB', name: 'Image population', unit: 'short', width: 140 },
        { ref: 'AA', name: 'Warnings', unit: 'short', width: 85 },
        { ref: 'V', name: 'Replicas', unit: 'short', width: 85 },
        { ref: 'K', name: 'CPU history', unit: 's', width: 100 },
        { ref: 'A', name: 'CPU request', unit: 'short', width: 105 },
        { ref: 'D', name: 'CPU p95', unit: 'short', width: 80 },
        { ref: 'E', name: 'CPU max', unit: 'short', width: 80 },
        { ref: 'R', name: 'CPU difference', unit: 'short', width: 120 },
        { ref: 'S', name: 'CPU difference %', unit: 'percentunit', width: 135 },
        { ref: 'B', name: 'CPU limit', unit: 'short', width: 90 },
        { ref: 'F', name: 'Memory request', unit: 'bytes', width: 120 },
        { ref: 'I', name: 'Memory max', unit: 'bytes', width: 105 },
        { ref: 'T', name: 'Memory difference', unit: 'bytes', width: 135 },
        { ref: 'U', name: 'Memory difference %', unit: 'percentunit', width: 155 },
        { ref: 'G', name: 'Memory limit', unit: 'bytes', width: 110 },
        { ref: 'M', name: 'OOM events', unit: 'short', width: 80 },
        { ref: 'N', name: 'Restarts', unit: 'short', width: 70 },
        { ref: 'Z', name: 'OOMKilled', unit: 'bool', width: 85 },
        { ref: 'O', name: 'Throttled periods', unit: 'percentunit', width: 120 },
        { ref: 'W', name: 'Throttled time', unit: 'short', width: 110 },
        { ref: 'X', name: 'CPU pressure', unit: 'percentunit', width: 100 },
        { ref: 'Y', name: 'Memory pressure', unit: 'percentunit', width: 115 },
      ], extraExclude=['namespace', 'workload_type', 'workload', 'revision_source'] + hiddenClusterFields, compact=true, fieldOrder=visibleClusterFields + ['revision', 'container'], extraOverrides=[
        {
          matcher: { id: 'byName', options: 'Image population' },
          properties: [
            {
              id: 'mappings',
              value: [
                { type: 'value', options: {
                  '0': { text: 'Unknown images', color: 'orange' },
                  '1': { text: '1 known image', color: 'blue' },
                } },
                { type: 'range', options: { from: 2, to: 1e9, result: { text: 'Mixed images', color: 'orange' } } },
              ],
            },
            { id: 'custom.cellOptions', value: { type: 'color-text' } },
          ],
        },
      ]),
    ]),

    row(20, 'CPU Evidence', 14, true, [
      timeSeries(21, 'CPU usage over time', 'CPU usage is a five-minute rate in cores. Each line keeps the Pod UID and revision identity.', grid(0, 15, 24, 9), [
        target('A', cpuUsage, podLegend + ' usage'),
      ]),
      table(22, 'p95 and maximum CPU usage', 'p95 and maximum are calculated independently for each Pod UID over the selected time window.', grid(0, 24, 24, 8), [
        target('A', p95(cpuUsage), 'CPU p95', true, 'table'),
        target('B', maximum(cpuUsage), 'CPU maximum', true, 'table'),
      ], [
        { ref: 'A', name: 'CPU p95', unit: 'short' },
        { ref: 'B', name: 'CPU maximum', unit: 'short' },
      ], extraExclude=[clusterLabel, 'namespace', 'workload_type', 'workload', 'revision_source', 'uid', 'image', 'image_id']),
      timeSeries(26, 'CPU request and limit', 'Request and limit lines retain Pod UID and revision identity. Request is dashed orange; limit is dashed red.', grid(0, 32, 24, 8), [
        target('A', cpuRequest, podLegend + ' request'),
        target('B', cpuLimit, podLegend + ' limit'),
      ], overrides=[dashedOverride('A', 'orange'), dashedOverride('B', 'red')]),
      table(27, 'Difference between the request and p95 usage', 'The table subtracts the displayed p95 from the configured request for each Pod UID. The ratio is omitted when the request is missing or zero.', grid(0, 40, 24, 8), [
        target('A', '(' + last(cpuRequest) + ' - ' + p95(cpuUsage) + ') and on (' + matchLabels + ') (' + last(cpuRequest) + ' > 0)', 'Request minus p95', true, 'table'),
        target('B', '((' + last(cpuRequest) + ' - ' + p95(cpuUsage) + ') / ' + last(cpuRequest) + ') and on (' + matchLabels + ') (' + last(cpuRequest) + ' > 0)', 'Difference ratio', true, 'table'),
      ], [
        { ref: 'A', name: 'Request minus p95', unit: 'short' },
        { ref: 'B', name: 'Difference ratio', unit: 'percentunit' },
      ], extraExclude=[clusterLabel, 'namespace', 'workload_type', 'workload', 'revision_source', 'uid', 'image', 'image_id']),
      timeSeries(23, 'CPU throttled-period percentage', 'Share of CPU quota periods containing throttling. It proves quota enforcement, not application impact. The threshold is a visual highlight, not a verdict.', grid(0, 48, 24, 8), [
        target('A', cpuThrottled, podLegend),
      ], 'percentunit', thresholds=[
        { color: 'green', value: null },
        { color: 'red', value: config.cpuThrottledWarningRatio },
      ]),
      timeSeries(24, 'CPU throttled time', 'Seconds of throttled task time per wall-clock second. Parallel tasks can make this value exceed one.', grid(0, 56, 24, 8), [
        target('A', cpuThrottledTime, podLegend),
      ], 'short'),
      timeSeries(25, 'CPU pressure when PSI metrics exist', 'Fraction of time with at least one runnable task waiting for CPU. No data means unavailable, not zero; PSI does not identify whether quota or node contention caused the wait.', grid(0, 64, 24, 8), [
        target('A', cpuPressure, podLegend + ' / {{node}}'),
      ], 'percentunit'),
    ]),

    row(30, 'Memory Evidence', 15, true, [
      timeSeries(31, 'Total container memory', 'Memory currently charged to the container cgroup. This includes more than application heap and can include file cache and kernel-accounted memory.', grid(0, 16, 24, 9), [
        target('A', memoryUsage, podLegend + ' total'),
      ], 'bytes'),
      timeSeries(32, 'Working-set memory', 'Total container memory minus inactive file cache. This is not the same as application memory or memory that Linux can never reclaim.', grid(0, 25, 24, 9), [
        target('B', memoryWss, podLegend + ' working set'),
      ], 'bytes'),
      timeSeries(33, 'RSS and cache', 'RSS primarily reflects resident anonymous memory; cache reflects file content retained for reuse. They do not account for every byte in total container memory.', grid(0, 34, 24, 8), [
        target('A', memoryRss, podLegend + ' RSS'),
        target('B', memoryCache, podLegend + ' cache'),
      ], 'bytes'),
      table(34, 'Maximum values for the selected period', 'The highest sampled total, working-set, RSS, and cache values are calculated separately for each Pod UID over the selected time period.', grid(0, 42, 24, 8), [
        target('A', maximum(memoryUsage), 'Total maximum', true, 'table'),
        target('B', maximum(memoryWss), 'Working-set maximum', true, 'table'),
        target('C', maximum(memoryRss), 'RSS maximum', true, 'table'),
        target('D', maximum(memoryCache), 'Cache maximum', true, 'table'),
      ], [
        { ref: 'A', name: 'Total maximum', unit: 'bytes' },
        { ref: 'B', name: 'Working-set maximum', unit: 'bytes' },
        { ref: 'C', name: 'RSS maximum', unit: 'bytes' },
        { ref: 'D', name: 'Cache maximum', unit: 'bytes' },
      ], extraExclude=[clusterLabel, 'namespace', 'workload_type', 'workload', 'revision_source', 'uid', 'image', 'image_id']),
      timeSeries(35, 'Memory request and limit', 'The request is used when Kubernetes schedules the Pod. The limit is the cgroup ceiling. Request is dashed orange; limit is dashed red.', grid(0, 50, 24, 8), [
        target('A', memoryRequest, podLegend + ' request'),
        target('B', memoryLimit, podLegend + ' limit'),
      ], 'bytes', overrides=[dashedOverride('A', 'orange'), dashedOverride('B', 'red')]),
      timeSeries(36, 'Memory pressure when PSI metrics exist', 'Fraction of time tasks could not make progress while Linux tried to reclaim memory. No data means unavailable, not zero.', grid(0, 58, 24, 8), [
        target('A', memoryPressure, podLegend + ' / {{node}}'),
      ], 'percentunit'),
      table(37, 'cAdvisor OOM events', 'New out-of-memory events reported by cAdvisor during the selected time period. Each row keeps the Pod UID and revision that produced the counter.', grid(0, 66, 24, 8), [
        target('A', oomEvents, 'cAdvisor OOM events', true, 'table'),
      ], [
        { ref: 'A', name: 'OOM events', unit: 'short' },
      ], extraExclude=[clusterLabel, 'namespace', 'workload_type', 'workload', 'revision_source', 'uid', 'image', 'image_id']),
      table(38, 'Kubernetes OOMKilled state', 'Whether OOMKilled was seen as the last termination reason during the selected time period. A newer termination reason can replace it, so this is not a count of every OOM kill.', grid(0, 74, 24, 8), [
        target('A', oomKilled, 'OOMKilled', true, 'table'),
      ], [
        { ref: 'A', name: 'OOMKilled', unit: 'bool' },
      ], extraExclude=[clusterLabel, 'namespace', 'workload_type', 'workload', 'revision_source', 'uid', 'image', 'image_id']),
      table(39, 'Container restarts', 'How many times each container restarted during the selected time period. This count does not say why the restart happened.', grid(0, 82, 24, 8), [
        target('A', restarts, 'Restarts', true, 'table'),
      ], [
        { ref: 'A', name: 'Restarts', unit: 'short' },
      ], extraExclude=[clusterLabel, 'namespace', 'workload_type', 'workload', 'revision_source', 'uid', 'image', 'image_id']),
    ]),

  ], function(panel) panel.gridPos.y), setPanelIDs=false)
  + { version: 8 }
