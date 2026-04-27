# tools/

Image build + push tooling for the four LGU-forked benchmarks that
don't publish their own images:

| system     | alias      | fork                                                     | tag scheme           |
| ---------- | ---------- | -------------------------------------------------------- | -------------------- |
| Hotel Reservation | `hs`       | `LGU-SE-Internal/DeathStarBench` (hotelReservation)      | `YYYYMMDD-<sha>`     |
| Social Network    | `sn`       | `LGU-SE-Internal/DeathStarBench` (socialNetwork)         | `YYYYMMDD-<sha>`     |
| Media Microservices | `media`  | `LGU-SE-Internal/DeathStarBench` (mediaMicroservices)    | `YYYYMMDD-<sha>`     |
| TeaStore   | `teastore` | `LGU-SE-Internal/TeaStore`                               | `YYYYMMDD-<sha>`     |

We no longer wrap these charts — they're published directly from the
forks' gh-pages workflows
(`https://lgu-se-internal.github.io/DeathStarBench/`,
`https://lgu-se-internal.github.io/TeaStore/`). This repo only owns
their container images.

**SockShop (`ss`) is fully self-hosted in its fork** and is NOT listed
above. The `LGU-SE-Internal/coherence-helidon-sockshop-sample` fork
publishes both its chart (gh-pages at
`https://lgu-se-internal.github.io/coherence-helidon-sockshop-sample/`)
and its images (`docker.io/opspai/ss-*` at tag `YYYYMMDD-<sha>`) from
its own CI workflows. Nothing in this repo drives its build pipeline —
bump the fork SHA there, not here.

## `versions.yaml`

Single source of truth for which upstream commit SHA each system is
pinned to. Bumping `versions.yaml` on `main` now triggers
`.github/workflows/build-images.yml` — manual `sync.sh` is only needed
for local debugging.

```bash
tools/sync.sh hs        # one system
tools/sync.sh all       # all four
```

The tag is computed as `YYYYMMDD-<sha>` at sync time; today's date
plus the SHA from `versions.yaml`.

## Scripts

- `tools/build-images.sh <sys|all> [--push] [--verify-only]` — main
  entry. Default mode is build-only (no push). `--push` builds and
  pushes; `--verify-only` just checks that the expected tags exist in
  the registry.
- `tools/sync.sh <sys|all>` — shorthand for `build-images.sh … --push`.
- `tools/lib/common.sh` — shared helpers (non-shallow clone, docker-
  login sanity check, retry, manifest verification, tag derivation).
- `tools/systems/<sys>.conf` — per-system bash config listing the
  images, Dockerfile paths, and build contexts.

## Prerequisites

- Run from the repo root.
- `docker login` on Docker Hub with push rights to `docker.io/opspai`.
- `docker buildx` set up for multi-arch builds.
- ~30 GB free on the clone cache (`/tmp/dsb-lgu`, `/tmp/teastore-lgu`)
  and whatever Docker uses.

## Bumping a fork

1. Edit the SHA in `versions.yaml`.
2. `tools/sync.sh <sys>`.
3. Check the registry for the new tag, then have the chart consumer
   (aegis seed) point at the new tag.
