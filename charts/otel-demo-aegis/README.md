# otel-demo-aegis

Wrapper around the upstream [opentelemetry-demo](https://github.com/open-telemetry/opentelemetry-demo) chart for the aegis platform.

## What this changes vs upstream

- **In-chart OTel collector disabled** (`opentelemetry-collector.enabled: false`). The demo's apps still dial the Service name `otel-collector:4317`; `templates/otel-shim.yaml` provides that name as an `ExternalName` resolving to the cluster collector (`otel-collector.otel.svc.cluster.local` by default).
- **Observability stack disabled** (`jaeger`, `grafana`, `prometheus`, `opensearch`). The cluster otel-kube-stack pipeline owns traces/metrics/logs; running the demo's full stack doubles the resource footprint and fights for port conflicts on kind.
- Everything else (45 demo components, flagd, load generator) renders unchanged.

## Overriding the cluster collector

```yaml
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

Bump `dependencies.opentelemetry-demo.version` and `appVersion` in `Chart.yaml`, then `helm lint` + `helm template` to verify. The `otel-collector` Service-name assumption (via `fullnameOverride: otel-collector`) is the load-bearing bit — if upstream renames it, update `templates/otel-shim.yaml.metadata.name`.
