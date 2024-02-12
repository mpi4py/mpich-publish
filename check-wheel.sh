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
    runlibs='lib(mpi|c|m|dl|rt|pthread)\.so\..*'
    runlibs=$runlibs'|(ld-linux-.*|ld64)\.so\..*'
    print-runpath() { patchelf --print-rpath  "$1"; }
    print-needed()  { patchelf --print-needed "$1"; }
    if test -f "$data"/lib/libucp.so; then
        runlibs=$runlibs'|libuc(m|p|s|t)'
    fi
fi
if test "$(uname)" = Darwin; then
    runpath='@executable_path/../lib/|@loader_path/'
    runlibs='lib(mpi|pmpi|System)\..*\.dylib'
    print-runpath() { otool -l "$1" | sed -n '/RPATH/{n;n;p;}'; }
    print-needed()  { otool -L "$1" | sed 1,1d; }
    if test -f "$data"/lib/libucp.dylib; then
        runlibs=$runlibs'|libuc(m|p|s|t)\.'
    fi
fi

check-dso() {
    local dso=$1 out1="" out2=""
    echo checking "$dso"...
    test -f "$dso" || printf "ERROR: file not found"
    out1="$(print-runpath "$dso" | grep -vE "$runpath" || true)"
    test -z "$out1" || printf "ERROR: RUNPATH\n%s\n" "$out1"
    out2="$(print-needed  "$dso" | grep -vE "$runlibs" || true)"
    test -z "$out2" || printf "ERROR: NEEDED\n%s\n" "$out2"
    test -z "$out1" -a  -z "$out2"
}

for hdr in "$data"/include/mpi.h "$data"/include/mpio.h; do
    echo checking "$hdr"...
    test -f "$hdr"
    test -z "$(grep -E '^#include\s+"mpicxx\.h"' "$hdr" || true)"
done
for script in "$data"/bin/mpicc "$data"/bin/mpicxx; do
    echo checking "$script"...
    test -f "$script"
    test -z "$(grep -E "/opt/$mpiname" "$script" || true)"
done
for bin in "$data"/bin/mpichversion "$data"/bin/mpivars; do
    check-dso "$bin"
done
for bin in "$data"/bin/mpiexec* "$data"/bin/hydra_*; do
    check-dso "$bin"
done
for lib in "$data"/lib/libmpi.*; do
    check-dso "$lib"
done
if test "$(uname)" = Linux; then
    libs=$(ls -d "$pkgname".libs)
    echo checking "$libs"...
    test -z "$(ls -A "$libs")"
fi

echo success!

done
