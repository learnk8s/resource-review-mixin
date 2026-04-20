#!/usr/bin/env bash

set -euo pipefail

KIND=${KIND:-kind}
CLUSTER_NAME=${CLUSTER_NAME:-resource-review-mixin}

echo "🧹 Removing kind development cluster: $CLUSTER_NAME"
"$KIND" delete cluster --name "$CLUSTER_NAME" 2>&1 | sed 's/^/   ↳ /'

echo "✅ Removed kind development cluster: $CLUSTER_NAME"
