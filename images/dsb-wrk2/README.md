# dsb-wrk2

Bundled wrk2 + DSB lua scripts for continuous load generation. Drop-in container for DSB (hotelReservation, socialNetwork) wrapper charts — DSB upstream ships wrk2 scripts but not a loadgen deployment, which leaves aegis fault-injection windows empty of traces.

## Build

The `src/` and `deps/` directories aren't vendored here (LuaJIT alone is ~5 MB of source and DSB's wrk2 is a pinned fork). Copy them from a DSB clone before building:

```bash
git clone --depth 1 https://github.com/delimitrou/DeathStarBench.git /tmp/dsb
cd /tmp/dsb && git submodule update --init --recursive wrk2
cp -r /tmp/dsb/wrk2/{src,deps,Makefile} <this-dir>/

docker build -t docker.io/opspai/dsb-wrk2:<tag> .
docker push docker.io/opspai/dsb-wrk2:<tag>
```

## Runtime

`entrypoint.sh` loops `wrk` forever. Required env:
- `TARGET_URL` — e.g. `http://nginx-thrift:8080/wrk2-api/post/compose`
- `LUA_SCRIPT` — e.g. `/scripts/social-network/compose-post.lua`

Optional: `THREADS` (2), `CONNS` (20), `DURATION` (30s), `RATE` (10).

Used by `charts/socialnetwork-aegis/templates/loadgen.yaml` and `charts/hotelreservation-aegis/templates/loadgen.yaml`.
