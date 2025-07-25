FROM docker.io/debian:stable-20250630-slim AS main

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
