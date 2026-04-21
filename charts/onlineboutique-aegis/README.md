# onlineboutique-aegis

Wrapper chart around
[Google's microservices-demo](https://github.com/GoogleCloudPlatform/microservices-demo)
(the "Online Boutique" cloud-native demo) with aegis-friendly defaults.

## What this chart adds

1. **ExternalName OTel shim.** Upstream gates `COLLECTOR_SERVICE_ADDR` on
   `opentelemetryCollector.create=true` (otherwise the env var is never
   set and apps emit no traces). We keep `create: true` but empty out
   the subchart's collector template so helm doesn't try to install a
   GCP-bound collector that would crashloop without `PROJECT_ID`.
   Instead, `templates/otel-shim.yaml` renders a plain `ExternalName`
   Service pointing at `otel-collector.otel.svc.cluster.local` — the
   cluster-wide aegis OTel collector.

2. **Kind-safe defaults.** `frontend.externalService: false`
   (no LoadBalancer in kind); `networkPolicies`, `sidecars`,
   `authorizationPolicies`, `shoppingAssistantService` all default off.

3. **Vendored subchart.** `charts/onlineboutique` is a trimmed copy of
   upstream 0.10.5 with only `templates/opentelemetry-collector.yaml`
   emptied out. Easier than fighting `dependencies:` on a chart that
   upstream doesn't publish to a helm repo.

## Values

Only one knob worth overriding in most cases:

```yaml
clusterCollector:
  service: otel-collector.otel.svc.cluster.local
```

Everything else (`onlineboutique.*`) is a passthrough to the upstream
chart; see
[upstream values.yaml](https://github.com/GoogleCloudPlatform/microservices-demo/blob/main/helm-chart/values.yaml)
for the full list. The defaults baked in here should work unchanged on
the `aegis-local` kind cluster.

## Upgrading the upstream version

```bash
# from repo root
rm -rf charts/onlineboutique-aegis/charts/onlineboutique
helm pull --untar --untardir charts/onlineboutique-aegis/charts \
  https://github.com/GoogleCloudPlatform/microservices-demo/raw/v0.XX.X/helm-chart
# (or git clone + cp; upstream does not publish a helm repo)

# empty out the GCP-bound collector template:
: > charts/onlineboutique-aegis/charts/onlineboutique/templates/opentelemetry-collector.yaml
echo "# Subchart collector disabled by onlineboutique-aegis wrapper." \
  > charts/onlineboutique-aegis/charts/onlineboutique/templates/opentelemetry-collector.yaml

# bump Chart.yaml version + appVersion to match upstream.
```
