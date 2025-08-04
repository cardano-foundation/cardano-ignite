FROM docker.io/debian:stable-slim AS main

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

RUN apt update && \
    apt install -y --no-install-recommends \
        bc \
        curl \
        dnsutils \
        doas \
        iproute2 \
        iputils-ping \
        jq \
        less \
        lsof \
        netbase \
        netcat-openbsd \
        openssl \
        procps \
        redis-server \
        redis-tools \
        tcpdump \
        telnet \
        vim

RUN install --directory --owner=root --group=root --mode=0755 /opt/redis && \
    install --directory --owner=redis --group=redis --mode=0750 /opt/redis/config && \
    install --directory --owner=redis --group=redis --mode=0750 /opt/redis/db

COPY --chown=root:root redis/cmd.sh /
RUN chmod 0755 /cmd.sh

USER redis
STOPSIGNAL SIGINT

CMD ["/bin/bash", "/cmd.sh"]
