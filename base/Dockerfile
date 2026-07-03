# Shared base image for all cardano-ignite images. Holds the single Debian
# pin and the default curl options (fail fast on unreachable hosts, retry
# transient failures), so every derived stage inherits them. Built by
# 'make build' as cardano-ignite-base and passed to the other Dockerfiles
# via the BASE_IMAGE build argument.
FROM docker.io/debian:stable-20260518-slim

RUN printf 'connect-timeout = 15\nretry = 5\n' > /root/.curlrc

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        tar && \
    rm -rf /var/lib/apt/lists/*
