# Build the SD card image with BuildKit:
#
#     docker buildx bake                          # -> out/sdcard.img
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

# Directory to write sdcard.img and sdcard.zip into.
variable "DEST" {
  default = "out"
}

group "default" {
  targets = ["sdcard"]
}

# The SD card image and ZIP archive, extracted as plain files.
target "sdcard" {
  dockerfile = "Dockerfile"
  target     = "artifacts"
  args = {
    UBUNTU_VERSION = UBUNTU_VERSION
    IPXE_EMBED     = IPXE_EMBED
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
