#!/bin/bash
set -euo pipefail

mpiname="${MPINAME:-mpich}"
variant="${VARIANT:-}"

SOURCE=${SOURCE:-$PWD/package/source}
WORKDIR=${WORKDIR:-$PWD/package/workdir}
DESTDIR=${DESTDIR:-$PWD/package/install}
PREFIX=${PREFIX:-"/opt/$mpiname"}

if test "$mpiname" = "mpich"; then
    version=$(sed -n 's/MPICH_VERSION=\(.*\)/\1/p' "$SOURCE"/maint/Version)
    options=(
        CC=cc
        CXX=c++
        --prefix="$PREFIX"
        --with-device=ch4:"${variant:-ofi}"
        --with-pm=hydra:gforker
        --with-libfabric=embedded
        --with-ucx=embedded
        --with-hwloc=embedded
        --with-yaksa=embedded
        --disable-cxx
        --disable-static
        --disable-doc
    )
    if test "${version%%.*}" -lt 4; then
        options=("${options[@]/--disable-cxx}")
        export FCFLAGS=-fallow-argument-mismatch
        export FFLAGS=-fallow-argument-mismatch
    fi
    if test "$(uname)" = Darwin; then
        options+=(--disable-opencl --disable-libxml2)
        export MPICH_MPICC_LDFLAGS="-Wl,-rpath,$PREFIX/lib"
        export MPICH_MPICXX_LDFLAGS="-Wl,-rpath,$PREFIX/lib"
        export MPICH_MPIFORT_LDFLAGS="-Wl,-rpath,$PREFIX/lib"
    fi
    disable_doc='s/^\(install-data-local:\s\+\)\$/\1#\$/'
    sed -i.orig "$disable_doc" "$SOURCE"/Makefile.in
fi


if test "$(uname)" = Darwin; then
    export MACOSX_DEPLOYMENT_TARGET="11.0"
    if test "$(uname -m)" = x86_64; then
        export MACOSX_DEPLOYMENT_TARGET="10.9"
        export ac_cv_func_aligned_alloc="no" # macOS>=10.15
    fi
    if test "$variant" = ucx; then
        echo "ERROR: UCX is not supported on macOS"; exit 1;
    fi
fi

case $(uname) in
    Linux)  njobs=$(nproc);;
    Darwin) njobs=$(sysctl -n hw.physicalcpu);;
esac

mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo running configure
"$SOURCE"/configure "${options[@]}" || cat config.log

echo running make with "${njobs:-1}" jobs
make -j "${njobs:-1}" install DESTDIR="$DESTDIR"

fixup-mpich() {

cd "${DESTDIR}${PREFIX}"
rm -f  include/*cxx.h
rm -f  include/*.mod
rm -f  include/*f.h
rm -fr include/rdma
rm -f  bin/mpif77
rm -f  bin/mpif90
rm -f  bin/mpifort
rm -f  bin/parkill
rm -f  lib/libmpl.*
rm -f  lib/libopa.*
rm -f  lib/lib*mpi.a
rm -f  lib/lib*mpi.la
rm -f  lib/lib*mpich*.*
rm -f  lib/lib*mpicxx.*
rm -f  lib/lib*mpifort.*
rm -fr lib/pkgconfig
rm -fr share

cd "${DESTDIR}${PREFIX}"
rm -f  bin/io_demo
rm -f  bin/ucx_read_profile
rm -f  lib/libuc[mpst]*.la
rm -f  lib/ucx/libuct_*.la
rm -fr lib/cmake

headers=(mpi.h)
scripts=(mpicc mpicxx)
executables=(mpichversion mpivars)

cd "${DESTDIR}${PREFIX}/include"
for header in "${headers[@]}"; do
    sed -i.orig 's:^#include "mpicxx.h"::g' "$header"
    rm "$header".orig
done

cd "${DESTDIR}${PREFIX}/bin"
for script in "${scripts[@]}"; do
    # shellcheck disable=SC2016
    topdir='$(CDPATH= cd -- "$(dirname -- "$0")/.." \&\& pwd -P)'
    sed -i.orig s:^prefix=.*:prefix="$topdir": "$script"
    sed -i.orig s:"$PREFIX":\"\$\{prefix\}\":g "$script"
    sed -i.orig s:-Wl,-commons,use_dylibs::g "$script"
    sed -i.orig s:/usr/bin/bash:/bin/bash:g "$script"
    sed -i.orig s:-lmpicxx::g "$script"
    rm "$script".orig
done

if test "$(uname)" = Linux; then
    libmpi="libmpi.so.12"
    cd "${DESTDIR}${PREFIX}/bin"
    for exe in "${executables[@]}"; do
        patchelf --set-rpath "\$ORIGIN/../lib" "$exe"
    done
    cd "${DESTDIR}${PREFIX}/lib"
    if test -f "$libmpi".*.*; then
        mv "$(readlink "$libmpi")" "$libmpi"
        ln -sf "$libmpi" "${libmpi%.*}"
    fi
    if test -f libucp.so; then
        patchelf --set-rpath "\$ORIGIN" "$libmpi"
        for lib in libuc[mpst]*.so.?; do
            if test -f "$lib".*; then
                mv "$(readlink "$lib")" "$lib"
                ln -sf "$lib" "${lib%.*}"
            fi
            patchelf --set-rpath "\$ORIGIN" "$lib"
            for exe in "${executables[@]}"; do
                patchelf --remove-needed "$lib" "../bin/$exe"
            done
        done
        patchelf --add-rpath "\$ORIGIN/ucx" libuct.so.?
        for lib in ucx/libuct_*.so.?; do
            if test -f "$lib".*; then
                mv "$(dirname "$lib")/$(readlink "$lib")" "$lib"
                ln -srf "$lib" "${lib%.*}"
            fi
            patchelf --set-rpath "\$ORIGIN/.." "$lib"
        done
    fi
fi

if test "$(uname)" = Darwin; then
    libdir="$PREFIX/lib"
    libmpi="libmpi.12.dylib"
    libpmpi="libpmpi.12.dylib"
    cd "${DESTDIR}${PREFIX}/bin"
    for exe in "${executables[@]}"; do
        install_name_tool -change "$libdir/$libmpi" "@rpath/$libmpi" "$exe"
        install_name_tool -change "$libdir/$libpmpi" "@rpath/$libpmpi" "$exe"
        install_name_tool -add_rpath "@executable_path/../lib/" "$exe"
    done
    cd "${DESTDIR}${PREFIX}/lib"
    for lib in "$libmpi" "$libpmpi"; do
        install_name_tool -id "@rpath/$lib" "$lib"
        install_name_tool -add_rpath "@loader_path/" "$lib"
    done
    install_name_tool -change "$libdir/$libpmpi" "@rpath/$libpmpi" "$libmpi"
fi

} # fixup-mpich()

echo fixing install tree
fixup-"$mpiname"
