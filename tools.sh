#!/bin/bash

YELLOW='\033[1;33m'
NC='\033[0m'

function prepare() {
    if [ -z "${2+x}" ]; then name="$1"; else name="$2"; fi
    echo -e "$YELLOW========== INSTALLING $name ============$NC"
    rm -rf $1*/ || true
    tar -xf $1*.tar.*
    cd $1*/
}
