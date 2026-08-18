ARG BASE_IMAGE=cardano-ignite-base
FROM ${BASE_IMAGE} AS testnet_builder

ARG UV_VERSION="0.11.18"
ARG TESTNET_GENERATION_TOOL_VERSION="v0.2.0"
# Must match the cardano-node binary version pinned in the
# testnet-generation-tool release (libs/mainnet_env.py)
ARG GENESIS_CARDANO_NODE_VERSION="10.2.1"
# Release archive the pre-fetch below downloads. Override both together with the
# tool version when a testnet needs a different genesis cardano-cli, e.g. Leios.
ARG GENESIS_CARDANO_NODE_URL="https://github.com/IntersectMBO/cardano-node/releases/download/${GENESIS_CARDANO_NODE_VERSION}/cardano-node-${GENESIS_CARDANO_NODE_VERSION}-linux.tar.gz"
ARG GENESIS_CARDANO_NODE_SHA256_URL="https://github.com/IntersectMBO/cardano-node/releases/download/${GENESIS_CARDANO_NODE_VERSION}/cardano-node-${GENESIS_CARDANO_NODE_VERSION}-sha256sums.txt"

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

RUN apt update && \
    apt install -y --no-install-recommends \
        binutils \
        git && \
    rm -rf /var/lib/apt/lists/*
# uv

RUN install --directory --owner=root --group=root --mode=0755 /usr/local/src/uv

RUN curl --proto '=https' --tlsv1.3 \
        --location https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz \
        --output /usr/local/src/uv/uv-x86_64-unknown-linux-gnu.tar.gz

RUN curl --proto '=https' --tlsv1.3 \
        --location https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz.sha256 \
        --output /usr/local/src/uv/uv-x86_64-unknown-linux-gnu.tar.gz.sha256

WORKDIR /usr/local/src/uv
RUN sha256sum --ignore-missing --check uv-x86_64-unknown-linux-gnu.tar.gz.sha256

RUN tar --extract --gzip --file=/usr/local/src/uv/uv-x86_64-unknown-linux-gnu.tar.gz --directory=/usr/local/src/uv

RUN chmod 0755 /usr/local/src/uv/uv-x86_64-unknown-linux-gnu/uv

RUN ln -s /usr/local/src/uv/uv-x86_64-unknown-linux-gnu/uv /usr/local/bin/uv

# testnet-generation-tool

WORKDIR /usr/local/src
RUN git clone --depth 1 --branch ${TESTNET_GENERATION_TOOL_VERSION} https://github.com/cardano-foundation/testnet-generation-tool.git

WORKDIR /usr/local/src/testnet-generation-tool
RUN uv sync

# Pre-fetch the cardano-node binary that genesis-cli.py would otherwise
# download itself using urllib without a timeout, which can hang
# indefinitely on unreliable networks. genesis-cli.py skips its download
# when cardano-node/bin already exists. Placed before the per-testnet
# COPY below so the download layer is cached across testnets.
RUN set -eu && \
    tarball="$(basename ${GENESIS_CARDANO_NODE_URL})" && \
    sums="$(basename ${GENESIS_CARDANO_NODE_SHA256_URL})" && \
    cd /tmp && \
    curl --proto '=https' --tlsv1.3 \
        --location ${GENESIS_CARDANO_NODE_URL} \
        --output "${tarball}" && \
    curl --proto '=https' --tlsv1.3 \
        --location ${GENESIS_CARDANO_NODE_SHA256_URL} \
        --output "${sums}" && \
    sha256sum --ignore-missing --check "${sums}" && \
    mkdir -p /usr/local/src/testnet-generation-tool/cardano-node && \
    tar --extract --gzip --wildcards --file="${tarball}" --directory=/usr/local/src/testnet-generation-tool/cardano-node '*bin/cardano-cli' '*bin/cardano-node' && \
    rm -f "${tarball}" "${sums}" && \
    strip --strip-unneeded /usr/local/src/testnet-generation-tool/cardano-node/bin/cardano-cli \
        /usr/local/src/testnet-generation-tool/cardano-node/bin/cardano-node

COPY --chown=root:root .testnet.yaml /usr/local/src/testnet-generation-tool/testnet.yaml

RUN uv run python3 genesis-cli.py testnet.yaml -o /tmp/testnet -c generate

# Remove dynamic topology.json
RUN find /tmp/testnet -type f -name 'topology.json' -exec rm -f '{}' ';'
