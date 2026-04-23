# otel-demo-aegis

Wrapper around the repo-local `otel-demo/` baseline for the aegis platform.

## What this changes vs upstream

- **In-chart OTel collector kept** (`opentelemetry-collector.enabled: true`). Demo components still dial the namespace-local Service name `otel-collector:4317`, but that collector now forwards traces, metrics, and logs upstream to the cluster collector (`otel-collector.otel.svc.cluster.local:4317` by default).
- **No cluster-scoped RBAC from the demo chart**. The wrapper disables the collector's `kubernetesAttributes` preset so installs in namespaces such as `otel-demo10`, `otel-demo11`, and `otel-demo12` do not fight over a shared `ClusterRole` / `ClusterRoleBinding`.
- **No cross-namespace `ExternalName` shim**. Each release keeps its own stable `otel-collector` Service, so namespaces such as `otel-demo0` and `otel-demo1` do not depend on cross-namespace DNS aliases.
- **Observability stack disabled** (`jaeger`, `grafana`, `prometheus`, `opensearch`). The cluster otel-kube-stack pipeline owns traces/metrics/logs; the local demo backends are not rendered.
- **Collector config replaced for aegis**. The wrapper swaps out the root chart's ClickHouse-oriented collector config and exports traces, metrics, and logs upstream to the cluster collector over OTLP instead.
- Everything else (45 demo components, flagd, load generator) renders unchanged.

## Overriding the cluster collector

```yaml
global:
  clusterCollector:
    service: my-collector.monitoring.svc.cluster.local
```

## How to upgrade upstream

The vendored subchart lives at `charts/opentelemetry-demo/` and should be refreshed from the repo-local `otel-demo/` directory.

```bash
rm -rf charts/otel-demo-aegis/charts/opentelemetry-demo
cp -r otel-demo charts/otel-demo-aegis/charts/opentelemetry-demo
```

After refreshing the vendored copy, re-apply the wrapper-only overrides in `values.yaml`, then run `helm lint` + `helm template` to verify. The `otel-collector` Service-name assumption (via `fullnameOverride: otel-collector`) is still the load-bearing bit.
