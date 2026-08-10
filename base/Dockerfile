# Shared base image for all cardano-ignite images. Holds the single Debian
# pin, the default curl options (fail fast on unreachable hosts, retry
# transient failures) and the common debugging toolbox every container
# should carry, so every derived stage inherits them in one shared layer
# instead of each image installing its own copy. Built by 'make build' as
# cardano-ignite-base and passed to the other Dockerfiles via the
# BASE_IMAGE build argument.
FROM docker.io/debian:stable-20260803-slim

# connect-timeout/retry guard the connection phase; speed-limit/speed-time
# abort a transfer that stalls after connecting (below 1 kB/s for 30s),
# which would otherwise hang a build forever.
RUN printf 'connect-timeout = 15\nretry = 5\nspeed-limit = 1000\nspeed-time = 30\n' > /root/.curlrc

# git does not read curlrc and has no default timeout, so a stalled
# connection hangs a build forever. Abort any git transfer that drops
# below 1 kB/s for 30 seconds; the build fails loudly and a rerun
# resumes from the layer cache.
RUN printf '[http]\n\tlowSpeedLimit = 1000\n\tlowSpeedTime = 30\n' > /etc/gitconfig

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bc \
        ca-certificates \
        curl \
        dnsutils \
        iproute2 \
        iputils-ping \
        jq \
        less \
        lsof \
        netbase \
        netcat-openbsd \
        openssl \
        procps \
        tar \
        tcpdump \
        telnet \
        traceroute \
        vim && \
    rm -rf /var/lib/apt/lists/*
