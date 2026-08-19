ARG BASE_IMAGE=cardano-ignite-base
FROM ${BASE_IMAGE} AS testnet_builder

ARG UV_VERSION="0.12.3"
ARG TESTNET_GENERATION_TOOL_VERSION="0.2.0"
# Must match the cardano-node binary version pinned in the
# testnet-generation-tool release (libs/mainnet_env.py)
ARG GENESIS_CARDANO_NODE_VERSION="10.2.1"

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
RUN ln -snf /usr/local/src/uv/uv-x86_64-unknown-linux-gnu/uv /usr/local/bin/uv

# testnet-generation-tool

WORKDIR /usr/local/src
RUN git clone --depth 1 --branch v${TESTNET_GENERATION_TOOL_VERSION} https://github.com/cardano-foundation/testnet-generation-tool.git

WORKDIR /usr/local/src/testnet-generation-tool
RUN uv sync

# Pre-fetch the cardano-node binary that genesis-cli.py would otherwise
# download itself using urllib without a timeout, which can hang
# indefinitely on unreliable networks. genesis-cli.py skips its download
# when cardano-node/bin already exists. Placed before the per-testnet
# COPY below so the download layer is cached across testnets.
RUN curl --proto '=https' --tlsv1.3 \
        --location https://github.com/IntersectMBO/cardano-node/releases/download/${GENESIS_CARDANO_NODE_VERSION}/cardano-node-${GENESIS_CARDANO_NODE_VERSION}-linux.tar.gz \
        --output /tmp/cardano-node-${GENESIS_CARDANO_NODE_VERSION}-linux.tar.gz && \
    curl --proto '=https' --tlsv1.3 \
        --location https://github.com/IntersectMBO/cardano-node/releases/download/${GENESIS_CARDANO_NODE_VERSION}/cardano-node-${GENESIS_CARDANO_NODE_VERSION}-sha256sums.txt \
        --output /tmp/cardano-node-${GENESIS_CARDANO_NODE_VERSION}-sha256sums.txt && \
    cd /tmp && \
    sha256sum --ignore-missing --check cardano-node-${GENESIS_CARDANO_NODE_VERSION}-sha256sums.txt && \
    mkdir -p /usr/local/src/testnet-generation-tool/cardano-node && \
    tar --extract --gzip --file=/tmp/cardano-node-${GENESIS_CARDANO_NODE_VERSION}-linux.tar.gz --directory=/usr/local/src/testnet-generation-tool/cardano-node ./bin/cardano-cli ./bin/cardano-node && \
    rm -f /tmp/cardano-node-${GENESIS_CARDANO_NODE_VERSION}-linux.tar.gz /tmp/cardano-node-${GENESIS_CARDANO_NODE_VERSION}-sha256sums.txt && \
    strip --strip-unneeded /usr/local/src/testnet-generation-tool/cardano-node/bin/cardano-cli \
        /usr/local/src/testnet-generation-tool/cardano-node/bin/cardano-node

COPY --chown=root:root .testnet.yaml /usr/local/src/testnet-generation-tool/testnet.yaml

RUN uv run python3 genesis-cli.py testnet.yaml -o /tmp/testnet -c generate

# Remove dynamic topology.json
RUN find /tmp/testnet -type f -name 'topology.json' -exec rm -f '{}' ';'
