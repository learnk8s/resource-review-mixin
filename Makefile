JSONNET ?= jsonnet
JSONNETFMT ?= jsonnetfmt
JSONNET_LINT ?= jsonnet-lint
PROMTOOL ?= promtool
PINT ?= pint
DASHBOARD_LINTER ?= dashboard-linter
KUBECONFORM ?= kubeconform
JQ ?= jq
JSONNET_PATHS ?= -J vendor -J .

JSONNET_SOURCES := $(shell find . -path './kubernetes-mixin' -prune -o -path './vendor' -prune -o \( -name '*.jsonnet' -o -name '*.libsonnet' \) -print)

.PHONY: all dev dev-open dev-down generate validate check-generated fmt-check jsonnet-lint rules-test dashboard-test manifest-test config-test smoke-grafana integration-test clean

all: check-generated validate

dev:
	@./scripts/dev-kind.sh

dev-open:
	@./scripts/open-dashboard.sh

dev-down:
	@./scripts/dev-kind-down.sh

generate:
	@mkdir -p generated manifests
	$(JSONNET) $(JSONNET_PATHS) -S -m generated lib/dashboards.jsonnet
	$(JSONNET) $(JSONNET_PATHS) -S lib/rules.jsonnet > generated/prometheus-rules.yaml
	$(JSONNET) $(JSONNET_PATHS) -S lib/prometheus-rule.jsonnet > manifests/prometheus-rule.yaml
	$(JSONNET) $(JSONNET_PATHS) -S lib/dashboard-configmap.jsonnet > manifests/dashboard-configmap.yaml

fmt-check:
	@for file in $(JSONNET_SOURCES); do \
		$(JSONNETFMT) -n 2 --max-blank-lines 2 --string-style s --comment-style s --test $$file; \
	done

jsonnet-lint:
	$(JSONNET_LINT) $(JSONNET_PATHS) $(JSONNET_SOURCES)

config-test:
	$(JSONNET) $(JSONNET_PATHS) tests/config-test.jsonnet >/dev/null
	@dashboard=$$(mktemp); \
	trap 'rm -f "$$dashboard"' EXIT; \
	$(JSONNET) $(JSONNET_PATHS) tests/multicluster-dashboard.jsonnet > "$$dashboard"; \
	DASHBOARD="$$dashboard" JSONNET=$(JSONNET) PROMTOOL=$(PROMTOOL) JQ=$(JQ) ./tests/check-dashboard-promql.sh; \
	DASHBOARD="$$dashboard" EXPECT_CLUSTER=true JQ=$(JQ) ./tests/check-dashboard-structure.sh

rules-test:
	$(PROMTOOL) check rules generated/prometheus-rules.yaml
	$(PROMTOOL) test rules tests/resource-review-rules-test.yaml
	@output=$$($(PINT) -n -o -l WARN lint generated/prometheus-rules.yaml 2>&1); \
	if [ -n "$$output" ]; then echo "$$output"; exit 1; fi

dashboard-test:
	$(JQ) empty generated/resource-review.json
	JSONNET=$(JSONNET) PROMTOOL=$(PROMTOOL) JQ=$(JQ) ./tests/check-dashboard-promql.sh
	JQ=$(JQ) ./tests/check-dashboard-structure.sh
	$(DASHBOARD_LINTER) lint --strict --config .lint generated/resource-review.json

manifest-test:
	$(KUBECONFORM) \
		-kubernetes-version 1.34.0 \
		-schema-location default \
		-schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
		-strict \
		-summary \
		manifests tests/fixtures/review-workload.yaml

smoke-grafana: generate
	./tests/smoke-grafana.sh

integration-test: generate
	./tests/integration-kind.sh

validate: generate fmt-check jsonnet-lint config-test rules-test dashboard-test manifest-test

check-generated:
	@tmp_dir=$$(mktemp -d); \
	trap 'rm -rf "$$tmp_dir"' EXIT; \
	mkdir -p "$$tmp_dir/generated" "$$tmp_dir/manifests"; \
	$(JSONNET) $(JSONNET_PATHS) -S -m "$$tmp_dir/generated" lib/dashboards.jsonnet >/dev/null; \
	$(JSONNET) $(JSONNET_PATHS) -S lib/rules.jsonnet > "$$tmp_dir/generated/prometheus-rules.yaml"; \
	$(JSONNET) $(JSONNET_PATHS) -S lib/prometheus-rule.jsonnet > "$$tmp_dir/manifests/prometheus-rule.yaml"; \
	$(JSONNET) $(JSONNET_PATHS) -S lib/dashboard-configmap.jsonnet > "$$tmp_dir/manifests/dashboard-configmap.yaml"; \
	diff -ru generated "$$tmp_dir/generated"; \
	diff -ru manifests "$$tmp_dir/manifests"

clean:
	rm -f generated/resource-review.json generated/prometheus-rules.yaml
	rm -f manifests/prometheus-rule.yaml manifests/dashboard-configmap.yaml
