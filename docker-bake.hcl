# Build the SD card image with BuildKit:
#
#     docker buildx bake                          # -> out/sdcard{,-gpt}.img
#     docker buildx bake --set '*.args.IPXE_EMBED=boot.ipxe'
#     DEST=/tmp/pipxe docker buildx bake
#
# See Dockerfile for the prerequisites.

variable "UBUNTU_VERSION" {
  default = "24.04"
}

# Path, relative to this directory, of an iPXE script to embed in the
# iPXE binary.  Empty means no embedded script.
variable "IPXE_EMBED" {
  default = ""
}

# Comma-separated certificates and a private key to build into iPXE
# (TLS client authentication, imgdecrypt, and chain building), and a
# comma-separated list of trusted root CAs.  Paths are relative to this
# directory, or absolute (e.g. under /embed).  See the Makefile.
variable "IPXE_CERT" {
  default = ""
}

variable "IPXE_PRIVKEY" {
  default = ""
}

variable "IPXE_TRUST" {
  default = ""
}

# Directory to write sdcard.img, sdcard-gpt.img and sdcard.zip into.
variable "DEST" {
  default = "out"
}

group "default" {
  targets = ["sdcard"]
}

# The SD card images (MBR and GPT) and ZIP archive, as plain files.
target "sdcard" {
  dockerfile = "Dockerfile"
  target     = "artifacts"
  args = {
    UBUNTU_VERSION = UBUNTU_VERSION
    IPXE_EMBED     = IPXE_EMBED
    IPXE_CERT      = IPXE_CERT
    IPXE_PRIVKEY   = IPXE_PRIVKEY
    IPXE_TRUST     = IPXE_TRUST
  }
  output = ["type=local,dest=${DEST}"]
}

# Just the build environment, for interactive use.
target "toolchain" {
  dockerfile = "Dockerfile"
  target     = "toolchain"
  args = {
    UBUNTU_VERSION = UBUNTU_VERSION
  }
  tags   = ["pipxe-toolchain"]
  output = ["type=docker"]
}
