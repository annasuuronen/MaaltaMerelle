#!/usr/bin/env python3
"""Offline orchestration: exact inputs, bounded reads, no WBT/Slurm/network calls."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shutil
import socket
import stat
import subprocess
import sys
import tarfile
import tempfile
import time

CODE = Path(__file__).absolute().parent.parent
ROOT = Path('/scratch/project_2004707/pienvedet/csc_validation_4bbf22b')
HYDRO = 'hydro_01_02/'
BASE = HYDRO + 'moderate_resume_20261014_v2/run/02_baseline/'
ORIGINAL = HYDRO + 'runs/E0510000_N7620000/02_baseline/'
REVIEW = HYDRO + 'moderate_scientific_review/job_rstudio_2354869_20261016T171249/'
WATER = BASE + 'routing_surface_land_water_FLT8S.tif'
LAKE = 'inputs/E0510000_N7620000/ranta10_lake_id.tif'
SUMMARY = BASE + '02D_lake_depression_component_summary.csv'
# External evidence pins: de3d3808 docs/moderate_roihu_readonly_review_20261016.md.
PINS = {WATER: '940d8198b3f383cceb0fdc2e9a9e341015cc99d7e31d7acc09e0b77764e19571',
        LAKE: 'a3b647067ebb35647639190c8cebd6c69864bbb1022a6db5a6047fe8bdea2db5'}
SMALL = [SUMMARY, ORIGINAL + '02A_storage_regression_QA.csv',
         BASE + '02A_storage_regression_QA.csv',
         HYDRO + 'logs/hydro_2264131_1.log',
         HYDRO + 'moderate_resume_20261014_v2/resume.log',
         HYDRO + 'moderate_resume_20261014_v2/resume.jobid',
         HYDRO + 'moderate_resume_20261014_v2/resume.sbatch',
         HYDRO + 'storage_provenance_20261014/comparisons.csv',
         HYDRO + 'storage_provenance_20261014/jobid',
         HYDRO + 'moderate_fill_recheck_20261014/summary.csv',
         HYDRO + 'moderate_fill_recheck_20261014/lake_summary.csv',
         REVIEW + 'provenance.txt', REVIEW + 'steps.txt', REVIEW + 'summary.txt']
# Stat only. Never load STORAGE, pointer, or a Whitebox binary in this package.
STAT_ONLY = [BASE + 'routing_surface_water_storage_FLT8S.tif',
             ORIGINAL + 'routing_surface_land_water_FLT8S.tif',
             ORIGINAL + 'routing_surface_water_storage_FLT8S.tif']
GIB = 1024 ** 3
MAX_SMALL = 5 * 1024 ** 2
MAX_HASH_FILE = GIB
MAX_PACKAGE = 24 * 1024 ** 2


class Blocked(Exception):
    pass


def safe_path(value):
    """Reject traversal and symlinks in every existing component; no globbing."""
    p = Path(value)
    if not p.is_absolute() or '..' in p.parts or any(c in str(p) for c in '*?[]\n\r\0'):
        raise Blocked('Unsafe path')
    for part in [*reversed(p.parents), p]:
        try:
            if stat.S_ISLNK(part.lstat().st_mode):
                raise Blocked('Symbolic link refused: ' + str(part))
        except FileNotFoundError:
            continue
    return p


def fingerprint(p):
    s = p.stat()
    return (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)


def regular(p, cap):
    safe_path(p)
    s = p.stat()
    if not stat.S_ISREG(s.st_mode) or s.st_size == 0 or s.st_size > cap:
        raise Blocked('Not a nonempty bounded regular file: ' + str(p))
    return fingerprint(p)


def digest(p, deadline):
    h = hashlib.sha256()
    # O_NOFOLLOW closes the final-component symlink race. Parent paths are
    # rechecked before/after; this assumes no hostile concurrent directory owner.
    fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as f:
        before = os.fstat(f.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_HASH_FILE:
            raise Blocked('Hash file exceeds limit or is not regular')
        n = 0
        while True:
            if time.monotonic() > deadline:
                raise Blocked('Total wall time exhausted during hashing')
            block = f.read(1024 ** 2)
            if not block:
                break
            n += len(block)
            if n > MAX_HASH_FILE:
                raise Blocked('Hash byte budget exceeded')
            h.update(block)
        after = os.fstat(f.fileno())
        if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns):
            raise Blocked('Input changed while hashing')
    return h.hexdigest()


def available_memory():
    """Physical availability plus all visible cgroup-v2 ancestor limits."""
    mem = Path('/proc/meminfo').read_text()
    match = re.search(r'^MemAvailable:\s+(\d+) kB$', mem, re.M)
    if not match:
        raise Blocked('Memory availability unknown')
    available = int(match[1]) * 1024
    observations = {'proc_available_bytes': available, 'cgroup_limits': []}
    groups = Path('/proc/self/cgroup').read_text().splitlines()
    v2 = next((x[3:] for x in groups if x.startswith('0::')), None)
    if v2 is None:
        raise Blocked('Cgroup-v2 memory accounting unavailable; allocation cannot be checked')
    # /proc may present an ancestor outside the cgroup namespace: root still
    # supplies the namespace's actual limit; never follow traversal components.
    base = Path('/sys/fs/cgroup')
    p = base / v2.lstrip('/') if '..' not in Path(v2).parts else base
    if not p.exists():
        p = base
    found = False
    while p == base or base in p.parents:
        limit_file = p / 'memory.max'
        usage_file = p / 'memory.current'
        if limit_file.is_file() and usage_file.is_file():
            found = True
            limit, usage = limit_file.read_text().strip(), int(usage_file.read_text())
            observations['cgroup_limits'].append({'limit': limit, 'usage_bytes': usage})
            if limit != 'max':
                available = min(available, int(limit) - usage)
        if p == base:
            break
        p = p.parent
    if not found:
        raise Blocked('Cgroup memory limit/usage unreadable')
    observations['available_bytes'] = available
    return observations


def write_json(p, value):
    p.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def inventory(root, names, deadline):
    result = []
    for name in names:
        entry = {'path': str(root / name), 'state': 'NOT_CHECKED', 'content_read': False}
        try:
            p = safe_path(root / name)
            s = p.stat()
            if not stat.S_ISREG(s.st_mode):
                raise Blocked('Not regular')
            entry.update(bytes=s.st_size, mtime_ns=s.st_mtime_ns)
            if s.st_size > MAX_SMALL:
                entry['reason'] = 'SIZE_LIMIT'; result.append(entry); continue
            before = fingerprint(p)
            entry['sha256'] = digest(p, deadline)
            # Export tokens/line numbers only, never raw historical logs, commands,
            # environment variables or credential-like contents.
            text = p.read_text(errors='replace')
            markers = {'fill_started': r'Running WATER_STORAGE FillDepressions',
                       'fill_tool_name': r'FillDepressions',
                       'fix_flats_false_text': r'fix_flats\s*[=:]\s*FALSE',
                       'cache_text': r'(?i)cache|checkpoint|skip|overwrite',
                       'gate_failed_text': r'all\(spill_lakes\$n_depression_components >= 1\)',
                       'binary_sha_text': r'96bb47a9d1f0fe8a3cb46df524242c990eab9bc2ae1930e540e09328331172e4'}
            entry['marker_lines'] = {k: [i for i, line in enumerate(text.splitlines(), 1)
                                         if re.search(pattern, line)][:100]
                                     for k, pattern in markers.items()}
            if fingerprint(p) != before:
                raise Blocked('Changed during inspection')
            entry.update(state='AVAILABLE', content_read=True)
        except FileNotFoundError:
            entry.update(state='MISSING', reason='Not present')
        except (OSError, Blocked) as exc:
            entry.update(state='UNREADABLE', reason=type(exc).__name__)
        result.append(entry)
    return result


def child_limits():
    resource.setrlimit(resource.RLIMIT_AS, (2 * GIB, 2 * GIB))
    resource.setrlimit(resource.RLIMIT_FSIZE, (128 * 1024, 128 * 1024))
    resource.setrlimit(resource.RLIMIT_CPU, (120, 120))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def execute(command, stdout, stderr, env, deadline):
    remaining = min(180, deadline - time.monotonic())
    if remaining <= 0:
        raise Blocked('Total wall time exhausted')
    with stdout.open('xb') as out, stderr.open('xb') as err:
        p = subprocess.Popen(command, stdout=out, stderr=err, env=env,
                             start_new_session=True, preexec_fn=child_limits, cwd=CODE)
        try:
            rc = p.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            import signal
            os.killpg(p.pid, signal.SIGKILL)
            p.wait()
            raise Blocked('R step exceeded wall time')
    if rc:
        raise Blocked('R step failed, exit=' + str(rc))


def run(args, report, state):
    deadline = time.monotonic() + 900
    actual = subprocess.check_output(['git', '-C', str(CODE), 'rev-parse', 'HEAD'], text=True).strip()
    state['code_commit'] = actual
    if not re.fullmatch('[0-9a-f]{40}', args.expected_commit) or actual != args.expected_commit:
        raise Blocked('Code commit mismatch')
    dirty = subprocess.check_output(['git', '-C', str(CODE), 'status', '--porcelain', '--untracked-files=all'], text=True)
    if dirty:
        raise Blocked('Checkout must be clean, including untracked files')
    safe_path(CODE)
    root = ROOT
    pins, small, stat_only = PINS, SMALL, STAT_ONLY
    profile = {'mode': 'real', 'total': 158, 'positive': 52, 'excluded': '203439,203443,203444', 'max_window': 250000}
    if args.synthetic_fixture:
        # An explicit CI-only profile cannot address /scratch or /projappl.
        f = safe_path(args.synthetic_fixture)
        regular(f, MAX_SMALL)
        profile = json.loads(f.read_text())
        root = safe_path(profile['root'])
        tmp = Path(tempfile.gettempdir()).resolve()
        if tmp not in root.parents or str(root).startswith(('/scratch/', '/projappl/')):
            raise Blocked('Synthetic root must be inside the system temporary directory')
        pins = profile['pins']; small = [SUMMARY, 'history.log']; stat_only = []
        if set(pins) != {WATER, LAKE} or profile['mode'] != 'synthetic':
            raise Blocked('Invalid synthetic fixture contract')
        if not (1 <= profile['total'] <= 158 and 1 <= profile['positive'] <= profile['total']):
            raise Blocked('Invalid fixture lake counts')
    else:
        # RStudio session already allocated by the operator; never allocate one.
        if not re.fullmatch(r'[1-9][0-9]*', os.getenv('SLURM_JOB_ID', '')):
            raise Blocked('No numeric existing SLURM_JOB_ID; use an allocated RStudio compute terminal')
        if re.search(r'(?i)login|^roihu-login', socket.gethostname()):
            raise Blocked('Login node refused')
        state['allocation_id'] = os.environ['SLURM_JOB_ID']
    safe_path(root)
    if root == report or root in report.parents or report in root.parents:
        raise Blocked('Reports and data root must be separate')
    state['profile'] = profile['mode']
    state['memory'] = available_memory()
    if state['memory']['available_bytes'] < 3 * GIB:
        raise Blocked('Less than 3 GiB available within physical/cgroup limits')
    if shutil.disk_usage(report).free < GIB:
        raise Blocked('Less than 1 GiB report/temp space')
    rscript = shutil.which('Rscript')
    if not rscript:
        raise Blocked('Rscript absent from this RStudio terminal PATH; no module is loaded')
    state['rscript'] = str(Path(rscript).resolve())
    entries = inventory(root, small, deadline)
    for name in stat_only:
        entry = {'path': str(root / name), 'state': 'NOT_CHECKED', 'content_read': False}
        try:
            p = safe_path(root / name); s = p.stat()
            if not stat.S_ISREG(s.st_mode):
                raise Blocked('Not regular')
            entry.update(state='AVAILABLE', bytes=s.st_size, mtime_ns=s.st_mtime_ns)
        except FileNotFoundError:
            entry['state'] = 'MISSING'
        except (OSError, Blocked):
            entry['state'] = 'UNREADABLE'
        entries.append(entry)
    # Unknown historical log/manifest names are not searched or guessed.
    entries.append({'path': 'original_02A_execution_receipt_and_cache_manifest', 'state': 'NOT_CHECKED',
                    'reason': 'No independently supplied exact path; no wildcard or directory search'})
    write_json(report / 'inventory.json', entries)
    state['historical_provenance'] = 'INCOMPLETE'
    state['historical_attribution_authorized'] = False
    write_json(report / 'provenance_gaps.json', {
        'status': 'INCOMPLETE', 'markers_are_execution_proof': False,
        'required_for_historical_attribution': [
            'Original 02A command, original code and actually executed Whitebox binary digest/version',
            'Original command exit/completion and bound input/output hashes',
            'OVERWRITE flag and file-existence/cache decision when original STORAGE was produced',
            'Cache/checkpoint manifest linking original and V2 copies; timestamps alone do not prove execution'],
        'unknown_exact_paths_not_searched': True,
        'known_prior_timeout_and_copy_are_not_a_success_receipt': True})
    # Current observation provenance is independent of incomplete historical
    # execution provenance. Both raster byte identities must match external pins.
    bindings = []
    for name, expected in pins.items():
        binding = {'path': str(root / name), 'expected_sha256': expected, 'state': 'NOT_CHECKED'}
        bindings.append(binding)
        try:
            p = safe_path(root / name)
            before = regular(p, MAX_HASH_FILE)
        except FileNotFoundError:
            binding['state'] = 'MISSING'
            write_json(report / 'input_bindings.json', bindings)
            raise Blocked('Required raster missing')
        except (OSError, Blocked):
            binding['state'] = 'UNREADABLE'
            write_json(report / 'input_bindings.json', bindings)
            raise Blocked('Required raster unreadable or unsafe')
        binding.update(state='AVAILABLE', stat_binding=before, hash_status='NOT_CHECKED')
        write_json(report / 'input_bindings.json', bindings)
        for suffix in ('.aux.xml', '.ovr', '.msk'):
            if os.path.lexists(str(p) + suffix):
                raise Blocked('Unpinned raster sidecar refused')
        got = digest(p, deadline)
        binding.update(observed_sha256=got, matched=got == expected, hash_status='CHECKED')
        write_json(report / 'input_bindings.json', bindings)
        if not re.fullmatch('[0-9a-f]{64}', expected) or got != expected:
            raise Blocked('Current raster hash does not match independent prior report')
        if fingerprint(p) != before:
            raise Blocked('Input changed during binding')
    q = safe_path(root / SUMMARY); summary_before = regular(q, MAX_SMALL)
    summary_bytes = q.read_bytes()
    state['summary_sha256'] = hashlib.sha256(summary_bytes).hexdigest()
    # Snapshot the small summary exactly once; both planning and probing use it.
    work = report / 'work'; work.mkdir(mode=0o700)
    (work / 'source_summary.csv').write_bytes(summary_bytes)
    env = os.environ.copy()
    env.update(TMPDIR=str(work), GDAL_PAM_ENABLED='NO', GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR',
               OMP_NUM_THREADS='1', OPENBLAS_NUM_THREADS='1', MKL_NUM_THREADS='1',
               R_ENVIRON_USER='/dev/null', R_PROFILE_USER='/dev/null')
    execute([rscript, '--vanilla', str(CODE / 'scripts/plan_fill_probe_windows.R'),
             str(root / WATER), str(root / LAKE), str(work / 'source_summary.csv'), str(work),
             profile['mode'], str(profile['total']), str(profile['positive']), profile['excluded'],
             str(profile['max_window'])], report / 'planner.log', report / 'planner.stderr.log', env, deadline)
    for name in ('windows.csv', 'readiness.csv'):
        shutil.copyfile(work / name, report / name)
    with (work / 'windows.csv').open(newline='') as f:
        plan = list(csv.DictReader(f))
    if not 1 <= len(plan) <= 49 or (profile['mode'] == 'real' and len(plan) != 49):
        raise Blocked('Unexpected target count')
    state['targets'] = len(plan)
    state['steps'] = []
    total = 0
    for row in plan:
        step = {'lake_objectid': row['lake_objectid'], 'status': row['status']}
        state['steps'].append(step)
        if row['status'] != 'PLANNED':
            continue
        if not re.fullmatch('[1-9][0-9]*', row['lake_objectid']):
            raise Blocked('Unsafe lake ID in plan')
        a, b, c, d = [int(row[k]) for k in ('row1', 'row2', 'col1', 'col2')]
        cells = (b - a + 1) * (d - c + 1)
        total += cells
        if not (1 <= a <= b and 1 <= c <= d and 9 <= cells <= 250000 and total <= 4000000):
            raise Blocked('Window or cumulative cell budget violated')
        if available_memory()['available_bytes'] < 3 * GIB:
            raise Blocked('Memory headroom lost before window')
        label = 'lake_' + row['lake_objectid']
        try:
            execute([rscript, '--vanilla', str(CODE / 'scripts/probe_fill_hypotheses_readonly.R'),
                     str(root / WATER), str(root / LAKE), str(work / ('target_' + row['lake_objectid'] + '.csv')),
                     '2000', f'{a}:{b}', f'{c}:{d}'], report / (label + '.csv'),
                    report / (label + '.stderr.log'), env, deadline)
            with (report / (label + '.csv')).open(newline='') as f:
                observations = list(csv.DictReader(f))
            if not observations or len(observations) > 100 or any(
                x['lake_objectid'] != row['lake_objectid'] or x['natural_outlet_verified'] != 'FALSE' or
                x['actual_whitebox_behaviour_verified'] != 'FALSE' or x['scientific_status'] != 'REVIEW_REQUIRED' or
                x['national_status'] != 'LOCKED' for x in observations):
                raise Blocked('Missing or unsafe probe result')
            step.update(status='OBSERVED', component_rows=len(observations),
                        diagnostic_statuses=sorted({x['diagnostic_status'] for x in observations}))
        except (Blocked, OSError, ValueError, KeyError) as exc:
            step.update(status='FAILED', reason=str(exc))
    for binding in bindings:
        if fingerprint(safe_path(binding['path'])) != tuple(binding['stat_binding']):
            raise Blocked('Raster changed since hash binding; observations invalidated')
    if fingerprint(q) != summary_before:
        raise Blocked('Source summary changed during observations')
    state['input_stat_bindings_unchanged'] = True
    state['observations_valid'] = any(x['status'] == 'OBSERVED' for x in state['steps'])
    state['technical_status'] = 'COMPLETE' if all(x['status'] == 'OBSERVED' for x in state['steps']) else 'PARTIAL'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-commit', required=True)
    parser.add_argument('--output-parent', required=True, help='Existing private output directory, outside data and checkout')
    parser.add_argument('--synthetic-fixture', help='CI only; temporary-directory synthetic inputs')
    args = parser.parse_args()
    os.umask(0o077)
    try:
        parent = safe_path(args.output_parent)
        if not parent.is_dir() or parent == CODE or CODE in parent.parents or parent in CODE.parents:
            raise Blocked('Output parent missing or overlaps checkout')
        if parent.stat().st_uid != os.geteuid() or parent.stat().st_mode & 0o022:
            raise Blocked('Output parent must be owned by this user and not writable by group/others')
        if parent == ROOT or ROOT in parent.parents or parent in ROOT.parents:
            raise Blocked('Output parent must be outside CSC input tree')
        report = Path(tempfile.mkdtemp(prefix='fill_probe_', dir=parent))
    except (OSError, Blocked) as exc:
        print('STOP before input reads: ' + str(exc), file=sys.stderr)
        return 2
    state = {'technical_status': 'BLOCKED', 'hydrological_success': 'NOT_ASSESSED',
             'MODERATE': 'REVIEW_REQUIRED', 'NATIONAL': 'LOCKED', 'continuation_authorized': False,
             'historical_provenance': 'NOT_CHECKED', 'historical_attribution_authorized': False,
             'observations_valid': False, 'python_version': sys.version.split()[0],
             'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
             'expected_commit': args.expected_commit, 'host': socket.gethostname(),
             'limits': {'window_cells': 250000, 'total_surface_cells': 4000000, 'id_block_cells': 65536,
                        'hash_file_bytes': MAX_HASH_FILE, 'hash_rasters': 2, 'visits_per_lake': 2000,
                        'total_visits_at_most': 98000, 'child_address_space_bytes': 2 * GIB,
                        'minimum_available_bytes': 3 * GIB, 'wall_seconds': 900}}
    try:
        run(args, report, state)
    except Exception as exc:
        state.update(technical_status='BLOCKED', reason=str(exc), observations_valid=False)
    state['finished_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    state['package_status'] = 'NEEDS_EVIDENCE'  # Never a hydrological PASS.
    write_json(report / 'summary.json', state)
    (report / 'README.txt').write_text(
        'Read summary.json first. COMPLETE means bounded observations executed, not scientific approval.\n'
        'Historical provenance remains INCOMPLETE; tokens and timestamps are not execution receipts.\n'
        'Window edges, visit caps and nonfinite contacts censor conclusions; no outlet absence is proven.\n'
        'No Whitebox, D8 retrace, production gate, job submission or raster writes were invoked.\n'
        'MODERATE=REVIEW_REQUIRED; NATIONAL=LOCKED; continuation_authorized=false.\n')
    # Explicit current-run report files only; never archive work/ or source data.
    fixed = {'summary.json', 'README.txt', 'inventory.json', 'provenance_gaps.json', 'input_bindings.json',
             'windows.csv', 'readiness.csv', 'planner.log', 'planner.stderr.log'}
    files = [p for p in report.iterdir() if p.name in fixed or re.fullmatch(r'lake_[1-9][0-9]*\.(csv|stderr\.log)', p.name)]
    if any(p.is_symlink() or not p.is_file() for p in files) or sum(p.stat().st_size for p in files) > MAX_PACKAGE:
        print('STOP: archive safety/size limit; report remains at ' + str(report), file=sys.stderr)
        return 2
    archive = report / 'review_bundle.tar.gz'
    with tarfile.open(archive, 'x:gz') as tar:
        for p in sorted(files):
            tar.add(p, arcname=p.name, recursive=False)
    (report / 'review_bundle.sha256').write_text(digest(archive, time.monotonic() + 30) + '  review_bundle.tar.gz\n')
    print('REPORT=' + str(archive))
    print('TECHNICAL_STATUS=' + state['technical_status'] + ' HISTORICAL_PROVENANCE=' + state['historical_provenance'])
    print('MODERATE=REVIEW_REQUIRED NATIONAL=LOCKED HYDROLOGICAL_SUCCESS=NOT_ASSESSED')
    return 0 if state['technical_status'] == 'COMPLETE' else 2


if __name__ == '__main__':
    sys.exit(main())
