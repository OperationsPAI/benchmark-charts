#!/bin/bash
# DSB load generator. Loops wrk2 forever against ${TARGET_URL} using ${LUA_SCRIPT}.
# Env:
#   TARGET_URL   - e.g. http://nginx-thrift:8080/wrk2-api/post/compose
#   LUA_SCRIPT   - absolute path inside container, e.g. /scripts/social-network/compose-post.lua
#   THREADS      - wrk threads (default 2)
#   CONNS        - concurrent connections (default 20)
#   DURATION     - per-batch duration (default 30s; loop runs until killed)
#   RATE         - target requests/sec (default 10)
set -u
: "${TARGET_URL:?TARGET_URL required}"
: "${LUA_SCRIPT:?LUA_SCRIPT required}"
THREADS=${THREADS:-2}
CONNS=${CONNS:-20}
DURATION=${DURATION:-30s}
RATE=${RATE:-10}

echo "[dsb-wrk2] target=$TARGET_URL script=$LUA_SCRIPT t=$THREADS c=$CONNS d=$DURATION r=$RATE"

# Wait briefly for target DNS
for i in $(seq 1 30); do
  getent hosts "$(echo "$TARGET_URL" | awk -F/ '{print $3}' | cut -d: -f1)" >/dev/null && break
  sleep 2
done

while true; do
  wrk -t "$THREADS" -c "$CONNS" -d "$DURATION" -L -s "$LUA_SCRIPT" "$TARGET_URL" -R "$RATE" || true
  sleep 1
done
