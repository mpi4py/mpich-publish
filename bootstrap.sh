#!/bin/bash
set -euo pipefail

mpiname=${MPINAME:-mpich}
case "$mpiname" in
    mpich)   version=4.3.0 ;;
    openmpi) version=5.0.7 ;;
esac
version=${VERSION:-$version}

PROJECT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PACKAGE=$PROJECT/package
SOURCE=$PACKAGE/source

if test "$mpiname" = "mpich"; then
    urlbase="https://www.mpich.org/static/downloads/$version"
    tarball="$mpiname-$version.tar.gz"
    license=COPYRIGHT
fi

if test "$mpiname" = "openmpi"; then
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
    patch="$PROJECT/patches/$mpiname-$version"
    if test -f "$patch"; then
        patch -p1 -i "$patch" -d "$SOURCE"
    fi
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
cp "$SOURCE"/"$license" "$PACKAGE/LICENSE"
