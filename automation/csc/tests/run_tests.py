#!/usr/bin/env python3
"""Run the local CSC contract tests, rejecting an empty discovery result."""

import argparse
from pathlib import Path
import sys
import unittest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pattern", default="test_*.py", help="unittest discovery pattern")
    args = parser.parse_args(argv)
    suite = unittest.defaultTestLoader.discover(
        start_dir=str(Path(__file__).resolve().parent), pattern=args.pattern
    )
    count = suite.countTestCases()
    if count == 0:
        print("ERROR: discovery selected zero tests; verification did not run.", file=sys.stderr)
        return 2
    print(f"Discovered {count} contract tests.", file=sys.stderr)
    return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())
