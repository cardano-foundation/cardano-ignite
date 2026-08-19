ARG BASE_IMAGE=cardano-ignite-base
FROM ${BASE_IMAGE} AS build

ENV PGDATA="/opt/postgresql/db" \
    PGHOST="/opt/postgresql/db" \
    PGPORT="5432" \
    unix_socket_directory="/opt/postgresql/db"

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

RUN apt update && \
    apt install -y --no-install-recommends \
        doas \
        locales \
        locales-all && \
    rm -rf /var/lib/apt/lists/*

# postgresql

COPY postgresql/gpg/accc4cf8.asc /etc/apt/keyrings/

RUN echo "deb [signed-by=/etc/apt/keyrings/accc4cf8.asc] https://apt.postgresql.org/pub/repos/apt $(awk -F '=' '/^VERSION_CODENAME/ {print $2}' /etc/os-release)-pgdg main" >/etc/apt/sources.list.d/pgdg.list

RUN apt update && \
    apt install -y --no-install-recommends \
        postgresql-17 && \
    rm -rf /var/lib/apt/lists/*

RUN groupmod --gid 10000 postgres && \
    usermod --uid 10000 postgres

RUN rm --force --recursive /etc/postgresql

RUN rm --force --recursive /var/lib/postgresql && \
    ln -s /var/local/postgresql/data /var/lib/postgresql

RUN rm --force --recursive /run/postgresql && \
    ln -s /var/local/postgresql/data/17/main /run/postgresql

RUN install --directory --owner=root --group=root --mode=0755 /var/local/postgresql && \
    install --directory --owner=postgres --group=postgres --mode=0750 /var/local/postgresql/data/17/main

RUN install --directory --owner=root --group=root --mode=0755 /opt/postgresql && \
    install --directory --owner=postgres --group=postgres --mode=0750 /opt/postgresql/db

COPY postgresql/cmd.sh /
RUN chmod 0755 /cmd.sh

USER postgres
STOPSIGNAL SIGINT

CMD ["/cmd.sh"]
