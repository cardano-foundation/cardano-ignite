# Shared base image for all cardano-ignite images. Holds the single Debian
# pin, the default curl options (fail fast on unreachable hosts, retry
# transient failures) and the common debugging toolbox every container
# should carry, so every derived stage inherits them in one shared layer
# instead of each image installing its own copy. Built by 'make build' as
# cardano-ignite-base and passed to the other Dockerfiles via the
# BASE_IMAGE build argument.
FROM docker.io/debian:stable-20260518-slim

RUN printf 'connect-timeout = 15\nretry = 5\n' > /root/.curlrc

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
