ARG TESTNET_BUILDER_IMAGE
ARG HASKELL_BUILDER_IMAGE

FROM ${TESTNET_BUILDER_IMAGE} AS testnet_builder

#---------------------------------------------------------------------

FROM ${HASKELL_BUILDER_IMAGE} AS build

# NOTE:
# Additional ARG definitions can be found further below in the Dockerfile.

# ouroboros-consensus

ARG OUROBOROS_CONSENSUS_REF="${OUROBOROS_CONSENSUS_REF:-abailly/snapshot-generator}"
ARG OUROBOROS_CONSENSUS_REPO="${OUROBOROS_CONSENSUS_REPO:-https://github.com/abailly/ouroboros-consensus.git}"

WORKDIR /usr/local/src
RUN git clone ${OUROBOROS_CONSENSUS_REPO}

WORKDIR /usr/local/src/ouroboros-consensus
RUN git fetch --all --recurse-submodules --tags && \
    git checkout ${OUROBOROS_CONSENSUS_REF}
RUN printf "jobs: 2\n\
semaphore: True" > /usr/local/src/ouroboros-consensus/cabal.project.local

WORKDIR /usr/local/src/ouroboros-consensus/ouroboros-consensus-cardano

RUN cabal update && \
    cabal install db-synthesizer --disable-test --install-method=copy \
      --installdir=/usr/local/bin --overwrite-policy=always

RUN strip --strip-unneeded /usr/local/bin/db-synthesizer

#---------------------------------------------------------------------

FROM docker.io/debian:stable-20251117-slim AS main

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bc \
        jq \
        less \
        lsof \
        procps \
        vim && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build --chown=root:root /usr/local/lib/libsodium.so /usr/local/lib
RUN ln -snf /usr/local/lib/libsodium.so /usr/local/lib/libsodium.so.23 && \
    ln -snf /usr/local/lib/libsodium.so /usr/local/lib/libsodium.so.23.3.0

COPY --from=build --chown=root:root /usr/local/src/secp256k1/.libs/libsecp256k1.so /usr/local/lib
RUN ln -snf /usr/local/lib/libsecp256k1.so /usr/local/lib/libsecp256k1.so.1 && \
    ln -snf /usr/local/lib/libsecp256k1.so /usr/local/lib/libsecp256k1.so.1.0.1
RUN ldconfig

COPY --from=build --chown=root:root /usr/local/bin/db-synthesizer /usr/local/bin/db-synthesizer

RUN groupadd --gid 10000 cardano && \
    useradd --comment 'cardano' --create-home --gid 10000 --password '!' --shell '/bin/bash' --uid 10000 cardano

COPY --from=testnet_builder --chown=cardano:cardano /tmp/testnet/pools /opt/cardano-node/pools
COPY --from=testnet_builder --chown=cardano:cardano /tmp/testnet/utxos /opt/cardano-node/utxos

RUN install --directory --owner=root --group=root --mode=0755 /opt/cardano-node && \
    install --directory --owner=cardano --group=cardano --mode=0750 /opt/cardano-node/data && \
    install --directory --owner=cardano --group=cardano --mode=0750 /opt/cardano-node/data/db && \
    install --directory --owner=cardano --group=cardano --mode=0750 /opt/cardano-node/pools

COPY db-synthesizer/cmd.sh /
RUN chmod 0755 /cmd.sh

USER cardano

CMD ["/cmd.sh"]
