#!/bin/bash

set -e

# create download directory
mkdir -p $LFS_BUILD_SOURCES
chmod a+wt $LFS_BUILD_SOURCES

# download packages
wget --input-file=package-list.txt --continue --directory-prefix=$LFS_BUILD_SOURCES

# check md5 sums
echo "verifying md5 sums"
MD5SUMS=$PWD/md5sums.txt
pushd $LFS_BUILD_SOURCES
md5sum -c $MD5SUMS
popd
