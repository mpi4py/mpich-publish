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
    runpath='\$ORIGIN/../lib'
    syslibs='lib(c|m|dl|rt|pthread)|ld-linux-'
    print-rpath() { patchelf --print-rpath "$1"; }
    print-needed() { patchelf --print-needed "$1"; }
    if test -f "$data"/lib/libucp.so; then
        # shellcheck disable=SC2016
        runpath=$runpath'|\$ORIGIN'
        syslibs=$syslibs'|libuc(m|p|s|t)'
    fi
fi
if test "$(uname)" = Darwin; then
    runpath='@executable_path/../lib/|@loader_path/'
    syslibs='lib(mpi|pmpi|System)'
    print-rpath()  { otool -l "$1" | sed -n '/RPATH/{n;n;p;}'; }
    print-needed() { otool -L "$1" | sed 1,1d; }
    if test -f "$data"/lib/libucp.dylib; then
        syslibs=$syslibs'|libuc(m|p|s|t)'
    fi
fi

for hdr in "$data"/include/mpi.h "$data"/include/mpio.h; do
    echo check "$hdr"...
    test -f "$hdr"
done
for script in "$data"/bin/mpicc "$data"/bin/mpicxx; do
    echo check "$script"...
    test -z "$(grep -E "/opt/$mpiname" "$script")"
done
for bin in "$data"/bin/mpichversion "$data"/bin/mpivars; do
    echo check "$bin"...
    test -z "$(print-rpath  "$bin" | grep -vE "$runpath")"
    test -z "$(print-needed "$bin" | grep -vE "$syslibs")"
done
for bin in "$data"/bin/mpiexec* "$data"/bin/hydra_*; do
    echo check "$bin"...
    test -z "$(print-rpath  "$bin" | grep -vE "$runpath")"
    test -z "$(print-needed "$bin" | grep -vE "$syslibs")"
done
for lib in "$data"/lib/libmpi.*; do
    echo check "$lib"...
    test -z "$(print-rpath  "$lib" | grep -vE "$runpath")"
    test -z "$(print-needed "$lib" | grep -vE "$syslibs")"
done
if test "$(uname)" = Linux; then
    libs=$(ls -d "$pkgname".libs)
    echo check "$libs"...
    test -z "$(ls -A "$libs")"
fi

echo success

done
