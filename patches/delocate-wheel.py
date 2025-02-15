#!/usr/bin/env python
import sys
from delocate.cmd.delocate_wheel import main

sys.argv[1:1] = """
--ignore-missing-dependencies
""".split()

if __name__ == "__main__":
    sys.exit(main())
