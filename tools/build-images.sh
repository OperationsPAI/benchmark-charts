#!/usr/bin/env bash
#
# tools/build-images.sh <sys|all> [--push] [--verify-only]
#
# Modes:
#   build         (default) build images with unified tag YYYYMMDD-<sha>, no push
#   --push        build then push each image; verify manifest after each push
#   --verify-only skip build; verify expected tags exist in the registry
#
# hs/sn/media: iterate IMAGES[] and docker buildx each one.
# teastore:    delegate to upstream tools/build_images.sh, then verify.
#
# Must be invoked from repo root.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

SUPPORTED=(hs sn media teastore)

usage() {
  sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

MODE=build
TARGETS=()
while (( "$#" )); do
  case "$1" in
    -h|--help) usage 0 ;;
    --push) MODE=push ;;
    --verify-only) MODE=verify ;;
    all) TARGETS=("${SUPPORTED[@]}") ;;
    hs|sn|media|teastore) TARGETS+=("$1") ;;
    *) usage 2 ;;
  esac
  shift
done

(( ${#TARGETS[@]} > 0 )) || usage 2

# Load one system conf into the current shell.
load_conf() {
  local sys="$1" conf="$HERE/systems/$1.conf"
  [[ -f "$conf" ]] || die "no conf for system '$sys' at $conf"
  unset SYS FORK_URL FORK_DIR SUBPATH IMAGES
  # shellcheck disable=SC1090
  source "$conf"
  [[ -n "${SYS:-}" && -n "${FORK_URL:-}" && -n "${FORK_DIR:-}" ]] \
    || die "$conf: SYS/FORK_URL/FORK_DIR required"
}

# Build + optionally push one image of a generic (non-teastore) system.
build_one_generic() {
  local entry="$1" tag="$2" do_push="$3"
  local name df ctx
  IFS=':' read -r name df ctx <<<"$entry"
  local image="${REGISTRY}/${name}:${tag}"
  local full_ctx="${FORK_DIR}/${ctx}"
  local full_df="${FORK_DIR}/${df}"
  [[ -d "$full_ctx" ]] || die "context missing: $full_ctx"
  [[ -f "$full_df"  ]] || die "Dockerfile missing: $full_df"

  log "build: $image  (ctx=$full_ctx  df=$full_df)"
  local start end elapsed push_flag=()
  start=$(date +%s)
  if [[ "$do_push" == "1" ]]; then
    push_flag=(--push)
  else
    push_flag=(--load)
  fi
  retry 3 docker buildx build \
    -t "$image" \
    -f "$full_df" \
    "${push_flag[@]}" \
    "$full_ctx"
  end=$(date +%s); elapsed=$(( end - start ))

  if [[ "$do_push" == "1" ]]; then
    local digest
    digest="$(verify_manifest "$image")"
    log "ok: $image  build+push=${elapsed}s  digest=${digest}"
  else
    log "ok: $image  build=${elapsed}s  (not pushed)"
  fi
}

handle_generic() {
  local sys="$1"
  load_conf "$sys"
  ensure_clone "$FORK_URL" "$FORK_DIR"
  # pin to desired SHA — versions.yaml is the source of truth
  local sha; sha="$(_read_sha "$sys")"
  log "checkout $FORK_DIR @ $sha"
  git -C "$FORK_DIR" checkout -q "$sha" \
    || die "git checkout $sha failed in $FORK_DIR"
  git -C "$FORK_DIR" submodule update --init --recursive \
    || die "post-checkout submodule update failed"

  local tag; tag="$(tag_for "$sys")"
  log "system=$sys tag=$tag mode=$MODE images=${#IMAGES[@]}"

  local do_push=0
  [[ "$MODE" == "push" ]] && do_push=1

  local entry
  for entry in "${IMAGES[@]}"; do
    build_one_generic "$entry" "$tag" "$do_push"
  done
}

handle_teastore() {
  load_conf teastore
  ensure_clone "$FORK_URL" "$FORK_DIR"
  local sha; sha="$(_read_sha teastore)"
  log "checkout $FORK_DIR @ $sha"
  git -C "$FORK_DIR" checkout -q "$sha" \
    || die "git checkout $sha failed in $FORK_DIR"
  git -C "$FORK_DIR" submodule update --init --recursive || true

  local tag; tag="$(tag_for teastore)"
  local upstream="$FORK_DIR/tools/build_images.sh"
  [[ -x "$upstream" ]] || die "upstream tools/build_images.sh not found/executable: $upstream"

  local flags="-m -b"
  [[ "$MODE" == "push" ]] && flags="$flags -p"

  log "teastore: invoking upstream $upstream $flags  (REGISTRY=$REGISTRY TAG=$tag)"
  (
    cd "$FORK_DIR"
    # upstream reads these to tag+push
    REGISTRY="$REGISTRY" TAG="$tag" retry 2 bash "$upstream" $flags
  )

  if [[ "$MODE" == "push" ]]; then
    local name image digest
    for name in "${IMAGES[@]}"; do
      image="${REGISTRY}/${name}:${tag}"
      digest="$(verify_manifest "$image")"
      log "ok: $image  digest=${digest}"
    done
  fi
}

verify_only() {
  local sys="$1"
  load_conf "$sys"
  local tag; tag="$(tag_for "$sys")"
  log "verify-only: system=$sys tag=$tag"
  local name image digest failures=0
  for name in "${IMAGES[@]}"; do
    # for generic systems, IMAGES entries are "name:df:ctx" — strip
    name="${name%%:*}"
    image="${REGISTRY}/${name}:${tag}"
    if digest="$(verify_manifest "$image" 2>/dev/null)"; then
      log "ok: $image  digest=${digest}"
    else
      log "MISSING: $image"
      failures=$(( failures + 1 ))
    fi
  done
  if (( failures > 0 )); then
    die "verify-only: $failures image(s) missing for $sys"
  fi
  log "verify-only: all ${#IMAGES[@]} images present for $sys"
}

main() {
  if [[ "$MODE" != "verify" ]]; then
    docker_logged_in
  fi

  local sys
  for sys in "${TARGETS[@]}"; do
    case "$MODE" in
      verify)
        verify_only "$sys"
        ;;
      build|push)
        if [[ "$sys" == "teastore" ]]; then
          handle_teastore
        else
          handle_generic "$sys"
        fi
        ;;
    esac
  done
}

main
