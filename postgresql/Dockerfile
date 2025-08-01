FROM docker.io/debian:stable-20250721-slim AS build

ARG PROCESS_EXPORTER_VERSION="${PROCESS_EXPORTER_VERSION:-0.8.7}"

ENV PGDATA="/opt/postgresql/db" \
    PGHOST="/opt/postgresql/db" \
    PGPORT="5432" \
    unix_socket_directory="/opt/postgresql/db"

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

RUN apt update && \
    apt install -y --no-install-recommends \
        bc \
        ca-certificates \
        curl \
        dnsutils \
        doas \
        iproute2 \
        iputils-ping \
        jq \
        less \
        locales \
        locales-all \
        lsof \
        netbase \
        netcat-openbsd \
        openssl \
        postgresql-15 \
        postgresql-client-15 \
        procps \
        tcpdump \
        telnet \
        vim

# postgresql

RUN groupmod --gid 10000 postgres && \
    usermod --uid 10000 postgres

RUN rm --force --recursive /var/run/postgresql && \
    ln -s /opt/postgresql/db /var/run/postgresql

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

RUN install --directory --owner=root --group=root --mode=0755 /opt/postgresql && \
    install --directory --owner=postgres --group=postgres --mode=0750 /opt/postgresql/db

COPY postgresql/cmd.sh /
RUN chmod 0755 /cmd.sh

USER postgres
STOPSIGNAL SIGINT

CMD ["/cmd.sh"]
