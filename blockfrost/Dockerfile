FROM docker.io/debian:stable-20260112-slim AS build

ARG BLOCKFROST_BACKEND_RYO="${BLOCKFROST_BACKEND_RYO:-5.0.0}"
ARG CARDANO_CLI_VERSION="${CARDANO_CLI_VERSION:-10.11.1.0}"
ARG NODEJS_MAJOR_VERSION="${NODEJS_MAJOR_VERSION:-20}"
ARG PROCESS_EXPORTER_VERSION="${PROCESS_EXPORTER_VERSION:-0.8.7}"

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

RUN apt update && \
    apt install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        lsb-release

# nodejs

COPY --chown=root:root blockfrost/gpg/nodesource.gpg /etc/apt/trusted.gpg.d/nodesource.asc
RUN echo "deb https://deb.nodesource.com/node_${NODEJS_MAJOR_VERSION}.x nodistro main" >/etc/apt/sources.list.d/nodesource.list

RUN apt update && \
    apt install -y --no-install-recommends \
        nodejs

# Set npm proxy/https-proxy if defined
RUN if [ -n "${http_proxy}" ] ; then npm config set proxy ${http_proxy} ; fi
RUN if [ -n "${https_proxy}" ] ; then npm config set https-proxy ${https_proxy} ; fi

RUN npm install --global yarn

# blockfrost-backend-ryo

WORKDIR /usr/local/src
RUN git clone --single-branch --branch v${BLOCKFROST_BACKEND_RYO} --recurse-submodules https://github.com/blockfrost/blockfrost-backend-ryo.git

WORKDIR /usr/local/src/blockfrost-backend-ryo
RUN yarn --frozen-lockfile && \
    yarn build

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

FROM docker.io/debian:stable-20260112-slim AS main

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
        postgresql-client \
        procps \
        tcpdump \
        telnet \
        vim

RUN install --directory --owner=root --group=root --mode=0755 /usr/local/src/blockfrost-backend-ryo && \
    install --directory --owner=root --group=root --mode=0755 /usr/local/src/blockfrost-backend-ryo/dist && \
    install --directory --owner=root --group=root --mode=0755 /usr/local/src/blockfrost-backend-ryo/genesis && \
    install --directory --owner=root --group=root --mode=0755 /usr/local/src/blockfrost-backend-ryo/node_modules

COPY --from=build --chown=root:root /usr/bin/node /usr/local/bin/node
COPY --from=build --chown=root:root /usr/local/bin/cardano-cli /usr/local/bin/cardano-cli
COPY --from=build --chown=root:root /usr/local/bin/process_exporter /usr/local/bin/process_exporter
COPY --from=build --chown=root:root /usr/local/src/blockfrost-backend-ryo/*.json /usr/local/src/blockfrost-backend-ryo/
COPY --from=build --chown=root:root /usr/local/src/blockfrost-backend-ryo/dist /usr/local/src/blockfrost-backend-ryo/dist
COPY --from=build --chown=root:root /usr/local/src/blockfrost-backend-ryo/genesis /usr/local/src/blockfrost-backend-ryo/genesis
COPY --from=build --chown=root:root /usr/local/src/blockfrost-backend-ryo/node_modules /usr/local/src/blockfrost-backend-ryo/node_modules

RUN groupadd --gid 10000 cardano && \
    useradd --comment 'cardano' --create-home --gid 10000 --password '!' --shell '/bin/bash' --uid 10000 cardano

RUN install --directory --owner=root --group=root --mode=0755 /var/local/cardano-node && \
    install --directory --owner=cardano --group=cardano --mode=0750 /var/local/cardano-node/db

COPY --chown=root:root blockfrost/indices.sql /usr/local/src/blockfrost-backend-ryo/
RUN chmod 0644 /usr/local/src/blockfrost-backend-ryo/indices.sql

COPY --chown=root:root blockfrost/cmd.sh /
RUN chmod 0755 /cmd.sh

USER cardano
STOPSIGNAL SIGINT

CMD ["/bin/bash", "/cmd.sh"]
