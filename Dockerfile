# syntax=docker/dockerfile:1

# Build:
#   docker build -t singularity-ce-debian:4.3.0 .
# Run a nested container (privileged mode is required by SingularityCE):
#   docker run --rm --privileged singularity-ce-debian:4.3.0 \
#     singularity exec docker://alpine:3.22 cat /etc/alpine-release

ARG DEBIAN_VERSION=trixie
ARG SINGULARITY_VERSION=4.3.0
ARG PIXI_VERSION=v0.76.2

FROM debian:${DEBIAN_VERSION}-slim AS build

ARG SINGULARITY_VERSION
ARG SINGULARITY_SHA256=1c881dd269e8420301efb064be5893dd6d73a3bac79f641e3a7878a8f38eada0

ENV DEBIAN_FRONTEND=noninteractive

# Build requirements from the SingularityCE 4.3 installation guide. Debian
# trixie provides Go >= 1.23.4, which is required by SingularityCE 4.3.0.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        build-essential \
        ca-certificates \
        cryptsetup \
        fuse \
        fuse2fs \
        git \
        golang-go \
        libfuse-dev \
        libseccomp-dev \
        libsubid-dev \
        libtool \
        pkg-config \
        runc \
        squashfs-tools \
        squashfs-tools-ng \
        uidmap \
        wget \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/singularity-build

RUN wget -q "https://github.com/sylabs/singularity/releases/download/v${SINGULARITY_VERSION}/singularity-ce-${SINGULARITY_VERSION}.tar.gz" \
    && echo "${SINGULARITY_SHA256}  singularity-ce-${SINGULARITY_VERSION}.tar.gz" | sha256sum --check --strict \
    && tar -xzf "singularity-ce-${SINGULARITY_VERSION}.tar.gz" --strip-components=1 \
    && ./mconfig \
    && make -C builddir -j"$(nproc)" \
    && make -C builddir install


FROM debian:${DEBIAN_VERSION}-slim AS runtime

ARG SINGULARITY_VERSION
ARG PIXI_VERSION

LABEL org.opencontainers.image.title="SingularityCE on Debian" \
      org.opencontainers.image.version="${SINGULARITY_VERSION}" \
      org.opencontainers.image.source="https://github.com/sylabs/singularity"

ENV DEBIAN_FRONTEND=noninteractive \
    SINGULARITY_CACHEDIR=/var/cache/singularity \
    SINGULARITY_TMPDIR=/var/tmp/singularity

# Runtime helpers cover native SIF execution, OCI mode, fakeroot, encrypted
# images, and Debian/Ubuntu definition-file bootstrapping.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        conmon \
        cryptsetup \
        curl \
        debootstrap \
        fuse \
        fuse2fs \
        git \
        libfuse2 \
        libseccomp2 \
        make \
        runc \
        squashfs-tools \
        squashfs-tools-ng \
        uidmap \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p "${SINGULARITY_CACHEDIR}" "${SINGULARITY_TMPDIR}"

COPY --from=build /usr/local/ /usr/local/

# Install Pixi as a system-wide, standalone binary. PIXI_BIN_DIR and
# PIXI_NO_PATH_UPDATE follow the drop-in installation documented by Prefix.
RUN curl -fsSL -o /tmp/install-pixi.sh https://pixi.sh/install.sh \
    && PIXI_VERSION="${PIXI_VERSION}" \
       PIXI_BIN_DIR=/usr/local/bin \
       PIXI_NO_PATH_UPDATE=1 \
       sh /tmp/install-pixi.sh \
    && rm /tmp/install-pixi.sh

# The installation itself can be checked without privileges. Executing or
# building nested containers requires `docker run --privileged`.
RUN singularity version \
    && test "$(singularity version)" = "${SINGULARITY_VERSION}" \
    && pixi --version

WORKDIR /work

CMD ["/bin/bash"]
