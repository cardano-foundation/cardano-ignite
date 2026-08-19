ARG BASE_IMAGE=cardano-ignite-base
FROM ${BASE_IMAGE} AS build

ARG CARDANO_CLI_VERSION="11.0.0.0"

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

# cardano-cli

RUN install --directory --owner=root --group=root --mode=0755 /usr/local/src/cardano-cli

RUN curl --proto '=https' --tlsv1.3 \
        --location https://github.com/IntersectMBO/cardano-cli/releases/download/cardano-cli-${CARDANO_CLI_VERSION}/cardano-cli-${CARDANO_CLI_VERSION}-x86_64-linux.tar.gz \
        --output /usr/local/src/cardano-cli/cardano-cli-${CARDANO_CLI_VERSION}-x86_64-linux.tar.gz
RUN curl --proto '=https' --tlsv1.3 \
        --location https://github.com/IntersectMBO/cardano-cli/releases/download/cardano-cli-${CARDANO_CLI_VERSION}/cardano-cli-${CARDANO_CLI_VERSION}-sha256sums.txt \
        --output /usr/local/src/cardano-cli/cardano-cli-${CARDANO_CLI_VERSION}-sha256sums.txt

WORKDIR /usr/local/src/cardano-cli
RUN sha256sum --ignore-missing --check cardano-cli-${CARDANO_CLI_VERSION}-sha256sums.txt

RUN tar --extract --gzip --file=/usr/local/src/cardano-cli/cardano-cli-${CARDANO_CLI_VERSION}-x86_64-linux.tar.gz --directory=/usr/local/src/cardano-cli
RUN chmod 0755 /usr/local/src/cardano-cli/cardano-cli-x86_64-linux
RUN ln -snf /usr/local/src/cardano-cli/cardano-cli-x86_64-linux /usr/local/bin/cardano-cli

#---------------------------------------------------------------------

FROM ${BASE_IMAGE} AS main

ARG GRAPHNODES

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

RUN apt update && \
    apt install -y --no-install-recommends \
        doas \
        postgresql-client && \
    rm -rf /var/lib/apt/lists/*

# cardano-cli

COPY --from=build --chown=root:root /usr/local/bin/cardano-cli /usr/local/bin/cardano-cli

# user and group

RUN groupadd --gid 10000 cardano && \
    useradd --comment 'cardano' --create-home --gid 10000 --password '!' --shell '/bin/bash' --uid 10000 cardano

RUN install --directory --owner=cardano --group=cardano --mode=0750 /opt/scripts

# Permit cardano user to run commands 'ip' and 'tc' as root
RUN echo 'permit setenv { PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin } :cardano' >> /etc/doas.conf
RUN echo 'permit nopass cardano as root cmd ip' >> /etc/doas.conf
RUN echo 'permit nopass cardano as root cmd tc' >> /etc/doas.conf

COPY sidecar/scripts/* /opt/scripts/
RUN chmod 0755 /opt/scripts/*

COPY ${GRAPHNODES} /

COPY sidecar/cmd.sh /
RUN chmod 0755 /cmd.sh

USER cardano

CMD ["/cmd.sh"]
