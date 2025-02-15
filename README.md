# mpi-publish

This repository builds and publishes [MPICH](https://www.mpich.org) and
[Open MPI](https://www.open-mpi.org/) Python wheels able to run in
a variety of

- operating systems: *Linux*, *macOS*;
- processor architectures: *AMD64*, *ARM64*;
- Python implementations: *CPython*, *PyPy*.

MPI wheels are uploaded to the [Anaconda.org](https://anaconda.org/mpi4py)
package server. These wheels can be installed with `pip` specifying the
alternative index URL:

```sh
python -m pip install mpich -i https://pypi.anaconda.org/mpi4py/simple
```

```sh
python -m pip install openmpi -i https://pypi.anaconda.org/mpi4py/simple
```

> [!CAUTION]
> MPI wheels are distributed with a focus on ease of use, compatibility, and
> interoperability. The Linux wheels are built in somewhat constrained
> environments with relatively dated Linux distributions
> ([manylinux](https://github.com/pypa/manylinux) container images).
> Therefore, they may lack support for high-performance features like
> cross-memory attach (XPMEM/CMA). In production scenarios, it is recommended
> to use external (either custom-built or system-provided) MPI installations.

> [!TIP]
> [Intel MPI](https://software.intel.com/intel-mpi-library) distributes [Linux
> and Windows wheels](https://pypi.org/project/impi-rt/#files) for Intel-based
> processor architectures (`x86_64`/`AMD64`). Intel MPI wheels for Linux are
> ABI-compatible with MPICH wheels and may offer better performance.
>
> ```sh
> python -m pip install impi-rt
> ```
