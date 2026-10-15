#!/usr/bin/env python3
"""Validate local control documents only; this CLI never installs approvals."""

import argparse
import json
import os
from pathlib import Path
import stat
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from phase2a import contracts as c


def read_control(path):
    path = Path(os.path.abspath(path))
    directory = c._open_directory(path.parent)
    try:
        fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        with os.fdopen(fd, "rb") as stream:
            metadata = os.fstat(stream.fileno())
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > c.MAX_JSON:
                raise c.Rejected("Invalid bounded control document.")
            raw = stream.read(c.MAX_JSON + 1)
            if len(raw) > c.MAX_JSON:
                raise c.Rejected("Control document grew beyond limit.")
            return raw
    finally:
        os.close(directory)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=["candidate-csv", "candidates", "inventory", "allowlist", "request"])
    parser.add_argument("document")
    args = parser.parse_args(argv)
    try:
        raw = read_control(args.document)
        document = (c.candidates_from_csv(raw) if args.kind == "candidate-csv" else
                    c.validate(c.load_json(raw), args.kind))
        result = {"status": "CONTRACT_VALID", "authorization": "NOT_GRANTED",
                  "scientific_acceptance": "NOT_GRANTED", "document_sha256": c.digest(document)}
        if args.kind == "candidate-csv":
            result["initial_inventory"] = c.unchecked_inventory(document)
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 0
    except (c.Rejected, OSError):
        print(json.dumps({"status": "REJECTED", "authorization": "NOT_GRANTED",
                          "scientific_acceptance": "NOT_GRANTED"}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
