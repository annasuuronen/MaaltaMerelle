#!/usr/bin/env python3
"""Only the new <=27-position suite, with a cumulative 120 s execution budget."""
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
REPO = ROOT.parents[1]
path = REPO / "diagnostics/land_network_topology/synthetic_scale/run_validation.py"
spec = importlib.util.spec_from_file_location("supervisor", path)
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
base.HERE, base.REPO, base.REPORT = ROOT, REPO, ROOT / "results.json"
base.BUDGET_S = 120.0
report = json.loads(base.REPORT.read_text()) if base.REPORT.exists() else {
    "parent_commit": "35808cf6fea0b74dcdc878ec9fb9629ee66f8ea5",
    "started_utc": datetime.now(timezone.utc).isoformat(), "execution_s": 0.0,
    "execution_budget_s": 120, "address_space_limit_mib": 1536,
    "sampled_group_rss_stop_mib": 1792, "max_grid_positions": 27,
    "max_owned_land_sources": 11, "runs": [],
    "not_run": ["previous_regression_campaigns", "1000_cells", "10000_cells", "real_rasters", "CSC"],
}
# Reinvocation never resets charged execution time; coding pauses are not tests.
report["deadline_epoch"] = time.time() + max(0, 120.0 - report["execution_s"])
files = [ROOT / "count_core.R", *HERE.glob("*.R"), Path(__file__)]
report.setdefault("source_snapshots", []).append({
    str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)
})
record = base.run_one(report, [os.environ.get("MM_RSCRIPT", "Rscript"), "--vanilla",
                             str(HERE / "test_count_core.R")],
                      {"phase": "targeted", "name": "count_core", "n": 27, "scenario": "complete_dag"}, 120)
if record["status"] == "PASS" and (record.get("checks", 0) <= 0 or record.get("cases", 0) <= 0):
    record.update(status="FAIL", reason="ZERO_TESTS_OR_MISSING_RESULT")
report["last_completed_utc"] = datetime.now(timezone.utc).isoformat()
base.save(report)
sys.exit(0 if record["status"] == "PASS" else 1)
