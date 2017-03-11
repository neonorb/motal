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

function cleanup() {
    umount /dev/loop0
    losetup -d $LOOP_ROOT
}
trap cleanup 0

# create partitions
parted $DRIVE mklabel gpt # create partition table
parted $DRIVE -a optimal mkpart primary ext4 $ROOT_START $ROOT_END # root partition
parted $DRIVE -a optimal mkpart primary zfs $HOME_START $HOME_END # home partition

# root partition
LOOP_ROOT=`losetup --offset=$ROOT_START --show -f $DRIVE` # create a loop device at the offset and store the device name in LOOP_ROOT
mkfs -t ext4 $LOOP_ROOT # create root filesystem on loop device
mkdir -p $DISK_ROOT # create mountpoint
mount $LOOP_ROOT $DISK_ROOT # mount root filesystem

grub-install $DRIVE # install GRUB

mkdir -p $DISK_ROOT/boot/ # create boot configs
cat > $DISK_ROOT/boot/grub/grub.cfg << EOF1
# Begin /boot/grub/grub.cfg
set default=0
set timeout=5

insmod ext2
set root=(hd0,2)

menuentry "GNU/Linux, Linux 4.7.2-lfs-7.10" {
    linux /boot/vmlinuz-4.7.2-lfs-7.10 root=/dev/sda1 ro
}
EOF1

# copy root fs
cp -r $LFS_ROOT/* $DISK_ROOT

# trap cleanup
