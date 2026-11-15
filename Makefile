# Raspberry Pi VC4 boot firmware
#
# Only the files needed to chainload UEFI on a BCM2711 (Pi 4B, Pi 400,
# CM4) are required: the Pi 4 boot ROM loads bootcode from the onboard
# SPI EEPROM, so no bootcode.bin is needed on the SD card.
#
FW_VERSION	:= 1.20260824
FW_URL		:= https://raw.githubusercontent.com/raspberrypi/firmware/$(FW_VERSION)/boot
FW_FILES	:= LICENCE.broadcom start4.elf fixup4.dat \
		   bcm2711-rpi-4-b.dtb bcm2711-rpi-400.dtb bcm2711-rpi-cm4.dtb \
		   overlays/miniuart-bt.dtbo overlays/upstream-pi4.dtbo
FW_STAMPS	:= $(addprefix firmware/,$(FW_FILES))

EFI_BUILD	:= RELEASE
EFI_ARCH	:= AARCH64
EFI_TOOLCHAIN	:= GCC
EFI_TIMEOUT	:= 3
# Expose all installed RAM rather than the EDK2 RPi4 default of 3GB.
# Within UEFI, DMA for PCIe devices (including the xHCI controller) is
# already bounced below 3GB, so the limit only matters to an OS that
# ignores the platform's DMA constraints.  Set to 1 to restore it.
EFI_RAM_LIMIT_3GB := 0
EFI_FLAGS	:= --pcd=PcdPlatformBootTimeOut=$(EFI_TIMEOUT) \
		   --pcd=PcdRamLimitTo3GB=$(EFI_RAM_LIMIT_3GB)
EFI_PLATFORM	:= RPi4
EFI_DSC		:= edk2-platforms/Platform/RaspberryPi/$(EFI_PLATFORM)/$(EFI_PLATFORM).dsc
EFI_FD		:= Build/$(EFI_PLATFORM)/$(EFI_BUILD)_$(EFI_TOOLCHAIN)/FV/RPI_EFI.fd

IPXE_CROSS	:= aarch64-linux-gnu-
IPXE_SRC	:= ipxe/src
IPXE_TGT	:= bin-arm64-efi/rpi.efi
IPXE_EFI	:= $(IPXE_SRC)/$(IPXE_TGT)
# The Pi 4 onboard NIC (Broadcom GENET) is driven by the UEFI firmware,
# so iPXE reaches it via the EFI SNP/NII driver.  The native USB network
# drivers are retained for USB Ethernet adapters.
IPXE_DRIVERS	:= snp smsc95xx lan78xx
# Optional iPXE script to embed in the binary, e.g.
#   make IPXE_EMBED=boot.ipxe
IPXE_EMBED	:=
# Optional comma-separated list of certificates, and a private key, to
# build into the binary.  The certificate matching IPXE_PRIVKEY is used
# as iPXE's TLS client certificate and to decrypt images with
# imgdecrypt.  Any other certificates are made available for building
# chains; this must include every IPXE_TRUST root, since IPXE_TRUST only
# records fingerprints and servers do not normally send their root.
IPXE_CERT	:=
IPXE_PRIVKEY	:=
# Optional comma-separated list of trusted root CA certificates.  Empty
# means iPXE's default.  Setting it *replaces* the default, so it must
# also include the roots of any public HTTPS server iPXE talks to.
IPXE_TRUST	:=
# Files copied over the iPXE submodule before building, at the same
# relative paths: ipxe-overlay/src/config/local/rpi/general.h becomes
# ipxe/src/config/local/rpi/general.h, the CONFIG=rpi build configuration.
# They live here because iPXE's repository ignores config/local.
IPXE_OVERLAY	:= ipxe-overlay

SDCARD_MB	:= 32
# Size of the FAT partition in the GPT image, in MiB.  It starts at 1MiB
# and must leave room for the backup GPT at the end of the image.
GPT_PART_MB	:= 30
# Prerequisites of the sdcard target.  A container build that has already
# built EFI and iPXE in earlier layers clears this, so that the (phony)
# EFI target is not rebuilt.
SDCARD_DEPS	:= firmware efi ipxe
export MTOOLSRC	:= mtoolsrc

SHELL		:= /bin/bash

all : sdcard sdcard.img sdcard-gpt.img sdcard.zip

# Update the submodules, unless we are building from a tree that has no
# git metadata (e.g. a source tarball, or a container image built from
# the working tree), in which case the sources must already be present.
submodules :
	if [ -e .git ] ; then \
		git submodule update --init --recursive ; \
	elif [ ! -e $(EFI_DSC) ] ; then \
		echo "No .git directory and no submodule sources" >&2 ; \
		exit 1 ; \
	fi

firmware : $(FW_STAMPS)

$(FW_STAMPS) : firmware/% :
	mkdir -p $(dir $@)
	curl -sSf -L -o $@.tmp $(FW_URL)/$*
	mv $@.tmp $@

efi : $(EFI_FD)

efi-basetools : submodules
	$(MAKE) -C edk2/BaseTools

$(EFI_FD) : submodules efi-basetools
	. ./edksetup.sh && \
	build -b $(EFI_BUILD) -a $(EFI_ARCH) -t $(EFI_TOOLCHAIN) \
		-p $(EFI_DSC) $(EFI_FLAGS)

ipxe : $(IPXE_EFI)

# Copy only files whose contents differ, so that iPXE is not rebuilt
# needlessly.
ipxe-overlay : submodules
	cd $(IPXE_OVERLAY) && find . -type f | while read -r f ; do \
		mkdir -p ../ipxe/$${f%/*} ; \
		cmp -s $$f ../ipxe/$$f || cp $$f ../ipxe/$$f ; \
	done

# abspath of each entry in a comma-separated list
COMMA	:= ,
SPACE	:= $(eval) $(eval)
abspaths = $(subst $(SPACE),$(COMMA),$(abspath $(subst $(COMMA),$(SPACE),$(1))))

$(IPXE_EFI) : submodules ipxe-overlay
	$(MAKE) -C $(IPXE_SRC) CROSS=$(IPXE_CROSS) CONFIG=rpi \
		DRIVERS_rpi="$(IPXE_DRIVERS)" \
		$(if $(IPXE_EMBED),EMBED=$(abspath $(IPXE_EMBED))) \
		$(if $(IPXE_CERT),CERT=$(call abspaths,$(IPXE_CERT))) \
		$(if $(IPXE_PRIVKEY),PRIVKEY=$(abspath $(IPXE_PRIVKEY))) \
		$(if $(IPXE_TRUST),TRUST=$(call abspaths,$(IPXE_TRUST))) \
		$(IPXE_TGT)

sdcard : $(SDCARD_DEPS)
	$(RM) -rf sdcard
	mkdir -p sdcard
	cp -r firmware/* sdcard/
	cp config.txt $(EFI_FD) edk2/License.txt sdcard/
	mkdir -p sdcard/efi/boot
	cp $(IPXE_EFI) sdcard/efi/boot/bootaa64.efi
	cp ipxe/COPYING* sdcard/

sdcard.img : sdcard
	truncate -s $(SDCARD_MB)M $@
	mpartition -I -c -b 32 -s 32 -h 64 -t $(SDCARD_MB) -a "z:"
	mformat -v "piPXE" "z:"
	mcopy -s sdcard/* "z:"

# The same files on a GPT disk, with the space after the FAT partition
# left free.  Unlike the MBR image, this can be extended with further
# partitions by tools that only handle GPT (e.g. Ignition).  The Pi 4
# EEPROM bootloader boots from GPT disks.
sdcard-gpt.img : sdcard
	$(RM) -f $@
	truncate -s $(SDCARD_MB)M $@
	sgdisk --clear --new=1:1M:+$(GPT_PART_MB)M --typecode=1:0700 \
		--change-name=1:piPXE $@
	mformat -i $@@@1M -T $$(( $(GPT_PART_MB) * 2048 )) -h 64 -s 32 -H 2048 \
		-v "piPXE" ::
	mcopy -i $@@@1M -s sdcard/* ::

sdcard.zip : sdcard
	$(RM) -f $@
	( pushd $< ; zip -q -r ../$@ * ; popd )

update:
	git submodule foreach git pull origin master

tag :
	git tag v`git show -s --format='%ad' --date=short | tr -d -`

.PHONY : submodules firmware efi efi-basetools $(EFI_FD) ipxe ipxe-overlay \
	 $(IPXE_EFI) sdcard sdcard.img sdcard-gpt.img

clean :
	$(RM) -rf firmware Build sdcard sdcard.img sdcard-gpt.img sdcard.zip
	if [ -d $(IPXE_SRC) ] ; then $(MAKE) -C $(IPXE_SRC) clean ; fi
