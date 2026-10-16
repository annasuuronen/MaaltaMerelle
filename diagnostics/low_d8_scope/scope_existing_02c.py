#!/usr/bin/env python3
"""Compare precomputed LOW 02C shoreline zeros and LOW 02F route terminals.

Metadata/CSV-only. This does NOT count all interior D8 zeros in the LOW raster.
No network access, no writes, no raster reads, no imports beyond Python stdlib.
"""

import argparse
import collections
import csv
from pathlib import Path

EXPECTED_TERMINALS = (10007129, 10031127, 15389414, 15401414,
                      23211319, 23355315, 23373314)
MAX_INPUT_BYTES = 256 * 1024 * 1024


def rows(directory, filename, required):
    path = directory / filename
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Missing regular CSV: {path}")
    if path.stat().st_size > MAX_INPUT_BYTES:
        raise ValueError(f"CSV exceeds read-only size guard: {path}")
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames or not required.issubset(reader.fieldnames):
            raise ValueError(f"Unexpected columns in {filename}: {reader.fieldnames}")
        for row in reader:
            if None in row:
                raise ValueError(f"Malformed CSV row in {filename}")
            yield row


def parse_positive_int(value, label):
    try:
        n = int(value)
    except (ValueError, TypeError):
        raise ValueError(f"Non-integer {label}: {value!r}") from None
    if n < 1:
        raise ValueError(f"Non-positive {label}: {value!r}")
    return n


def summarize(directory):
    directory = Path(directory)
    known = set(EXPECTED_TERMINALS)
    components = collections.Counter()
    known_components = {}
    n_02c_rows = 0
    for row in rows(directory, "02C_zero_pointer_cells.csv", {"cell", "component_id"}):
        cell = parse_positive_int(row["cell"], "cell")
        component = parse_positive_int(row["component_id"], "component_id")
        n_02c_rows += 1
        components[component] += 1
        if cell in known:
            if cell in known_components:
                raise ValueError(f"Duplicate 02C zero cell {cell}")
            known_components[cell] = component

    classified = {}
    statuses = collections.Counter()
    n_classified = 0
    for row in rows(directory, "02C_shore_component_classification.csv",
                    {"component_id", "connector_status", "n_zero_cells"}):
        component = parse_positive_int(row["component_id"], "component_id")
        n_cells = parse_positive_int(row["n_zero_cells"], "n_zero_cells")
        status = row["connector_status"].strip()
        if not status or component in classified:
            raise ValueError("Blank or duplicate component classification")
        classified[component] = (status, n_cells)
        statuses[status] += 1
        n_classified += n_cells

    if sum(components.values()) != n_02c_rows or n_classified != n_02c_rows:
        raise ValueError("02C classified and observed zero-cell counts disagree")
    if set(components) != set(classified):
        raise ValueError("02C classification component IDs do not reconcile")
    for comp, count in components.items():
        if count != classified[comp][1]:
            raise ValueError(f"Component {comp} zero-cell count mismatch")

    route_status = collections.Counter()
    terminal_routes = collections.Counter()
    n_routes = 0
    for row in rows(directory, "02F_water_connected_route_evidence.csv",
                    {"route_status", "terminal_cell"}):
        status = row["route_status"].strip()
        if not status:
            raise ValueError("Blank route_status in 02F")
        n_routes += 1
        route_status[status] += 1
        if status == "D8_ZERO_INTERIOR":
            terminal_routes[parse_positive_int(row["terminal_cell"], "terminal_cell")] += 1

    return {
        "02c_zero_cells": n_02c_rows,
        "02c_components": len(components),
        "02c_component_classes": dict(sorted(statuses.items())),
        "02f_routes": n_routes,
        "02f_statuses": dict(sorted(route_status.items())),
        "02f_unique_zero_terminals": len(terminal_routes),
        "02f_zero_routes": sum(terminal_routes.values()),
        "02f_zero_in_02c": sum(1 for cell in terminal_routes if cell in known_components),
        "known_terminals": [
            {
                "cell": cell,
                "02f_routes": terminal_routes.get(cell, 0),
                "02c_component": known_components.get(cell),
                "02c_class": (classified[known_components[cell]][0]
                              if cell in known_components else None),
            }
            for cell in EXPECTED_TERMINALS
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline_dir", type=Path, help="Existing LOW 02_baseline directory")
    args = parser.parse_args()
    result = summarize(args.baseline_dir)
    print("========== LOW 02C + 02F EXISTING CSV SCOPE (READ ONLY) ==========")
    for k in ("02c_zero_cells", "02c_components", "02f_routes",
              "02f_zero_routes", "02f_unique_zero_terminals", "02f_zero_in_02c"):
        print(f"{k}: {result[k]}")
    print("02C COMPONENT CLASSES:", result["02c_component_classes"])
    print("02F ROUTE CLASSES:", result["02f_statuses"])
    for term in result["known_terminals"]:
        print("TERMINAL", term["cell"], "02F_ROUTES", term["02f_routes"],
              "02C_COMPONENT", term["02c_component"], "02C_CLASS", term["02c_class"])
    if result["02f_zero_routes"] != 41 or result["02f_unique_zero_terminals"] != 7:
        raise ValueError("Unexpected 02F baseline; stop rather than interpret as the pinned LOW case")
    print("NOTE: 02C samples land zeros adjacent to mapped water; it is NOT a full-raster scan.")
    print("SCIENTIFIC_STATUS: REVIEW_REQUIRED; NO D8 OR OUTLET CHANGES")
    print("========== LOW CSV SCOPE DONE ==========")


if __name__ == "__main__":
    main()
