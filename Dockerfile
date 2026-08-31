# syntax=docker/dockerfile:1
#
# Build the piPXE SD card image without installing a toolchain locally:
#
#     docker buildx bake
#
# which writes out/sdcard.img and out/sdcard.zip.
#
# The submodule sources are taken from the build context, so check them
# out first:
#
#     git submodule update --init --recursive

ARG UBUNTU_VERSION=24.04

FROM ubuntu:${UBUNTU_VERSION} AS toolchain
ENV DEBIAN_FRONTEND=noninteractive
RUN rm -f /etc/apt/apt.conf.d/docker-clean
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl gcc-aarch64-linux-gnu \
        iasl mtools python3 uuid-dev zip

FROM toolchain AS build
WORKDIR /pipxe

# The submodule sources are copied first, and separately, so that
# editing config.txt or the Makefile does not invalidate their (large)
# layers.
COPY edk2 edk2
COPY edk2-platforms edk2-platforms
COPY edk2-non-osi edk2-non-osi
COPY ipxe ipxe
COPY . .

# Optional iPXE script to embed in the binary, as a path relative to the
# build context (see IPXE_EMBED in the Makefile).
ARG IPXE_EMBED=

RUN make IPXE_EMBED="${IPXE_EMBED}" ipxe -j "$(nproc)"
RUN make IPXE_EMBED="${IPXE_EMBED}"

FROM scratch AS artifacts
COPY --from=build /pipxe/sdcard.img /pipxe/sdcard.zip /
