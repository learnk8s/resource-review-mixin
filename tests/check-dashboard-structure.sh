#!/usr/bin/env bash

set -euo pipefail

JQ=${JQ:-jq}
DASHBOARD=${DASHBOARD:-generated/resource-review.json}
expected_variables='["datasource","cluster","namespace","workload_type","workload","revision","pod","container"]'

# The dollar-prefixed names below belong to jq and Grafana, not the shell.
# shellcheck disable=SC2016
"$JQ" -e --argjson expected_variables "$expected_variables" '
  [.. | objects | select(has("type") and has("gridPos"))] as $panels
  | [.. | objects | select(has("targets")) | .targets[]?.expr] as $expressions
  | .editable == false
  and .time.from == "now-7d"
  and (.timepicker.time_options | index("30d") != null)
  and .schemaVersion >= 39
  and .version >= 9
  and ([.templating.list[].name] == $expected_variables)
  and ([.templating.list[] | select(.name == "cluster" and .label == "Cluster" and .hide == 0)] | length == 1)
  and ([.templating.list[] | select(.name == "revision" and .label == "Workload revision")] | length == 1)
  and (all($panels[] | select(.type != "row"); (.description // "") | length > 0))
  and (all($panels[] | select(.type == "table");
    .fieldConfig.defaults.unit != null
    and ([.transformations[].id] | index("merge") != null)
    and ([.transformations[].id] | index("organize") != null)
  ))
  and ([$expressions[] | select(contains("$window"))] | length == 0)
  and ([$expressions[] | select(test("increase\\((container_oom_events_total|kube_pod_container_status_restarts_total)"))] | length == 0)
  and ([$panels[] | select(.id == 51).title] == ["Workload revision and container review"])
  and ([$panels[] | select(.id >= 52 and .id <= 58)] | length == 0)
  and (all($panels[] | select(.id == 51).targets[]; .expr | contains("revision_source")))
  and ([ $panels[] | select(.id == 51).targets[].legendFormat ] | sort == ["CPU absolute difference from request", "CPU maximum", "CPU p95", "CPU percentage difference from request", "CPU pressure", "Current CPU limit", "Current CPU request", "Current memory limit", "Current memory request", "Image population", "Memory absolute difference from request", "Memory maximum", "Memory percentage difference from request", "Memory pressure", "Missing evidence warnings", "OOM events", "OOMKilled", "Observation duration", "Replica count", "Restarts", "Throttled-period percentage", "Throttled-time rate"])
  and ([$panels[] | select(.id == 51).targets[] | select(.refId == "V").expr | select(contains("max_over_time(resource_review:workload_revision_pod_container_info") and contains("[$__range]"))] | length == 1)
  and (all($panels[] | select(.id == 51).targets[] | select(.refId == "A" or .refId == "B" or .refId == "F" or .refId == "G"); .expr | contains("last_over_time")))
  and ([$panels[] | select(.id == 51).targets[] | select(.refId == "I").expr | select(contains("resource_review:container_memory_usage_bytes"))] | length == 1)
  and (all($panels[] | select(.id == 51).targets[] | select(.refId != "AA"); .expr | test("by \\([^,]+, namespace, workload_type, workload, revision, revision_source, container\\)")))
  and ([$panels[] | select(.id == 12).title] == ["Pod executions"])
  and ([$panels[] | select(.id == 18).title] == ["Revisions"])
  and ([$panels[] | select(.id == 17).title] == ["Nodes"])
  and ([$panels[] | select(.id == 14).title] == ["Shortest history"])
  and ([$panels[] | select(.id == 15).title] == ["CPU coverage"])
  and ([.panels[] | select(.type == "row")] | length == 0)
  and ([$panels[] | select(.id == 16).title] == ["Mixed image groups"])
  and ([$panels[] | select(.id == 9).title] == ["Current workload revisions and configuration"])
  and ([ $panels[] | select(.id == 9).targets[].legendFormat ] | sort == ["Available observation history", "CPU limit", "CPU request", "Memory limit", "Memory request", "Replica count", "Revision age"])
  and (all($panels[] | select(.id == 9).targets[]; .expr | contains("image, image_id")))
  and ([ $panels[] | select(.type == "timeseries").title ] | sort == (["CPU usage, request, and limit", "Memory usage, request, and limit", "CPU throttled periods", "CPU throttled time", "CPU pressure (PSI)", "Memory pressure (PSI)", "Memory breakdown: working set, RSS, and cache", "OOM and restart activity"] | sort))
  and ([ $panels[] | select(.id == 21).targets[].refId ] == ["A", "B", "C"])
  and ([ $panels[] | select(.id == 31).targets[].refId ] == ["A", "B", "C"])
  and ([ $panels[] | select(.id == 32).targets[].refId ] == ["A", "B", "C"])
  and ([$panels[] | select(.id == 24) | .gridPos | {x, w}] == [{"x":6,"w":6}])
  and (all($panels[] | select(.id == 23 or .id == 24 or .id == 25 or .id == 36); .gridPos.y == 13))
  and ([$panels[] | select(.id == 22 or .id == 26 or .id == 27 or .id == 33 or .id == 34 or .id == 35 or .id == 38 or .id == 39)] | length == 0)
  and (all($panels[] | select(.id == 37).targets[]; .interval == "1m" and (.expr | contains("$__rate_interval"))))
  and ([$panels[] | select(.id == 62)] | length == 0)
  and ([$panels[] | select(.id == 51).targets[] | select(.refId == "AA").expr | select(contains("CPU PSI unavailable") and contains("Memory PSI unavailable") and contains("CPU throttled-period evidence unavailable") and contains("CPU throttled-time evidence unavailable"))] | length == 1)
  and ([$panels[] | select(.id == 51).targets[] | select(.refId == "AA").expr | select(test("count by \\([^,]+, namespace, workload_type, workload, revision, revision_source, container, warning\\)"))] | length == 1)
  and ([$panels[] | select(.id == 41).title] == ["CPU usage, throttling, and pressure by Pod and node"])
  and ([$panels[] | select(.id == 42).title] == ["Memory, OOM events, and restarts by Pod and node"])
  and ([ $panels[] | select(.id == 41).targets[].legendFormat ] | sort == (["Average CPU", "Coverage", "History", "Maximum CPU", "Maximum CPU pressure", "Maximum throttled-period percentage", "Maximum throttled-time rate", "p95 CPU", "CPU request", "Request minus p95", "Difference ratio"] | sort))
  and ([ $panels[] | select(.id == 42).targets[].legendFormat ] | sort == (["Average working set", "Maximum memory pressure", "Maximum total memory", "Maximum working set", "OOM events", "OOMKilled", "Restarts", "Maximum RSS", "Maximum cache"] | sort))
  and (all($panels[] | select(.id == 41 or .id == 42).targets[]; .expr | contains("pod=~\"$pod\"")))
  and (all($panels[] | select(.id == 41 or .id == 42);
    all(.transformations[] | select(.id == "organize");
      (.options.excludeByName.pod // false) == false
      and (.options.excludeByName.node // false) == false
      and .options.excludeByName.uid == true
    )
  ))
  and ([ $panels[] | select(.id == 51).targets[].legendFormat ] | index("Throttled-time rate") != null)
  and ([ $panels[] | select(.id == 51).targets[].legendFormat ] | index("CPU pressure") != null)
  and ([ $panels[] | select(.id == 51).targets[].legendFormat ] | index("Memory pressure") != null)
  and ([ $panels[] | select(.id == 51).targets[].legendFormat ] | index("OOMKilled") != null)
  and ([.links[].title] == ["Read the Kubernetes Rightsizing guide", "Metric definitions and limitations"])
  and ([$expressions[] | select(contains("or vector(0)"))] | length == 0)
  and ([.panels[] | (.gridPos.y + .gridPos.h)] | max <= 61)
  and (all(.panels[] | select(.type == "timeseries"); .gridPos.y < 28))
  and (([.panels[] | select(.id == 21).gridPos.y][0]) < ([.panels[] | select(.id == 41).gridPos.y][0]))
  and ([$panels[] | select(.id == 41 or .id == 42).targets[].expr | select(contains("avg_over_time"))] | length == 2)
  and (all($panels[] | select(.id == 41 or .id == 42);
    ([.fieldConfig.overrides[]
      | select([.properties[].id] | index("custom.width") != null)] | length) >= 10
  ))
  and ([.. | objects | select(.id? == "links")] | length >= 3)
  and (([$panels[].id] | length) == ([$panels[].id] | unique | length))
' "$DASHBOARD" >/dev/null
