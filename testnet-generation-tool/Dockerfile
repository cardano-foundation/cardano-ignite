FROM docker.io/debian:stable-20251117-slim AS testnet_builder

#ARG UV_VERSION="${UV_VERSION:-0.9.1}"
ARG UV_VERSION="0.9.13"

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

# testnet-generation-tool

WORKDIR /usr/local/src
RUN git clone --branch main https://github.com/cardano-foundation/testnet-generation-tool.git

WORKDIR /usr/local/src/testnet-generation-tool
RUN uv sync

COPY --chown=root:root .testnet.yaml /usr/local/src/testnet-generation-tool/testnet.yaml

RUN uv run python3 genesis-cli.py testnet.yaml -o /tmp/testnet -c generate

# Remove dynamic topology.json
RUN find /tmp/testnet -type f -name 'topology.json' -exec rm -f '{}' ';'
