/*
 * Local iPXE configuration for the piPXE build (CONFIG=rpi).
 *
 * Copied to ipxe/src/config/local/rpi/general.h by the Makefile, along
 * with everything else under ipxe-overlay/.
 */

/* Signature verification: imgtrust, imgverify */
#define IMAGE_TRUST_CMD

/* Decryption of CMS-encrypted images: imgdecrypt */
#define IMAGE_CRYPT_CMD
