#!/bin/bash
set -euo pipefail

mpiname="${MPINAME:-mpich}"

PROJECT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PACKAGE=$PROJECT/package

SOURCE=${SOURCE:-$PACKAGE/source}
WORKDIR=${WORKDIR:-$PACKAGE/workdir}
DESTDIR=${DESTDIR:-$PACKAGE/install}
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
        --disable-doc
        --disable-static
        --disable-opencl
        --disable-libxml2
        --disable-dependency-tracking
    )
    if test "${version%%.*}" -lt 4; then
        options=("${options[@]/--disable-cxx}")
        export FCFLAGS=-fallow-argument-mismatch
        export FFLAGS=-fallow-argument-mismatch
    fi
    if test "$(uname)" = Darwin; then
        export MPICH_MPICC_LDFLAGS="-Wl,-rpath,$PREFIX/lib"
        export MPICH_MPICXX_LDFLAGS="-Wl,-rpath,$PREFIX/lib"
        export MPICH_MPIFORT_LDFLAGS="-Wl,-rpath,$PREFIX/lib"
    fi
    disable_doc='s/^\(install-data-local:\s\+\)\$/\1#\$/'
    sed -i.orig "$disable_doc" "$SOURCE"/Makefile.in
fi

if test "$mpiname" = "openmpi"; then
    options=(
        CC=cc
        CXX=c++
        --prefix="$PREFIX"
        --disable-dlopen
        --disable-oshmem
        --without-ofi
        --without-ucx
        --without-psm2
        --without-cuda
        --without-rocm
        --with-pmix=internal
        --with-prrte=internal
        --with-libevent=internal
        --with-hwloc=internal
        --disable-static
        --disable-opencl
        --disable-libxml2
        --disable-libompitrace
        --enable-mpi-fortran=mpifh
        --disable-dependency-tracking
    )
fi

if test "$(uname)" = Darwin; then
    export MACOSX_DEPLOYMENT_TARGET="11.0"
    if test "$(uname -m)" = x86_64; then
        export MACOSX_DEPLOYMENT_TARGET="10.9"
        export ac_cv_func_aligned_alloc="no" # macOS>=10.15
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
scripts=(mpicc mpic++ mpicxx)
executables=(mpichversion mpivars)

cd "${DESTDIR}${PREFIX}/include"
for header in "${headers[@]}"; do
    sed -i.orig 's:^#include "mpicxx.h"::g' "$header"
    rm "$header".orig
done

cd "${DESTDIR}${PREFIX}/bin"
for script in "${scripts[@]}"; do
    test ! -L "$script" || continue
    # shellcheck disable=SC2016
    topdir='$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE:-$0}")/.." \&\& pwd)'
    sed -i.orig s@^prefix=.*@prefix="$topdir"@ "$script"
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

fixup-openmpi() {

cd "${DESTDIR}${PREFIX}"
rm -fr include/ev*
rm -fr include/hwloc*
rm -fr include/pmix*
rm -fr include/prte*
rm -f  include/mpif*.h
rm -f  include/*/*/*mpifh.h
rm -f  bin/ev*
rm -f  bin/hwloc*
rm -f  bin/lstopo*

#rm -f  bin/pmix_info
rm -f  bin/palloc
rm -f  bin/pattrs
rm -f  bin/pctrl
rm -f  bin/pevent
rm -f  bin/plookup
rm -f  bin/pps
rm -f  bin/pquery

#rm -f  bin/prte_info
#rm -f  bin/prte
#rm -f  bin/prted
#rm -f  bin/prterun
rm -f  bin/prun
rm -f  bin/psched
rm -f  bin/pterm

rm -fr sbin
rm -f  bin/pmixcc
rm -f  bin/mpif77
rm -f  bin/mpif90
rm -f  bin/mpifort
rm -f  bin/oshrun
rm -f  lib/*.mod
rm -f  lib/lib*.a
rm -f  lib/lib*.la
rm -f  lib/libmpi_mpifh*.*
rm -f  lib/libmpi_usempi*.*
rm -f  lib/libompitrace.*
rm -fr lib/openmpi
rm -fr lib/pkgconfig
rm -fr share/bash-completion
rm -fr share/doc
rm -fr share/man
rm -fr share/hwloc
rm -fr share/prte/rst
rm -f  share/openmpi/mpif77-wrapper-data.txt
rm -f  share/openmpi/mpif90-wrapper-data.txt
rm -f  share/openmpi/mpifort-wrapper-data.txt
rm -f  share/pmix/pmixcc-wrapper-data.txt
rm -f  share/*/*.supp
rm -f  share/*/*/example.conf

cd "${DESTDIR}${PREFIX}/bin"
unset executables
for exe in 'mpirun' 'ompi*' 'pmix*' 'prte*' 'opal*' 'orte*'; do
    while IFS= read -r filename
    do executables+=("$(basename "$filename")")
    done < <(find . -name "$exe" -type f)
done

cd "${DESTDIR}${PREFIX}/lib"
unset libraries
for lib in 'lib*.so.*' 'lib*.*.dylib'; do
    while IFS= read -r filename
    do libraries+=("$(basename "$filename")")
    done < <(find . -name "$lib" -type f)
done

if test "$(uname)" = Linux; then
    cd "${DESTDIR}${PREFIX}/bin"
    for exe in "${executables[@]}"; do
        patchelf --set-rpath "\$ORIGIN/../lib" "$exe"
    done
    cd "${DESTDIR}${PREFIX}/lib"
    for lib in lib*.so; do
        patchelf --set-rpath "\$ORIGIN" "$lib"
        soname=$(patchelf --print-soname "$lib")
        if test -L "$soname"; then
            mv "$(readlink "$soname")" "$soname"
            ln -sf "$soname" "$lib"
        fi
    done
fi

if test "$(uname)" = Darwin; then
    cd "${DESTDIR}${PREFIX}/bin"
    for exe in "${executables[@]}"; do
        install_name_tool -add_rpath "@executable_path/../lib/" "$exe"
        unset dependencies
        while IFS= read -r dep
        do dependencies+=("$dep")
        done < <(otool -L "$exe" | awk '(NR>1) {print $1}')
        for dep in "${dependencies[@]}"; do
            if test "$(dirname "$dep")" = "$(dirname "$PREFIX/lib/.")"; then
                installname="@rpath/$(basename "$dep")"
                install_name_tool -change "$dep" "$installname" "$exe"
            fi
        done
    done
    cd "${DESTDIR}${PREFIX}/lib"
    for lib in lib*.*.dylib; do
        install_name_tool -id "@rpath/$lib" "$lib"
        install_name_tool -add_rpath "@loader_path/" "$lib"
        while IFS= read -r dep
        do dependencies+=("$dep")
        done < <(otool -L "$lib" | awk '(NR>1) {print $1}')
        for dep in "${dependencies[@]}"; do
            if test "$(dirname "$dep")" = "$(dirname "$PREFIX/lib/.")"; then
                installname="@rpath/$(basename "$dep")"
                install_name_tool -change "$dep" "$installname" "$lib"
            fi
        done
    done
fi

cd "${DESTDIR}${PREFIX}/share/openmpi"
for cmd in mpicc mpic++ mpicxx mpiCC ortecc; do
    wrapper_data="$cmd-wrapper-data.txt"
    test -e "$wrapper_data" || continue
    test ! -L "$wrapper_data" || continue
    flags="\(linker_flags=\) *"
    rpath="-Wl,-rpath,@{libdir}"
    sed -i.orig "s:^$flags$:\1$rpath:" "$wrapper_data"
    flags="\(linker_flags=-L\${libdir}\) *"
    rpath="-Wl,-rpath,\${libdir}"
    sed -i.orig "s:^$flags$:\1 $rpath:" "$wrapper_data"
    rm "$wrapper_data".orig
done

cd "${DESTDIR}${PREFIX}/bin"
wrapper_cmd=opal_wrapper
wrapper_src="$PROJECT/cibw-ompi-wrapper.c"
wrapper_bin="$WORKDIR/cibw-ompi-wrapper.exe"
cc -DWRAPPER="$wrapper_cmd" "$wrapper_src" -o "$wrapper_bin"
executables=(mpicc mpic++ mpicxx mpiCC ortecc)
for exe in "${executables[@]}"; do
    test -e "$exe" || continue
    test -L "$exe" || continue
    install "$wrapper_bin" "$exe"
done

cd "${DESTDIR}${PREFIX}/bin"
if test -f prterun; then
    executor=mpirun
    wrapper=ompirun_wrapper
else
    executor=orterun
    wrapper=orterun_wrapper
fi
mv "$executor" "$wrapper"
ln -s "$wrapper" "$executor"
wrapper_src="$PROJECT/cibw-ompi-wrapper.c"
wrapper_bin="$WORKDIR/cibw-ompi-wrapper.exe"
cc -DWRAPPER="$wrapper" "$wrapper_src" -o "$wrapper_bin"
executables=(mpirun mpiexec orterun)
for exe in "${executables[@]}"; do
    test -e "$exe" || continue
    test -L "$exe" || continue
    install "$wrapper_bin" "$exe"
done

} # fixup-openmpi()

echo fixing install tree
fixup-"$mpiname"
