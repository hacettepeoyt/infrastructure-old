#!/usr/bin/env bash

# Script for automatically installing a single-disk Arch Linux instance from archiso environment.

set -e

if [[ "$(cat /etc/hostname)" != "archiso" ]]; then
  echo "This script must be run from archiso." 1>&2
  exit 1
fi

DISK="$(ls /dev | grep -E "^([sv]d[a-z]+|nvme[0-9]+n[0-9]+)$")"

if [ $(wc -l <<< "$DISK") -ne 1 ]; then
  echo "Multiple disks detected:" 1>&2
  echo "$DISK" 1>&2
  echo "Bailing out."
  exit 1
fi

DISK="/dev/$DISK"

# Might be left in a mounted state if the script was run before.
umount -R /mnt || true

parted -s $DISK mktable gpt
parted -a optimal -s $DISK mkpart bootloader fat32 1MiB 301MiB
parted -s $DISK set 1 esp on
parted -a optimal -s $DISK mkpart primary ext4 301MiB 100%
yes | mkfs.fat -F 32 ${DISK}1 
yes | mkfs.ext4 -q ${DISK}2

mount ${DISK}2 /mnt
mkdir -p /mnt/boot
mount ${DISK}1 /mnt/boot

echo "Created partitions."

mkdir -p /mnt/{root/.ssh,etc}
cp /root/.ssh/authorized_keys /mnt/root/.ssh/authorized_keys

cat > /mnt/etc/mkinitcpio.conf <<EOF
MODULES=(ext4)
HOOKS=(systemd autodetect block fsck)
EOF

if lscpu | grep "Vendor ID" | grep "Intel" > /dev/null; then
    MICROCODE="intel-ucode"
    echo "Installing microcode for Intel CPUs."
elif lscpu | grep "Vendor ID" | grep "AMD" > /dev/null; then
    MICROCODE="amd-ucode"
    echo "Installing microcode for AMD CPUs."
else
    MICROCODE=""
    echo "Could not detect CPU vendor for microcode, skipping."
fi

sed -i -E 's/^#?ParallelDownloads/ParallelDownloads/g' /etc/pacman.conf
pacstrap /mnt base linux-hardened openssh dhcpcd efibootmgr $MICROCODE
genfstab -U /mnt >> /mnt/etc/fstab

echo "Installed required packages."

arch-chroot /mnt bash <<EOF

set -e

sed -i -E 's/^#?ParallelDownloads/ParallelDownloads/g' /etc/pacman.conf

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "vps" > /etc/hostname

systemctl enable dhcpcd
systemctl enable sshd
passwd -l root

efibootmgr --create --disk $DISK --part 1 --label "Arch Linux" --loader /vmlinuz-linux-hardened --unicode 'root=${DISK}2 rw initrd=\initramfs-linux-hardened.img'

EOF

umount -R /mnt

echo "Installation complete."
