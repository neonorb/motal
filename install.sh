#!/bin/bash

set -e

export REMOVE_UP_TO=/home/
export BUILD=$PWD/build/
export LFS_ROOT=$BUILD/root/
export DISK_ROOT=$BUILD/disk_root
export SOURCES=$BUILD/sources/
export TOOLS=$BUILD/tools/
export TIME_ZONE="America/New_York"

function usage() {
  echo "Usage:"
  echo "  ./install.sh <hard drive>"
  exit
}

if [ $# -eq 0 ]; then
  usage
fi

# download everything
if [ -z "$SKIP_DOWNLOAD" ]; then ./download.sh; else echo "skipping download"; fi
# build temporary tools
if [ -z "$SKIP_TOOLS" ]; then ./buildtools.sh; else echo "skipping tools"; fi
# install main system
echo "=========="
echo "As this script requires chrooting to finish building, you must authenticate as root."
echo "If you're in a GUI environment, there should be a GUI authentication window available."
pkexec bash -c "cd $PWD; TIME_ZONE=$TIME_ZONE LFS_ROOT=$LFS_ROOT TOOLS=$TOOLS SOURCES=$SOURCES ./buildsystem.sh"
# clone it to the image
echo "=========="
echo "Now we need to copy the new root onto the image you specified."
echo "To do this, we again need root permissions in order to mount stuffs."
pkexec bash -c "cd $PWD; LFS_ROOT=$LFS_ROOT DISK_ROOT=$DISK_ROOT ./createdrive.sh $1"
