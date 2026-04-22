# otel-demo-aegis

Wrapper around the upstream [opentelemetry-demo](https://github.com/open-telemetry/opentelemetry-demo) chart for the aegis platform.

## What this changes vs upstream

- **In-chart OTel collector kept** (`opentelemetry-collector.enabled: true`). Demo components still dial the namespace-local Service name `otel-collector:4317`, but that collector now forwards traces, metrics, and logs upstream to the cluster collector (`otel-collector.otel.svc.cluster.local:4317` by default).
- **No cross-namespace `ExternalName` shim**. Each release keeps its own stable `otel-collector` Service, so namespaces such as `otel-demo0` and `otel-demo1` do not depend on cross-namespace DNS aliases.
- **Observability stack disabled** (`jaeger`, `grafana`, `prometheus`, `opensearch`). The cluster otel-kube-stack pipeline owns traces/metrics/logs; running the demo's full stack doubles the resource footprint and fights for port conflicts on kind.
- **Local collector exports OTLP only**. The wrapper repoints the demo collector away from Jaeger/Prometheus/OpenSearch and sends all signals straight to the cluster collector, so this chart does not need local ClickHouse or other backend wiring.
- Everything else (45 demo components, flagd, load generator) renders unchanged.

## Overriding the cluster collector

```yaml
global:
  clusterCollector:
    service: my-collector.monitoring.svc.cluster.local
```

## How to upgrade upstream

The vendored subchart lives at `charts/opentelemetry-demo/`.

```bash
helm pull open-telemetry/opentelemetry-demo --version <new> --untar --untardir /tmp
rm -rf charts/opentelemetry-demo
cp -r /tmp/opentelemetry-demo charts/
```

Bump `dependencies.opentelemetry-demo.version` and `appVersion` in `Chart.yaml`, then `helm lint` + `helm template` to verify. The `otel-collector` Service-name assumption (via `fullnameOverride: otel-collector`) is still the load-bearing bit — if upstream renames it, update the wrapper's collector overrides in `values.yaml`.
