#!/bin/bash
set -euo pipefail

mpiname=${MPINAME:-mpich}

if test "$mpiname" = "mpich"; then
    version=${VERSION:-4.1.2}
    urlbase="https://www.mpich.org/static/downloads/$version"
    tarball="$mpiname-$version.tar.gz"
    license=COPYRIGHT
fi

SOURCE=package/source
if test ! -d "$SOURCE"; then
    if test ! -f "$tarball"; then
        echo downloading "$urlbase"/"$tarball"...
        curl -sO "$urlbase"/"$tarball"
    else
        echo reusing "$tarball"...
    fi
    echo extracting "$tarball" to "$SOURCE"...
    tar xf "$tarball"
    mv "$mpiname-$version" "$SOURCE"
    disable_doc='s/^\(INSTALL_DATA_LOCAL_TARGETS +=\)/#\1/g'
    sed -i.orig "$disable_doc" "$SOURCE"/Makefile.am
else
    echo reusing directory "$SOURCE"...
fi
echo copying license file...
cp "$SOURCE"/"$license" "package/LICENSE"
