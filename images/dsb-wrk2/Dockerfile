FROM ubuntu:22.04 AS builder
WORKDIR /workspace
RUN apt-get update -y && \
    apt-get install -y libssl-dev libz-dev luarocks make gcc g++ && \
    luarocks install luasocket
COPY src/ src/
COPY deps/ deps/
COPY Makefile Makefile
RUN make && make install

FROM ubuntu:22.04
RUN apt-get update -y && apt-get install -y lua5.1 liblua5.1-0 libssl3 luarocks && luarocks install luasocket && apt-get clean && rm -rf /var/lib/apt/lists/*
COPY --from=builder /usr/local/bin/wrk /usr/local/bin/wrk
COPY --from=builder /usr/local/lib/lua /usr/local/lib/lua
COPY --from=builder /usr/local/share/lua /usr/local/share/lua
COPY scripts/ /scripts/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
