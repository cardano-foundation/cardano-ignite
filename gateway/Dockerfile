FROM docker.io/debian:stable-20251117-slim AS build

ARG NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.10.2}"

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

RUN apt update && \
    apt install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        tar

# node_exporter

RUN install --directory --owner=root --group=root --mode=0755 /usr/local/src/node_exporter

RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz \
        --output /usr/local/src/node_exporter/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz

RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/sha256sums.txt \
        --output /usr/local/src/node_exporter/sha256sums.txt

WORKDIR /usr/local/src/node_exporter
RUN sha256sum --ignore-missing --check sha256sums.txt

RUN tar --extract --gzip --file=/usr/local/src/node_exporter/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz --directory=/usr/local/src/node_exporter

RUN chmod 0755 /usr/local/src/node_exporter/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64

RUN ln -s /usr/local/src/node_exporter/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/node_exporter

#---------------------------------------------------------------------

FROM docker.io/debian:stable-20251117-slim AS main

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

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

COPY --from=build --chown=root:root /usr/local/bin/node_exporter /usr/local/bin/node_exporter

RUN groupadd --gid 10000 cardano && \
    useradd --comment 'cardano' --create-home --gid 10000 --password '!' --shell '/bin/bash' --uid 10000 cardano

RUN install --directory --owner=cardano --group=cardano --mode=0750 /opt/scripts

COPY gateway/scripts/*.sh /opt/scripts/
RUN chmod 0755 /opt/scripts/*

COPY gateway/cmd.sh /
RUN chmod 0755 /cmd.sh

CMD ["/cmd.sh"]
