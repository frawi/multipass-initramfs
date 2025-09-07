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

# load configuration
[ ! -r /etc/default/multipass ] || . /etc/default/multipass

KEYS_DIR="${KEYS_DIR:-/etc/multipass}"
KEY_DEST="${KEY_DEST:-/tmp/rpool.key}"
PROMPT="${PROMPT:-Encryption Passphrase}"
DECRYPT="${DECRYPT:-openssl enc -d -aes-256-cbc -pbkdf2 -pass stdin -in}"
ATTEMPTS="${ATTEMPTS:-5}"
PCR="${PCR:-0,2,4,7,16}"

ask_pass()
{
	if /bin/plymouth --ping 2>/dev/null; then
		plymouth ask-for-password --prompt "$PROMPT"
	elif [ -e /run/systemd/system ]; then
		systemd-ask-password --no-tty "$PROMPT"
	else
		read -r storeprintk _ < /proc/sys/kernel/printk
		echo 7 > /proc/sys/kernel/printk
		echo "$PROMPT:" >&2
		echo "$storeprintk" > /proc/sys/kernel/printk
		read -s -r password
		echo "$password"
	fi
}

unseal_key()
{
	tpm2-initramfs-tool unseal -p "$PCR" > "$KEY_DEST.tmp" || return 0
	mv "$KEY_DEST.tmp" "$KEY_DEST"
}

reseal_key()
{
	tpm2-initramfs-tool seal --data "$(cat "$1")" -p "$PCR" > /dev/null
}

unseal_key || true

count=0
while [ ! -s "$KEY_DEST" ]; do
	count=$((count + 1))
	[ "$count" -le "$ATTEMPTS" ] || break
	password="$(ask_pass)"

	for key in "$KEYS_DIR"/*.enc; do
		echo "$password" | $DECRYPT "$key" 2> /dev/null > "$KEY_DEST.tmp" || continue
		mv "$KEY_DEST.tmp" "$KEY_DEST"
		break
	done
done

if [ -s "$KEY_DEST" ]; then
	reseal_key "$KEY_DEST" || true
	# prevent the key from leaking into the booted system
	tpm2_pcrextend 16:sha256=$(sha256sum "$KEY_DEST" | cut -d" " -f1)
fi

exit 0
