#!/usr/bin/env python3
"""Stdlib-only supervisor. No network, raster data or CSC commands.

Every R child has a 1.5 GiB address-space ceiling. Aggregate process RSS
is stopped at 1.75 GiB, below the user's 2 GiB ceiling. A persistent report
charges every phase to the same 1200-second execution budget.
"""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import time

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
REPORT = HERE / "results.json"
BUDGET_S = 1200.0
AS_BYTES = 1536 * 1024**2
RSS_STOP_KIB = 1792 * 1024


def process_rss_kib(group):
    total = 0
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            if os.getpgid(int(entry.name)) != group:
                continue
            for line in (entry / "status").read_text().splitlines():
                if line.startswith("VmRSS:"):
                    total += int(line.split()[1])
                    break
        except (OSError, ProcessLookupError):
            pass
    return total


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (AS_BYTES, AS_BYTES))
    resource.setrlimit(resource.RLIMIT_CPU, (1190, 1190))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def save(report):
    REPORT.write_text(json.dumps(report, indent=2) + "\n")
    fields = ["phase", "name", "n", "scenario", "cap", "status", "reason", "wall_s",
              "build_s", "inventory_s", "oracle_s", "peak_rss_mib", "peak_group_rss_mib",
              "network_mib", "inventory_mib", "land", "edges", "confluences", "exits", "checks"]
    with (HERE / "results.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fields, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(report["runs"])


def run_one(report, command, metadata, allowance):
    remaining = min(BUDGET_S - report["execution_s"], report["deadline_epoch"] - time.time())
    if remaining <= 2:
        record = dict(metadata, status="NOT_RUN", reason="PACKAGE_TIME_BUDGET_EXHAUSTED")
        report["runs"].append(record)
        save(report)
        return record
    started = time.monotonic()
    env = dict(os.environ, OPENBLAS_NUM_THREADS="1", OMP_NUM_THREADS="1", MKL_NUM_THREADS="1")
    # Files are bounded local test logs; they contain only synthetic evidence.
    stem = metadata["phase"] + "_" + metadata["name"]
    log = HERE / (stem + ".log")
    attempt = 1
    while log.exists():
        attempt += 1
        log = HERE / (stem + f"_attempt{attempt}.log")
    with log.open("w") as output:
        proc = subprocess.Popen(command, cwd=REPO, env=env, stdout=output,
                                stderr=subprocess.STDOUT, start_new_session=True,
                                preexec_fn=limits)
        peak_group = 0
        stop_reason = None
        while True:
            waited, state, usage = os.wait4(proc.pid, os.WNOHANG)
            if waited:
                proc.returncode = os.waitstatus_to_exitcode(state)
                break
            peak_group = max(peak_group, process_rss_kib(proc.pid))
            elapsed = time.monotonic() - started
            if stop_reason is None and (elapsed > min(allowance, remaining - 1) or peak_group >= RSS_STOP_KIB):
                stop_reason = "MEMORY_STOP" if peak_group >= RSS_STOP_KIB else "TIME_STOP"
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                stopped_at = time.monotonic()
            elif stop_reason and time.monotonic() - stopped_at > 1:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            time.sleep(0.05)
    elapsed = time.monotonic() - started
    report["execution_s"] += elapsed
    record = dict(metadata, status="PASS" if proc.returncode == 0 and stop_reason is None else "FAIL",
                  reason=stop_reason or "", exit_code=proc.returncode, wall_s=round(elapsed, 4),
                  peak_rss_mib=round(usage.ru_maxrss / 1024, 3),
                  peak_group_rss_mib=round(peak_group / 1024, 3))
    text = log.read_text()
    record["log_raw_sha256"] = hashlib.sha256(log.read_bytes()).hexdigest()
    # Keep review transcripts whitespace-clean; the original byte digest and
    # original failure text remain available for provenance.
    normalized = "\n".join(line.rstrip() for line in text.splitlines()).rstrip()
    log.write_text(normalized + "\n" if normalized else "")
    record["log_normalized_sha256"] = hashlib.sha256(log.read_bytes()).hexdigest()
    for line in text.splitlines():
        if line.startswith("RESULT "):
            for field in line.split()[1:]:
                key, value = field.split("=", 1)
                if key not in ("n", "scenario", "cap", "status"):
                    record[key] = float(value) if "." in value else int(value)
    if metadata.get("n") and metadata.get("scenario") in ("fan", "long", "mixed", "random") and record["status"] == "PASS":
        if not any(line.startswith("RESULT ") for line in text.splitlines()):
            record.update(status="FAIL", reason="MISSING_RESULT")
        elif record.get("checks", 0) <= 0:
            record.update(status="FAIL", reason="ZERO_CHECKS")
    record["log"] = log.name
    if record["status"] == "FAIL":
        record["failure_output"] = text[-8000:]
    report["runs"].append(record)
    save(report)
    print(json.dumps(record), flush=True)
    return record


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rscript", default="Rscript")
    parser.add_argument("--phase", choices=("baseline", "baseline_fixed", "final", "optimized"), required=True)
    parser.add_argument("--sizes", nargs="+", type=int, default=[100, 1000, 10000])
    parser.add_argument("--regressions", action="store_true")
    parser.add_argument("--consider-100000", action="store_true")
    args = parser.parse_args()
    if not set(args.sizes) <= {100, 1000, 10000}:
        parser.error("100000 needs the safety gate, never an unconditional CLI size")
    report = json.loads(REPORT.read_text()) if REPORT.exists() else {
        "execution_s": 0.0, "wall_budget_s": BUDGET_S, "address_space_limit_mib": 1536,
        "aggregate_rss_stop_mib": 1792, "runs": []}
    methods = [HERE.parent / n for n in ("land_network_topology.R", "analyse_land_network_topology.R")]
    report.setdefault("sources", {})[args.phase] = {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in methods}
    # A persisted absolute deadline also charges pauses between phases. Old
    # interrupted reports use their first surviving log timestamp.
    if "deadline_epoch" not in report:
        logs = list(HERE.glob("*.log"))
        started = min((p.stat().st_mtime for p in logs), default=time.time())
        report["started_utc"] = datetime.fromtimestamp(started, timezone.utc).isoformat()
        report["deadline_epoch"] = started + BUDGET_S
    report["environment"] = {"platform": os.uname().sysname, "rscript": args.rscript,
        "parent_commit": "effab29aa4d44ecc897efc0c91c96f3bfc1b4db6",
        "generator_version": "synthetic-generator-v1", "global_route_cap": 4}
    r = args.rscript
    outcomes = []
    outcomes.append(run_one(report, ["python3", "-B", str(HERE / "test_supervisor.py")],
        dict(phase=args.phase, name="test_supervisor", scenario="regression"), 10))
    for n in args.sizes:
        for scenario in ("fan", "long", "mixed", "random"):
            metadata = dict(phase=args.phase, name=f"{scenario}_{n}", n=n, scenario=scenario, cap=4)
            outcomes.append(run_one(report, [r, "--vanilla", str(HERE / "run_case.R"), str(n), scenario, "4"], metadata, 180))
    # Complete exiting-route identity under a longer budget, separately from
    # the fixed-cap scaling series. Large graphs also get 256-step sparse probes.
    outcomes.append(run_one(report, [r, "--vanilla", str(HERE / "run_case.R"), "100", "fan", "16"],
                            dict(phase=args.phase, name="fan_complete_100", n=100, scenario="fan", cap=16), 60))
    if args.consider_100000:
        tenk = [x for x in outcomes if x.get("n") == 10000]
        safe = len(tenk) == 4 and all(x["status"] == "PASS" and
                x["peak_rss_mib"] * 15 < 1024 and x["wall_s"] * 15 <
                min(180, min(BUDGET_S - report["execution_s"], report["deadline_epoch"] - time.time()) / 4) for x in tenk)
        if safe:
            for scenario in ("fan", "long", "mixed", "random"):
                outcomes.append(run_one(report, [r, "--vanilla", str(HERE / "run_case.R"), "100000", scenario, "4"],
                    dict(phase=args.phase, name=f"{scenario}_100000", n=100000, scenario=scenario, cap=4), 180))
        else:
            report["runs"].append(dict(phase=args.phase, name="optional_100000", n=100000,
                status="NOT_RUN", reason="CONSERVATIVE_15X_TIME_OR_MEMORY_PROJECTION_NOT_SAFE"))
            save(report)
    if args.regressions:
        scripts = ["synthetic_scale/test_harness.R", "synthetic_scale/test_inventory_compatibility.R", "test_land_network_topology.R", "test_land_network_topology_inventory.R",
                   "test_one_low_network_window.R", "test_boundary_receivers.R",
                   "../land_d8_continuity/test_land_d8_route.R", "../land_first_water/test_first_water_contact.R",
                   "../low_d8_scope/test_lake_1847_focus.R", "../../tests/water_connected_route_diagnostics.R"]
        for script in scripts:
            path = (HERE.parent / script).resolve()
            outcomes.append(run_one(report, [r, "--vanilla", str(path)],
                dict(phase=args.phase, name=path.stem, scenario="regression"), 60))
    report["last_completed_utc"] = datetime.now(timezone.utc).isoformat()
    save(report)
    if not outcomes or any(x["status"] != "PASS" for x in outcomes):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
