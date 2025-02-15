#!/usr/bin/env python

#
# https://github.com/pypa/auditwheel/pull/517
#

import os
import sys
import auditwheel.main
import auditwheel.tools

os_walk = os.walk


def walk(topdir, *args, **kwargs):
    topdir = os.path.normpath(topdir)
    for dirpath, dirnames, filenames in os_walk(topdir, *args, **kwargs):
        # sort list of dirnames in-place such that `os.walk`
        # will recurse into subdirectories in reproducible order
        dirnames.sort()
        # recurse into any top-level .dist-info subdirectory last
        if dirpath == topdir:
            subdirs = []
            dist_info = []
            for dir in dirnames:
                if dir.endswith(".dist-info"):
                    dist_info.append(dir)
                else:
                    subdirs.append(dir)
            dirnames[:] = subdirs
            dirnames.extend(dist_info)
            del dist_info
        # sort list of filenames for iteration in reproducible order
        filenames.sort()
        # list any dist-info/RECORD file last
        if dirpath.endswith(".dist-info") and os.path.dirname(dirpath) == topdir:
            if "RECORD" in filenames:
                filenames.remove("RECORD")
                filenames.append("RECORD")
        yield dirpath, dirnames, filenames


def dir2zip(in_dir, zip_fname, date_time=None):
    import zipfile
    from datetime import datetime, timezone
    in_dir = os.path.normpath(in_dir)
    if date_time is None:
        st = os.stat(in_dir)
        date_time = datetime.fromtimestamp(st.st_mtime, tz=timezone.utc)
    date_time_args = date_time.timetuple()[:6]
    compression = zipfile.ZIP_DEFLATED
    with zipfile.ZipFile(zip_fname, "w", compression=compression) as z:
        for root, dirs, files in walk(in_dir):
            if root != in_dir and not (dirs or files):
                dname = root
                out_dname = os.path.relpath(dname, in_dir) + "/"
                zinfo = zipfile.ZipInfo.from_file(dname, out_dname)
                zinfo.date_time = date_time_args
                z.writestr(zinfo, b"")
            for file in files:
                fname = os.path.join(root, file)
                out_fname = os.path.relpath(fname, in_dir)
                zinfo = zipfile.ZipInfo.from_file(fname, out_fname)
                zinfo.date_time = date_time_args
                zinfo.compress_type = compression
                with open(fname, "rb") as fp:
                    z.writestr(zinfo, fp.read())


os.walk = walk
auditwheel.tools.dir2zip = dir2zip

if __name__ == "__main__":
    sys.argv.append("--only-plat")
    sys.exit(auditwheel.main.main())
