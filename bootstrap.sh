#!/bin/bash
set -euo pipefail

mpiname=${MPINAME:-mpich}

PROJECT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PACKAGE=$PROJECT/package
SOURCE=$PACKAGE/source

if test "$mpiname" = "mpich"; then
    version=${VERSION:-4.2.2}
    urlbase="https://www.mpich.org/static/downloads/$version"
    tarball="$mpiname-$version.tar.gz"
    license=COPYRIGHT
fi

if test "$mpiname" = "openmpi"; then
    version=${VERSION:-5.0.3}
    urlbase=https://download.open-mpi.org/release/open-mpi/v${version%.*}
    tarball="$mpiname-$version.tar.gz"
    license=LICENSE
fi

if test ! -d "$SOURCE"; then
    if test ! -f "$tarball"; then
        echo downloading "$urlbase"/"$tarball"...
        curl -fsO "$urlbase"/"$tarball"
    else
        echo reusing "$tarball"...
    fi
    echo extracting "$tarball" to "$SOURCE"...
    tar xf "$tarball"
    mv "$mpiname-$version" "$SOURCE"
    if test "$mpiname-$(uname)" = "openmpi-Darwin"; then
        if test -d "$SOURCE"/3rd-party; then
            cd "$SOURCE"/3rd-party
            tar xf libevent-*.tar.gz && cd libevent-*
            echo running autogen.sh on "$(basename "$(pwd)")"
            ./autogen.sh
            cd "$PROJECT"
        fi
    fi
else
    echo reusing directory "$SOURCE"...
fi
echo copying license file...
cp "$SOURCE"/"$license" "package/LICENSE"
