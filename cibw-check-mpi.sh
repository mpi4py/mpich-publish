#!/bin/bash
set -euo pipefail

mpiname="${MPINAME:-mpich}"

tempdir="$(mktemp -d)"
trap 'rm -rf $tempdir' EXIT
cd "$tempdir"

cat > helloworld.c << EOF
#include <mpi.h>
#include <stdio.h>

int main(int argc, char *argv[])
{
  int size, rank, len;
  char name[MPI_MAX_PROCESSOR_NAME];

  MPI_Init(&argc, &argv);
  MPI_Comm_size(MPI_COMM_WORLD, &size);
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);
  MPI_Get_processor_name(name, &len);
  printf("Hello, World! I am process %d of %d on %s.\n", rank, size, name);
  MPI_Finalize();
  return 0;
}
EOF
ln -s helloworld.c helloworld.cxx

if test "$mpiname" = "openmpi"; then
    export OMPI_ALLOW_RUN_AS_ROOT=1
    export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
    export OMPI_MCA_btl=tcp,self
    export OMPI_MCA_plm_rsh_agent=false
    export OMPI_MCA_plm_ssh_agent=false
    export OMPI_MCA_mpi_yield_when_idle=true
    export OMPI_MCA_rmaps_base_oversubscribe=true
    export OMPI_MCA_rmaps_default_mapping_policy=:oversubscribe
fi

export MPIEXEC_TIMEOUT=60

RUN() { echo + "$@"; "$@"; }

if test "$mpiname" = "mpich"; then
    RUN command -v mpichversion
    RUN mpichversion
fi

if test "$mpiname" = "mpich"; then
    RUN command -v mpivars
    RUN mpivars -nodesc | grep 'Category .* has'
fi

if test "$mpiname" = "openmpi"; then
    RUN command -v ompi_info
    RUN ompi_info
fi

RUN command -v mpicc
RUN mpicc -show
RUN mpicc helloworld.c -o helloworld-c

RUN command -v mpicxx
RUN mpicxx -show
RUN mpicxx helloworld.cxx -o helloworld-cxx

RUN command -v mpiexec
RUN mpiexec -n 3 ./helloworld-c
RUN mpiexec -n 3 ./helloworld-cxx
