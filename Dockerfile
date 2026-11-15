# syntax=docker/dockerfile:1
#
# Build the piPXE SD card image without installing a toolchain locally:
#
#     docker buildx bake
#
# which writes out/sdcard.img, out/sdcard-gpt.img and out/sdcard.zip.
#
# The submodule sources are taken from the build context, so check them
# out first:
#
#     git submodule update --init --recursive
#
# Files to build into iPXE (IPXE_EMBED, IPXE_CERT, IPXE_PRIVKEY,
# IPXE_TRUST) are paths relative to the build context.  They can instead
# come from a separate "embed" named context, which is copied to /embed,
# e.g. from another repository's bake file:
#
#     contexts = { embed = "./my-ipxe-files" }
#     args     = { IPXE_EMBED = "/embed/boot.ipxe" }

ARG UBUNTU_VERSION=24.04

FROM ubuntu:${UBUNTU_VERSION} AS toolchain
ENV DEBIAN_FRONTEND=noninteractive
RUN rm -f /etc/apt/apt.conf.d/docker-clean
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl gcc-aarch64-linux-gnu \
        gdisk iasl mtools python3 uuid-dev zip

# Empty unless overridden with a named context.
FROM scratch AS embed

FROM toolchain AS efi
WORKDIR /pipxe

# The submodule sources are copied first, and separately, so that
# editing config.txt or the Makefile does not invalidate their (large)
# layers.
COPY edk2 edk2
COPY edk2-platforms edk2-platforms
COPY edk2-non-osi edk2-non-osi
COPY ipxe ipxe
COPY . .

# The firmware and UEFI do not depend on anything embedded in iPXE, so
# they are built before the embedded files are added.  Builds that differ
# only in those files share this layer.
RUN make firmware efi

FROM efi AS build
COPY --from=embed / /embed/

ARG IPXE_EMBED=
ARG IPXE_CERT=
ARG IPXE_PRIVKEY=
ARG IPXE_TRUST=

RUN make IPXE_EMBED="${IPXE_EMBED}" IPXE_CERT="${IPXE_CERT}" \
         IPXE_PRIVKEY="${IPXE_PRIVKEY}" IPXE_TRUST="${IPXE_TRUST}" \
         ipxe -j "$(nproc)"
RUN make SDCARD_DEPS= sdcard sdcard.img sdcard-gpt.img sdcard.zip

FROM scratch AS artifacts
COPY --from=build /pipxe/sdcard.img /pipxe/sdcard-gpt.img /pipxe/sdcard.zip /
