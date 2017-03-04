#!/bin/bash

set -e

if [ -z "${LFS_ROOT+x}" ]; then echo "missing \$LFS_ROOT";exit ;else echo "using lfs root: $LFS_ROOT"; fi
if [ -z "${DISK_ROOT+x}" ]; then echo "missing \$DISK_ROOT";exit ;else echo "using disk root: $DISK_ROOT"; fi

if [ -n $1 ]; then
  echo "Usage:"
  echo "  ./createdrive.sh <hard drive>"
  exit
fi

ROOT_START=1MB
ROOT_END=5G

HOME_START=5G
HOME_END=100%

DRIVE=$1

# create partitions
parted $DRIVE mklabel gpt # create partition table
parted $DRIVE -a optimal mkpart primary ext4 $ROOT_START $ROOT_END # root partition
parted $DRIVE -a optimal mkpart primary zfs $HOME_START $HOME_END # home partition

# root partition
losetup --offset=$ROOT_START /dev/loop0 $DRIVE
mkfs -t ext4 /dev/loop0
mkdir -p $DISK_ROOT
mount /dev/loop0 $DISK_ROOT

# install GRUB
grub-install $DRIVE
mkdir -p $DISK_ROOT/boot/
mount /dev/loop0 $DISK_ROOT/boot/
cat > $DISK_ROOT/boot/grub/grub.cfg << EOF1
# Begin /boot/grub/grub.cfg
set default=0
set timeout=5

insmod ext2
set root=(hd0,2)

menuentry "GNU/Linux, Linux 4.7.2-lfs-7.10" {
    linux /boot/vmlinuz-4.7.2-lfs-7.10 root=/dev/sda2 ro
}
EOF1

# copy root fs
cp -r $LFS_ROOT/* $DISK_ROOT

# unmount filesystems
umount /dev/loop0
losetup -d /dev/loop0
umount /dev/loop1
losetup -d /dev/loop1
