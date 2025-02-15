#!/bin/bash
set -euo pipefail

wheelhouse="${1:-wheelhouse}"
ls -d "$wheelhouse" > /dev/null

venv=$(mktemp -d)
trap 'rm -rf $venv' EXIT

mpiname=${MPINAME:-mpich}
version=${VERSION:-}
release=${RELEASE:-}
mpispec="$mpiname"
test -n "$version" && mpispec+="==$version"
test -n "$release" && mpispec+=".post$release"

RUN() { echo + "$@"; "$@"; }

RUN python3 -m venv "$venv"
RUN source "$venv"/bin/activate

RUN python -m pip install "$mpispec" \
    --no-index --find-links "${1:-wheelhouse}"

RUN ./cibw-check-mpi.sh
