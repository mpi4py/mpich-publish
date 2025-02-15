#!/bin/bash
set -euo pipefail

mpiname=${MPINAME:-mpich}
case "$mpiname" in
    mpich)   version=4.3.0 ;;
    openmpi) version=5.0.7 ;;
esac
version=${VERSION:-$version}

ucxversion=1.18.0
ofiversion=1.22.0
ucxversion=${UCXVERSION:-$ucxversion}
ofiversion=${OFIVERSION:-$ofiversion}

PROJECT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PACKAGE=$PROJECT/package
SOURCE=$PACKAGE/source

if test "$mpiname" = "mpich"; then
    urlbase="https://www.mpich.org/static/downloads/$version"
    tarball="$mpiname-$version.tar.gz"
fi
if test "$mpiname" = "openmpi"; then
    urlbase=https://download.open-mpi.org/release/open-mpi/v${version%.*}
    tarball="$mpiname-$version.tar.gz"
fi
if test ! -d "$SOURCE"; then
    if test ! -f "$tarball"; then
        echo downloading "$urlbase"/"$tarball"...
        curl -fsSLO "$urlbase"/"$tarball"
    else
        echo reusing "$tarball"...
    fi
    echo extracting "$tarball"...
    tar xf "$tarball"
    mv "$mpiname-$version" "$SOURCE"
    patch="$PROJECT/patches/$mpiname-$version"
    if test -f "$patch"; then
        patch -p1 -i "$patch" -d "$SOURCE"
    fi
    if test "$mpiname" = "mpich"; then
        if test "${version}" \< "4.2.0"; then
            disable_doc='s/^\(install-data-local:\s\+\)\$/\1#\$/'
            sed -i.orig "$disable_doc" "$SOURCE"/Makefile.in
        fi
    fi
    if test "$mpiname" = "openmpi"; then
        for deptarball in "$SOURCE"/3rd-party/*.tar.*; do
            test -f "$deptarball" || continue
            echo extracting "$(basename "$deptarball")"
            tar xf "$deptarball" -C "$(dirname "$deptarball")"
        done
        makefiles=(
            "$SOURCE"/3rd-party/openpmix/src/util/keyval/Makefile.in
            "$SOURCE"/3rd-party/prrte/src/mca/rmaps/rank_file/Makefile.in
            "$SOURCE"/3rd-party/prrte/src/util/hostfile/Makefile.in
        )
        for makefile in "${makefiles[@]}"; do
            test -f "$makefile" || continue
            echo "PMIX_CFLAGS_BEFORE_PICKY = @CFLAGS@" >> "$makefile"
            echo "PRTE_CFLAGS_BEFORE_PICKY = @CFLAGS@" >> "$makefile"
        done
    fi
    if test "$mpiname" = "openmpi" && test "${version}" \< "5.0.5"; then
        if test "$(uname)" = "Darwin" && test -d "$SOURCE"/3rd-party; then
            cd "$SOURCE"/3rd-party/libevent-*
            echo running autogen.sh on "$(basename "$(pwd)")"
            ./autogen.sh
            cd "$PROJECT"
        fi
    fi
    echo writing package metadata ...
    echo "Name: $mpiname" > "$PACKAGE/METADATA"
    echo "Version: $version" >> "$PACKAGE/METADATA"
else
    echo reusing directory "$SOURCE"...
    check() { test "$(awk "/$1/"'{print $2}' "$PACKAGE/METADATA")" = "$2"; }
    check Name    "$mpiname" || (echo not "$mpiname-$version"!!! && exit 1)
    check Version "$version" || (echo not "$mpiname-$version"!!! && exit 1)
fi

if test "$(uname)" = "Linux"; then
    case "$mpiname" in
        mpich)   MODSOURCE="$SOURCE"/modules   ;;
        openmpi) MODSOURCE="$SOURCE"/3rd-party ;;
    esac
    ofigithub="https://github.com/ofiwg/libfabric"
    ofiurlbase="$ofigithub/releases/download/v$ofiversion"
    ofitarball="libfabric-$ofiversion.tar.bz2"
    ofidestdir="$MODSOURCE"/"${ofitarball%%.tar.*}"
    if test ! -d "$ofidestdir"; then
        if test ! -f "$ofitarball"; then
            echo downloading "$ofiurlbase"/"$ofitarball"...
            curl -fsSLO "$ofiurlbase"/"$ofitarball"
        else
            echo reusing "$ofitarball"...
        fi
        echo extracting "$ofitarball"...
        tar xf "$ofitarball"
        mkdir -p "$(dirname "$ofidestdir")"
        mv "$(basename "$ofidestdir")" "$ofidestdir"
    else
        echo reusing directory "$ofidestdir"...
    fi
    ucxgithub="https://github.com/openucx/ucx"
    ucxurlbase="$ucxgithub/releases/download/v$ucxversion"
    ucxtarball="ucx-$ucxversion.tar.gz"
    ucxdestdir="$MODSOURCE"/"${ucxtarball%%.tar.*}"
    if test ! -d "$ucxdestdir"; then
        if test ! -f "$ucxtarball"; then
            echo downloading "$ucxurlbase"/"$ucxtarball"...
            curl -fsSLO "$ucxurlbase"/"$ucxtarball"
        else
            echo reusing "$ucxtarball"...
        fi
        echo extracting "$ucxtarball"...
        tar xf "$ucxtarball"
        mkdir -p "$(dirname "$ucxdestdir")"
        mv "$(basename "$ucxdestdir")" "$ucxdestdir"
        if test "${ucxversion}" \< "1.17.1"; then
            cmd='s/\(#include <limits.h>\)/\1\n#include <math.h>/'
            sed -i.orig "$cmd" "$ucxdestdir/src/ucs/time/time.h"
        fi
    else
        echo reusing directory "$ucxdestdir"...
    fi
fi

if test "$mpiname" = "mpich"; then
    mpidate=$(sed -nE "s/MPICH_RELEASE_DATE=\"(.*)\"/\1/p" "$SOURCE/configure")
fi
if test "$mpiname" = "openmpi"; then
    mpidate=$(sed -nE "s/date=\"(.*)\"/\1/p" "$SOURCE/VERSION")
fi
if test -n "${mpidate+x}"; then
    case "$(uname)" in
        Linux)
            timestamp=$(date -d "$mpidate" "+%s")
            ;;
        Darwin)
            datefmt="%b %d, %Y %T%z"
            if test "$mpiname" = "mpich"; then
                mpidate=$(awk '{$3=$3",";print $2,$3,$NF}' <<< "$mpidate")
            fi
            timestamp=$(date -j -f "$datefmt" "$mpidate 12:00:00+0000" "+%s")
            ;;
    esac
    echo writing source-date-epoch ...
    echo "$timestamp" > "$SOURCE/source-date-epoch"
fi

if test "$mpiname" = "mpich"; then
    mpilicense="$SOURCE"/COPYRIGHT
    otherlicenses=(
        "$SOURCE"/modules/hwloc/COPYING
        "$SOURCE"/modules/json-c/COPYING
        "$SOURCE"/modules/yaksa/COPYRIGHT
    )
fi
if test "$mpiname" = "openmpi"; then
    mpilicense="$SOURCE"/LICENSE
    otherlicenses=(
        "$SOURCE"/3rd-party/hwloc-*/COPYING
        "$SOURCE"/3rd-party/libevent-*/LICENSE
        "$SOURCE"/3rd-party/openpmix/LICENSE
        "$SOURCE"/3rd-party/prrte/LICENSE
        "$SOURCE"/3rd-party/treematch/COPYING
        "$SOURCE"/opal/mca/event/libevent2022/libevent/LICENSE
        "$SOURCE"/opal/mca/pmix/pmix3x/pmix/LICENSE
        "$SOURCE"/ompi/mca/topo/treematch/treematch/COPYING
    )
fi
echo copying MPI license file...
cp "$mpilicense" "$PACKAGE/LICENSE"
if test -n "${ofidestdir+x}"; then
    echo copying OFI license file...
    cp "$ofidestdir/COPYING" "$PACKAGE/LICENSE.ofi"
fi
if test -n "${ucxdestdir+x}"; then
    echo copying UCX license file...
    cp "$ucxdestdir/LICENSE" "$PACKAGE/LICENSE.ucx"
fi
for license in "${otherlicenses[@]}"; do
    test -f "$license" || continue
    module=$(basename "$(dirname "$license")")
    module="${module%%-[0-9]*}"
    echo copying "$module" license file...
    cp "$license" "$PACKAGE/LICENSE.$module"
done
