#!/bin/bash
set -euo pipefail

mpiname=${MPINAME:-mpich}

if test "$mpiname" = "mpich"; then
    version=${VERSION:-4.2.0}
    urlbase="https://www.mpich.org/static/downloads/$version"
    tarball="$mpiname-$version.tar.gz"
    license=COPYRIGHT
fi

SOURCE=package/source
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
else
    echo reusing directory "$SOURCE"...
fi
echo copying license file...
cp "$SOURCE"/"$license" "package/LICENSE"
