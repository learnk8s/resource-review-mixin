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
  and ([$panels[] | select(.id == 51).targets[].expr | select(contains("image_id"))] | length > 0)
  and ([$panels[] | select(.id == 51).targets[].legendFormat] | index("Current Pods") != null)
  and ([$panels[] | select(.id == 51).targets[].legendFormat] | index("Pod executions") != null)
  and ([$panels[] | select(.id == 12).title] == ["Pod executions"])
  and ([$panels[] | select(.id == 18).title] == ["Revisions"])
  and ([$panels[] | select(.id == 17).title] == ["Nodes"])
  and ([$panels[] | select(.id == 14).title] == ["Shortest history"])
  and ([$panels[] | select(.id == 15).title] == ["CPU coverage"])
  and ([$panels[] | select(.id == 10).title] == ["Workload Context"])
  and ([$panels[] | select(.id == 9).title] == ["Current workload revisions and configuration"])
  and ([ $panels[] | select(.id == 9).targets[].legendFormat ] | sort == ["Available observation history", "CPU limit", "CPU request", "Memory limit", "Memory request", "Replica count", "Revision age"])
  and ([$panels[] | select(.id == 60).title] == ["Peak usage vs limits"])
  and ([$panels[] | select(.id == 61).title] == ["Peak CPU as % of limit"])
  and ([$panels[] | select(.id == 62).title] == ["Peak memory as % of limit"])
  and ([$panels[] | select(.id == 52).targets[].expr | select(contains("CPU PSI unavailable"))] | length == 1)
  and ([$panels[] | select(.id == 52).targets[].expr | select(contains("Memory PSI unavailable"))] | length == 1)
  and ([$panels[] | select(.id == 52).targets[].expr | select(contains("CPU throttled-period evidence unavailable"))] | length == 1)
  and ([$panels[] | select(.id == 52).targets[].expr | select(contains("CPU throttled-time evidence unavailable"))] | length == 1)
  and ([ $panels[] | select(.id == 41).targets[].legendFormat ] | index("Max CPU pressure") != null)
  and ([ $panels[] | select(.id == 41).targets[].legendFormat ] | index("Max throttled time") != null)
  and ([ $panels[] | select(.id == 42).targets[].legendFormat ] | index("OOMKilled") != null)
  and ([ $panels[] | select(.id == 51).targets[].legendFormat ] | index("Maximum throttled time") != null)
  and ([ $panels[] | select(.id == 51).targets[].legendFormat ] | index("Maximum CPU pressure") != null)
  and ([ $panels[] | select(.id == 51).targets[].legendFormat ] | index("Maximum memory pressure") != null)
  and ([ $panels[] | select(.id == 51).targets[].legendFormat ] | index("OOMKilled") != null)
  and ([ $panels[] | select(.id == 51).targets[].legendFormat ] | index("Observed revision age") != null)
  and ([.links[].title] | index("Open-source project sponsored by StormForge") != null)
  and ([$expressions[] | select(contains("or vector(0)"))] | length == 0)
  and ([.panels[] | (.gridPos.y + .gridPos.h)] | max <= 45)
  and (all(.panels[] | select(.id == 20 or .id == 30 or .id == 50 or .id == 70); .collapsed == true and (.panels | length > 0)))
  and (([.panels[] | select(.id == 61).gridPos.y][0]) < ([.panels[] | select(.id == 41).gridPos.y][0]))
  and ([$panels[] | select(.id == 41 or .id == 42).targets[].expr | select(contains("avg_over_time"))] | length == 2)
  and (all($panels[] | select(.id == 41 or .id == 42);
    ([.fieldConfig.overrides[]
      | select([.properties[].id] | index("custom.width") != null)] | length) >= 10
  ))
  and ([.. | objects | select(.id? == "links")] | length >= 3)
  and (([$panels[].id] | length) == ([$panels[].id] | unique | length))
' "$DASHBOARD" >/dev/null
