#!/bin/bash
set -euo pipefail

PROJECT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PACKAGE=$PROJECT/package

SOURCE=${SOURCE:-$PACKAGE/source}
WORKDIR=${WORKDIR:-$PACKAGE/workdir}
DESTDIR=${DESTDIR:-$PACKAGE/install}

test -f "$PACKAGE"/METADATA
mpiname=$(awk '/Name/{print $2}' "$PACKAGE"/METADATA)
version=$(awk '/Version/{print $2}' "$PACKAGE"/METADATA)

case $(uname) in
    Linux)  njobs=$(nproc);;
    Darwin) njobs=$(sysctl -n hw.physicalcpu);;
esac

if test "$(uname)" = Darwin; then
    if test -z "${MACOSX_DEPLOYMENT_TARGET+x}"; then
        case $(uname -m) in
            arm64)  export MACOSX_DEPLOYMENT_TARGET=11.0  ;;
            x86_64) export MACOSX_DEPLOYMENT_TARGET=10.15 ;;
        esac
    fi
    if test -z "${ZERO_AR_DATE+x}"; then
        export ZERO_AR_DATE=1
    fi
fi

PREFIX=${PREFIX:-"/opt/$mpiname"}

build_cflags+=("-ffile-prefix-map=$SOURCE=/$mpiname-$version")
build_cflags+=("-ffile-prefix-map=$WORKDIR=/$mpiname-$version")
build_ldflags=()
if test "$(uname)" = Linux; then
    build_cflags+=("-Wl,--build-id=none")
    build_ldflags+=("-Wl,--as-needed")
fi
if test "$(uname)" = Darwin; then
    build_ldflags+=("-Wl,-dead_strip_dylibs")
fi

case "$mpiname" in
    mpich)   MODSOURCE="$SOURCE"/modules   ;;
    openmpi) MODSOURCE="$SOURCE"/3rd-party ;;
esac

if test -d "$MODSOURCE"/ucx-*; then
    ucxdir=$(basename "$(ls -d "$MODSOURCE"/ucx-*)")
    UCXSOURCE="$MODSOURCE"/"$ucxdir"
    UCXWORKDIR="$WORKDIR"/"$(basename "$MODSOURCE")"/"$ucxdir"
    mkdir -p "$UCXWORKDIR" && cd "$UCXWORKDIR"
    if test ! -e "$UCXWORKDIR"/config.log; then
        echo running configure for UCX
        ucxconfigure="$UCXSOURCE"/contrib/configure-release-mt
        ucxoptions=(--prefix="$PREFIX" --disable-static)
        "$ucxconfigure" "${ucxoptions[@]}" \
                        CFLAGS="${build_cflags[*]}" \
                        LDFLAGS="${build_ldflags[*]}"
    fi
    echo running make with "${njobs:-1}" jobs for UCX
    make -j "${njobs:-1}" install-strip DESTDIR="$DESTDIR"
    for lib in "${DESTDIR}${PREFIX}"/lib/libuc[mpst].la; do
        sed -i "/dependency_libs\s*=/s|\($PREFIX\)|$DESTDIR\1|g" "$lib"
    done
    for pkg in "${DESTDIR}${PREFIX}"/lib/pkgconfig/ucx*.pc; do
        sed -i "/prefix\s*=/s|\($PREFIX\)|$DESTDIR\1|g" "$pkg"
    done
fi

if test -d "$MODSOURCE"/libfabric-*; then
    ofidir=$(basename "$(ls -d "$MODSOURCE"/libfabric-*)")
    OFISOURCE="$MODSOURCE"/"$ofidir"
    OFIWORKDIR="$WORKDIR"/"$(basename "$MODSOURCE")"/"$ofidir"
    mkdir -p "$OFIWORKDIR" && cd "$OFIWORKDIR"
    if test ! -e "$OFIWORKDIR"/config.log; then
        echo running configure for OFI
        oficonfigure="$OFISOURCE"/configure
        ofioptions=(--prefix="$PREFIX" --disable-static)
        "$oficonfigure" "${ofioptions[@]}" \
                        CFLAGS="${build_cflags[*]}" \
                        LDFLAGS="${build_ldflags[*]}"
    fi
    echo running make with "${njobs:-1}" jobs for OFI
    make -j "${njobs:-1}" install-strip DESTDIR="$DESTDIR"
    for lib in "${DESTDIR}${PREFIX}"/lib/libfabric*.la; do
        sed -i "/dependency_libs\s*=/s|\($PREFIX\)|$DESTDIR\1|g" "$lib"
    done
    for pkg in "${DESTDIR}${PREFIX}"/lib/pkgconfig/libfabric*.pc; do
        sed -i "/prefix\s*=/s|\($PREFIX\)|$DESTDIR\1|g" "$pkg"
    done
fi

if test "$mpiname" = "mpich"; then
    case $(uname) in
        Linux)  netmod=ucx,ofi ;;
        Darwin) netmod=ofi ;;
    esac
    options=(
        CC=cc
        CXX=c++
        --prefix="$PREFIX"
        --with-device="ch4:$netmod"
        --with-pm=hydra:gforker
        --with-ucx=embedded
        --with-libfabric=embedded
        --with-hwloc=embedded
        --with-yaksa=embedded
        --disable-cxx
        --disable-doc
        --disable-debug
        --disable-dlopen
        --disable-static
        --disable-pci
        --disable-opencl
        --disable-libxml2
        --disable-dependency-tracking
    )
    if test -d "$SOURCE"/modules/ucx-*; then
        options=("${options[@]/--with-ucx=embedded/--with-ucx=$DESTDIR$PREFIX}")
    fi
    if test -d "$SOURCE"/modules/libfabric-*; then
        options=("${options[@]/--with-libfabric=embedded/--with-libfabric=$DESTDIR$PREFIX}")
    fi
    generated_files+=(src/include/mpichinfo.h)
    generated_files+=(src/pm/hydra/hydra_config.h)
    generated_files+=(src/pm/hydra/include/hydra_config.h)
    generated_files+=(modules/ucx/config.h)
    generated_files+=(modules/ucx/src/tools/info/build_config.h)
    export BASH_SHELL="/bin/bash"
    export MPICHLIB_CFLAGS="${build_cflags[*]}"
    export MPICHLIB_LDFLAGS="${build_ldflags[*]}"
    if test "${version%%.*}" -lt 4; then
        options=("${options[@]/--disable-cxx}")
        options=("${options[@]}" --disable-numa)
        export CFLAGS=$MPICHLIB_CFLAGS
        export LDFLAGS=$MPICHLIB_LDFLAGS
        export FFLAGS=-fallow-argument-mismatch
        export FCFLAGS=-fallow-argument-mismatch
        export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:$DESTDIR$PREFIX/lib"
    fi
    if test "$(uname)" = Darwin; then
        export MPICH_MPICC_LDFLAGS="-Wl,-rpath,$PREFIX/lib"
        export MPICH_MPICXX_LDFLAGS="-Wl,-rpath,$PREFIX/lib"
        export MPICH_MPIFORT_LDFLAGS="-Wl,-rpath,$PREFIX/lib"
    fi
fi

if test "$mpiname" = "openmpi"; then
    options=(
        CC=cc
        CXX=c++
        --prefix="$PREFIX"
        --without-ucx
        --without-ofi
        --without-cuda
        --without-rocm
        --with-hwloc=internal
        --with-libevent=internal
        --with-pmix=internal
        --with-prrte=internal
        --enable-ipv6
        --disable-doc
        --disable-debug
        --disable-dlopen
        --disable-static
        --disable-oshmem
        --disable-libompitrace
        --disable-pci
        --disable-opencl
        --disable-libxml2
        --enable-mpi-fortran=mpifh
        --disable-dependency-tracking
    )
    if test -d "$SOURCE"/3rd-party/ucx-*; then
        options=("${options[@]/--without-ucx/--with-ucx=$DESTDIR$PREFIX}")
    fi
    if test -d "$SOURCE"/3rd-party/libfabric-*; then
        options=("${options[@]/--without-ofi/--with-ofi=$DESTDIR$PREFIX}")
    fi
    if test "${version%%.*}" -lt 5; then
        options=("${options[@]/--disable-pci/--disable-hwloc-pci}")
    fi
    generated_files+=(ompi/tools/ompi_info/Makefile)
    generated_files+=(oshmem/tools/oshmem_info/Makefile)
    generated_files+=(3rd-party/openpmix/src/tools/*/Makefile)
    generated_files+=(3rd-party/prrte/src/tools/*/Makefile)
    generated_files+=(opal/include/opal_config.h)
    generated_files+=(opal/include/opal/version.h)
    generated_files+=(3rd-party/openpmix/src/include/pmix_config.h)
    generated_files+=(3rd-party/prrte/src/include/prte_config.h)
    generated_files+=(ompi/tools/mpisync/Makefile)
    generated_files+=(orte/tools/orte-info/Makefile)
    generated_files+=(opal/mca/pmix/pmix3x/pmix/src/tools/pmix_info/Makefile)
    generated_files+=(opal/mca/pmix/pmix3x/pmix/src/include/pmix_config.h)
    export CFLAGS="${build_cflags[*]}"
    export LDFLAGS="${build_ldflags[*]}"
    export USER=user HOSTNAME=localhost
fi

mkdir -p "$WORKDIR" && cd "$WORKDIR"

if test ! -e "$WORKDIR"/config.log; then
    echo running configure for MPI
    "$SOURCE"/configure "${options[@]}" || cat config.log
    # shellcheck disable=SC2206
    generated_files=(${generated_files[@]:-})
    for filename in "${generated_files[@]}"; do
        test -n "$filename" || continue
        test -f "$filename" || continue
        source="s|$SOURCE|/$mpiname-$version|g"
        workdir="s|$WORKDIR|/$mpiname-$version|g"
        destdir="s|$DESTDIR||g"
        echo removing source/build/install paths in "$filename"
        if test "$(basename "$filename")" = "Makefile"; then
            sed -i.orig "/-D.*_BUILD_CFLAGS=/$source" "$filename"
            sed -i.orig "/-D.*_BUILD_CFLAGS=/$workdir" "$filename"
            sed -i.orig "/-D.*_BUILD_CFLAGS=/$destdir" "$filename"
            sed -i.orig "/-D.*_BUILD_CPPFLAGS=/$source" "$filename"
            sed -i.orig "/-D.*_BUILD_CPPFLAGS=/$workdir" "$filename"
            sed -i.orig "/-D.*_BUILD_CPPFLAGS=/$destdir" "$filename"
            sed -i.orig "/-D.*_BUILD_LIBS=/$source" "$filename"
            sed -i.orig "/-D.*_BUILD_LIBS=/$workdir" "$filename"
            sed -i.orig "/-D.*_BUILD_LIBS=/$destdir" "$filename"
        else
            sed -i.orig "$source" "$filename"
            sed -i.orig "$workdir" "$filename"
            sed -i.orig "$destdir" "$filename"
        fi
    done
fi

echo running make with "${njobs:-1}" jobs for MPI
make -j "${njobs:-1}" install-strip DESTDIR="$DESTDIR"

fixup-ucx() {

cd "${DESTDIR}${PREFIX}"
rm -fr include/uc[mpst]
rm -f  bin/io_demo
rm -f  bin/ucx_*
rm -fr etc/ucx
rm -f  lib/libuc[mpst]*.a
rm -f  lib/libuc[mpst]*.la
rm -f  lib/ucx/libuc[mt]_*.a
rm -f  lib/ucx/libuc[mt]_*.la
rm -fr lib/cmake/ucx
rm -f  lib/pkgconfig/ucx*.pc
rm -fr share/ucx

cd "${DESTDIR}${PREFIX}/lib"
test -f libucp.so || return 0
for lib in libuc[mpst]*.so.?; do
    if test -f "$lib".*; then
        mv "$(readlink "$lib")" "$lib"
        ln -sf "$lib" "${lib%.*}"
    fi
    patchelf --set-rpath "\$ORIGIN" "$lib"
done
patchelf --add-rpath "\$ORIGIN/ucx" libucm.so.?
patchelf --add-rpath "\$ORIGIN/ucx" libuct.so.?
for lib in ucx/libuc[mt]_*.so.?; do
    if test -f "$lib".*; then
        mv "$(dirname "$lib")/$(readlink "$lib")" "$lib"
        ln -srf "$lib" "${lib%.*}"
    fi
    patchelf --set-rpath "\$ORIGIN" "$lib"
    patchelf --add-rpath "\$ORIGIN/.." "$lib"
done

} # fixup-ucx()

fixup-ofi() {

cd "${DESTDIR}${PREFIX}"
rm -fr include/rdma
rm -f  bin/fi_*
rm -f  lib/libfabric.a
rm -f  lib/libfabric.la
rm -f  lib/pkgconfig/libfabric.pc
rm -f  share/man/man?/fabric.?
rm -f  share/man/man?/fi_*.?

cd "${DESTDIR}${PREFIX}/lib"
test -f libfabric.so || return 0
for lib in libfabric.so.?; do
    if test -f "$lib".*.*; then
        mv "$(readlink "$lib")" "$lib"
        ln -sf "$lib" "${lib%.*}"
    fi
    patchelf --set-rpath "\$ORIGIN" "$lib"
done

} # fixup-ofi()

fixup-mpi-mpich() {

cd "${DESTDIR}${PREFIX}"
rm -f  include/*cxx.h
rm -f  include/*.mod
rm -f  include/*f.h
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
    sed -i.orig s:"\s*${build_cflags[*]}"::g "$script"
    sed -i.orig s:"$PREFIX":\"\$\{prefix\}\":g "$script"
    sed -i.orig s:"$WORKDIR.*/lib.*\.la"::g "$script"
    sed -i.orig s:"$DESTDIR.*/lib.*\.la"::g "$script"
    sed -i.orig s:"$DESTDIR"::g "$script"
    sed -i.orig s:-Wl,-commons,use_dylibs::g "$script"
    sed -i.orig s:/usr/bin/bash:/bin/bash:g "$script"
    sed -i.orig s:-lmpicxx::g "$script"
    rm "$script".orig
done

if test "$(uname)" = Linux; then
    cd "${DESTDIR}${PREFIX}/bin"
    for exe in "${executables[@]}"; do
        patchelf --set-rpath "\$ORIGIN/../lib" "$exe"
    done
    cd "${DESTDIR}${PREFIX}/lib"
    for lib in libfabric.so.? libuc[mpst]*.so.?; do
        test -f "$lib" || continue
        for exe in "${executables[@]}"; do
            patchelf --remove-needed "$lib" "../bin/$exe"
        done
    done
    cd "${DESTDIR}${PREFIX}/lib"
    rm -fr "$mpiname"
    if test -f libfabric.so; then
        mkdir -p "$mpiname"
        mv libfabric.* "$mpiname"
    fi
    if test -f libucp.so; then
        mkdir -p "$mpiname"
        mv libuc[mpst]*.* ucx "$mpiname"
    fi
    cd "${DESTDIR}${PREFIX}/lib"
    for lib in lib*.so; do
        patchelf --set-rpath "\$ORIGIN" "$lib"
        soname=$(patchelf --print-soname "$lib")
        if test -L "$soname"; then
            mv "$(readlink "$soname")" "$soname"
            ln -sf "$soname" "$lib"
        fi
    done
    if test -d "$mpiname"; then
        patchelf --add-rpath "\$ORIGIN/$mpiname" libmpi.so.*
    fi
    cd "${DESTDIR}${PREFIX}/lib"
    find . -name '*.so' -type l -delete
    ln -s libmpi.so.* libmpi.so
fi

if test "$(uname)" = Darwin; then
    libdir="$PREFIX/lib"
    libmpi=$(basename "${DESTDIR}$libdir"/libmpi.*.dylib)
    libpmpi=$(basename "${DESTDIR}$libdir"/libpmpi.*.dylib)
    cd "${DESTDIR}${PREFIX}/bin"
    for exe in "${executables[@]}"; do
        install_name_tool -add_rpath "@executable_path/../lib/" "$exe"
        for lib in "$libmpi" "$libpmpi"; do
            install_name_tool -change "$libdir/$lib" "@rpath/$lib" "$exe"
        done
    done
    cd "${DESTDIR}${PREFIX}/lib"
    for lib in "$libmpi" "$libpmpi"; do
        install_name_tool -id "@rpath/$lib" "$lib"
        install_name_tool -add_rpath "@loader_path/" "$lib"
    done
    install_name_tool -change "$libdir/$libpmpi" "@rpath/$libpmpi" "$libmpi"
    cd "${DESTDIR}${PREFIX}/lib"
    find . -name '*.dylib' -type l -delete
    ln -s "$libmpi" libmpi.dylib
    ln -s "$libpmpi" libpmpi.dylib
fi

} # fixup-mpi-mpich()

fixup-mpi-openmpi() {

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
rm -f  bin/pcc
rm -f  bin/pmixcc
rm -f  bin/mpif77
rm -f  bin/mpif90
rm -f  bin/mpifort
rm -f  bin/oshrun
rm -f  lib/*.mod
rm -f  lib/lib*.a
rm -f  lib/lib*.la
rm -f  lib/*/lib*.a
rm -f  lib/*/lib*.la
rm -f  lib/libmpi_mpifh*.*
rm -f  lib/libmpi_usempi*.*
rm -f  lib/libompitrace.*
rm -fr lib/cmake
rm -fr lib/openmpi
rm -fr lib/pkgconfig
rm -fr share/bash-completion
rm -fr share/doc
rm -fr share/man
rm -fr share/hwloc
rm -fr share/prte/rst
rm -fr share/ucx
rm -f  share/openmpi/mpif77-wrapper-data.txt
rm -f  share/openmpi/mpif90-wrapper-data.txt
rm -f  share/openmpi/mpifort-wrapper-data.txt
rm -f  share/pmix/pmixcc-wrapper-data.txt
rm -f  share/*/*.supp
rm -f  share/*/*/example.conf

cd "${DESTDIR}${PREFIX}/bin"
rm -f ompirun_wrapper
rm -f orterun_wrapper

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
    for lib in libfabric.so.? libuc[mpst]*.so.?; do
        test -f "$lib" || continue
        for exe in "${executables[@]}"; do
            patchelf --remove-needed "$lib" "../bin/$exe"
        done
    done
    cd "${DESTDIR}${PREFIX}/lib"
    rm -fr "$mpiname"
    if test -f libfabric.so; then
        mkdir -p "$mpiname"
        mv libfabric.* "$mpiname"
    fi
    if test -f libucp.so; then
        mkdir -p "$mpiname"
        mv libuc[mpst]*.* ucx "$mpiname"
    fi
    for lib in lib*.so; do
        patchelf --set-rpath "\$ORIGIN" "$lib"
        soname=$(patchelf --print-soname "$lib")
        if test -L "$soname"; then
            mv "$(readlink "$soname")" "$soname"
            ln -sf "$soname" "$lib"
        fi
    done
    cd "${DESTDIR}${PREFIX}/lib"
    if true; then
        dependencies=(
            libevent*.so.*
            libhwloc.so.*
            libpmix.so.*
            libprrte.so.*
        )
        for lib in "${dependencies[@]}"; do
            test -f "$lib" || continue
            mkdir -p "$mpiname"
            mv "$lib" "$mpiname"
        done
    fi
    cd "${DESTDIR}${PREFIX}/lib"
    if test -d "$mpiname"; then
        exepath="\$ORIGIN/../lib/$mpiname"
        libpath="\$ORIGIN/$mpiname"
        for exe in "${executables[@]}"; do
            patchelf --add-rpath "$exepath" ../bin/"$exe"
        done
        patchelf --add-rpath "$libpath" libmpi.so.*
        patchelf --add-rpath "$libpath" libopen-*.so.*
    fi
    cd "${DESTDIR}${PREFIX}/lib"
    find . -name '*.so' -type l -delete
    ln -s libmpi.so.* libmpi.so
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
        unset dependencies
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
    cd "${DESTDIR}${PREFIX}/lib"
    if true; then
        dependencies=(
            libevent*.*.dylib
            libhwloc.*.dylib
            libpmix.*.dylib
            libprrte.*.dylib
        )
        for lib in "${dependencies[@]}"; do
            test -f "$lib" || continue
            mkdir -p "$mpiname"
            mv "$lib" "$mpiname"
        done
    fi
    cd "${DESTDIR}${PREFIX}/lib"
    if test -d "$mpiname"; then
        exepath="@executable_path/../lib/$mpiname/"
        libpath="@loader_path/$mpiname/"
        for exe in "${executables[@]}"; do
            install_name_tool -add_rpath "$exepath" ../bin/"$exe"
        done
        install_name_tool -add_rpath "$libpath" libmpi.*.dylib
        install_name_tool -add_rpath "$libpath" libopen-*.*.dylib
    fi
    cd "${DESTDIR}${PREFIX}/lib"
    find . -name '*.dylib' -type l -delete
    ln -s libmpi.*.dylib libmpi.dylib
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
    libdir="$DESTDIR$PREFIX/lib"
    sed -i.orig "s:$libdir:\${libdir}:g" "$wrapper_data"
    rm "$wrapper_data".orig
done

cd "${DESTDIR}${PREFIX}/bin"
wrapper_cmd=opal_wrapper
wrapper_src="$PROJECT/cibw-ompi-wrapper.c"
wrapper_bin="$WORKDIR/cibw-ompi-wrapper.exe"
cc -O -DWRAPPER="$wrapper_cmd" "$wrapper_src" -o "$wrapper_bin"
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
cc -O -DWRAPPER="$wrapper" "$wrapper_src" -o "$wrapper_bin"
executables=(mpirun mpiexec orterun)
for exe in "${executables[@]}"; do
    test -e "$exe" || continue
    test -L "$exe" || continue
    install -s "$wrapper_bin" "$exe"
done

} # fixup-mpi-openmpi()

echo fixing UCX install tree
fixup-ucx
echo fixing OFI install tree
fixup-ofi
echo fixing MPI install tree
fixup-mpi-"$mpiname"

echo checking install tree
cd "${DESTDIR}${PREFIX}"
dirty=0
echo checking for files with SOURCE
if grep -lr "$SOURCE" ; then dirty=1; fi
echo checking for files with WORKDIR
if grep -lr "$WORKDIR"; then dirty=1; fi
echo checking for files with DESTDIR
if grep -lr "$DESTDIR"; then dirty=1; fi
test "$dirty" -eq 0
