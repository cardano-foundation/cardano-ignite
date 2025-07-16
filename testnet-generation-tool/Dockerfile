FROM docker.io/debian:stable-20250630-slim AS testnet_builder

ARG UV_VERSION="${UV_VERSION:-0.7.21}"

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

# Create uv source directory
RUN install --directory --owner=root --group=root --mode=0755 /usr/local/src/uv

# Download uv archive
RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz \
        --output /usr/local/src/uv/uv-x86_64-unknown-linux-gnu.tar.gz

# Download uv checksum
RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz.sha256 \
        --output /usr/local/src/uv/uv-x86_64-unknown-linux-gnu.tar.gz.sha256

# Verify uv checksum
WORKDIR /usr/local/src/uv
RUN sha256sum --ignore-missing --check uv-x86_64-unknown-linux-gnu.tar.gz.sha256

# Unarchive uv tarball
RUN tar --extract --gzip --file=/usr/local/src/uv/uv-x86_64-unknown-linux-gnu.tar.gz --directory=/usr/local/src/uv

# Make uv executable
RUN chmod 0755 /usr/local/src/uv/uv-x86_64-unknown-linux-gnu/uv

# Create uv symlink
RUN ln -s /usr/local/src/uv/uv-x86_64-unknown-linux-gnu/uv /usr/local/bin/uv

# Clone testnet-generation-tool.git repository
WORKDIR /usr/local/src
RUN git clone --branch main https://github.com/cardano-foundation/testnet-generation-tool.git

# Download testnet-generation-tool dependencies
WORKDIR /usr/local/src/testnet-generation-tool
RUN uv sync

# Copy testnet.yaml specification
COPY --chown=root:root .testnet.yaml /usr/local/src/testnet-generation-tool/testnet.yaml

# Build testnet configuration files
RUN uv run python3 genesis-cli.py testnet.yaml -o /tmp/testnet -c generate

# Remove dynamic topology.json
RUN find /tmp/testnet -type f -name 'topology.json' -exec rm -f '{}' ';'
