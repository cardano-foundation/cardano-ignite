# Shared base image for all cardano-ignite images. Holds the single Debian
# pin, the default curl options (fail fast on unreachable hosts, retry
# transient failures) and the common debugging toolbox every container
# should carry, so every derived stage inherits them in one shared layer
# instead of each image installing its own copy. Built by 'make build' as
# cardano-ignite-base and passed to the other Dockerfiles via the
# BASE_IMAGE build argument.
FROM docker.io/debian:stable-20260803-slim AS base-builder

ARG NODE_EXPORTER_VERSION="1.12.1"
ARG PROCESS_EXPORTER_VERSION="0.8.7"

RUN apt update && \
    apt install -y --no-install-recommends \
        ca-certificates \
        curl && \
    rm -rf /var/lib/apt/lists/*

RUN printf 'connect-timeout = 15\nretry = 5\nspeed-limit = 1000\nspeed-time = 30\n' > /root/.curlrc

# node_exporter

RUN install --directory --owner=root --group=root --mode=0755 /usr/local/src/node_exporter

RUN curl --proto '=https' --tlsv1.3 \
--location https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz \
--output /usr/local/src/node_exporter/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
RUN curl --proto '=https' --tlsv1.3 \
--location https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/sha256sums.txt \
--output /usr/local/src/node_exporter/sha256sums.txt

WORKDIR /usr/local/src/node_exporter
RUN sha256sum --ignore-missing --check sha256sums.txt

RUN tar --extract --gzip --file=/usr/local/src/node_exporter/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz --directory=/usr/local/src/node_exporter
RUN chmod 0755 /usr/local/src/node_exporter/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64
RUN ln -snf /usr/local/src/node_exporter/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/node_exporter

# process_exporter

RUN install --directory --owner=root --group=root --mode=0755 /usr/local/src/process_exporter

RUN curl --proto '=https' --tlsv1.3 \
--location https://github.com/ncabatoff/process-exporter/releases/download/v${PROCESS_EXPORTER_VERSION}/process-exporter-${PROCESS_EXPORTER_VERSION}.linux-amd64.tar.gz \
--output /usr/local/src/process_exporter/process-exporter-${PROCESS_EXPORTER_VERSION}.linux-amd64.tar.gz
RUN curl --proto '=https' --tlsv1.3 \
--location https://github.com/ncabatoff/process-exporter/releases/download/v${PROCESS_EXPORTER_VERSION}/checksums.txt \
--output /usr/local/src/process_exporter/checksums.txt

WORKDIR /usr/local/src/process_exporter
RUN sha256sum --ignore-missing --check checksums.txt

RUN tar --extract --gzip --file=/usr/local/src/process_exporter/process-exporter-${PROCESS_EXPORTER_VERSION}.linux-amd64.tar.gz --directory=/usr/local/src/process_exporter
RUN chmod 0755 /usr/local/src/process_exporter/process-exporter-${PROCESS_EXPORTER_VERSION}.linux-amd64/process-exporter
RUN ln -snf /usr/local/src/process_exporter/process-exporter-${PROCESS_EXPORTER_VERSION}.linux-amd64/process-exporter /usr/local/bin/process_exporter

# reset working director
WORKDIR /

#---------------------------------------------------------------------

FROM docker.io/debian:stable-20260803-slim AS cardano-ignite-base

# connect-timeout/retry guard the connection phase; speed-limit/speed-time
# abort a transfer that stalls after connecting (below 1 kB/s for 30s),
# which would otherwise hang a build forever.
RUN printf 'connect-timeout = 15\nretry = 5\nspeed-limit = 1000\nspeed-time = 30\n' > /root/.curlrc

# git does not read curlrc and has no default timeout, so a stalled
# connection hangs a build forever. Abort any git transfer that drops
# below 1 kB/s for 30 seconds; the build fails loudly and a rerun
# resumes from the layer cache.
RUN printf '[http]\n\tlowSpeedLimit = 1000\n\tlowSpeedTime = 30\n' > /etc/gitconfig

RUN apt update && \
    apt install -y --no-install-recommends \
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

# node_exporter

COPY --from=base-builder --chown=root:root /usr/local/bin/node_exporter /usr/local/bin/node_exporter

# process_exporter

COPY --from=base-builder --chown=root:root /usr/local/bin/process_exporter /usr/local/bin/process_exporter
