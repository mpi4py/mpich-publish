#!/bin/bash
set -euo pipefail

SOURCE=package/source
WORKDIR=package/workdir
DESTDIR=package/install
ARCHLIST=${ARCHLIST:-$(uname -m)}

read -r SOURCE_DATE_EPOCH < "$SOURCE"/source-date-epoch
export SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH

export CIBW_BUILD_FRONTEND='build[uv]'
export CIBW_BUILD='cp313-*'
export CIBW_SKIP='*musllinux*'
export CIBW_ARCHS=$ARCHLIST
export CIBW_BEFORE_ALL='bash {project}/cibw-build-mpi.sh'
export CIBW_BEFORE_BUILD='bash {project}/cibw-patch-cmd.sh'
export CIBW_TEST_COMMAND='bash {project}/cibw-check-mpi.sh'
export CIBW_ENVIRONMENT_PASS='MPINAME RELEASE SOURCE WORKDIR DESTDIR'
export CIBW_MANYLINUX_AARCH64_IMAGE=manylinux_2_28
export CIBW_MANYLINUX_X86_64_IMAGE=manylinux_2_28

if test "$(uname)" = Linux; then
    containerengine=$(basename "$(command -v podman || command -v docker)")
    export CIBW_CONTAINER_ENGINE=$containerengine
    export SOURCE="/project/$SOURCE"
    export WORKDIR="/host$PWD/$WORKDIR"
    export DESTDIR="/host$PWD/$DESTDIR"
    platform=linux
fi
if test "$(uname)" = Darwin; then
    case "$(uname -m)" in
        arm64)  export MACOSX_DEPLOYMENT_TARGET=11.0  ;;
        x86_64) export MACOSX_DEPLOYMENT_TARGET=10.15 ;;
    esac
    export CIBW_BUILD_FRONTEND='build'
    export CIBW_BUILD='pp310-*'
    export SOURCE="$PWD/$SOURCE"
    export WORKDIR="$PWD/$WORKDIR"
    export DESTDIR="$PWD/$DESTDIR"
    platform=macos
fi

pipx run \
cibuildwheel \
--platform "$platform" \
--output-dir "${1:-dist}" \
package
