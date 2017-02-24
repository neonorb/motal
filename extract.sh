#!/bin/bash

set -e

# extract packages
(cd $LFS_BUILD_SOURCES
  for filename in *.tar*; do
    echo "extracting $filename"
    tar -xf $filename
  done
)
