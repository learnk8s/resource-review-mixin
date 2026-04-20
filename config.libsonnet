{
  name: 'Kubernetes Resource Review',
  dashboardUid: 'learnk8s-resource-review',
  dashboardFolder: 'Kubernetes',
  dashboardTags: ['kubernetes', 'resources', 'rightsizing', 'learnk8s'],
  datasourceName: 'Prometheus',
  // Match kubernetes-mixin's single-cluster default. Enable this only when the
  // source series carry clusterLabel consistently across KSM and cAdvisor.
  showMultiCluster: false,
  clusterLabel: 'cluster',
  kubeStateMetricsSelector: 'job="kube-state-metrics"',
  cadvisorSelector: 'job="kubelet", metrics_path="/metrics/cadvisor"',
  namespace: 'monitoring',
  prometheusRuleName: 'resource-review-mixin',
  dashboardConfigMapName: 'resource-review-dashboard',
  prometheusRuleLabels: {
    release: 'kube-prometheus-stack',
  },
  dashboardConfigMapLabels: {
    grafana_dashboard: '1',
  },
  defaultTimeRange: 'now-7d',
  // Colors the CPU throttled-period ratio panel red above this share. Purely
  // a visual highlight of the recorded ratio; it is not a recommendation.
  cpuThrottledWarningRatio: 0.25,
  // Colors the CPU/memory "max usage as a share of limit" bar gauges red
  // above this share. Purely a visual highlight of recorded evidence; it is
  // not a recommendation to change a limit.
  limitHeadroomWarningRatio: 0.8,
  // Standard kubernetes-mixin dashboard UIDs. kube-prometheus-stack ships
  // these dashboards, so table fields can drill down without hard-coding a
  // site-specific Grafana URL. Override the UIDs or prefix when required.
  kubernetesMixinLinkPrefix: '',
  kubernetesMixinDashboardUids: {
    workload: 'a164a7f0339f99e89cea5cb47e9be617',
    pod: '6581e46e4e5c7ba40a07646395ef7b23',
    node: '200ac8fdbfbb74b39aff88118e4d1c2c',
  },
  // Linked from the dashboard and the README so a reviewer can jump straight
  // from the evidence to the review process it implements.
  bookUrl: 'https://learnkube.com/kubernetes-rightsizing',
}
