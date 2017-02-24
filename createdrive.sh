#!/bin/bash

set -e

if [ -n $1 ]; then
  echo "Usage:"
  echo "  ./partition.sh <hard drive>"
  exit
fi

BOOT_START=1M
BOOT_END=100MB

ROOT_START=100MB
ROOT_END=5G

HOME_START=5G
HOME_END=100%

DRIVE=$1

# create partitions
parted $DRIVE mklabel gpt # create partition table
parted $DRIVE -a optimal mkpart primary fat32 $BOOT_START $BOOT_END # boot partition
parted $DRIVE -a optimal mkpart primary ext4 $ROOT_START $ROOT_END # root partition
parted $DRIVE -a optimal mkpart primary zfs $HOME_START $HOME_END # home partition

sudo su <<EOF # enter root mode

# root partition
losetup --offset=$ROOT_START /dev/loop0 $1
mkfs -t ext4 /dev/loop0
mkdir -p build/drive/root
mount /dev/loop0 build/drive/root

# TODO copy

# unmount filesystems
umount /dev/loop0
losetup -d /dev/loop0

EOF
