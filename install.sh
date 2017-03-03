#!/bin/bash

set -e

export REMOVE_UP_TO=/home/
export BUILD=$PWD/build/
export LFS_ROOT=$BUILD/root/
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
./buildtools.sh
# install main system
echo "=========="
echo "As this script requires chrooting to finish building, you must authenticate as root."
echo "If you're in a GUI environment, there should be a GUI authentication window available."
pkexec bash -c "cd $PWD; TIME_ZONE=$TIME_ZONE LFS_ROOT=$LFS_ROOT TOOLS=$TOOLS SOURCES=$SOURCES ./buildsystem.sh"
# clone it to the image
# TODO ./createdrive.sh $1
