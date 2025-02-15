#!/bin/bash
set -euo pipefail

wheelhouse="${1:-wheelhouse}"
ls -d "$wheelhouse" > /dev/null

savedir=$(pwd)
tempdir=$(mktemp -d)
workdir=$tempdir/wheel
trap 'rm -rf $tempdir' EXIT

for wheelfile in "$wheelhouse"/*.whl; do
cd "$savedir" && rm -rf "$workdir"
unzip -vv "$wheelfile"
unzip -qq "$wheelfile" -d "$workdir"
cd "$workdir"

whlname=$(basename "$wheelfile")
whlinfo=${whlname%%-py*}
pkgname=${whlinfo%%-*}
version=${whlinfo##*-}
mpiname=${pkgname}

data=$(ls -d "$pkgname"-*.data/data)
if test "$(uname)" = Linux; then
    # shellcheck disable=SC2016
    runpath='\$ORIGIN/../lib|\$ORIGIN'
    soregex='\.so\..*'
    runlibs='lib(mpi|c|m|dl|rt|pthread)'$soregex
    runlibs=$runlibs'|(ld-linux-.*|ld64)'$soregex
    libsdir=.libs
    print-runpath() { patchelf --print-rpath  "$1"; }
    print-needed()  { patchelf --print-needed "$1"; }
    if test -f "$data"/lib/*/libucp.so.*; then
        runlibs=$runlibs'|libuc(m|p|s|t)'$soregex
    fi
    if test -f "$data"/lib/*/libfabric.so.*; then
        runlibs=$runlibs'|libfabric'$soregex
    fi
fi
if test "$(uname)" = Darwin; then
    runpath='@executable_path/../lib/|@loader_path/'
    soregex='\..*\.dylib'
    runlibs='lib(mpi|pmpi|System|objc)'$soregex
    runlibs=$runlibs'|(Foundation|IOKit)\.framework'
    libsdir=.dylibs
    print-runpath() { otool -l "$1" | sed -n '/RPATH/{n;n;p;}'; }
    print-needed()  { otool -L "$1" | sed 1,1d; }
    if test -f "$data"/lib/libucp.*.dylib; then
        runlibs=$runlibs'|libuc(m|p|s|t)'$soregex
    fi
    if test -f "$data"/lib/libfabric.*.dylib; then
        runlibs=$runlibs'|libfabric'$soregex
    fi
fi

if test "$mpiname" = "mpich"; then
    headers=(
        "$data"/include/mpi.h
        "$data"/include/mpio.h
    )
    scripts=(
        "$data"/bin/mpicc
        "$data"/bin/mpic++
        "$data"/bin/mpicxx
    )
    wrappers=()
    programs=(
        "$data"/bin/mpichversion
        "$data"/bin/mpivars
        "$data"/bin/mpiexec
        "$data"/bin/mpiexec.*
        "$data"/bin/hydra_*
    )
    libraries=(
        "$data"/lib/lib*mpi.*
    )
    if ls "$data"/lib/*/libfabric.* > /dev/null 2>&1; then
        libraries+=(
            "$data"/lib/*/libfabric.*
        )
    fi
    if ls "$data"/lib/*/libucp.* > /dev/null 2>&1; then
        libraries+=(
            "$data"/lib/*/libuc[mpst]*.*
            "$data"/lib/*/ucx/libuc[mpst]*.*
        )
    fi
fi

if test "$mpiname" = "openmpi"; then
    headers=(
        "$data"/include/mpi.h
    )
    scripts=()
    wrappers=(
        "$data"/bin/mpicc
        "$data"/bin/mpic++
        "$data"/bin/mpicxx
        "$data"/bin/mpiCC
        "$data"/bin/mpirun
        "$data"/bin/mpiexec
    )
    programs=(
        "$data"/bin/*_info
        "$data"/bin/*_wrapper
    )
    libraries=(
        "$data"/lib/libmpi.*
        "$data"/lib/libopen-*.*
    )
    if test "${version%%.*}" -ge 5; then
        libraries+=(
            "$data"/lib/openmpi/libevent*.*
            "$data"/lib/openmpi/libhwloc.*
            "$data"/lib/openmpi/libpmix.*
            "$data"/lib/openmpi/libprrte.*
        )
    fi
    if ls "$data"/lib/*/libucp.* > /dev/null 2>&1; then
        libraries+=(
            "$data"/lib/*/libuc[mpst]*.*
            "$data"/lib/*/ucx/libuc[mpst]*.*
        )
    fi
    if ls "$data"/lib/*/libfabric.* > /dev/null 2>&1; then
        libraries+=(
            "$data"/lib/*/libfabric.*
        )
    fi
    runlibs+='|lib(z|util|event.*|hwloc)'$soregex
    runlibs+='|lib(open-(pal|rte)|pmix|prrte)'$soregex
fi

check-binary() {
    local dso=$1 out1="" out2=""
    echo checking "$dso"...
    test -f "$dso" || (printf "ERROR: file not found\n"; exit 1)
    out1="$(print-runpath "$dso" | grep -vE "$runpath" || true)"
    test -z "$out1" || printf "ERROR: RUNPATH\n%s\n" "$out1"
    out2="$(print-needed  "$dso" | grep -vE "$runlibs" || true)"
    test -z "$out2" || printf "ERROR: NEEDED\n%s\n" "$out2"
    test -z "$out1"
    test -z "$out2"
}

for header in "${headers[@]-}"; do
    test -n "$header" || break
    echo checking "$header"...
    test -f "$header" || (printf "ERROR: file not found\n"; exit 1)
    out=$(grep -E '^#include\s+"mpicxx\.h"' "$header" || true)
    test -z "$out" || printf "ERROR: include\n%s\n" "$out"
    test -z "$out"
done
for script in "${scripts[@]-}"; do
    test -n "$script" || break
    echo checking "$script"...
    test -f "$script" || (printf "ERROR: file not found\n"; exit 1)
    out=$(grep -E "/opt/$mpiname" "$script" || true)
    test -z "$out" || printf "ERROR: prefix\n%s\n" "$out"
    test -z "$out"
done
for bin in "${wrappers[@]-}"; do
    test -n "$bin" || break
    check-binary "$bin"
done
for bin in "${programs[@]-}"; do
    test -n "$bin" || break
    check-binary "$bin"
done
for lib in "${libraries[@]-}"; do
    test -n "$lib" || break
    check-binary "$lib"
done
if test -d "$pkgname$libsdir"; then
    echo checking "$pkgname$libsdir"...
    out=$(ls -A "$pkgname$libsdir")
    test -z "$out" || printf "ERROR: library\n%s\n" "$out"
    test -z "$out"
fi

echo success!

done
