JSONNET ?= jsonnet
JSONNETFMT ?= jsonnetfmt
JSONNET_LINT ?= jsonnet-lint
PROMTOOL ?= promtool
PINT ?= pint
DASHBOARD_LINTER ?= dashboard-linter
KUBECONFORM ?= kubeconform
KUBECTL ?= kubectl
JQ ?= jq
JSONNET_PATHS ?= -J vendor -J .
TOOLS_BIN := $(CURDIR)/.tools/bin
export PATH := $(TOOLS_BIN):$(PATH)

ifneq ($(filter dev,$(MAKECMDGOALS)),)
ifneq ($(strip $(MAKECMDGOALS)),dev)
INVALID_DEV_INVOCATION := true
endif
endif

ifeq ($(INVALID_DEV_INVOCATION),true)
DEV_USAGE := $(if $(filter down,$(MAKECMDGOALS)),make dev-down,make dev)

.PHONY: $(MAKECMDGOALS)

dev:
	@printf '⚠️  Did you mean `$(DEV_USAGE)`?\n'

$(filter-out dev,$(MAKECMDGOALS)):
	@:

else

JSONNET_SOURCES := $(shell find . -path './kubernetes-mixin' -prune -o -path './vendor' -prune -o \( -name '*.jsonnet' -o -name '*.libsonnet' \) -print)

.PHONY: all dev dev-open dev-down tools generate validate _validate check-generated cluster-check fmt-check jsonnet-lint rules-test dashboard-test manifest-test config-test smoke-grafana integration-test clean

all: check-generated validate

tools:
	@TOOLS_BIN="$(TOOLS_BIN)" ./scripts/ensure-tools.sh

dev:
	@./scripts/dev-kind.sh

dev-open:
	@./scripts/open-dashboard.sh

dev-down:
	@./scripts/dev-kind-down.sh

generate:
	@printf '   ↳ Generating the dashboard, rules, and Kubernetes files\n'
	@output=$$({ \
		set -e; \
		tmp_dir=$$(mktemp -d); \
		trap 'rm -rf "$$tmp_dir"' EXIT; \
		mkdir -p "$$tmp_dir/generated" "$$tmp_dir/manifests"; \
		$(JSONNET) $(JSONNET_PATHS) -S -m "$$tmp_dir/generated" lib/dashboards.jsonnet; \
		$(JSONNET) $(JSONNET_PATHS) -S lib/rules.jsonnet > "$$tmp_dir/generated/prometheus-rules.yaml"; \
		$(JSONNET) $(JSONNET_PATHS) -S lib/prometheus-rule.jsonnet > "$$tmp_dir/manifests/prometheus-rule.yaml"; \
		$(JSONNET) $(JSONNET_PATHS) -S lib/dashboard-configmap.jsonnet > "$$tmp_dir/manifests/dashboard-configmap.yaml"; \
		mkdir -p generated manifests; \
		cp "$$tmp_dir/generated/resource-review.json" generated/resource-review.json; \
		cp "$$tmp_dir/generated/prometheus-rules.yaml" generated/prometheus-rules.yaml; \
		cp "$$tmp_dir/manifests/prometheus-rule.yaml" manifests/prometheus-rule.yaml; \
		cp "$$tmp_dir/manifests/dashboard-configmap.yaml" manifests/dashboard-configmap.yaml; \
	} 2>&1) || { status=$$?; printf '❌ File generation failed\n' >&2; test -z "$$output" || printf '%s\n' "$$output" >&2; exit $$status; }

fmt-check:
	@printf '   ↳ Checking Jsonnet formatting\n'
	@output=$$({ \
		set -e; \
		for file in $(JSONNET_SOURCES); do \
			$(JSONNETFMT) -n 2 --max-blank-lines 2 --string-style s --comment-style s --test $$file; \
		done; \
	} 2>&1) || { status=$$?; printf '❌ Jsonnet formatting check failed\n' >&2; test -z "$$output" || printf '%s\n' "$$output" >&2; exit $$status; }

jsonnet-lint:
	@printf '   ↳ Checking Jsonnet source\n'
	@output=$$($(JSONNET_LINT) $(JSONNET_PATHS) $(JSONNET_SOURCES) 2>&1) || { \
		status=$$?; printf '❌ Jsonnet source check failed\n' >&2; test -z "$$output" || printf '%s\n' "$$output" >&2; exit $$status; \
	}

config-test:
	@printf '   ↳ Checking configuration variants\n'
	@output=$$({ \
		set -e; \
		$(JSONNET) $(JSONNET_PATHS) tests/config-test.jsonnet >/dev/null; \
		dashboard=$$(mktemp); \
		trap 'rm -f "$$dashboard"' EXIT; \
		$(JSONNET) $(JSONNET_PATHS) tests/multicluster-dashboard.jsonnet > "$$dashboard"; \
		DASHBOARD="$$dashboard" JSONNET=$(JSONNET) PROMTOOL=$(PROMTOOL) JQ=$(JQ) ./tests/check-dashboard-promql.sh; \
		DASHBOARD="$$dashboard" EXPECT_CLUSTER=true JQ=$(JQ) ./tests/check-dashboard-structure.sh; \
	} 2>&1) || { status=$$?; printf '❌ Configuration check failed\n' >&2; test -z "$$output" || printf '%s\n' "$$output" >&2; exit $$status; }

rules-test:
	@printf '   ↳ Checking Prometheus rules\n'
	@output=$$({ \
		set -e; \
		$(PROMTOOL) check rules generated/prometheus-rules.yaml; \
		$(PROMTOOL) test rules tests/resource-review-rules-test.yaml; \
		pint_output=$$($(PINT) -n -o -l WARN lint generated/prometheus-rules.yaml 2>&1) || { \
			status=$$?; printf '%s\n' "$$pint_output"; exit $$status; \
		}; \
		if [ -n "$$pint_output" ]; then printf '%s\n' "$$pint_output"; exit 1; fi; \
	} 2>&1) || { status=$$?; printf '❌ Prometheus rule check failed\n' >&2; test -z "$$output" || printf '%s\n' "$$output" >&2; exit $$status; }

dashboard-test:
	@printf '   ↳ Checking the dashboard JSON, queries, and panels\n'
	@output=$$({ \
		set -e; \
		$(JQ) empty generated/resource-review.json; \
		JSONNET=$(JSONNET) PROMTOOL=$(PROMTOOL) JQ=$(JQ) ./tests/check-dashboard-promql.sh; \
		JQ=$(JQ) ./tests/check-dashboard-structure.sh; \
		$(DASHBOARD_LINTER) lint --strict --config .lint generated/resource-review.json; \
	} 2>&1) || { status=$$?; printf '❌ Dashboard check failed\n' >&2; test -z "$$output" || printf '%s\n' "$$output" >&2; exit $$status; }

manifest-test:
	@printf '   ↳ Checking Kubernetes files\n'
	@output=$$($(KUBECONFORM) \
		-kubernetes-version 1.34.0 \
		-schema-location default \
		-schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
		-strict \
		-summary \
		manifests tests/fixtures/review-workload.yaml 2>&1) || { \
		status=$$?; printf '❌ Kubernetes file check failed\n' >&2; test -z "$$output" || printf '%s\n' "$$output" >&2; exit $$status; \
	}

smoke-grafana: generate
	./tests/smoke-grafana.sh

integration-test: generate
	./tests/integration-kind.sh

validate: tools
	@printf '🔎 Validating source and generated files\n'
	@$(MAKE) --no-print-directory _validate
	@printf '\n✅ Validation passed.\n'

_validate: generate fmt-check jsonnet-lint config-test rules-test dashboard-test manifest-test

check-generated: tools
	@printf '🔄 Checking committed generated files\n'
	@output=$$({ \
		set -e; \
		tmp_dir=$$(mktemp -d); \
		trap 'rm -rf "$$tmp_dir"' EXIT; \
		mkdir -p "$$tmp_dir/generated" "$$tmp_dir/manifests"; \
		$(JSONNET) $(JSONNET_PATHS) -S -m "$$tmp_dir/generated" lib/dashboards.jsonnet >/dev/null; \
		$(JSONNET) $(JSONNET_PATHS) -S lib/rules.jsonnet > "$$tmp_dir/generated/prometheus-rules.yaml"; \
		$(JSONNET) $(JSONNET_PATHS) -S lib/prometheus-rule.jsonnet > "$$tmp_dir/manifests/prometheus-rule.yaml"; \
		$(JSONNET) $(JSONNET_PATHS) -S lib/dashboard-configmap.jsonnet > "$$tmp_dir/manifests/dashboard-configmap.yaml"; \
		diff -ru generated "$$tmp_dir/generated"; \
		diff -ru manifests "$$tmp_dir/manifests"; \
	} 2>&1) || { status=$$?; printf '❌ Generated files do not match the source\n' >&2; test -z "$$output" || printf '%s\n' "$$output" >&2; exit $$status; }; \
	printf '✅ Committed generated files match the source\n'

cluster-check:
	@printf '🔎 Checking Kubernetes files with the API server\n'
	@output=$$($(KUBECTL) apply --dry-run=server -f manifests/prometheus-rule.yaml 2>&1) || { \
		status=$$?; printf '❌ PrometheusRule check failed\n' >&2; test -z "$$output" || printf '%s\n' "$$output" >&2; exit $$status; \
	}; \
	printf '   ↳ PrometheusRule passed\n'
	@output=$$($(KUBECTL) apply --dry-run=server -f manifests/dashboard-configmap.yaml 2>&1) || { \
		status=$$?; printf '❌ Dashboard ConfigMap check failed\n' >&2; test -z "$$output" || printf '%s\n' "$$output" >&2; exit $$status; \
	}; \
	printf '   ↳ Dashboard ConfigMap passed\n'; \
	printf '\n✅ Kubernetes API server check passed.\n'

clean:
	rm -f generated/resource-review.json generated/prometheus-rules.yaml
	rm -f manifests/prometheus-rule.yaml manifests/dashboard-configmap.yaml

endif
