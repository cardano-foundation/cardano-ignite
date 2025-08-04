FROM docker.io/debian:stable-slim AS build

ARG CARDANO_CLI_VERSION="${CARDANO_CLI_VERSION:-10.11.1.0}"
ARG OURA_VERSION="${OURA_VERSION:-1.9.4}"
ARG PROCESS_EXPORTER_VERSION="${PROCESS_EXPORTER_VERSION:-0.8.7}"

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

RUN apt update && \
    apt install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        tar

# oura

RUN install --directory --owner=root --group=root --mode=0755 /usr/local/src/oura

RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/txpipe/oura/releases/download/v${OURA_VERSION}/oura-x86_64-unknown-linux-gnu.tar.gz \
        --output /usr/local/src/oura-x86_64-unknown-linux-gnu.tar.gz

RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/txpipe/oura/releases/download/v${OURA_VERSION}/oura-x86_64-unknown-linux-gnu.tar.gz.sha256 \
        --output /usr/local/src/oura-x86_64-unknown-linux-gnu.tar.gz.sha256

RUN echo "$(cat /usr/local/src/oura-x86_64-unknown-linux-gnu.tar.gz.sha256) oura-x86_64-unknown-linux-gnu.tar.gz" > /usr/local/src/oura-x86_64-unknown-linux-gnu.tar.gz.checksum

WORKDIR /usr/local/src
RUN sha256sum --ignore-missing --check oura-x86_64-unknown-linux-gnu.tar.gz.checksum

RUN tar --extract --gzip --file=/usr/local/src/oura-x86_64-unknown-linux-gnu.tar.gz --directory=/usr/local/src/oura

# cardano-cli

RUN install --directory --owner=root --group=root --mode=0755 /usr/local/src/cardano-cli

RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/IntersectMBO/cardano-cli/releases/download/cardano-cli-${CARDANO_CLI_VERSION}/cardano-cli-${CARDANO_CLI_VERSION}-x86_64-linux.tar.gz \
        --output /usr/local/src/cardano-cli/cardano-cli-${CARDANO_CLI_VERSION}-x86_64-linux.tar.gz

RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/IntersectMBO/cardano-cli/releases/download/cardano-cli-${CARDANO_CLI_VERSION}/cardano-cli-${CARDANO_CLI_VERSION}-sha256sums.txt \
        --output /usr/local/src/cardano-cli/cardano-cli-${CARDANO_CLI_VERSION}-sha256sums.txt

WORKDIR /usr/local/src/cardano-cli
RUN sha256sum --ignore-missing --check cardano-cli-${CARDANO_CLI_VERSION}-sha256sums.txt

RUN tar --extract --gzip --file=/usr/local/src/cardano-cli/cardano-cli-${CARDANO_CLI_VERSION}-x86_64-linux.tar.gz --directory=/usr/local/src/cardano-cli

RUN chmod 0755 /usr/local/src/cardano-cli/cardano-cli-x86_64-linux

RUN ln -s /usr/local/src/cardano-cli/cardano-cli-x86_64-linux /usr/local/bin/cardano-cli

# process_exporter

RUN install --directory --owner=root --group=root --mode=0755 /usr/local/src/process_exporter

RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/ncabatoff/process-exporter/releases/download/v${PROCESS_EXPORTER_VERSION}/process-exporter-${PROCESS_EXPORTER_VERSION}.linux-amd64.tar.gz \
        --output /usr/local/src/process_exporter/process-exporter-${PROCESS_EXPORTER_VERSION}.linux-amd64.tar.gz

RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/ncabatoff/process-exporter/releases/download/v${PROCESS_EXPORTER_VERSION}/checksums.txt \
        --output /usr/local/src/process_exporter/checksums.txt

WORKDIR /usr/local/src/process_exporter
RUN sha256sum --ignore-missing --check checksums.txt

RUN tar --extract --gzip --file=/usr/local/src/process_exporter/process-exporter-${PROCESS_EXPORTER_VERSION}.linux-amd64.tar.gz --directory=/usr/local/src/process_exporter

RUN chmod 0755 /usr/local/src/process_exporter/process-exporter-${PROCESS_EXPORTER_VERSION}.linux-amd64/process-exporter

RUN ln -s /usr/local/src/process_exporter/process-exporter-${PROCESS_EXPORTER_VERSION}.linux-amd64/process-exporter /usr/local/bin/process_exporter

#---------------------------------------------------------------------

FROM docker.io/debian:stable-slim AS main

ENV CARDANO_NODE_SOCKET_PATH="/opt/cardano-node/data/db/node.socket"

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

RUN apt update && \
    apt install -y --no-install-recommends \
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
        tcpdump \
        telnet \
        vim

COPY --from=build --chown=root:root /usr/local/bin/cardano-cli /usr/local/bin/cardano-cli
COPY --from=build --chown=root:root /usr/local/src/oura/oura /usr/local/bin/oura

RUN install --directory --owner=root --group=root --mode=0755 /usr/local/etc/oura

COPY --chown=root:root oura/config /usr/local/etc/oura
RUN chmod 0644 /usr/local/etc/oura/*

RUN groupadd --gid 10000 cardano && \
    useradd --comment 'cardano' --create-home --gid 10000 --password '!' --shell '/bin/bash' --uid 10000 cardano

RUN install --directory --owner=root --group=root --mode=0755 /opt/oura && \
    install --directory --owner=cardano --group=cardano --mode=0755 /opt/oura/config && \
    install --directory --owner=cardano --group=cardano --mode=0755 /opt/oura/sink

RUN install --directory --owner=root --group=root --mode=0755 /opt/cardano-node && \
    install --directory --owner=cardano --group=cardano --mode=0750 /opt/cardano-node/db

COPY oura/cmd.sh /
RUN chmod 0755 /cmd.sh

USER cardano
STOPSIGNAL SIGTERM

CMD ["/bin/bash", "/cmd.sh"]
