#!/usr/bin/env bash

set -euo pipefail

JQ=${JQ:-jq}
PROMTOOL=${PROMTOOL:-promtool}
DASHBOARD=${DASHBOARD:-generated/resource-review.json}

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

check_range() {
  local range=$1
  local range_seconds=$2
  local tmp_file="$tmp_dir/dashboard-$range.yaml"

  # The dollar-prefixed names below belong to jq and Grafana, not the shell.
  # shellcheck disable=SC2016
  "$JQ" --arg range "$range" --arg range_seconds "$range_seconds" '
  [.. | objects | select(has("targets")) | .targets[]?.expr] as $expressions
  | {
      groups: [
        {
          name: "resource-review-dashboard-promql",
          rules: [
            range(0; $expressions | length) as $index
            | {
                record: ("resource_review_dashboard_query_" + ($index | tostring)),
                expr: (
                   $expressions[$index]
                   | gsub("\\$__rate_interval"; "5m")
                  | gsub("\\$__range_s"; $range_seconds)
                  | gsub("\\$__range"; $range)
                  | gsub("\\$(cluster|namespace|workload_type|workload|revision|pod|container)"; ".*")
                )
              }
          ]
        }
      ]
    }
  ' "$DASHBOARD" > "$tmp_file"

  "$PROMTOOL" check rules "$tmp_file"
}

check_range 1h 3600
check_range 30d 2592000
