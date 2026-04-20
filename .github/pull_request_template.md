## What changed

<!-- Describe the review need or operational failure mode. -->

## Identity and cardinality impact

<!-- Explain changes to cluster/workload/revision/UID/image labels and series count. -->

## Verification

- [ ] `make validate`
- [ ] `make check-generated`
- [ ] New PromQL behavior has a rule or dashboard test
- [ ] Dashboard changes were smoke-tested in Grafana when possible
- [ ] Identity, selector, manifest, or observation-window changes passed `make integration-test`
- [ ] Compatibility matrix was updated when a pinned version or source metric changed
- [ ] Documentation and changelog were updated
- [ ] Missing evidence is not converted to zero
- [ ] The change does not make an automatic resource recommendation
