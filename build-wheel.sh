#!/bin/bash
set -euo pipefail

SOURCE=package/source
WORKDIR=package/workdir
DESTDIR=package/install
ARCHLIST=${ARCHLIST:-$(uname -m)}

export CIBW_BUILD_FRONTEND='build'
export CIBW_BUILD='cp312-*'
export CIBW_SKIP='*musllinux*'
export CIBW_ARCHS=$ARCHLIST
export CIBW_BEFORE_ALL='bash {project}/cibw-build-mpi.sh'
export CIBW_TEST_COMMAND='bash {project}/cibw-check-mpi.sh'
export CIBW_ENVIRONMENT_PASS='MPINAME VARIANT RELEASE SOURCE WORKDIR DESTDIR'
export CIBW_REPAIR_WHEEL_COMMAND_MACOS='delocate-wheel --ignore-missing-dependencies --exclude libmpi --exclude libpmpi --require-archs {delocate_archs -w {dest_dir} -v {wheel}'

if test "$(uname)" = Linux; then
    export SOURCE="/project/$SOURCE"
    export WORKDIR="/host/$PWD/$WORKDIR"
    export DESTDIR="/host/$PWD/$DESTDIR"
    platform=linux
fi
if test "$(uname)" = Darwin; then
    export SOURCE="$PWD/$SOURCE"
    export WORKDIR="$PWD/$WORKDIR"
    export DESTDIR="$PWD/$DESTDIR"
    export CIBW_BUILD='pp310-*'
    platform=macos
fi

python -m pipx run \
cibuildwheel \
--platform "$platform" \
--output-dir "${1:-dist}" \
package
