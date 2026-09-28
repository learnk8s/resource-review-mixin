#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TOOLS_BIN=${TOOLS_BIN:-"$ROOT_DIR/.tools/bin"}
PATH="$TOOLS_BIN:$PATH"
export PATH

JSONNET_VERSION=0.22.0
PROMETHEUS_VERSION=3.14.0
PINT_VERSION=0.87.0
DASHBOARD_LINTER_VERSION=0.1.0
KUBECONFORM_VERSION=0.7.0
JQ_VERSION=1.8.1

echo '🔧 Checking validation tools'

all_tools_present=true
for tool in jsonnet jsonnetfmt jsonnet-lint promtool pint dashboard-linter kubeconform jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    all_tools_present=false
    break
  fi
done

if [[ "$all_tools_present" == true ]]; then
  printf '   ↳ Jsonnet tools: found\n'
  for tool in promtool Pint dashboard-linter kubeconform jq; do
    printf '   ↳ %s: found\n' "$tool"
  done
  echo '✅ Validation tools are ready.'
  exit 0
fi

fail() {
  printf '❌ %s\n' "$1" >&2
  if [[ -n "${2:-}" ]]; then
    printf '   %s\n' "$2" >&2
  fi
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Required bootstrap command not found: $1." "Install $1 and run make validate again."
  fi
}

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) fail "Unsupported operating system: $(uname -s)." 'Use Linux or macOS.' ;;
esac

case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) fail "Unsupported processor architecture: $(uname -m)." 'Use amd64 or arm64.' ;;
esac

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    fail 'No SHA-256 command was found.' 'Install sha256sum or shasum and run make validate again.'
  fi
}

checksum() {
  case "$1:$os:$arch" in
    jsonnet:linux:amd64) printf '%s' 'e87a93ea44e34da92c15636205c7f2240bf3ac92d00ccb855dbb4e7e03ea6941' ;;
    jsonnet:linux:arm64) printf '%s' '3016b049254cb92548ba99304b6f44ec3795e6173f908e3ce3c5add57243fe20' ;;
    jsonnet:darwin:amd64) printf '%s' '2ada40ece13e8b4e1f37c06315783110c84b496963b0b8b90809daf69df7dfc9' ;;
    jsonnet:darwin:arm64) printf '%s' '112534191b6e27f2ae01bb80c6ab82950fb7bf5772e2e81c5472f59a069700f5' ;;
    promtool:linux:amd64) printf '%s' 'f665c6da19eb7ba399c915d30c7d9793c9b417bf8a749b504bc470678631478d' ;;
    promtool:linux:arm64) printf '%s' '077f3781ab7245dc04c9a3c9b78ba120fc8e41aa0dc97489b0af67247e50ba83' ;;
    promtool:darwin:amd64) printf '%s' 'a14307b9726e66cadb81be9a544732623af26dabeb7702c987aa9c3c062ada34' ;;
    promtool:darwin:arm64) printf '%s' 'a9623f7f4fe65b1b171b423c1a72bbf23dfdf41a171dcb33e7dd302af80dc01c' ;;
    pint:linux:amd64) printf '%s' 'f0e91491f10adbb9bf2bdefd213eb63c92685ae4565aee340b9eec6fb7ff4049' ;;
    pint:linux:arm64) printf '%s' 'fd9709d755c1e1c01526c9957fb4a43d58aa1ba2f46da5ef4f83bfb05b52b6a8' ;;
    pint:darwin:amd64) printf '%s' '03dd3d715c63022f4f02bf3f8f164b2db193f3ebf479aa9928912ec7fef0f358' ;;
    pint:darwin:arm64) printf '%s' '6afb6c6425e8a8b4e261068083884597a70b3502e53386ccc9a7cf5fed79b843' ;;
    dashboard-linter:linux:amd64) printf '%s' 'a51970b1b7db199a1e557fcf8442e2c65dd8341df05d06cb7bd699206c7c5bbd' ;;
    dashboard-linter:linux:arm64) printf '%s' 'c0bff10cecd0b11b17b807883fbfeffbe57b6768c3904748e583f49a37bb7930' ;;
    dashboard-linter:darwin:amd64) printf '%s' '01008ad35afb48ef4691adb5f94d64b16eb894ec358b527fb63d32f936e01656' ;;
    dashboard-linter:darwin:arm64) printf '%s' '23ae4b7a0f6ef62ce36c3dcfb63fdbf63349a03949726ac153835e61b9eb0c61' ;;
    kubeconform:linux:amd64) printf '%s' 'c31518ddd122663b3f3aa874cfe8178cb0988de944f29c74a0b9260920d115d3' ;;
    kubeconform:linux:arm64) printf '%s' 'cc907ccf9e3c34523f0f32b69745265e0a6908ca85b92f41931d4537860eb83c' ;;
    kubeconform:darwin:amd64) printf '%s' 'c6771cc894d82e1b12f35ee797dcda1f7da6a3787aa30902a15c264056dd40d4' ;;
    kubeconform:darwin:arm64) printf '%s' 'b5d32b2cb77f9c781c976b20a85e2d0bc8f9184d5d1cfe665a2f31a19f99eeb9' ;;
    jq:linux:amd64) printf '%s' '020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d' ;;
    jq:linux:arm64) printf '%s' '6bc62f25981328edd3cfcfe6fe51b073f2d7e7710d7ef7fcdac28d4e384fc3d4' ;;
    jq:darwin:amd64) printf '%s' 'e80dbe0d2a2597e3c11c404f03337b981d74b4a8504b70586c354b7697a7c27f' ;;
    jq:darwin:arm64) printf '%s' 'a9fe3ea2f86dfc72f6728417521ec9067b343277152b114f4e98d8cb0e263603' ;;
    *) fail "No checksum is configured for $1 on $os/$arch." ;;
  esac
}

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/resource-review-tools.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$TOOLS_BIN"

download() {
  local url=$1
  local destination=$2

  require_command curl
  if ! curl \
      --proto '=https' \
      --tlsv1.2 \
      --fail \
      --location \
      --retry 3 \
      --silent \
      --show-error \
      "$url" \
      --output "$destination" >/dev/null 2>&1; then
    fail 'Could not download a validation tool.' 'Check the network connection and access to github.com, then retry.'
  fi
}

verify() {
  local package=$1
  local file=$2
  local expected actual

  expected=$(checksum "$package")
  actual=$(sha256_file "$file")
  if [[ "$actual" != "$expected" ]]; then
    fail "Checksum verification failed for $package." 'The downloaded file was removed and was not installed.'
  fi
}

install_binary() {
  local source=$1
  local name=$2
  local pending="$TOOLS_BIN/.$name.$$"

  cp "$source" "$pending"
  chmod 0755 "$pending"
  mv "$pending" "$TOOLS_BIN/$name"
}

install_archive_member() {
  local archive=$1
  local member=$2
  local name=$3

  require_command tar
  if ! tar -tzf "$archive" | grep --fixed-strings --line-regexp "$member" >/dev/null; then
    fail "Expected file was not found in the $name archive." 'The downloaded file was not installed.'
  fi
  tar -xzf "$archive" -C "$work_dir" "$member"
  install_binary "$work_dir/$member" "$name"
}

found() {
  printf '   ↳ %s: found\n' "$1"
}

if command -v jsonnet >/dev/null 2>&1 &&
  command -v jsonnetfmt >/dev/null 2>&1 &&
  command -v jsonnet-lint >/dev/null 2>&1; then
  found 'Jsonnet tools'
else
  archive="go-jsonnet_${JSONNET_VERSION}_${os}_${arch}.tar.gz"
  url="https://github.com/google/go-jsonnet/releases/download/v${JSONNET_VERSION}/${archive}"
  echo "   ↳ Installing Jsonnet tools $JSONNET_VERSION"
  download "$url" "$work_dir/$archive"
  verify jsonnet "$work_dir/$archive"
  for tool in jsonnet jsonnetfmt jsonnet-lint; do
    install_archive_member "$work_dir/$archive" "$tool" "$tool"
  done
fi

if command -v promtool >/dev/null 2>&1; then
  found promtool
else
  archive="prometheus-${PROMETHEUS_VERSION}.${os}-${arch}.tar.gz"
  url="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${archive}"
  echo "   ↳ Installing promtool $PROMETHEUS_VERSION"
  download "$url" "$work_dir/$archive"
  verify promtool "$work_dir/$archive"
  install_archive_member "$work_dir/$archive" "prometheus-${PROMETHEUS_VERSION}.${os}-${arch}/promtool" promtool
fi

if command -v pint >/dev/null 2>&1; then
  found Pint
else
  archive="pint-${PINT_VERSION}-${os}-${arch}.tar.gz"
  url="https://github.com/cloudflare/pint/releases/download/v${PINT_VERSION}/${archive}"
  echo "   ↳ Installing Pint $PINT_VERSION"
  download "$url" "$work_dir/$archive"
  verify pint "$work_dir/$archive"
  install_archive_member "$work_dir/$archive" "pint-${os}-${arch}" pint
fi

if command -v dashboard-linter >/dev/null 2>&1; then
  found dashboard-linter
else
  archive="dashboard-linter_${DASHBOARD_LINTER_VERSION}_${os}_${arch}.tar.gz"
  url="https://github.com/grafana/dashboard-linter/releases/download/v${DASHBOARD_LINTER_VERSION}/${archive}"
  echo "   ↳ Installing dashboard-linter $DASHBOARD_LINTER_VERSION"
  download "$url" "$work_dir/$archive"
  verify dashboard-linter "$work_dir/$archive"
  install_archive_member "$work_dir/$archive" dashboard-linter dashboard-linter
fi

if command -v kubeconform >/dev/null 2>&1; then
  found kubeconform
else
  archive="kubeconform-${os}-${arch}.tar.gz"
  url="https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/${archive}"
  echo "   ↳ Installing kubeconform $KUBECONFORM_VERSION"
  download "$url" "$work_dir/$archive"
  verify kubeconform "$work_dir/$archive"
  install_archive_member "$work_dir/$archive" kubeconform kubeconform
fi

if command -v jq >/dev/null 2>&1; then
  found jq
else
  if [[ "$os" == darwin ]]; then
    asset="jq-macos-$arch"
  else
    asset="jq-linux-$arch"
  fi
  url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/${asset}"
  echo "   ↳ Installing jq $JQ_VERSION"
  download "$url" "$work_dir/$asset"
  verify jq "$work_dir/$asset"
  install_binary "$work_dir/$asset" jq
fi

echo '✅ Validation tools are ready.'
