#!/usr/bin/env python3
"""One small synthetic protocol suite; reuse the reviewed resource supervisor."""
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
base.HERE = ROOT
base.REPORT = ROOT / "results.json"
base.REPO = REPO
start = time.time()
report = json.loads(base.REPORT.read_text()) if base.REPORT.exists() else {
    "execution_s": 0.0, "runs": [],
    "parent_commit": "08a7b17f856aa266cd989a3c9c2bb9734e623900",
    "started_utc": datetime.fromtimestamp(start, timezone.utc).isoformat(),
    "deadline_epoch": start + 1200,
    "wall_budget_s": 1200, "test_timeout_s": 120,
    "address_space_limit_mib": 1536, "aggregate_rss_stop_mib": 1792,
}
sources = [ROOT / "messages.R", *HERE.glob("*.R"), Path(__file__)]
report.setdefault("source_snapshots", []).append({
    str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(sources)
})
record = base.run_one(report, [os.environ.get("MM_RSCRIPT", "Rscript"), "--vanilla",
                             str(HERE / "test_protocol.R")],
                      {"phase": "targeted", "name": "protocol", "n": 27, "scenario": "receipts"}, 120)
if record["status"] == "PASS" and (record.get("checks", 0) <= 0 or record.get("cases", 0) <= 0):
    record.update(status="FAIL", reason="ZERO_TESTS_OR_MISSING_RESULT")
report["last_completed_utc"] = datetime.now(timezone.utc).isoformat()
base.save(report)
sys.exit(0 if record["status"] == "PASS" else 1)
