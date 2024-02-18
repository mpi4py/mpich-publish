#!/bin/bash
set -euo pipefail

mpiname="${MPINAME:-mpich}"
variant="${VARIANT:-}"
test -z "$variant" \
    && pkgname="${mpiname}" \
    || pkgname="${mpiname}_${variant}"

wheelhouse="${1:-wheelhouse}"
ls -d "$wheelhouse" > /dev/null

savedir=$(pwd)
tempdir=$(mktemp -d)
workdir=$tempdir/wheel
trap 'rm -rf $tempdir' EXIT

for wheelfile in "$wheelhouse/$pkgname"-*.whl; do
cd "$savedir" && rm -rf "$workdir"
unzip -vv "$wheelfile"
unzip -qq "$wheelfile" -d "$workdir"
cd "$workdir"

data=$(ls -d "$pkgname"-*.data/data)
if test "$(uname)" = Linux; then
    # shellcheck disable=SC2016
    runpath='\$ORIGIN/../lib|\$ORIGIN'
    soregex='\.so\..*'
    runlibs='lib(mpi|c|m|dl|rt|pthread)'$soregex
    runlibs=$runlibs'|(ld-linux-.*|ld64)'$soregex
    print-runpath() { patchelf --print-rpath  "$1"; }
    print-needed()  { patchelf --print-needed "$1"; }
    if test -f "$data"/lib/libucp.so; then
        runlibs=$runlibs'|libuc(m|p|s|t)'$soregex
    fi
fi
if test "$(uname)" = Darwin; then
    runpath='@executable_path/../lib/|@loader_path/'
    soregex='\..*\.dylib'
    runlibs='lib(mpi|pmpi|System)'$soregex
    runlibs=$runlibs'|(Foundation|IOKit)\.framework'
    print-runpath() { otool -l "$1" | sed -n '/RPATH/{n;n;p;}'; }
    print-needed()  { otool -L "$1" | sed 1,1d; }
    if test -f "$data"/lib/libucp.dylib; then
        runlibs=$runlibs'|libuc(m|p|s|t)'$soregex
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
    programs=(
        "$data"/bin/mpichversion
        "$data"/bin/mpivars
        "$data"/bin/mpiexec
        "$data"/bin/mpiexec.*
        "$data"/bin/hydra_*
    )
    libraries=(
        "$data"/lib/libmpi.*
    )
    if test "$variant" = "ucx"; then
        libraries+=(
            "$data"/lib/libuc[mpst]*.*
            "$data"/lib/ucx/libuc*.*
        )
    fi
fi

check-dso() {
    local dso=$1 out1="" out2=""
    echo checking "$dso"...
    test -f "$dso" || printf "ERROR: file not found\n"
    out1="$(print-runpath "$dso" | grep -vE "$runpath" || true)"
    test -z "$out1" || printf "ERROR: RUNPATH\n%s\n" "$out1"
    out2="$(print-needed  "$dso" | grep -vE "$runlibs" || true)"
    test -z "$out2" || printf "ERROR: NEEDED\n%s\n" "$out2"
    test -z "$out1" -a -z "$out2"
}

for header in "${headers[@]}"; do
    echo checking "$header"...
    test -f "$header"
    out=$(grep -E '^#include\s+"mpicxx\.h"' "$header" || true)
    test -z "$out" || printf "ERROR: include\n%s\n" "$out"
    test -z "$out"
done
for script in "${scripts[@]}"; do
    echo checking "$script"...
    test -f "$script"
    out=$(grep -E "/opt/$mpiname" "$script" || true)
    test -z "$out" || printf "ERROR: prefix\n%s\n" "$out"
    test -z "$out"
done
for bin in "${programs[@]}"; do
    check-dso "$bin"
done
for lib in "${libraries[@]}"; do
    check-dso "$lib"
done
if test "$(uname)" = Linux; then
    echo checking "$pkgname".libs...
    out=$(ls -A "$pkgname".libs)
    test -z "$out" || printf "ERROR: library\n%s\n" "$out"
    test -z "$out"
fi

echo success!

done
