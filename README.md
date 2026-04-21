# benchmark-charts

Helm charts for the microservice benchmarks supported by
[AegisLab](https://github.com/OperationsPAI/aegis). Each chart wraps an
upstream demo app and adds:

- A static `ExternalName` Service (`opentelemetrycollector` / equivalent
  inside the release namespace) that forwards OTLP to the cluster-wide
  OTel collector configured by aegis.
- Defaults that work on a plain kind / bare-metal cluster: no LoadBalancer
  Services, no GCP-specific sidecars, no NetworkPolicies that would need
  Cilium, no reliance on unexposed cloud metadata servers.

AegisLab consumes these charts via the OCI-registry path
`oci://docker.io/opspai/<chart>`, versioned the same as the chart's
`version` field. See each chart's README for the exact values surface.

## Layout

```
charts/
  <system>-aegis/          # one directory per wrapper chart
    Chart.yaml
    values.yaml            # aegis-friendly defaults; AegisLab overrides per-deploy
    templates/
      otel-shim.yaml       # ExternalName to cluster OTel collector
    charts/<system>/       # vendored upstream subchart (see README in each)
```

## Adding a new system

1. Fork or vendor the upstream chart into `charts/<system>-aegis/charts/<system>/`.
2. Disable or override any upstream features that break on aegis-local
   (LoadBalancer, GCP-hosted services, cluster-specific TLS).
3. Add a `templates/otel-shim.yaml` that points at
   `.Values.clusterCollector.service` (`otel-collector.otel.svc.cluster.local`
   by default) — do NOT assume pods reach the cloud provider's collector.
4. Bump the chart `version`. Release is automatic on `main`.

## Release

Push to `main` runs `.github/workflows/release.yml`, which:

- Validates every `charts/*/Chart.yaml`.
- For each chart whose `version` doesn't yet exist as a git tag
  (`chart/<name>-<version>`), runs `helm package` and
  `helm push oci://docker.io/opspai`, then creates the tag.

Manual release (for the first push or if CI is down):

```bash
helm registry login docker.io -u opspai
cd charts/<system>-aegis
helm dep update    # only if Chart.yaml lists external deps
cd ..
helm package <system>-aegis
helm push <system>-aegis-*.tgz oci://docker.io/opspai
git tag chart/<system>-aegis-<version>
git push --tags
```

## Consumer configuration (AegisLab)

In `AegisLab/data/initial_data/{prod,staging}/data.yaml`, each chart gets
one `helm_configs` entry:

```yaml
helm_configs:
  - chart_name: onlineboutique-aegis
    version: 0.1.1
    repo_name: opspai
    repo_url: oci://docker.io/opspai
```

Per-environment value overrides live next to the seed file
(`ob.yaml`, `sockshop.yaml`, ...) — one file per system.
