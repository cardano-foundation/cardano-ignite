# -------------------------------------------------
#  Shared build environment for Cardano binaries
# -------------------------------------------------
ARG BASE_IMAGE=cardano-ignite-base
FROM ${BASE_IMAGE} AS haskell-builder

# ── Common ARGs (keep the defaults from the originals) ──
ARG BLST_VERSION=0.3.14
ARG JOBS=8
# Full commit hashes: git fetch of an exact commit requires the full id.
ARG LIBSODIUM_VERSION=dbb48cce5429cb6585c9034f002568964f1ce567
ARG SECP256K1_VERSION=ac83be33d0956faf6b7f61a60ab524ef7d6a473a
ARG BOOTSTRAP_HASKELL_CABAL_VERSION=3.14.2.0
ARG BOOTSTRAP_HASKELL_GHC_VERSION=9.6.7
ARG BOOTSTRAP_HASKELL_GHCUP_VERSION=0.1.50.2
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
        g++ \
        git \
        gnupg \
        libffi-dev \
        libgmp-dev \
        liblmdb-dev \
        libncurses-dev \
        libsnappy-dev \
        libssl-dev \
        libsystemd-dev \
        libtinfo-dev \
        libtool \
        liburing-dev \
        pkg-config \
        protobuf-compiler \
        zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

# ── libsodium ──
WORKDIR /usr/local/src
RUN git init libsodium && \
    cd libsodium && \
    git fetch --depth 1 https://github.com/IntersectMBO/libsodium.git ${LIBSODIUM_VERSION} && \
    git checkout FETCH_HEAD && \
    ./autogen.sh && \
    ./configure && \
    make && make check && make install -j${JOBS}

# ── secp256k1 ──
WORKDIR /usr/local/src
RUN git init secp256k1 && \
    cd secp256k1 && \
    git fetch --depth 1 https://github.com/bitcoin-core/secp256k1.git ${SECP256K1_VERSION} && \
    git checkout FETCH_HEAD && \
    ./autogen.sh && \
    ./configure --prefix=/usr --enable-module-schnorrsig --enable-experimental && \
    make && make check && make install -j${JOBS}

# ── blst ──
WORKDIR /usr/local/src
RUN git init blst && \
    cd blst && \
    git fetch --depth 1 https://github.com/supranational/blst.git v${BLST_VERSION} && \
    git checkout FETCH_HEAD && \
    ./build.sh && \
    printf "prefix=/usr/local\nexec_prefix=/usr/local\nlibdir=/usr/local/lib\nincludedir=/usr/local/include\n\nName: libblst\nDescription: Multilingual BLS12-381 signature library\nURL: https://github.com/supranational/blst\nVersion: %s\nCflags: -I/usr/local/include\nLibs: -L/usr/local/lib -lblst" ${BLST_VERSION} > libblst.pc && \
    mv libblst.pc /usr/local/lib/pkgconfig/ && \
    mv bindings/blst.h bindings/blst.hpp bindings/blst_aux.h /usr/local/include/ && \
    mv libblst.a /usr/local/lib

ENV LD_LIBRARY_PATH="/usr/local/lib" \
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig"

# ── GHCup (bootstrap Haskell toolchain) ──
RUN curl -L https://downloads.haskell.org/~ghcup/${BOOTSTRAP_HASKELL_GHCUP_VERSION}/x86_64-linux-ghcup-${BOOTSTRAP_HASKELL_GHCUP_VERSION} \
        -o /tmp/x86_64-linux-ghcup-${BOOTSTRAP_HASKELL_GHCUP_VERSION} && \
    curl -L https://downloads.haskell.org/~ghcup/${BOOTSTRAP_HASKELL_GHCUP_VERSION}/SHA256SUMS \
        -o /tmp/SHA256SUMS && \
    cd /tmp && \
    sha256sum --ignore-missing --check SHA256SUMS && \
    install --mode=0755 /tmp/x86_64-linux-ghcup-${BOOTSTRAP_HASKELL_GHCUP_VERSION} /usr/local/bin/ghcup && \
    rm -f /tmp/x86_64-linux-ghcup-${BOOTSTRAP_HASKELL_GHCUP_VERSION} /tmp/SHA256SUMS && \
    ghcup install cabal ${BOOTSTRAP_HASKELL_CABAL_VERSION} && \
    ghcup set cabal ${BOOTSTRAP_HASKELL_CABAL_VERSION} && \
    ghcup install ghc ${BOOTSTRAP_HASKELL_GHC_VERSION} && \
    ghcup set ghc ${BOOTSTRAP_HASKELL_GHC_VERSION}

ENV PATH="/root/.ghcup/bin:/root/.cabal/bin:${PATH}"

RUN cabal update
