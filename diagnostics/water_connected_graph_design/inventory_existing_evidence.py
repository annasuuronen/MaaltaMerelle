#!/usr/bin/env python3
"""Read-only cross-table evidence inventory for existing LOW 02D.8/02D/02E/02F CSV outputs.

No raster reads, tracing, candidate approval, outlet selection or accumulation.
Only writes derived summaries to a new, separately provided output directory.
"""
import argparse
import csv
import hashlib
import json
import math
import os
from collections import Counter, defaultdict
from pathlib import Path

FILES = {
    "groups": "02D8_final_spill_evidence.csv",
    "shore": "02D_lowest_spill_shore_edges.csv",
    "candidates": "02E_water_connected_candidate_evidence.csv",
    "candidate_edges": "02E_water_connected_candidate_spill_edges.csv",
    "routes": "02F_water_connected_candidate_route_edges.csv",
}
FIELDS = {
    "groups": {"spill_group_id", "lake_objectid", "spill_level_m", "has_external_evidence",
               "needs_review", "evidence_status", "outlet_selection"},
    "shore": {"spill_group_id", "lake_objectid", "source_cell", "receiver_cell",
              "storage_step_level_m", "receiver_type"},
    "candidates": {"spill_group_id", "lake_objectid", "spill_level_m",
                   "evidence_status", "needs_review", "candidate_included",
                   "outlet_selection", "water_connected_candidate_status"},
    "candidate_edges": {"spill_group_id", "lake_objectid", "source_cell", "receiver_cell"},
    "routes": {"spill_group_id", "lake_objectid", "source_cell", "receiver_cell",
               "route_id", "route_status", "route_terminal_cell",
               "terminal_water_class", "terminal_lake_objectid"},
}
STATUS = {
    "RETURNS_TO_ORIGIN_LAKE", "REACHES_OTHER_LAKE",
    "REACHES_RIVER_AREA", "REACHES_RIVER_LINE", "D8_CYCLE",
    "START_OUTSIDE_RASTER", "D8_DOMAIN_EXIT", "D8_ZERO_AT_RASTER_EDGE",
    "D8_ZERO_INTERIOR", "D8_POINTER_NA", "D8_POINTER_INVALID",
    "INVALID_WATER_CLASS", "LAKE_ID_MISSING", "STEP_LIMIT",
}
WATER_FIRST = {"REACHES_OTHER_LAKE", "REACHES_RIVER_AREA", "REACHES_RIVER_LINE"}
GRID = 6000
MAX_FILE_BYTES = 15_000_000
MAX_ROWS = 200_000


class EvidenceError(ValueError):
    pass


def require(ok, msg):
    if not ok:
        raise EvidenceError("STOP: " + msg)


def number(raw, kind="id"):
    try:
        if raw is None or raw.strip() in {"", "NA", "NaN"}:
            raise ValueError()
        v = float(raw)
    except (ValueError, TypeError, OverflowError):
        raise EvidenceError("STOP: MALFORMED_" + kind)
    require(math.isfinite(v), "NONFINITE_" + kind)
    if kind == "id":
        require(v.is_integer() and 1 <= v <= GRID * GRID, "INVALID_ID")
        return int(v)
    return v


def truth(x):
    require(x in ("TRUE", "FALSE"), "INVALID_BOOLEAN")
    return x == "TRUE"


def edge_key(row):
    return (number(row["spill_group_id"]), number(row["lake_objectid"]),
            number(row["source_cell"]), number(row["receiver_cell"]))


def group_key(row):
    return number(row["spill_group_id"])


def geom(source, receiver):
    r1, c1 = divmod(source - 1, GRID)
    r2, c2 = divmod(receiver - 1, GRID)
    dr, dc = abs(r2 - r1), abs(c2 - c1)
    require(max(dr, dc) == 1, "NON_ADJACENT_SHORE_EDGE")
    return dr == 1 and dc == 1


def read_csv(path, required):
    require(path.is_file() and not path.is_symlink(), "MISSING_OR_SYMLINK_" + path.name)
    require(0 < path.stat().st_size <= MAX_FILE_BYTES, "FILE_SIZE_LIMIT_" + path.name)
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            digest.update(block)
    with path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        require(reader.fieldnames is not None and len(reader.fieldnames) ==
                len(set(reader.fieldnames)) and required <= set(reader.fieldnames),
                "CSV_SCHEMA_" + path.name)
        rows = []
        for row in reader:
            require(len(rows) < MAX_ROWS, "CSV_ROW_LIMIT_" + path.name)
            require(None not in row and all(x is not None for x in row.values()),
                    "CSV_RAGGED_" + path.name)
            rows.append(row)
    return rows, digest.hexdigest()


def evaluate(data):
    groups = {}
    for row in data["groups"]:
        g = group_key(row)
        require(g not in groups, "DUPLICATE_GROUP")
        number(row["lake_objectid"])
        number(row["spill_level_m"], kind="level")
        require(row["outlet_selection"] == "UNASSIGNED", "REAL_OUTLET_SELECTION_FORBIDDEN")
        needs, external = truth(row["needs_review"]), truth(row["has_external_evidence"])
        expected = "REVIEW_REQUIRED" if needs else ("EXTERNAL_EVIDENCE" if external else "NO_EXTERNAL_EVIDENCE")
        require(row["evidence_status"] == expected, "GROUP_STATUS_INCONSISTENT")
        groups[g] = row
    require(groups, "EMPTY_GROUP_EVIDENCE")

    candidates = {}
    for row in data["candidates"]:
        g = group_key(row)
        require(g in groups and g not in candidates, "CANDIDATE_GROUP_KEY")
        original = groups[g]
        require(number(row["lake_objectid"]) == number(original["lake_objectid"]),
                "CANDIDATE_LAKE_MISMATCH")
        require(abs(number(row["spill_level_m"],kind="level") -
                    number(original["spill_level_m"],kind="level")) <= 1e-9,
                "CANDIDATE_LEVEL_MISMATCH")
        require(row["evidence_status"] == original["evidence_status"] and
                row["outlet_selection"] == "UNASSIGNED" and
                truth(row["needs_review"]) == truth(original["needs_review"]),
                "CANDIDATE_STATUS_MISMATCH")
        inc = truth(row["candidate_included"])
        require(inc == (original["evidence_status"] == "EXTERNAL_EVIDENCE" and
                         not truth(original["needs_review"])), "CANDIDATE_FLAG_MISMATCH")
        expected = "INCLUDED_PARALLEL_CANDIDATE" if inc else (
            "REVIEW_REQUIRED" if truth(original["needs_review"]) else "NO_EXTERNAL_EVIDENCE")
        require(row["water_connected_candidate_status"] == expected,
                "CANDIDATE_STATUS_INVALID")
        candidates[g] = row
    require(set(candidates) == set(groups), "MISSING_02E_GROUPS")

    shore, eligible = {}, {}
    for kind in ("shore", "candidate_edges"):
        target = shore if kind == "shore" else eligible
        for row in data[kind]:
            key = edge_key(row)
            g, lake, source, receiver = key
            require(g in groups and lake == number(groups[g]["lake_objectid"]),
                    "EDGE_GROUP_OR_LAKE_MISMATCH")
            geom(source, receiver)
            require(key not in target, "DUPLICATE_EDGE_" + kind)
            if kind == "shore":
                require(math.isfinite(number(row["storage_step_level_m"], kind="level")),
                        "INVALID_SHORE_STORAGE_LEVEL")
                require(row["receiver_type"] in {"LAND", "OTHER_LAKE", "RIVER_AREA", "RIVER_LINE"},
                        "INVALID_RECEIVER_TYPE")
            else:
                require(truth(candidates[g]["candidate_included"]),
                        "INELIGIBLE_CANDIDATE_EDGE")
                require(key in shore, "CANDIDATE_EDGE_NOT_IN_SHORE")
            target[key] = row
    require(shore, "EMPTY_LOWEST_SHORE_EVIDENCE")
    require({k[0] for k in shore} == set(groups), "SHORE_GROUP_COVERAGE_MISMATCH")
    expected_keys = {k for k in shore if truth(candidates[k[0]]["candidate_included"])}
    require(set(eligible) == expected_keys, "CANDIDATE_EDGE_COVERAGE_MISMATCH")

    routes = {}
    for row in data["routes"]:
        key = edge_key(row)
        require(key in eligible and key not in routes, "ROUTE_EDGE_COVERAGE_OR_DUPLICATE")
        route_id = number(row["route_id"])
        require(row["route_status"] in STATUS, "UNKNOWN_ROUTE_STATUS")
        terminal = number(row["route_terminal_cell"])
        cls = row["terminal_water_class"]
        target = row["terminal_lake_objectid"]
        status = row["route_status"]
        if status in WATER_FIRST or status == "RETURNS_TO_ORIGIN_LAKE":
            expected_cls = {"REACHES_OTHER_LAKE": "1",
                            "RETURNS_TO_ORIGIN_LAKE": "1",
                            "REACHES_RIVER_AREA": "2",
                            "REACHES_RIVER_LINE": "3"}[status]
            require(cls == expected_cls, "TERMINAL_WATER_CLASS_MISMATCH")
            if expected_cls == "1":
                target_id = number(target)
                origin = key[1]
                require((target_id == origin) == (status == "RETURNS_TO_ORIGIN_LAKE"),
                        "TERMINAL_LAKE_RELATION")
        routes[key] = row
    require(set(routes) == set(eligible), "MISSING_02F_ROUTE_EDGES")
    # 02F deduplicates traces per (receiver_cell, origin_lake), not per spill group.
    trace_ids = {}
    for key, row in routes.items():
        trace_key = (key[1], key[3])
        signature = (row["route_id"], row["route_status"],
                     row["route_terminal_cell"], row["terminal_water_class"],
                     row["terminal_lake_objectid"])
        require(trace_key not in trace_ids or trace_ids[trace_key] == signature,
                "SAME_RECEIVER_DIFFERENT_TRACE")
        trace_ids[trace_key] = signature

    bygroup = defaultdict(list)
    bycand = defaultdict(list)
    for key in shore: bygroup[key[0]].append(key)
    for key in eligible: bycand[key[0]].append(key)
    group_rows = []
    for gid in sorted(groups):
        g = groups[gid]
        keys = bygroup[gid]
        ckeys = bycand[gid]
        statuses = Counter(routes[key]["route_status"] for key in ckeys)
        n_water = sum(statuses[s] for s in WATER_FIRST)
        if g["evidence_status"] == "REVIEW_REQUIRED":
            case = "EVIDENCE_REVIEW_REQUIRED"
        elif g["evidence_status"] == "NO_EXTERNAL_EVIDENCE":
            case = "NO_EXTERNAL_EVIDENCE"
        elif n_water == len(ckeys):
            case = "FIRST_WATER_CONTACT_ONLY"
        else:
            case = "MIXED_OR_UNRESOLVED_FIRST_WATER"
        group_rows.append({
            "lake_objectid":number(g["lake_objectid"]),
            "spill_group_id":gid, "evidence_status":g["evidence_status"],
            "outlet_selection":"UNASSIGNED",
            "candidate_included":truth(candidates[gid]["candidate_included"]),
            "n_lowest_spill_edges":len(keys),
            "n_diagonal_shore_edges":sum(geom(k[2],k[3]) for k in keys),
            "n_candidate_edges":len(ckeys),
            "n_first_water_contact_edges":n_water,
            "n_other_outcome_edges":len(ckeys)-n_water,
            "route_status_counts":";".join(f"{s}:{statuses[s]}" for s in sorted(statuses)),
            "inventory_case":case,
            "fully_connected_to_sea":"NOT_ASSESSED",
            "hydrological_validation":"NOT_ASSESSED",
        })

    bylake = defaultdict(list)
    for row in group_rows: bylake[row["lake_objectid"]].append(row)
    lake_rows = []
    for lake, rows in sorted(bylake.items()):
        classes = Counter(row["inventory_case"] for row in rows)
        lake_rows.append({
            "lake_objectid":lake, "n_spill_groups":len(rows),
            "n_included_candidate_groups":sum(row["candidate_included"] for row in rows),
            "n_review_groups":classes["EVIDENCE_REVIEW_REQUIRED"],
            "n_no_external_groups":classes["NO_EXTERNAL_EVIDENCE"],
            "n_first_water_only_groups":classes["FIRST_WATER_CONTACT_ONLY"],
            "n_mixed_or_unresolved_groups":classes["MIXED_OR_UNRESOLVED_FIRST_WATER"],
            "n_lowest_spill_edges":sum(row["n_lowest_spill_edges"] for row in rows),
            "n_candidate_edges":sum(row["n_candidate_edges"] for row in rows),
            "outlet_selection":"UNASSIGNED",
            "complete_downstream_network":"NOT_ASSESSED",
        })
    return group_rows,lake_rows,{
        "n_lakes_with_spill_evidence":len(lake_rows),
        "n_spill_groups":len(group_rows),
        "n_lowest_spill_edges":len(shore),
        "n_diagonal_shore_edges":sum(row["n_diagonal_shore_edges"] for row in group_rows),
        "n_candidate_edges":len(eligible),
        "n_02f_edge_routes":len(routes),
        "n_unique_02f_origin_receiver_traces":len(trace_ids),
        "n_first_water_contact_edge_routes":sum(row["n_first_water_contact_edges"] for row in group_rows),
        "n_not_first_water_contact_edge_routes":sum(row["n_other_outcome_edges"] for row in group_rows),
        "n_lakes_with_multiple_included_candidate_groups":
            sum(row["n_included_candidate_groups"] > 1 for row in lake_rows),
        "n_lakes_with_review_groups":sum(row["n_review_groups"] > 0 for row in lake_rows),
        "outlets_selected":0, "downstream_to_sea_validated":0,
        "verified_outlet_count":"NOT_ASSESSED",
        "hydrological_corrections_needed":"NOT_ESTIMABLE",
        "flow_accumulation":"NOT_COMPUTED",
        "hydrological_validation":"NOT_ASSESSED",
        "channel_interpretation":"NOT_ASSESSED",
        "MODERATE":"REVIEW_REQUIRED","NATIONAL":"LOCKED",
        "warning":"First-water contact is not a validated outlet or route to sea; 8-neighbour diagonal not proof of corner-only vector connection.",
    }


def execute(input_dir, output_dir, evidence_label):
    require(input_dir.is_dir() and output_dir != input_dir and
            not output_dir.exists(), "INPUT_MISSING_OR_OUTPUT_EXISTS")
    require(evidence_label and len(evidence_label) <= 180, "EVIDENCE_LABEL_REQUIRED")
    values, hashes = {}, {}
    for role, name in FILES.items():
        values[role], hashes[name] = read_csv(input_dir / name, FIELDS[role])
    groups,lakes,summary = evaluate(values)
    summary["evidence_label_operator_supplied_unverified"] = evidence_label
    summary["sha256_input_csv"] = hashes
    summary["csv_file_row_counts"] = {FILES[role]:len(v) for role,v in values.items()}
    # Prevent source-tree or existing-file overwrite by requiring nonexistent output dir.
    output_dir.mkdir(mode=0o700, parents=False, exist_ok=False)
    for name,table in (("spill_group_inventory.csv",groups),("lake_inventory.csv",lakes)):
        with (output_dir/name).open("x",newline="",encoding="utf-8") as f:
            w=csv.DictWriter(f,fieldnames=list(table[0]))
            w.writeheader();w.writerows(table)
    with (output_dir/"summary.json").open("x",encoding="utf-8") as f:
        json.dump(summary,f,indent=2,sort_keys=True);f.write("\n")
    return summary


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input-dir",type=Path,required=True)
    p.add_argument("--output-dir",type=Path,required=True)
    p.add_argument("--evidence-label",required=True)
    a=p.parse_args()
    report=execute(a.input_dir,a.output_dir,a.evidence_label)
    print("=== TULOKSET ALKAVAT ===")
    print(json.dumps(report,indent=2,sort_keys=True))
    print("=== TULOKSET LOPPUVAT ===")


if __name__=="__main__":
    try: main()
    except (EvidenceError,OSError,ValueError) as exc:
        raise SystemExit(str(exc) if str(exc).startswith("STOP:") else "STOP: " + str(exc))
