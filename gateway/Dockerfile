ARG BASE_IMAGE=cardano-ignite-base
FROM ${BASE_IMAGE} AS main

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

RUN apt update && \
    apt install -y --no-install-recommends \
        iptables && \
    rm -rf /var/lib/apt/lists/*

# user and group

RUN groupadd --gid 10000 cardano && \
    useradd --comment 'cardano' --create-home --gid 10000 --password '!' --shell '/bin/bash' --uid 10000 cardano

RUN install --directory --owner=cardano --group=cardano --mode=0750 /opt/scripts

COPY gateway/scripts/*.sh /opt/scripts/
RUN chmod 0755 /opt/scripts/*

COPY gateway/cmd.sh /
RUN chmod 0755 /cmd.sh

CMD ["/cmd.sh"]
