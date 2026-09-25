#!/usr/bin/env bash

set -euo pipefail

DASHBOARD_URL=${DASHBOARD_URL:-http://127.0.0.1:3000/d/learnk8s-resource-review/kubernetes-resource-review}

echo '🌐 Opening Grafana in your default browser...'

if command -v xdg-open >/dev/null 2>&1; then
  nohup xdg-open "$DASHBOARD_URL" >/dev/null 2>&1 &
elif command -v open >/dev/null 2>&1; then
  nohup open "$DASHBOARD_URL" >/dev/null 2>&1 &
elif command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -Command "Start-Process '$DASHBOARD_URL'" >/dev/null 2>&1
else
  echo 'Could not find a system browser opener; open this URL manually:' >&2
  echo "$DASHBOARD_URL" >&2
  exit 1
fi
