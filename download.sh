#!/bin/bash

set -e

# create download directory
mkdir -p $SOURCES
chmod a+wt $SOURCES

# download packages
wget --input-file=package-list.txt --continue --directory-prefix=$SOURCES || (echo "download failed"; exit 1)

# check md5 sums
echo "verifying md5 sums"
MD5SUMS=$PWD/md5sums.txt
pushd $SOURCES
md5sum -c $MD5SUMS
popd
