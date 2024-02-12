#!/bin/bash
set -euo pipefail

mpiname=${MPINAME:-mpich}
version=${VERSION:-4.1.2}

if test "$mpiname" = "mpich"; then
    urlbase="https://www.mpich.org/static/downloads/$version"
    tarball="$mpiname-$version.tar.gz"
    license=COPYRIGHT
fi

if test ! -d package/source; then
    if test ! -f "$tarball"; then
        echo downloading "$urlbase"/"$tarball"...
        curl -sO "$urlbase"/"$tarball"
    else
        echo reusing "$tarball"...
    fi
    echo extracting "$tarball"...
    tar xf "$tarball"
    mv "$mpiname-$version" "package/source"
else
    echo reusing "package/source"...
fi
echo copying license file...
cp "package/source/$license" "package/LICENSE"
