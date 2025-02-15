#!/bin/bash
set -euo pipefail

case "$(uname)" in
    Linux)  toolname=auditwheel;;
    Darwin) toolname=delocate-wheel;;
esac

topdir=$(cd "$(dirname -- "$0")" && pwd -P)
toolpatch="$topdir/patches/$toolname.py"
test -f "$toolpatch" || exit 0

filename=$(command -v "$toolname")
shebang=$(head -n 1 "$filename")
sed "1 s|^.*$|$shebang|" "$toolpatch" > "$filename"
