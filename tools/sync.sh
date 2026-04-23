#!/usr/bin/env bash
# tools/sync.sh <sys|all>
#
# Convenience wrapper: build + push the images for one (or all)
# LGU-fork systems using the unified YYYYMMDD-<sha> tag. No chart
# vendoring — those 4 systems consume charts straight from the fork's
# gh-pages site.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if (( $# < 1 )); then
  echo "usage: tools/sync.sh <sys|all>" >&2
  exit 2
fi

exec "$HERE/build-images.sh" "$@" --push
