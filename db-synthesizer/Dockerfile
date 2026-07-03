ARG BASE_IMAGE=cardano-ignite-base
ARG TESTNET_BUILDER_IMAGE=scratch
ARG HASKELL_BUILDER_IMAGE=scratch

FROM ${TESTNET_BUILDER_IMAGE} AS testnet_builder

#---------------------------------------------------------------------
# Fork build. The abailly fork additionally emits the ledger-state
# snapshots that amaru nodes bootstrap from, so it is only needed by
# testnets that run amaru (build target "full" below).

FROM ${HASKELL_BUILDER_IMAGE} AS build

# NOTE:
# Additional ARG definitions can be found further below in the Dockerfile.

# ouroboros-consensus

ARG OUROBOROS_CONSENSUS_REF="abailly/snapshot-generator"
ARG OUROBOROS_CONSENSUS_REPO="https://github.com/abailly/ouroboros-consensus.git"

WORKDIR /usr/local/src
RUN git init ouroboros-consensus

WORKDIR /usr/local/src/ouroboros-consensus
RUN git fetch --depth 1 ${OUROBOROS_CONSENSUS_REPO} ${OUROBOROS_CONSENSUS_REF} && \
    git checkout FETCH_HEAD && \
    git submodule update --init --recursive
RUN printf "package *\n\
  ghc-options: +RTS -A128m -n2m -RTS\n\
\n\
jobs: \$ncpus\n\
semaphore: True" > /usr/local/src/ouroboros-consensus/cabal.project.local

WORKDIR /usr/local/src/ouroboros-consensus/ouroboros-consensus-cardano

RUN cabal update && \
    cabal install db-synthesizer --disable-test --install-method=copy \
      --installdir=/usr/local/bin --overwrite-policy=always

RUN strip --strip-unneeded /usr/local/bin/db-synthesizer

#---------------------------------------------------------------------
# Stock db-synthesizer from the cardano-node release archive. It supports
# every flag cmd.sh uses (--config --db --bulk-credentials-file -e) but
# does not generate the amaru ledger-state snapshots.

FROM ${BASE_IMAGE} AS tarball

ARG DB_SYNTHESIZER_VERSION="11.0.1"

RUN install --directory --owner=root --group=root --mode=0755 /usr/local/src/cardano-node

RUN curl --proto '=https' --tlsv1.3 --fail \
        --location https://github.com/IntersectMBO/cardano-node/releases/download/${DB_SYNTHESIZER_VERSION}/cardano-node-${DB_SYNTHESIZER_VERSION}-linux-amd64.tar.gz \
        --output /usr/local/src/cardano-node/node.tar.gz

RUN tar --extract --gzip --file=/usr/local/src/cardano-node/node.tar.gz --directory=/usr/local/src/cardano-node ./bin/db-synthesizer && \
    chmod 0755 /usr/local/src/cardano-node/bin/db-synthesizer

#---------------------------------------------------------------------
# Shared runtime stage without a db-synthesizer binary. Testnets that never
# synthesize epoch blocks (e.g. Leios) use this directly as target "light";
# cmd.sh fails loudly if PRE_EPOCHS > 0 and the binary is missing.

FROM ${BASE_IMAGE} AS light

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

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

#---------------------------------------------------------------------
# Stock binary from the release archive. For testnets without amaru nodes;
# supports PRE_EPOCHS > 0 without any Haskell build.

FROM light AS binary

COPY --from=tarball --chown=root:root /usr/local/src/cardano-node/bin/db-synthesizer /usr/local/bin/db-synthesizer

#---------------------------------------------------------------------
# Fork binary with the amaru snapshot support. Default target so that a
# build without an explicit target keeps the previous behaviour.

FROM light AS full

USER root

COPY --from=build --chown=root:root /usr/local/lib/libsodium.so /usr/local/lib
RUN ln -snf /usr/local/lib/libsodium.so /usr/local/lib/libsodium.so.23 && \
    ln -snf /usr/local/lib/libsodium.so /usr/local/lib/libsodium.so.23.3.0

COPY --from=build --chown=root:root /usr/local/src/secp256k1/.libs/libsecp256k1.so /usr/local/lib
RUN ln -snf /usr/local/lib/libsecp256k1.so /usr/local/lib/libsecp256k1.so.1 && \
    ln -snf /usr/local/lib/libsecp256k1.so /usr/local/lib/libsecp256k1.so.1.0.1
RUN ldconfig

COPY --from=build --chown=root:root /usr/local/bin/db-synthesizer /usr/local/bin/db-synthesizer

USER cardano
