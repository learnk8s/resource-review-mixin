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
  and .version >= 8
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
  and (all($panels[] | select(.id == 51).targets[]; .expr | contains("image_id") and contains("revision_source")))
  and ([ $panels[] | select(.id == 51).targets[].legendFormat ] | sort == ["CPU difference ratio", "CPU limit", "CPU request", "CPU request minus p95", "Highest replica CPU maximum", "Highest replica CPU p95", "Highest replica memory maximum", "Maximum CPU pressure", "Maximum memory pressure", "Maximum throttled time", "Maximum throttling", "Memory difference ratio", "Memory limit", "Memory request", "Memory request minus maximum", "Missing evidence warnings", "OOM events", "OOMKilled", "Observation duration", "Replica count", "Restarts"])
  and ([$panels[] | select(.id == 51).targets[] | select(.refId == "V").expr | select(contains("max_over_time(resource_review:workload_revision_pod_container_info") and contains("[$__range]"))] | length == 1)
  and (all($panels[] | select(.id == 51).targets[] | select(.refId == "A" or .refId == "B" or .refId == "F" or .refId == "G"); .expr | contains("last_over_time")))
  and ([$panels[] | select(.id == 51).targets[] | select(.refId == "I").expr | select(contains("resource_review:container_memory_usage_bytes"))] | length == 1)
  and ([$panels[] | select(.id == 12).title] == ["Pod executions"])
  and ([$panels[] | select(.id == 18).title] == ["Revisions"])
  and ([$panels[] | select(.id == 17).title] == ["Nodes"])
  and ([$panels[] | select(.id == 14).title] == ["Shortest history"])
  and ([$panels[] | select(.id == 15).title] == ["CPU coverage"])
  and ([$panels[] | select(.id == 10).title] == ["Workload Context"])
  and ([.panels[] | select(.type == "row") | .title] == ["Workload Context", "CPU Evidence", "Memory Evidence", "Replica Comparison", "Review Table"])
  and ([$panels[] | select(.id == 9).title] == ["Current workload revisions and configuration"])
  and ([ $panels[] | select(.id == 9).targets[].legendFormat ] | sort == ["Available observation history", "CPU limit", "CPU request", "Memory limit", "Memory request", "Replica count", "Revision age"])
  and (all($panels[] | select(.id == 9).targets[]; .expr | contains("image, image_id")))
  and ([ $panels[] | select(.id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 26 or .id == 27).title ] | sort == (["CPU usage over time", "p95 and maximum CPU usage", "CPU request and limit", "Difference between the request and p95 usage", "CPU throttled-period percentage", "CPU throttled time", "CPU pressure when PSI metrics exist"] | sort))
  and ([$panels[] | select(.id == 24) | .gridPos | {x, w}] == [{"x":0,"w":24}])
  and (([$panels[] | select(.id == 23).gridPos.y][0]) < ([$panels[] | select(.id == 24).gridPos.y][0]))
  and (([$panels[] | select(.id == 24).gridPos.y][0]) < ([$panels[] | select(.id == 25).gridPos.y][0]))
  and (([$panels[] | select(.id >= 31 and .id <= 39)] | sort_by(.gridPos.y) | map(.title)) == ["Total container memory", "Working-set memory", "RSS and cache", "Maximum values for the selected period", "Memory request and limit", "Memory pressure when PSI metrics exist", "cAdvisor OOM events", "Kubernetes OOMKilled state", "Container restarts"])
  and (all($panels[] | select(.id >= 31 and .id <= 39); .gridPos.x == 0 and .gridPos.w == 24))
  and ([$panels[] | select(.id == 62)] | length == 0)
  and ([$panels[] | select(.id == 51).targets[] | select(.refId == "AA").expr | select(contains("CPU PSI unavailable") and contains("Memory PSI unavailable") and contains("CPU throttled-period evidence unavailable") and contains("CPU throttled-time evidence unavailable"))] | length == 1)
  and ([$panels[] | select(.id == 52)] | length == 0)
  and ([ $panels[] | select(.id == 41).targets[].legendFormat ] | index("Max CPU pressure") != null)
  and ([ $panels[] | select(.id == 41).targets[].legendFormat ] | index("Max throttled time") != null)
  and ([ $panels[] | select(.id == 42).targets[].legendFormat ] | index("OOMKilled") != null)
  and ([ $panels[] | select(.id == 51).targets[].legendFormat ] | index("Maximum throttled time") != null)
  and ([ $panels[] | select(.id == 51).targets[].legendFormat ] | index("Maximum CPU pressure") != null)
  and ([ $panels[] | select(.id == 51).targets[].legendFormat ] | index("Maximum memory pressure") != null)
  and ([ $panels[] | select(.id == 51).targets[].legendFormat ] | index("OOMKilled") != null)
  and ([.links[].title] | index("Open-source project sponsored by StormForge") != null)
  and ([$expressions[] | select(contains("or vector(0)"))] | length == 0)
  and ([.panels[] | (.gridPos.y + .gridPos.h)] | max <= 45)
  and (all(.panels[] | select(.id == 20 or .id == 30 or .id == 50); .collapsed == true and (.panels | length > 0)))
  and (([.panels[] | select(.id == 21).gridPos.y][0]) < ([.panels[] | select(.id == 41).gridPos.y][0]))
  and ([$panels[] | select(.id == 41 or .id == 42).targets[].expr | select(contains("avg_over_time"))] | length == 2)
  and (all($panels[] | select(.id == 41 or .id == 42);
    ([.fieldConfig.overrides[]
      | select([.properties[].id] | index("custom.width") != null)] | length) >= 10
  ))
  and ([.. | objects | select(.id? == "links")] | length >= 3)
  and (([$panels[].id] | length) == ([$panels[].id] | unique | length))
' "$DASHBOARD" >/dev/null
