#!/bin/bash
set -euo pipefail

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

set -x

command -v mpichversion
mpichversion

command -v mpivars
mpivars -nodesc | grep 'Category .* has'

command -v mpicc
mpicc -show
mpicc helloworld.c -o helloworld-c

command -v mpicxx
mpicxx -show
mpicxx helloworld.cxx -o helloworld-cxx

command -v mpiexec
mpiexec -n 5 ./helloworld-c
mpiexec -n 5 ./helloworld-cxx
