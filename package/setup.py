from setuptools import setup
from wheel.bdist_wheel import bdist_wheel
import glob
import re
import os


class bdist_wheel(bdist_wheel):

    def finalize_options(self):
        super().finalize_options()
        self.root_is_pure = False
        self.build_number = release or None

    def get_tag(self):
        plat_tag = super().get_tag()[-1]
        return (self.python_tag, "none", plat_tag)


mpiname = os.environ.get("MPINAME", "mpich")
variant = os.environ.get("VARIANT", "")
release = os.environ.get("RELEASE", "")
pkgname = f"{mpiname}-{variant}" if variant else mpiname

version_re = re.compile(r"#define\s+MPICH_VERSION\s+\"(.*)\"")
license = "LicenseRef-MPICH"
description = "A high performance implementation of MPI"
long_description = """`MPICH <https://www.mpich.org/>`_ is a
high-performance and widely portable implementation of the Message
Passing Interface (`MPI <https://www.mpi-forum.org/>`_) standard."""
author = "MPICH Team"
author_email = "discuss@mpich.org"
project_urls = {
    "Homepage":      "https://www.mpich.org",
    "Downloads":     "https://www.mpich.org/downloads/",
    "Documentation": "https://www.mpich.org/documentation/guides/",
    "Source":        "https://github.com/pmodels/mpich",
    "Issues":        "https://github.com/pmodels/mpich/issues",
    "Discussions":   "https://github.com/pmodels/mpich/discussions",
}

prefix = os.environ.get("PREFIX", f"/opt/{mpiname}")
basedir = os.path.dirname(__file__)
destdir = os.environ.get("DESTDIR", f"{basedir}/install")
rootdir = f"{destdir}{prefix}"

with open(f"{rootdir}/include/mpi.h") as fobj:
    version = version_re.search(fobj.read()).groups()[0]
data_files = [
    (subdir, glob.glob(f"{rootdir}/{subdir}/*"))
    for subdir in ("include", "bin", "lib")
]
cmdclass = {
    "bdist_wheel": bdist_wheel,
}

setup(
    name=pkgname,
    version=version,
    license=license,
    license_files=["LICENSE"],
    description=description,
    long_description=long_description,
    long_description_content_type="text/x-rst",
    author=author,
    author_email=author_email,
    maintainer="Lisandro Dalcin",
    maintainer_email="dalcinl@gmail.com",
    url=project_urls["Homepage"],
    project_urls=project_urls,
    packages=[],
    data_files=data_files,
    cmdclass=cmdclass,
)
