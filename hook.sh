#!/bin/sh

set -e

PREREQ=""

prereqs()
{
	echo "${PREREQ}"
}

case "${1}" in
	prereqs)
		prereqs
		exit 0
		;;
esac

. /usr/share/initramfs-tools/hook-functions

[ ! -r /etc/default/multipass ] || . /etc/default/multipass

KEYS_DIR="${KEYS_DIR:-/etc/multipass}"

# used to unseal and reseal key to TPM
copy_exec /usr/lib/x86_64-linux-gnu/libtss2-tcti-device.so.0
copy_exec /usr/bin/tpm2-initramfs-tool
copy_exec /usr/bin/sha256sum
copy_exec /usr/bin/tpm2_pcrextend

# decrypt key from user passphrase
copy_exec /usr/bin/openssl

# copy configuration

mkdir -p "${DESTDIR}/etc/default"
cp "/etc/default/multipass" "${DESTDIR}/etc/default"

# copy encrypted key files
mkdir -p "${DESTDIR}/$KEYS_DIR"
cp "$KEYS_DIR"/*.enc "${DESTDIR}/$KEYS_DIR"
