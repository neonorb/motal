#!/bin/bash

set -e

if [ $# -eq 0 ]; then
  echo "Usage:"
  echo "  ./install.sh <hard drive>"
  exit
fi

DRIVE=$1

# boot (fat32) partition
BOOT_START=1MB
BOOT_END=1G

# root (ext4) partition
ROOT_START=1G
ROOT_END=100%

function cleanup() {
    sleep 1 # device might be still busy (dunno why)
    umount ./mnt/ || (echo ok;) # unmount anything that might still be there
    rmdir ./mnt/ || (echo ok;) # remove mountpoint
    partx -d $LOOP || (echo ok;) # get rid of partitions
    losetup -d $LOOP || (echo ok;) # remove loop device
}
trap cleanup 0

# create partitions
parted $DRIVE mklabel gpt # create partition table
parted $DRIVE -a optimal mkpart primary fat32 $BOOT_START $BOOT_END # boot partition
parted $DRIVE set 1 boot on # enable boot flag
parted $DRIVE -a optimal mkpart primary ext4 $ROOT_START $ROOT_END # root partition

# setup loop device
LOOP=$(losetup --show -f $DRIVE) # create loop device
partx -a $LOOP # tell kernel about the partitions on it

mkdir mnt # create mountpoint

# install root
ROOT=${LOOP}p2
mkfs.ext4 -L motal-root $ROOT # create root file system
mount $ROOT ./mnt/ # mount root file system
tar -xf ./buildroot/output/images/rootfs.tar -C ./mnt/ # extract root file system
cp ./fstab ./mnt/etc/fstab # copy fstab
chown root:root ./mnt/etc/fstab
cp ../mish-linux/build/x86_64/mish-linux.bin ./mnt/opt/mish
cp ./motal-main.service ./mnt/etc/systemd/system/motal-main.service
chown root:root ./mnt/etc/systemd/system/motal-main.service
systemctl --root=./mnt/ enable motal-main.service
umount $ROOT # unmount root filesystem

# install boot
BOOT=${LOOP}p1
mkfs.vfat -n motal-boot $BOOT # create boot file system
mount $BOOT ./mnt/ # mount boot file system
cp -r ./buildroot/output/images/efi-part/* ./mnt/ # copy bootloader
cp ./buildroot/output/images/bzImage ./mnt/bzImage # copy Linux image
# configure grub
UUID=$(blkid -o export $ROOT | grep -Po "(?<=^PARTUUID=).*")
cp ./grub.cfg ./mnt/EFI/BOOT/grub.cfg # copy grub config
sed -i -- "s/<uuid>/$UUID/g" ./mnt/EFI/BOOT/grub.cfg
umount ./mnt/ # unmount boot filesystem

rmdir mnt # remove mountpoint

# cleanup loop device
partx -d $LOOP # delete partitions from kernel knowing
losetup -d $LOOP # remove loop device
