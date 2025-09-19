ARG TESTNET_BUILDER_IMAGE

#---------------------------------------------------------------------

FROM ${TESTNET_BUILDER_IMAGE} AS testnet_builder

#---------------------------------------------------------------------

FROM docker.io/debian:stable-20250721-slim AS build

# NOTE:
# Additional ARG definitions can be found further below in the Dockerfile.

ARG BLST_VERSION="${BLST_VERSION:-0.3.11}"
ARG JOBS="${JOBS:-8}"
ARG LIBSODIUM_VERSION="${LIBSODIUM_VERSION:-dbb48cc}"
ARG SECP256K1_VERSION="${SECP256K1_VERSION:-ac83be33}"

ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        build-essential \
        ca-certificates \
        curl \
        g++ \
        git \
        gnupg \
        libffi-dev \
        libgmp-dev \
        liblmdb-dev \
        libncurses-dev \
        libssl-dev \
        libsystemd-dev \
        libtinfo-dev \
        libtool \
        pkg-config \
        tar \
        zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

# libsodium

WORKDIR /usr/local/src
RUN git clone --branch master https://github.com/IntersectMBO/libsodium.git

WORKDIR /usr/local/src/libsodium
RUN git checkout ${LIBSODIUM_VERSION} && \
    ./autogen.sh && \
    ./configure && \
    make && \
    make check && \
    make install -j${JOBS}

# secp256k1

WORKDIR /usr/local/src
RUN git clone --branch master https://github.com/bitcoin-core/secp256k1.git

WORKDIR /usr/local/src/secp256k1
RUN git checkout ${SECP256K1_VERSION} && \
    ./autogen.sh && \
    ./configure --prefix=/usr --enable-module-schnorrsig --enable-experimental && \
    make && \
    make check && \
    make install -j${JOBS}

# blst

WORKDIR /usr/local/src
RUN git clone --branch master https://github.com/supranational/blst.git

WORKDIR /usr/local/src/blst
RUN git checkout v${BLST_VERSION} && \
    ./build.sh
RUN printf "prefix=/usr/local\n\
exec_prefix=/usr/local\n\
libdir=/usr/local/lib\n\
includedir=/usr/local/include\n\
\n\
Name: libblst\n\
Description: Multilingual BLS12-381 signature library\n\
URL: https://github.com/supranational/blst\n\
Version: %s\n\
Cflags: -I/usr/local/include\n\
Libs: -L/usr/local/lib -lblst" ${BLST_VERSION}>/usr/local/src/blst/libblst.pc

RUN mv /usr/local/src/blst/libblst.pc /usr/local/lib/pkgconfig/ && \
    mv /usr/local/src/blst/bindings/blst.h /usr/local/include/ && \
    mv /usr/local/src/blst/bindings/blst.hpp /usr/local/include/ && \
    mv /usr/local/src/blst/bindings/blst_aux.h /usr/local/include/ && \
    mv /usr/local/src/blst/libblst.a /usr/local/lib

ENV LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH" \
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"

# GHCup

ARG BOOTSTRAP_HASKELL_CABAL_VERSION="${BOOTSTRAP_HASKELL_CABAL_VERSION:-3.14.2.0}"
ARG BOOTSTRAP_HASKELL_GHC_VERSION="${BOOTSTRAP_HASKELL_GHC_VERSION:-9.6.7}"
ARG BOOTSTRAP_HASKELL_GHCUP_VERSION="${BOOTSTRAP_HASKELL_GHCUP_VERSION:-0.1.50.2}"

RUN --mount=type=cache,target=/root/.ghcup,id=ghcup-cache \
    curl -L https://downloads.haskell.org/~ghcup/${BOOTSTRAP_HASKELL_GHCUP_VERSION}/x86_64-linux-ghcup-${BOOTSTRAP_HASKELL_GHCUP_VERSION} -o /usr/local/bin/ghcup && \
    chmod +x /usr/local/bin/ghcup

ENV PATH="/root/.ghcup/bin:/root/.cabal/bin:${PATH}"

RUN --mount=type=cache,target=/root/.ghcup,id=ghcup-cache \
    ghcup install cabal ${BOOTSTRAP_HASKELL_CABAL_VERSION} && \
    ghcup set cabal ${BOOTSTRAP_HASKELL_CABAL_VERSION} && \
    ghcup install ghc ${BOOTSTRAP_HASKELL_GHC_VERSION} && \
    ghcup set ghc ${BOOTSTRAP_HASKELL_GHC_VERSION}

# ouroboros-consensus

ARG OUROBOROS_CONSENSUS_REF="${OUROBOROS_CONSENSUS_REF:-abailly/snapshot-generator}"
ARG OUROBOROS_CONSENSUS_REPO="${OUROBOROS_CONSENSUS_REPO:-https://github.com/abailly/ouroboros-consensus.git}"

WORKDIR /usr/local/src
RUN git clone ${OUROBOROS_CONSENSUS_REPO}

WORKDIR /usr/local/src/ouroboros-consensus
RUN git fetch --all --recurse-submodules --tags && \
    git checkout ${OUROBOROS_CONSENSUS_REF}
RUN printf "package *\n\
  ghc-options: +RTS -A128m -n2m -RTS\n\
\n\
jobs: \$ncpus\n\
semaphore: True" > /usr/local/src/ouroboros-consensus/cabal.project.local

WORKDIR /usr/local/src/ouroboros-consensus/ouroboros-consensus-cardano

RUN --mount=type=cache,target=/root/.ghcup,id=ghcup-cache \
    --mount=type=cache,target=/root/.local/state/cabal/store,id=cabal-store-cache \
    --mount=type=cache,target=/root/.cache/cabal,id=cabal-cache \
    --mount=type=cache,target=/root/.cabal,id=root-cabal-cache \
    cabal update

RUN --mount=type=cache,target=/root/.ghcup,id=ghcup-cache \
    --mount=type=cache,target=/root/.local/state/cabal/store,id=cabal-store-cache \
    --mount=type=cache,target=/root/.cache/cabal,id=cabal-cache \
    --mount=type=cache,target=/root/.cabal,id=root-cabal-cache \
    --mount=type=cache,target=./dist-newstyle \
    cabal install db-synthesizer --disable-test --install-method=copy \
      --installdir=/usr/local/bin --overwrite-policy=always

RUN strip --strip-unneeded /usr/local/bin/db-synthesizer

#---------------------------------------------------------------------

FROM docker.io/debian:stable-20250721-slim AS main

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
