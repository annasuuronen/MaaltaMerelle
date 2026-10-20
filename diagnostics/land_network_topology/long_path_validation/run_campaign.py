#!/usr/bin/env python3
"""Reuse the pinned synthetic supervisor; no CSC, raster or workflow commands."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import time

HERE = Path(__file__).resolve().parent
SUPERVISOR = HERE.parent / "synthetic_scale" / "run_validation.py"
spec = importlib.util.spec_from_file_location("scale_supervisor", SUPERVISOR)
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
# Only output locations change. All address-space/RSS/time limits are reused.
base.HERE = HERE
base.REPORT = HERE / "results.json"
PIN = "01485c080cab48fadece38f30dc8526f6b575b40"
# Selected before any outcomes: exactly one possible new 10k/cap16 long case.
SELECTED_C = {"n": 10000, "scenario": "long", "cap": 16}


def execute(report, command, metadata, allowance=180):
    record = base.run_one(report, command, metadata, min(180, allowance))
    if "STOP_BASELINE_MISMATCH" in record.get("failure_output", ""):
        report["stop_reason"] = "STOP_BASELINE_MISMATCH"
        base.save(report)
        raise SystemExit("Pinned baseline differs; inspect before any continuation")
    return record


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rscript", default="Rscript")
    parser.add_argument("--section", choices=("all", "A", "B", "regressions"), default="all")
    args = parser.parse_args()
    if base.REPORT.exists():
        report = json.loads(base.REPORT.read_text())
    else:
        now = time.time()
        report = {"execution_s": 0.0, "wall_budget_s": 1200, "deadline_epoch": now + 1200,
            "started_utc": datetime.fromtimestamp(now, timezone.utc).isoformat(),
            "address_space_limit_mib": 1536, "aggregate_rss_stop_mib": 1792,
            "parent_commit": PIN, "comparison_commit": "effab29aa4d44ecc897efc0c91c96f3bfc1b4db6",
            "selected_optional_case": SELECTED_C, "runs": []}
    files = [p for p in HERE.iterdir() if p.suffix in (".R", ".py")]
    files += [SUPERVISOR, HERE.parent / "synthetic_scale" / "generator.R",
              HERE.parent / "synthetic_scale" / "oracle.R",
              HERE.parent / "analyse_land_network_topology.R"]
    source_hashes = {str(p.relative_to(base.REPO)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    report.setdefault("attempt_sources", []).append({"section": args.section, "sha256": source_hashes})
    report["R_version"] = subprocess.check_output([args.rscript, "--version"], text=True).strip()
    base.save(report)
    outcomes = []
    a = []
    if args.section in ("A", "all"):
        for n in (100, 1000):
            for scenario in ("fan", "long", "mixed", "random"):
                metadata = dict(phase="A", name=f"{scenario}_{n}_caps_4_16_32",
                    n=n, scenario=scenario, cap="4,16,32")
                record = execute(report, [args.rscript, "--vanilla", str(HERE / "run_case.R"), str(n), scenario], metadata)
                outcomes.append(record); a.append(record)
    if args.section in ("B", "all"):
        outcomes.append(execute(report, [args.rscript, "--vanilla", str(HERE / "test_long_paths.R")],
            dict(phase="B", name="sparse_and_serial", n=1000, scenario="sparse", cap=256)))
    if args.section == "all":
        calibration = next((x for x in a if x["n"] == 1000 and x["scenario"] == "long"), None)
        remaining = min(1200 - report["execution_s"], report["deadline_epoch"] - time.time())
        # Deliberately conservative upper bound from the complete 1k three-cap
        # worker. 10x cells times 1.5 headroom; never subtract observed overhead.
        projected_mib = max(calibration.get("peak_rss_mib", 0), calibration.get("peak_group_rss_mib", 0)) * 15 if calibration else None
        projected_s = calibration.get("wall_s", 0) * 15 if calibration else None
        gate = len(a) == 8 and all(x["status"] == "PASS" for x in outcomes) and calibration and \
            projected_mib < 1024 and projected_s < 180 and remaining > projected_s + 90
        report["optional_gate"] = {"selected_case": SELECTED_C, "calibration": "A/long_1000_caps_4_16_32",
            "factor": 15, "projected_rss_mib": projected_mib, "projected_s": projected_s,
            "remaining_s": remaining, "projection_scope": "entire three-cap worker, conservative upper bound",
            "decision": "RUN" if gate else "NOT_RUN_RESOURCE_GATE"}
        if gate:
            outcomes.append(execute(report, [args.rscript, "--vanilla", str(HERE / "run_case.R"), "10000", "long", "16"],
                dict(phase="C", name="long_10000_cap_16", **SELECTED_C)))
        else:
            report["runs"].append(dict(phase="C", name="long_10000_cap_16", **SELECTED_C,
                status="NOT_RUN_RESOURCE_GATE", reason="RESOURCE_HEADROOM_NOT_ESTABLISHED"))
            base.save(report)
    if args.section in ("regressions", "all"):
        rfiles = ["test_land_network_topology.R", "test_land_network_topology_inventory.R",
            "test_one_low_network_window.R", "test_boundary_receivers.R",
            "../land_d8_continuity/test_land_d8_route.R", "../land_first_water/test_first_water_contact.R",
            "../low_d8_scope/test_lake_1847_focus.R", "../../tests/water_connected_route_diagnostics.R",
            "synthetic_scale/test_harness.R", "synthetic_scale/test_inventory_compatibility.R"]
        for name in rfiles:
            path = (HERE.parent / name).resolve()
            outcomes.append(execute(report, [args.rscript, "--vanilla", str(path)],
                dict(phase="regressions", name=path.stem, scenario="regression"), 60))
        outcomes.append(execute(report, ["python3", "-B", str(HERE.parent / "synthetic_scale" / "test_supervisor.py")],
            dict(phase="regressions", name="test_supervisor", scenario="regression"), 10))
    report["last_completed_utc"] = datetime.now(timezone.utc).isoformat()
    base.save(report)
    if not outcomes or any(x["status"] != "PASS" for x in outcomes):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
