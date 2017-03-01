#!/bin/bash

set -e

REMOVE_UP_TO=/home/
LFS_ROOT=$PWD/build/root/
LFS_BUILD=$LFS_ROOT/build/
LFS_BUILD_SOURCES=$LFS_BUILD/sources/
LFS_BUILD_TOOLS=$LFS_BUILD/tools/

function usage() {
  echo "Usage:"
  echo "  ./install.sh <hard drive>"
  exit
}

if [ $# -eq 0 ]; then
  usage
fi

# download everything
#LFS_BUILD_SOURCES=$LFS_BUILD_SOURCES ./download.sh
# extract everything
#LFS_BUILD_SOURCES=$LFS_BUILD_SOURCES ./extract.sh
# build temporary tools
LFS_BUILD_SOURCES=$LFS_BUILD_SOURCES LFS_BUILD_TOOLS=$LFS_BUILD_TOOLS ./build.sh
# install main system
LFS_BUILD_SOURCES=$LFS_BUILD_SOURCES LFS_BUILD_TOOLS=$LFS_BUILD_TOOLS LFS_ROOT=$LFS_ROOT TIME_ZONE="America/New_York" ./buildsystem.sh
# clone it to the image
# TODO ./createdrive.sh $1
