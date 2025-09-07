===========
 Multipass
===========

This is a tool intended to help with Full Disk Encryption (FDE) setups with
ZFS. The idea is to improve the usability of FDE in two ways:

1. Allow multiple passphrases to unlock the root filesystem. This is useful if
   you want to give other people access to the machine without sharing a single
   encryption passphrase.

2. Use TPM to unlock the disc encryption without manual passphrase. This should
   make it more convenient to use FDE and also allows remote reboots. The manual
   passphrase is then used as backup in case the TPM unlock fails.

This repos contains a script to manage the keys and scripts for the initramfs to
unlock the proper keyfile used to unlock the FDE.

Requirements
============

* This assumes you already have a FDE setup with ZFS. If you look for
  instructions for that, checkout
  https://openzfs.github.io/openzfs-docs/Getting%20Started/index.html
* I use ``systemd-boot`` as bootloader. This should work with Grub as well but
  there might be some unknown issues.
* The scripts are intended for usage with initramfs-tools. This is installed by
  default on Debian.
* ``openssl`` - for managing the keys
* ``tpm2-initramfs-tool`` - for interacting with TPM2

Setup with ZFS
==============

After you installed the above requirements, install the scripts with::

    make install

Next, we setup our key infrastructure. We store encrypted keys and identify
them by name. The names are not special, use what you want. The following
command prompts for a passphrase and stores a randomly generated key encrypted
by this passphrase::

    multipas setup rpool.root

To make modifications of keys effective, the initramfs needs to be updated.
This will also setup our script to retrieve the encryption key before ZFS gets
mounted::

    update-initramfs -u

IMPORTANT: I recommend to check that everything actually is installed in the
initramfs. Otherwise you will be in trouble accessing your system later. I
would also recommend to make a copy of your keys to another system, so that you
have a change to recover if anything goes wrong. The keys live in the directory
``/etc/multipass``. It can also be helpful to setup ``dropbear-initramfs`` to
allow troubleshooting over a network. All of this was very helpful for me to
get these scripts working and can prevent dataloss in case anything goes wrong.

Check the initramfs to verify that the keys and scripts are installed (the
paths here will be different depending on your setup)::

    lsinitramfs /boot/initrd.img-6.12.38+deb13-amd64 | grep multipass

You should see your key files and the multipass script. Additionally, you
should check for ``openssl`` and the ``tpm2-initramfs-tool`` in a similar way.

The final step is to actually switch the ZFS
encryption key. This is the part where stuff can break and you really should
have backups before proceeding.

To switch out the key, use the following commands::

    multipass get > /tmp/rpool.key
    zfs change-key -o keyformat=raw -o keylocation=file:///tmp/rpool.key rpool
    rm /tmp/rpool.key

We temporarily store the key in ``/tmp``. This is also where the initramfs will
store the decrypted key on booting. In the booted system, the key will not be
there anymore.

This is it. Now comes the moment where you reboot and hope everything works.
You will be prompted for the passphrase. This will decrypt the key and store it
in ``/tmp`` (see Configuration section). The decrypted key will be sealed in
TPM and will be automatically available on next boot. Then booting continues.
The standard ZFS unlocking should pickup the key from there and should be able
to boot into your system.

Configuration
=============

By default the scripts are setup to load ``/etc/default/multipsas``. You can
override the default paths and files used in there. The important variables are::

    # directory where encrypted keys are stored
    KEYS_DIR=/etc/multipass

    # size of the key generated on setup
    KEY_LEN=32

    # location where the decrypted key will be stored at boot
    KEY_DEST=/tmp/rpool.key

    # number of passphrase attempts before continuing in the boot process
    ATTEMPTS=5


systemd-boot
============

To install ZFS on root with ``systemd-boot``, you can use the guide at
https://openzfs.github.io/openzfs-docs/Getting%20Started/index.html and make
the following modifications:

1. Skip all steps involving the boot pool (``bpool``).
2. Instead of installing grub, install ``systemd-boot``.
3. Create and mount the EFI partition as described.
4. Install with ``bootctl install``.
5. Modify the boot entry in ``/boot/efi/loader/entries/``. Remove the boot
   options from the live system. Add ``root=zfs=rpool/ROOT/debian``.


Secure Boot
===========

Full Disc Encryption makes most sense when using Secure Boot. This prevents
someone from modifying your unencrypted boot chain and extracting your keys.
The documentation on this is not so great, so for my own sake I provide the
steps I took to set this up.

This starts with an installed system without Secure Boot. For ZFS on Root this
is necessary, because most likely you will not get signed ZFS kernel modules
from the distro. The target setup uses the signed shim bootloader to work out
of the box with most systems. The distro kernel and packages should be signed
already. But we also need to setup signing for our DKMS kernel modules.

1. Install ``shim-signed`` and ``mokutil``.
2. Make sure ``shimx64.efi`` is present in ``/boot/efi/EFI``.
3. Make sure there is a bootloader listed pointing to ``shimx64.efi`` with
   ``bootctl status``.
4. There should already be a file ``/var/lib/dkms/mok.pub`` which is used for
   signing the DKMS modules.
5. Start enrolling this key with ``mokutil --import /var/lib/dkms/mok.pub``
6. Reboot the system and enable Secure Boot
7. The next reboot should boot the shim, which should prompt you for confirming
   the enrolled key.

If you do not get prompted for the confirmation, you are probably not booting
shim. You can check ``mokutil --list-new`` to confirm that you have a key
wating for confirmation.

If you are not booting shim, check that you have a matchint bootloader entry.
You can create one manually with::

    efibootmgr --create --disk /dev/sdX --part Y --label "Debian (shim)" \
        --loader "EFI/debian/shimx64.efi"

If ``shimx64.efi`` is not present in the EFI partition, you either reinstall
the respective package, or you can manually copy it there from
``/usr/lib/shim/shimx64.efi.signed``.

Remote Unlocking
================

Normally the system should boot with the TPM key. But if that doesn't work for
some reason (maybe the bootloader changed), you can use SSH for remote
unlocking.

If you installed ``dropbear-initramfs`` you can remote unlock the system with
SSH. Connect with ssh and unlock the key with ``/scripts/multipass``. Now you
only need to continue the boot process by killing the existing multipass
process, which waits for a user input. Run ``ps`` to identify the process ID.
Then kill the process. You should get kicked out and the system boots normally.

Troubleshooting
===============

When the decryption fails, you are not probably stuck in the initramfs shell.
To get back into your system, you need to get the key, unlock the root pool,
mount it to ``/root`` and boot into the system.

1. Check if the key got decrypted with ``ls /tmp``. If not you should be able
   to decrypt it with ``/scripts/multipass`` and entering a passphrase.

2. Check if ZFS is unlocked with ``zfs get -H -ovalue keystatus "rpool"``. If
   it says ``unavailable``, load the key with ``zfs load-key``. In most cases
   you now should be able to get back into your system by just exiting the
   shell with ``exit``. If not, see the next steps.

3. Check if it is mounted to ``/root``. If not you can mount it with::

    mount -o zfsutil -t zfs rpool/ROOT/debian /root

4. Boot into the system with::

    exec switch_root /root /sbin/init

If all else fails, you can still boot from a USB stick and use your backed up
keys to decrypt the system and potentially change the key. You probably have to
disable Secure Boot for that.
