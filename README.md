piPXE - iPXE for the Raspberry Pi
=================================

[![Build](https://img.shields.io/github/actions/workflow/status/ipxe/pipxe/build.yml?branch=master)](https://github.com/ipxe/pipxe/actions?query=workflow%3ABuild+branch%3Amaster)
[![Release](https://img.shields.io/github/v/release/ipxe/pipxe)](https://github.com/ipxe/pipxe/releases/latest)

piPXE is a build of the [iPXE] network boot firmware for the
[Raspberry Pi].

Supported models
----------------

piPXE targets the BCM2711-based models:

* Raspberry Pi 4 Model B
* Raspberry Pi 400
* Raspberry Pi Compute Module 4

Quick start
-----------

1. Download [sdcard.img] and write it onto any blank micro SD card
using a tool such as `dd` or [Etcher].

2. Insert the micro SD card into your Raspberry Pi.

3. Power on your Raspberry Pi.

Within a few seconds you should see iPXE appear and begin booting from
the network:

![Screenshot](screenshot.png)

Building from source
--------------------

To build from source, clone this repository and run `make`.  This will
build all of the required components and eventually generate the SD
card image [sdcard.img].

You will need various build tools installed, including a
cross-compiling version of `gcc` for building AArch64 binaries.

Fedora build tools:

    sudo dnf install -y binutils curl gcc gcc-aarch64-linux-gnu \
                        gcc-c++ git-core iasl libuuid-devel make \
                        mtools perl python3 xz-devel zip

Ubuntu build tools:

    sudo apt install -y build-essential curl gcc-aarch64-linux-gnu \
                        git iasl lzma-dev mtools perl python3 \
                        uuid-dev zip

Alternatively, build inside a container with no local toolchain at all.
This uses BuildKit file outputs, so nothing is left behind but the
artifacts:

    git submodule update --init --recursive
    docker buildx bake

which writes `out/sdcard.img`, `out/sdcard-gpt.img` and `out/sdcard.zip`.  The submodule
sources are taken from the working tree, so they must be checked out
first.

To build without `bake`:

    docker buildx build --target artifacts --output type=local,dest=out .

How it works
------------

The SD card image contains:

* Broadcom [VC4 boot firmware]: `start4.elf`, `fixup4.dat` and the
  BCM2711 device tree blobs
* [TianoCore EDK2] UEFI firmware built for the [RPi4] platform: `RPI_EFI.fd`
* [iPXE] built for the `arm64-efi` platform: `/efi/boot/bootaa64.efi`

The Raspberry Pi has a somewhat convoluted boot process in which the
VC4 GPU is responsible for loading the initial executable ARM CPU
code.  On the Raspberry Pi 4 the first stage lives in an onboard SPI
EEPROM rather than on the SD card, so there is no `bootcode.bin`.  The
flow of execution is approximately:

1. The GPU code in the onboard boot ROM loads the second stage bootloader
   from the SPI EEPROM.
2. The EEPROM bootloader loads `start4.elf` from the SD card.
3. The GPU executes `start4.elf`, which reads `config.txt` and loads
   `RPI_EFI.fd` as the Arm stub.
4. The GPU allows the CPU to start executing `RPI_EFI.fd`, which runs
   Arm Trusted Firmware and then the UEFI firmware.
5. The CPU executes `RPI_EFI.fd` and loads `bootaa64.efi` from the SD card.
6. The CPU executes `bootaa64.efi` (i.e. iPXE) to boot from the network.

The onboard gigabit Ethernet controller (Broadcom GENET) is driven by
the UEFI firmware; iPXE uses it via the UEFI Simple Network Protocol.
USB Ethernet adapters are supported via the UEFI USB I/O protocol.

Note that the Raspberry Pi 4 EEPROM bootloader must be new enough to
load `start4.elf`.  Any Raspberry Pi 4 shipped with a reasonably recent
EEPROM will work; if in doubt, update the EEPROM using [Raspberry Pi
Imager] before using piPXE.

The EDK2 RPi4 platform limits the visible RAM to 3GB by default (a
workaround for operating systems that do not respect the PCIe
controller's DMA constraints).  piPXE disables this limit so that all
installed RAM is available; build with `make EFI_RAM_LIMIT_3GB=1` to
restore it.  The firmware also exposes ACPI rather than a Device Tree
by default.  Both settings can be changed from the UEFI setup menu,
reached by pressing `Esc` during the three second boot timeout.

Embedding a boot script
-----------------------

iPXE's `EMBED` mechanism works on this platform, and can be used to
build an image that runs a fixed script instead of relying on DHCP
options to point at one.  Write the script, then:

    make IPXE_EMBED=boot.ipxe

or, for a container build:

    docker buildx bake --set '*.args.IPXE_EMBED=boot.ipxe'

The script path is relative to the top of this repository (and must be
inside it for the container build, since it is read from the build
context).  For example:

    #!ipxe
    dhcp
    chain --autofree http://boot.example.com/menu.ipxe

The embedded script is executed in place of the default autoboot
sequence, so it must bring up the network itself.

Certificates and keys can be built in the same way, with `IPXE_CERT`
(comma-separated certificates), `IPXE_PRIVKEY` (the private key for one of
them: iPXE's TLS client certificate and `imgdecrypt` key) and `IPXE_TRUST`
(comma-separated trusted roots, replacing iPXE's default).  Every
`IPXE_TRUST` root must also be listed in `IPXE_CERT`, since `IPXE_TRUST`
only records fingerprints.

For a container build driven from another repository, put these files in
a named context called `embed`; it is copied to `/embed`:

    target "pipxe" {
      context  = "https://github.com/davejbax/pipxe-4.git#<commit>"
      target   = "artifacts"
      contexts = { embed = "./ipxe-files" }
      args     = { IPXE_EMBED = "/embed/boot.ipxe" }
    }

The `imgtrust`, `imgverify` and `imgdecrypt` commands are enabled (see
`ipxe-overlay/src/config/local/rpi/general.h`).  Files under
`ipxe-overlay/` are copied over the `ipxe` submodule at the same paths
before building.

GPT image
---------

`sdcard-gpt.img` holds the same files on a GPT disk, with space after
the FAT partition left free.  Unlike `sdcard.img` it can be extended by
tools that only handle GPT, such as Ignition.  The Pi 4 EEPROM
bootloader boots from GPT disks.

Licence
-------

Every component is under an open source licence.  See the individual
subproject licensing terms for more details:

* <https://github.com/raspberrypi/firmware/blob/master/boot/LICENCE.broadcom>
* <https://github.com/tianocore/edk2/blob/master/Readme.md>
* <https://ipxe.org/licensing>

[iPXE]: https://ipxe.org
[Raspberry Pi]: https://www.raspberrypi.com
[sdcard.img]: https://github.com/ipxe/pipxe/releases/latest/download/sdcard.img
[Etcher]: https://www.balena.io/etcher
[Raspberry Pi Imager]: https://www.raspberrypi.com/software/
[VC4 boot firmware]: https://github.com/raspberrypi/firmware/tree/master/boot
[TianoCore EDK2]: https://github.com/tianocore/edk2
[RPi4]: https://github.com/tianocore/edk2-platforms/tree/master/Platform/RaspberryPi/RPi4
