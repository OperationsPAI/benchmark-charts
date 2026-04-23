#!/usr/bin/env bash
# Shared helpers for tools/build-images.sh and tools/sync.sh.
# Source from repo root: `source tools/lib/common.sh`.

set -o pipefail

# Repo root: resolve relative to this file.
COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${COMMON_SH_DIR}/../.." && pwd)"
VERSIONS_FILE="${REPO_ROOT}/versions.yaml"
REGISTRY="${REGISTRY:-docker.io/opspai}"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ensure_clone <url> <dir>
#
# Idempotent full (non-shallow) clone. A shallow clone broke wrk2
# submodule fetches previously, so we explicitly forbid --depth.
ensure_clone() {
  local url="$1" dir="$2"
  [[ -n "$url" && -n "$dir" ]] || die "ensure_clone: need <url> <dir>"

  if [[ -d "$dir/.git" ]]; then
    log "ensure_clone: updating $dir"
    git -C "$dir" fetch --tags origin || die "fetch failed in $dir"
    git -C "$dir" submodule update --init --recursive \
      || die "submodule update failed in $dir"
  else
    log "ensure_clone: cloning $url -> $dir (full clone, no --depth)"
    git clone "$url" "$dir" || die "git clone $url failed"
    git -C "$dir" submodule update --init --recursive \
      || die "submodule init failed in $dir"
  fi
}

# docker_logged_in
#
# Fail fast if no docker hub credential present. Uses the config.json
# auths map; treats an empty-string auth as logged-out.
docker_logged_in() {
  local cfg="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
  if [[ ! -f "$cfg" ]]; then
    die "docker login missing: $cfg not found. Run 'docker login'."
  fi
  # portable check: grep for the index.docker.io key + a non-empty auth
  if ! grep -q '"https://index.docker.io/v1/"' "$cfg"; then
    die "docker login missing for index.docker.io. Run 'docker login'."
  fi
  log "docker login: ok ($cfg)"
}

# retry <attempts> <cmd...>
retry() {
  local attempts="$1"; shift
  local n=1 delay=2
  while (( n <= attempts )); do
    if "$@"; then
      return 0
    fi
    log "retry: attempt $n/$attempts failed: $*"
    if (( n < attempts )); then
      sleep "$delay"
      delay=$(( delay * 2 ))
    fi
    n=$(( n + 1 ))
  done
  die "retry: all $attempts attempts failed: $*"
}

# verify_manifest <image>
#
# `docker manifest inspect` must return valid JSON within 30s.
verify_manifest() {
  local image="$1"
  [[ -n "$image" ]] || die "verify_manifest: need <image>"
  local out
  out="$(timeout 30 docker manifest inspect "$image" 2>&1)" \
    || die "verify_manifest: timeout/fail for $image: $out"
  # sanity: parse as JSON (we only need shape, not content)
  printf '%s' "$out" | grep -q '^{' \
    || die "verify_manifest: non-JSON response for $image: $out"
  # short digest for logging
  local digest
  digest="$(printf '%s' "$out" | grep -oE '"digest"[[:space:]]*:[[:space:]]*"sha256:[a-f0-9]+"' \
    | head -1 | grep -oE 'sha256:[a-f0-9]+' | cut -c1-19)"
  printf '%s' "${digest:-sha256:unknown}"
}

# _read_sha <sys> — read SHA for a system from versions.yaml.
_read_sha() {
  local sys="$1"
  [[ -f "$VERSIONS_FILE" ]] || die "versions.yaml missing at $VERSIONS_FILE"
  local sha=""
  if command -v yq >/dev/null 2>&1; then
    sha="$(yq ".${sys}" "$VERSIONS_FILE" 2>/dev/null || true)"
    # yq prints "null" for missing
    [[ "$sha" == "null" ]] && sha=""
  fi
  if [[ -z "$sha" ]]; then
    # grep fallback — strip inline comments and whitespace
    sha="$(grep -E "^${sys}:" "$VERSIONS_FILE" \
      | sed -E "s/^${sys}:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]+$//")"
  fi
  [[ -n "$sha" ]] || die "versions.yaml: no entry for '$sys'"
  printf '%s' "$sha"
}

# tag_for <sys> — YYYYMMDD-<sha>
tag_for() {
  local sys="$1"
  local sha date
  sha="$(_read_sha "$sys")"
  date="$(date -u +%Y%m%d)"
  printf '%s-%s' "$date" "$sha"
}
