#!/usr/bin/env python3
"""Bounded Linux offline supervisor. No network, CSC or real raster access."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import time

HERE = Path(__file__).resolve().parent
BRANCH = "codex/low-pr22-receiver-evidence-one-shot-v1"
PR22 = "effab29aa4d44ecc897efc0c91c96f3bfc1b4db6"
PR32 = "fb5c673b5fb08652e846191074095627b364d7db"
PR32_DIR = "diagnostics/02g_complete_local_dag_core"
ORIGIN = "https://github.com/annasuuronen/MaaltaMerelle.git"
MEMORY_BYTES = 2 * 1024**3
TOTAL_SECONDS = 300
ACTIVE_DEADLINE = None
MAX_LOG_BYTES = 4 * 1024**2
SUITES = ("observations", "supervisor", "terra_compatibility", "pr32_separate_dag")
CHILD_ENV = {"PYTHONDONTWRITEBYTECODE": "1", "OMP_NUM_THREADS": "1",
             "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
             "NUMEXPR_NUM_THREADS": "1", "GDAL_NUM_THREADS": "1"}


class Stop(RuntimeError):
    pass


class Arguments(argparse.ArgumentParser):
    def error(self, message):
        raise Stop("ARGUMENT_ERROR: "+message)


def git(repo, *args):
    remaining = 10 if ACTIVE_DEADLINE is None else min(10, ACTIVE_DEADLINE-time.monotonic())
    if remaining <= 0:
        raise Stop("TOTAL_TIME_LIMIT")
    try:
        return subprocess.check_output(["git", "-C", str(repo), *args],
                                       stderr=subprocess.STDOUT, timeout=remaining).decode().strip()
    except (OSError, subprocess.SubprocessError) as exc:
        raise Stop("LOCAL_GIT_CHECK_FAILED") from exc


def snapshot(repo):
    result = {}
    for name in filter(None, git(repo, "ls-files", "-z").split("\0")):
        p = repo / name
        if p.is_symlink() or not p.is_file():
            raise Stop("TRACKED_REGULAR_FILES_REQUIRED")
        result[name] = hashlib.sha256(p.read_bytes()).hexdigest()
    return result


def checkout(repo, expected, branch=None):
    if not re.fullmatch(r"[0-9a-f]{40}", expected or ""):
        raise Stop("EXPECTED_FULL_COMMIT_REQUIRED")
    if git(repo, "rev-parse", "HEAD") != expected:
        raise Stop("EXPECTED_COMMIT_MISMATCH")
    if git(repo, "remote", "get-url", "origin") != ORIGIN:
        raise Stop("ORIGIN_MISMATCH")
    if branch and git(repo, "branch", "--show-current") != branch:
        raise Stop("WRONG_BRANCH")
    if git(repo, "status", "--porcelain=v1", "--untracked-files=all", "--ignored"):
        raise Stop("DIRTY_CHECKOUT")
    return snapshot(repo)


def process_tree(pgid):
    """Include descendants even if a wrapper creates a new process group."""
    processes = {}
    for p in Path("/proc").iterdir():
        if not p.name.isdigit():
            continue
        try:
            stat = (p / "stat").read_text().rsplit(")", 1)[1].split()
            processes[int(p.name)] = (int(stat[1]), int(stat[2]),
                                     max(0, int(stat[21])) * os.sysconf("SC_PAGE_SIZE"))
        except (FileNotFoundError, ProcessLookupError):
            continue
        except (PermissionError, ValueError, IndexError) as exc:
            raise Stop("MEMORY_OBSERVATION_UNAVAILABLE") from exc
    selected = {pid for pid, (_, group, _) in processes.items() if group == pgid or pid == pgid}
    while True:
        more = {pid for pid, (parent, _, _) in processes.items() if parent in selected}
        if more <= selected:
            break
        selected.update(more)
    return {pid: processes[pid][2] for pid in selected}


def group_rss(pgid):
    return sum(process_tree(pgid).values())


def kill_group(pgid):
    try:
        descendants = process_tree(pgid)
    except Stop:
        descendants = {}  # Still stop the known process group on /proc errors.
    for pid in descendants:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    try:
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def bounded(command, log, cwd, seconds, deadline, memory=MEMORY_BYTES):
    started = time.monotonic()
    peak = 0
    reason = None
    with log.open("xb") as stream:
        try:
            proc = subprocess.Popen(command, cwd=cwd, env=dict(os.environ, **CHILD_ENV),
                                    stdout=stream, stderr=subprocess.STDOUT,
                                    start_new_session=True)
        except OSError:
            return {"status": "FAIL", "reason": "DEPENDENCY_EXEC_FAILED", "seconds": 0,
                    "peak_rss_bytes": 0, "returncode": None}
        try:
            while True:
                peak = max(peak, group_rss(proc.pid))
                if peak > memory:
                    reason = "MEMORY_LIMIT"
                elif time.monotonic() >= min(started + seconds, deadline):
                    reason = "TIME_LIMIT"
                elif log.stat().st_size > MAX_LOG_BYTES:
                    reason = "LOG_LIMIT"
                if reason or proc.poll() is not None:
                    break
                time.sleep(0.02)
        except BaseException:
            kill_group(proc.pid)
            proc.wait()
            raise
        finally:
            # Includes children left behind after parent exit. Never auto-retry.
            kill_group(proc.pid)
        rc = proc.wait()
    return {"status": "PASS" if not reason and rc == 0 else "FAIL",
            "reason": reason or ("EXIT_ZERO" if rc == 0 else "NONZERO_EXIT"),
            "seconds": round(time.monotonic()-started, 4), "peak_rss_bytes": peak,
            "returncode": rc}


def require_summary(text):
    rows = re.findall(r"^SUITE_RESULT cases=(\d+) pass=(\d+) fail=(\d+) not_run=(\d+)$", text, re.M)
    if len(rows) != 1:
        raise Stop("MISSING_OR_DUPLICATE_TEST_SUMMARY")
    cases, passed, failed, not_run = map(int, rows[0])
    if cases == 0 or cases != passed+failed+not_run or failed or not_run:
        raise Stop("ZERO_FAILED_OR_PARTIAL_TESTS")
    return {"cases": cases, "pass": passed, "fail": failed, "not_run": not_run}


def require_pr32_summary(text):
    rows = re.findall(r"^RESULT n=27 scenario=complete_dag cases=(\d+) checks=(\d+) stop_cases=(\d+) status=PASS$", text, re.M)
    if len(rows) != 1 or tuple(map(int, rows[0])) != (15,739,53):
        raise Stop("PR32_PINNED_SUMMARY_MISMATCH")
    return {"cases": 15, "checks": 739, "expected_stops": 53}


def deadline_stop(signum, frame):
    raise Stop("TOTAL_TIME_LIMIT_OR_TERMINATED")


def prepare_pr32(repo, destination):
    """Pinned unit copied to scratch: its existing R tests write example CSVs."""
    archive = destination / "pr32.tar"
    with archive.open("xb") as f:
        subprocess.run(["git", "-C", str(repo), "archive", PR32, PR32_DIR],
                       stdout=f, stderr=subprocess.PIPE, check=True, timeout=10)
    root = destination / "pr32_disposable"
    root.mkdir()
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            p = Path(member.name)
            if p.is_absolute() or ".." in p.parts or not (member.isdir() or member.isfile()):
                raise Stop("UNSAFE_PR32_ARCHIVE")
        if hasattr(tarfile, "data_filter"):
            tar.extractall(root, filter="data")
        else:
            # Python 3.8: all entries were already checked as relative regular
            # files/directories from the pinned Git archive into a fresh root.
            tar.extractall(root)
    return root / PR32_DIR


def main(argv=None):
    global ACTIVE_DEADLINE
    print("========== TULOKSET ALKAVAT ==========", flush=True)
    started = time.monotonic()
    # Leave time for post-run source checks and the final report.
    deadline = started + TOTAL_SECONDS - 30
    previous_deadline = ACTIVE_DEADLINE
    ACTIVE_DEADLINE = started + TOTAL_SECONDS
    repo = HERE.parent.parent
    records = {name: {"status": "NOT_RUN", "reason": "NOT_STARTED"} for name in SUITES}
    summary = {"schema_version": 1, "mode": "OFFLINE_SYNTHETIC_ONLY", "commit": None,
               "pr32_commit": None,
               "limits": {"total_seconds": TOTAL_SECONDS, "aggregate_rss_bytes": MEMORY_BYTES,
                          "poll_seconds": 0.02, "log_bytes_per_suite": MAX_LOG_BYTES},
               "rss_measurement": "SAMPLED_PROCESS_GROUP_SUM_SHARED_PAGES_COUNTED_PER_PROCESS",
               "hydrological_validation": "NOT_ASSESSED", "channel_interpretation": "NOT_ASSESSED",
               "MODERATE": "REVIEW_REQUIRED", "NATIONAL": "LOCKED", "suites": records}
    output = None
    originals = {}
    fatal = None
    previous_alarm = signal.signal(signal.SIGALRM, deadline_stop)
    previous_term = signal.signal(signal.SIGTERM, deadline_stop)
    signal.setitimer(signal.ITIMER_REAL, TOTAL_SECONDS)
    try:
        parser = Arguments()
        parser.add_argument("--expected-commit", required=True)
        parser.add_argument("--report-dir", type=Path, required=True)
        parser.add_argument("--pr32-repo", type=Path)
        parser.add_argument("--expected-r-version")
        parser.add_argument("--expected-terra-version")
        args = parser.parse_args(argv)
        summary.update(commit=args.expected_commit, pr32_commit=PR32 if args.pr32_repo else None)
        originals[repo] = (args.expected_commit, BRANCH, checkout(repo, args.expected_commit, BRANCH))
        if git(repo, "merge-base", PR22, args.expected_commit) != PR22:
            raise Stop("PR22_BASE_NOT_ANCESTOR")
        from test_observed_receivers import audit_provenance
        summary["observation_provenance"] = audit_provenance()
        summary["test_sources_sha256"] = {
            name: digest for name, digest in originals[repo][2].items()
            if name.startswith("diagnostics/low_receiver_evidence/")
            and name.endswith((".py", ".R", ".sh", ".json", ".csv"))}
        candidate = args.report_dir.absolute()
        sources = [repo]
        if args.pr32_repo:
            pr32_repo = args.pr32_repo.resolve(strict=True)
            if pr32_repo == repo:
                raise Stop("SEPARATE_PR32_CHECKOUT_REQUIRED")
            originals[pr32_repo] = (PR32, None, checkout(pr32_repo, PR32))
            sources.append(pr32_repo)
        if candidate.resolve() != candidate or any(candidate == p or p in candidate.parents for p in sources):
            raise Stop("REPORT_PATH_MUST_BE_EXTERNAL_AND_UNLINKED")
        candidate.mkdir(mode=0o700)  # exclusive: no repeat/overwrite of this run
        output = candidate
        if not Path("/proc/self/stat").is_file() or group_rss(os.getpgrp()) <= 0:
            raise Stop("LINUX_RSS_OBSERVATION_REQUIRED")
        summary["python"] = sys.version.split()[0]
        rscript = shutil.which("Rscript")
        print("MODE=OFFLINE_SYNTHETIC_ONLY NO_REAL_RASTER_READ NO_CSC_CONNECTION", flush=True)
        print("COMMIT="+args.expected_commit+" REPORT_DIR="+str(output), flush=True)

        def run(name, command, seconds, parse=True):
            if any(r.get("reason") == "MEMORY_LIMIT" for r in records.values()):
                records[name] = {"status": "NOT_RUN", "reason": "MEMORY_STOP"}
                return
            if time.monotonic() >= deadline:
                records[name] = {"status": "NOT_RUN", "reason": "TOTAL_TIME_LIMIT"}
                return
            log = output / (name+".log")
            record = bounded(command, log, output, seconds, deadline)
            text = log.read_text(errors="replace")
            if parse and record["status"] == "PASS":
                try:
                    check = require_summary if parse is True else parse
                    record.update(check(text))
                except Stop as exc:
                    record.update(status="FAIL", reason=str(exc))
            records[name] = record
            print("SUITE="+name+" "+json.dumps(record, sort_keys=True), flush=True)
            # Child logs cannot duplicate the top-level opening marker.

        run("observations", [sys.executable, "-B", str(HERE/"test_observed_receivers.py")], 45)
        run("supervisor", [sys.executable, "-B", str(HERE/"test_one_shot.py")], 60)
        if not rscript:
            for name in ("terra_compatibility", "pr32_separate_dag"):
                records[name] = {"status": "NOT_RUN", "reason": "RSCRIPT_MISSING"}
        else:
            if any(r.get("reason") == "MEMORY_LIMIT" for r in records.values()):
                raise Stop("MEMORY_LIMIT_NO_MORE_CHILDREN")
            probe = bounded([rscript, "--vanilla", "-e",
                'cat("R_VERSION=",as.character(getRversion()),"\\n",sep=""); '
                'stopifnot(requireNamespace("terra",quietly=TRUE)); '
                'cat("TERRA_VERSION=",as.character(packageVersion("terra")),"\\n",sep="")'],
                output/"r_dependencies.log", output, 30, deadline)
            summary["r_dependencies"] = probe
            summary["r_versions_output"] = (output/"r_dependencies.log").read_text(errors="replace")
            if probe["reason"] == "MEMORY_LIMIT":
                raise Stop("MEMORY_LIMIT_DURING_R_DEPENDENCY_CHECK")
            for label, wanted in (("R_VERSION", args.expected_r_version),
                                  ("TERRA_VERSION", args.expected_terra_version)):
                if wanted and re.findall(r"^"+label+r"=([^\s]+)$", summary["r_versions_output"], re.M) != [wanted]:
                    raise Stop(label+"_MISMATCH_OR_UNAVAILABLE")
            if probe["status"] == "PASS":
                run("terra_compatibility", [rscript, "--vanilla", str(HERE/"test_terra_compatibility.R")], 90)
            else:
                records["terra_compatibility"] = {"status": "NOT_RUN", "reason": "TERRA_DEPENDENCY_FAILED"}
            if args.pr32_repo:
                unit = prepare_pr32(pr32_repo, output)
                run("pr32_separate_dag", [rscript, "--vanilla", str(unit/"tests/test_count_core.R")],
                    30, parse=require_pr32_summary)
            else:
                records["pr32_separate_dag"] = {"status": "NOT_RUN", "reason": "SEPARATE_PINNED_CHECKOUT_NOT_SUPPLIED"}
    except (Stop, OSError, ValueError, subprocess.SubprocessError) as exc:
        fatal = str(exc)
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_alarm)
        signal.signal(signal.SIGTERM, previous_term)
        for source, (pin, branch, before) in originals.items():
            try:
                if checkout(source, pin, branch) != before:
                    raise Stop("REPOSITORY_CONTENT_CHANGED")
            except (Stop, OSError) as exc:
                fatal = "POST_TEST_SOURCE_CHECK: "+str(exc)
        if fatal:
            for record in records.values():
                if record["status"] == "NOT_RUN" and record["reason"] == "NOT_STARTED":
                    record["reason"] = "STOP: "+fatal
        counts = {state: sum(r["status"] == state for r in records.values())
                  for state in ("PASS", "FAIL", "NOT_RUN")}
        ok = not fatal and counts["PASS"] == len(SUITES)
        summary.update(status="PASS" if ok else "FAIL", stop_reason=fatal,
                       suite_counts=counts, seconds=round(time.monotonic()-started,4))
        if output:
            try:
                (output/"summary.json").write_text(json.dumps(summary, indent=2)+"\n")
            except OSError as exc:
                ok = False
                summary.update(status="FAIL", stop_reason="REPORT_WRITE_FAILED: "+str(exc))
        print("SUMMARY="+json.dumps(summary, sort_keys=True), flush=True)
        print("hydrological_validation=NOT_ASSESSED channel_interpretation=NOT_ASSESSED", flush=True)
        print("MODERATE=REVIEW_REQUIRED NATIONAL=LOCKED", flush=True)
        ACTIVE_DEADLINE = previous_deadline
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
