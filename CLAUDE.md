# CLAUDE.md

This file briefs Claude Code (claude.ai/code) on how to manage the
benchmark Helm charts in this repo. Read it before adding a new chart
or bumping an existing one.

## What this repo is

A single-purpose Helm chart registry + image build pipeline for the
microservice benchmarks supported by
[AegisLab](https://github.com/OperationsPAI/aegis). Each wrapper chart
adapts an upstream demo app for the aegis platform: kind-safe defaults,
a standard ExternalName shim that forwards OTLP to the cluster OTel
collector, disabled upstream features that assume cloud-provider
infrastructure.

**LGU-fork systems (hs / sn / media / teastore) are not wrapped here.**
For those four we consume the helm chart directly from the fork's own
gh-pages site
(`https://lgu-se-internal.github.io/{DeathStarBench,TeaStore}/`) and
this repo only owns the container images — see `tools/` and
`versions.yaml`. The LGU fork already provides an aegis-friendly chart
(configurable OTel endpoint, kind-safe), so wrapping it again would
just add drift.

Wrapping is still retained for:
- `onlineboutique-aegis` — upstream is GoogleCloudPlatform's
  microservices-demo; no aegis-friendly chart upstream.
- `otel-demo-aegis` — upstream is open-telemetry/opentelemetry-demo;
  needs kind-safe + OTel-endpoint overrides.
- `sockshop-aegis` — pending rework; upstream is abandoned-ish.

For those three we own the wrapping — we do not fork the upstream app.
The upstream chart is vendored under
`charts/<system>-aegis/charts/<system>/` and kept as close to stock as
practical; only the pieces that break on our infra get patched out.

## Repo layout

```
charts/
  <system>-aegis/                     # one directory per wrapper chart
    Chart.yaml                        # name: <system>-aegis, dependencies.onlineboutique{}
    values.yaml                       # aegis defaults (consumer overrides via AegisLab seed)
    README.md                         # chart-specific notes (how the upstream was vendored, etc.)
    templates/
      otel-shim.yaml                  # ExternalName → clusterCollector.service
    charts/<system>/                  # vendored upstream chart, lightly patched
.github/workflows/release.yml          # on push to main: package + OCI push + tag
```

## Adding a new chart

**Wrapping is the fallback, not the default.** If the upstream (or a
trusted fork like `LGU-SE-Internal/*`) already publishes its own chart
via a gh-pages workflow AND that chart is aegis-friendly (configurable
OTel endpoint, kind-safe, no cloud-only Services), skip wrapping
entirely: register the chart directly in the aegis seed with values
overrides, and — if you also own the images — add a `tools/systems/`
conf + a `versions.yaml` entry so image builds stay reproducible.

Only fall through to a wrapper chart when the upstream hardcodes the
OTLP collector address, ships LoadBalancer Services or cloud agents,
or otherwise can't be configured via values.

When wrapping is needed, use an existing chart as the template — right
now `onlineboutique-aegis` is the reference:

1. `cp -r charts/onlineboutique-aegis charts/<new>-aegis`
2. Remove the vendored subchart, pull the new upstream in. Upstreams
   that don't publish a helm repo (most of ours) need a manual copy:
   ```bash
   rm -rf charts/<new>-aegis/charts/<system>
   # option A: git clone + copy
   # option B: helm pull --untar if upstream has a repo
   ```
   Commit the whole subchart tree. Yes, it's hundreds of files. Yes,
   that's fine — reproducibility beats cleanliness.
3. Edit `charts/<new>-aegis/Chart.yaml`:
   - `name`: `<system>-aegis`
   - `version`: start at `0.1.0`
   - `appVersion`: match the upstream version exactly
   - `dependencies.<system>.version`: the vendored version
4. Edit `charts/<new>-aegis/values.yaml`:
   - `clusterCollector.service` defaults to
     `otel-collector.otel.svc.cluster.local`.
   - Under `<system>:`, disable anything that needs cloud infra:
     LoadBalancer Services, GCP-bound agents, NetworkPolicies that
     assume Cilium, upstream OTel collectors that need `PROJECT_ID`.
     See the onlineboutique `values.yaml` for the canonical set.
5. Rewrite `templates/otel-shim.yaml` for the new app:
   - `metadata.name` must match the Service name the upstream wires
     into its pods via `COLLECTOR_SERVICE_ADDR` (or equivalent).
   - Ports must cover both the grpc (4317) and http (4318) OTLP ports
     the apps try to reach, even if only one is used — upstream SDKs
     sometimes probe both.
6. If the upstream's OTel collector template would crashloop (most do),
   empty it out (keep the file, just blank contents with a one-line
   explanatory comment):
   ```bash
   echo "# Disabled by <new>-aegis wrapper: see README" \
     > charts/<new>-aegis/charts/<system>/templates/<collector>.yaml
   ```
7. Write `charts/<new>-aegis/README.md`: one section per non-obvious
   override, a "how to upgrade upstream" recipe at the bottom.
8. Verify: `helm lint charts/<new>-aegis` must pass,
   `helm template charts/<new>-aegis` must render without errors.
9. Commit: `chore(<new>): bootstrap <new>-aegis 0.1.0`.

Push to `main` → CI packages and publishes automatically (see below).

## Bumping an existing chart

Chart version bumps only happen when something changes. Rules:

- **Patch bump** (`0.1.0 → 0.1.1`) for values defaults, template fixes,
  subchart template patches.
- **Minor bump** for upstream vendored-subchart version upgrades,
  significant default behaviour changes.
- **Major bump** for breaking interface changes (renaming
  `clusterCollector.service`, renaming the ExternalName service, etc.)
  — these also need a corresponding change in the AegisLab seed.

The CI skips any chart whose `version` already exists as a git tag
(`chart/<name>-<version>`). So forgetting to bump is a harmless no-op,
not a broken release.

## How releases work

`.github/workflows/release.yml` runs on every push to `main`:

1. `helm show chart` each `charts/*/Chart.yaml` to read `name`, `version`.
2. For each `(name, version)` whose `chart/<name>-<version>` tag does NOT
   already exist:
   - `helm dependency update` (no-op when deps are vendored).
   - `helm package` → `dist/<name>-<version>.tgz`.
   - `helm push` to `oci://registry-1.docker.io/opspai`.
   - `git tag chart/<name>-<version> && git push origin <tag>`.

The tag is the source of truth for "was this version published". Don't
delete tags; cut a new version instead.

### One-time CI prerequisite

Before CI can push anything, the repo needs two secrets in
**Settings → Secrets and variables → Actions**:

- `DOCKERHUB_USERNAME` — the account pushing to `opspai/*` (currently
  just `opspai`).
- `DOCKERHUB_TOKEN` — a Docker Hub Personal Access Token with
  Read/Write/Delete scope on `opspai`. Never reuse a DockerHub password.

Without these, the workflow fails at the `helm registry login` step and
no charts get published, but nothing destructive happens.

### Manual release (CI down, or first-ever push)

Run locally from the repo root:

```bash
helm registry login registry-1.docker.io -u opspai
helm lint charts/<name>-aegis
helm package charts/<name>-aegis --destination dist
helm push dist/<name>-aegis-<version>.tgz oci://registry-1.docker.io/opspai
git tag chart/<name>-aegis-<version>
git push origin chart/<name>-aegis-<version>
```

Verify from a different machine:

```bash
helm pull oci://registry-1.docker.io/opspai/<name>-aegis --version <version>
```

## Consumer contract (AegisLab)

AegisLab reads `data/initial_data/{prod,staging}/data.yaml`. Every
chart in this repo needs a corresponding seed entry over there:

```yaml
  - type: 2                                # 2 = pedestal (workload under test)
    name: <name>                           # e.g. ob
    is_public: true
    status: 1
    versions:
      - name: <chart-version>              # 0.1.1
        github_link: <upstream repo>       # GoogleCloudPlatform/microservices-demo
        status: 1
        helm_config:
          version: <chart-version>         # 0.1.1
          chart_name: <name>-aegis         # onlineboutique-aegis
          repo_name: opspai
          repo_url: oci://registry-1.docker.io/opspai
          status: 1
          values:                          # optional — inline overrides per env
            - {key: ..., value_type: 0, default_value: ..., overridable: true}
```

If a new chart version breaks the values contract, both this repo's
chart AND AegisLab's seed change in the same PR cycle — don't ship one
without the other.

## Conventions

- **Naming.** Chart directory and `Chart.yaml.name` are both
  `<system>-aegis`. The vendored subchart under `charts/<system>/`
  keeps the upstream's original name. This keeps the dependency block
  stable: `dependencies: [{name: <system>, repository: ""}]`.

- **Kind-safe defaults.** No LoadBalancer Services, no post-install
  hooks (aegis's helm gateway uses `Wait=true`; hooks fire AFTER Wait,
  which deadlocks), no cert-manager-provided secrets. If the upstream
  needs any of these, either disable via values or patch the subchart
  template.

- **OTel shim, only when needed.** A wrapper's `templates/otel-shim.yaml`
  (an `ExternalName` Service — never a Deployment) is included **only
  if the upstream hardcodes the OTLP collector address and can't be
  reconfigured via values**. When the upstream exposes a normal
  `otlpExporter.endpoint` / `OTEL_EXPORTER_OTLP_ENDPOINT` value, point
  it at the cluster collector directly and skip the shim. The real
  collector lives in the cluster's `otel` namespace (see
  AegisLab/manifests/otel-collector/); wrappers must never
  re-implement it, and must never hardcode its address anywhere other
  than `.Values.clusterCollector.service`.

- **One-way upstream vendoring.** Never commit modifications to files
  under `charts/<system>-aegis/charts/<system>/` unless you can't
  achieve the same thing via values. If you DO modify, leave a
  `# wrapper-patched: <reason>` comment at the top of every modified
  file so upgrades can re-apply the change.

- **No CI secrets in commits.** The workflow reads `DOCKERHUB_*` from
  GitHub secrets; don't add a `.env` or set defaults.

## Related issues (aegis repo)

- [OperationsPAI/aegis#92](https://github.com/OperationsPAI/aegis/issues/92)
  — parent issue for this repo.
- [OperationsPAI/aegis#99](https://github.com/OperationsPAI/aegis/issues/99)
  — outstanding follow-ups on the consumer side (collector config
  convergence, validator policy, legacy Service name coupling).
- Per-system sub-issues: #94 (hotel), #95 (media), #96 (sn), #97 (tea),
  #98 (sockshop). #93 (ob) is closed as the reference implementation.
