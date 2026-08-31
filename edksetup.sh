export WORKSPACE=$(pwd)
export PACKAGES_PATH=$WORKSPACE/edk2:$WORKSPACE/edk2-platforms:$WORKSPACE/edk2-non-osi
export GCC_ARM_PREFIX=arm-linux-gnu-
export GCC_AARCH64_PREFIX=aarch64-linux-gnu-

. ./edk2/edksetup.sh
