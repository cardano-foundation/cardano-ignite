# -------------------------------------------------
#  Shared build environment for Cardano binaries
# -------------------------------------------------
ARG BASE_IMAGE=docker.io/debian:stable-20250721-slim
FROM ${BASE_IMAGE} AS haskell-builder

# ── Common ARGs (keep the defaults from the originals) ──
ARG BLST_VERSION="${BLST_VERSION:-0.3.11}"
ARG JOBS="${JOBS:-8}"
ARG LIBSODIUM_VERSION="${LIBSODIUM_VERSION:-dbb48cc}"
ARG SECP256K1_VERSION="${SECP256K1_VERSION:-ac83be33}"
ARG BOOTSTRAP_HASKELL_CABAL_VERSION="${BOOTSTRAP_HASKELL_CABAL_VERSION:-3.14.2.0}"
ARG BOOTSTRAP_HASKELL_GHC_VERSION="${BOOTSTRAP_HASKELL_GHC_VERSION:-9.6.7}"
ARG BOOTSTRAP_HASKELL_GHCUP_VERSION="${BOOTSTRAP_HASKELL_GHCUP_VERSION:-0.1.50.2}"
ENV TZ="UTC"

# ── Timezone ──
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

# ── Packages needed for all builds ──
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

# ── libsodium ──
WORKDIR /usr/local/src
RUN git clone --branch master https://github.com/IntersectMBO/libsodium.git && \
    cd libsodium && \
    git checkout ${LIBSODIUM_VERSION} && \
    ./autogen.sh && \
    ./configure && \
    make && make check && make install -j${JOBS}

# ── secp256k1 ──
WORKDIR /usr/local/src
RUN git clone --branch master https://github.com/bitcoin-core/secp256k1.git && \
    cd secp256k1 && \
    git checkout ${SECP256K1_VERSION} && \
    ./autogen.sh && \
    ./configure --prefix=/usr --enable-module-schnorrsig --enable-experimental && \
    make && make check && make install -j${JOBS}

# ── blst ──
WORKDIR /usr/local/src
RUN git clone --branch master https://github.com/supranational/blst.git && \
    cd blst && \
    git checkout v${BLST_VERSION} && \
    ./build.sh && \
    printf "prefix=/usr/local\nexec_prefix=/usr/local\nlibdir=/usr/local/lib\nincludedir=/usr/local/include\n\nName: libblst\nDescription: Multilingual BLS12-381 signature library\nURL: https://github.com/supranational/blst\nVersion: %s\nCflags: -I/usr/local/include\nLibs: -L/usr/local/lib -lblst" ${BLST_VERSION} > libblst.pc && \
    mv libblst.pc /usr/local/lib/pkgconfig/ && \
    mv bindings/blst.h bindings/blst.hpp bindings/blst_aux.h /usr/local/include/ && \
    mv libblst.a /usr/local/lib

ENV LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH" \
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"

# ── GHCup (bootstrap Haskell toolchain) ──
RUN curl -L https://downloads.haskell.org/~ghcup/${BOOTSTRAP_HASKELL_GHCUP_VERSION}/x86_64-linux-ghcup-${BOOTSTRAP_HASKELL_GHCUP_VERSION} \
        -o /usr/local/bin/ghcup && \
    chmod +x /usr/local/bin/ghcup && \
    ghcup install cabal ${BOOTSTRAP_HASKELL_CABAL_VERSION} && \
    ghcup set cabal ${BOOTSTRAP_HASKELL_CABAL_VERSION} && \
    ghcup install ghc ${BOOTSTRAP_HASKELL_GHC_VERSION} && \
    ghcup set ghc ${BOOTSTRAP_HASKELL_GHC_VERSION}

ENV PATH="/root/.ghcup/bin:/root/.cabal/bin:${PATH}"

RUN cabal update
