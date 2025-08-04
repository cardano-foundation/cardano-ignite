FROM docker.io/debian:stable-20250721-slim AS build

ARG CARDANO_CLI_VERSION="${CARDANO_CLI_VERSION:-10.11.1.0}"
ARG HERON_VERSION="${HERON_VERSION:-1753d4eed7b2b24f7b3eb4559d21ee2ffd722f04}"
ARG PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
ARG UV_VERSION="${UV_VERSION:-0.7.21}"

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

RUN apt update && \
    apt install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        tar

# uv

RUN install --directory --owner=root --group=root --mode=0755 /usr/local/src/uv

RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz \
        --output /usr/local/src/uv/uv-x86_64-unknown-linux-gnu.tar.gz

RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz.sha256 \
        --output /usr/local/src/uv/uv-x86_64-unknown-linux-gnu.tar.gz.sha256

WORKDIR /usr/local/src/uv
RUN sha256sum --ignore-missing --check uv-x86_64-unknown-linux-gnu.tar.gz.sha256

RUN tar --extract --gzip --file=/usr/local/src/uv/uv-x86_64-unknown-linux-gnu.tar.gz --directory=/usr/local/src/uv

RUN chmod 0755 /usr/local/src/uv/uv-x86_64-unknown-linux-gnu/uv

RUN ln -s /usr/local/src/uv/uv-x86_64-unknown-linux-gnu/uv /usr/local/bin/uv

# heron

WORKDIR /usr/local/src
RUN git clone --branch master https://github.com/Godspeed-exe/heron-cardano.git

WORKDIR /usr/local/src/heron-cardano
RUN git checkout ${HERON_VERSION}

RUN uv python install ${PYTHON_VERSION}

# TODO

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

#---------------------------------------------------------------------

#FROM docker.io/debian:stable-20250721-slim AS main

ENV CARDANO_NODE_SOCKET_PATH="/opt/cardano-node/data/db/node.socket"

#ENV TZ="UTC"
#RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
#    echo ${TZ} > /etc/timezone

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
        postgresql-client-15 \
        procps \
        redis-tools \
        tcpdump \
        telnet \
        vim

COPY heron/scripts/*.sh /
RUN chmod 0755 /*.sh

COPY heron/cmd.sh /
RUN chmod 0755 /cmd.sh

CMD ["/bin/bash", "/cmd.sh"]
