FROM docker.io/debian:stable-20250721-slim AS build

ARG NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.9.1}"

# Set time zone
ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

# Install packages required in build stage
RUN apt update && \
    apt install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        tar

# Create node_exporter source directory
RUN install --directory --owner=root --group=root --mode=0755 /usr/local/src/node_exporter

# Download node_exporter archive
RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz \
        --output /usr/local/src/node_exporter/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz

# Download node_exporter checksum
RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/sha256sums.txt \
        --output /usr/local/src/node_exporter/sha256sums.txt

# Verify node_exporter checksum
WORKDIR /usr/local/src/node_exporter
RUN sha256sum --ignore-missing --check sha256sums.txt

# Unarchive node_exporter tarball
RUN tar --extract --gzip --file=/usr/local/src/node_exporter/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz --directory=/usr/local/src/node_exporter

# Make node_exporter executable
RUN chmod 0755 /usr/local/src/node_exporter/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64

# Create node_exporter symlink
RUN ln -s /usr/local/src/node_exporter/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/node_exporter


FROM docker.io/debian:stable-20250721-slim AS main

# Set time zone
ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

# Install packages required in main stage
RUN apt update && \
    apt install -y --no-install-recommends \
        dnsutils \
        iproute2 \
        iptables \
        iputils-ping \
        jq \
        less \
        lsof \
        netbase \
        netcat-openbsd \
        openssl \
        procps \
        tcpdump \
        telnet \
        traceroute \
        vim

# Copy binaries from build stage
COPY --from=build --chown=root:root /usr/local/bin/node_exporter /usr/local/bin/node_exporter

# Create cardano group and user
RUN groupadd --gid 10000 cardano && \
    useradd --comment 'cardano' --create-home --gid 10000 --password '!' --shell '/bin/bash' --uid 10000 cardano

# Create scripts directory
RUN install --directory --owner=cardano --group=cardano --mode=0750 /opt/scripts

COPY gateway/scripts/*.sh /opt/scripts/
RUN chmod 0755 /opt/scripts/*

#Setup routing functionality here
# Copy cardano-node.sh
COPY gateway/cmd.sh /
RUN chmod 0755 /cmd.sh

CMD ["/cmd.sh"]
