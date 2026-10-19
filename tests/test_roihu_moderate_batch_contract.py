#!/usr/bin/env python3
"""Offline launcher checks with synthetic Slurm clients; never contacts CSC."""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/roihu_moderate_bounded_batch.sbatch'


class RoihuSlurmBatchContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.body = SCRIPT.read_text(encoding='utf-8')
        cls.sb = dict(re.findall(r'^#SBATCH --([a-z-]+)=(\S+)', cls.body, re.M))

    def test_valid_bash_syntax(self):
        subprocess.run(['bash', '-n', str(SCRIPT)], check=True, timeout=10)

    def test_single_node_bounded_resource_request(self):
        self.assertEqual(self.sb['account'], 'project_2004707')
        self.assertEqual(self.sb['partition'], 'small')
        for key in ('nodes', 'ntasks', 'cpus-per-task'):
            self.assertEqual(self.sb[key], '1')
        self.assertEqual(self.sb['mem'], '32G')
        self.assertEqual(self.sb['time'], '00:30:00')
        self.assertNotIn('array', self.sb)
        self.assertNotIn('requeue', self.sb)
        # sbatch --output and --error are supplied from the submitter scratch dir.
        self.assertNotIn('output', self.sb)
        self.assertNotIn('error', self.sb)

    def test_memory_verified_before_r_or_hydrology_read(self):
        markers = ['PHASE=ALLOCATION_AND_MEMORY_PREFLIGHT',
                   '--memory-preflight-only', 'PHASE=R_TERRA_ENVIRONMENT',
                   'module load r-env/461', 'PHASE=BOUNDED_49_LAKE_READONLY_PROBE']
        offsets = [self.body.index(marker) for marker in markers]
        self.assertEqual(offsets, sorted(offsets))
        self.assertEqual(self.body.count('bash scripts/roihu_probe_rstudio.sh'), 1)
        self.assertIn('scripts/roihu_probe_rstudio.sh', self.body)
        self.assertIn('"$MM_HOST_PYTHON" -I -B scripts/roihu_probe_bundle.py', self.body)
        self.assertNotIn('--synthetic-fixture', self.body)
        self.assertNotIn('--overwrite', self.body)

    def test_fails_closed_and_runs_only_in_existing_batch_allocation(self):
        for text in ('set -euo pipefail', 'umask 077',
                     'SLURM_JOB_ID', 'MM_EXPECTED_COMMIT',
                     'rev-parse HEAD', 'status --porcelain --untracked-files=all',
                     'MM_REPORT_PARENT', 'PHASE=FINISHED',
                     'SCIENTIFIC_STATUS=REVIEW_REQUIRED NATIONAL=LOCKED',
                     'HYDROLOGICAL_APPROVAL=false'):
            self.assertIn(text, self.body)
        self.assertNotRegex(self.body, r'(?m)^\s*(sbatch|scancel|salloc|srun)\b')
        self.assertNotRegex(self.body, r'(?m)^\s*(rm|mv|cp|rsync|git push)\b')
        self.assertNotRegex(self.body, r'(?m)^\s*Rscript\b.+(02_build_baseline|FillDepressions)')

    def test_private_report_mode_accepts_setgid_but_rejects_group_access(self):
        # Execute the Bash function from the launcher itself, not a Python copy.
        match = re.search(r'(?ms)^mm_private_report_mode\(\) \{\n.*?^\}', self.body)
        self.assertIsNotNone(match)
        implementation = match.group(0)
        for mode in ('700', '2700'):
            with self.subTest(mode=mode):
                p = subprocess.run(['bash', '-c', implementation + '\nmm_private_report_mode "$1"',
                                    '_', mode], capture_output=True, text=True, timeout=5)
                self.assertEqual(p.returncode, 0, p.stderr)
        for mode in ('770', '2770', '750', '2750', '701', '2701', '1777', '3700', '0'):
            with self.subTest(mode=mode):
                p = subprocess.run(['bash', '-c', implementation + '\nmm_private_report_mode "$1"',
                                    '_', mode], capture_output=True, text=True, timeout=5)
                self.assertNotEqual(p.returncode, 0)

    def test_host_slurm_path_restoration_is_fail_closed(self):
        # Extract and execute the exact Bash helper, with synthetic binaries.
        import tempfile
        match = re.search(r'(?ms)^mm_probe_path_for_slurm\(\) \{\n.*?^\}', self.body)
        self.assertIsNotNone(match)
        helper = match.group(0)
        with tempfile.TemporaryDirectory(prefix='mm-batch-path-') as temp:
            host, module = Path(temp) / 'host', Path(temp) / 'module'
            host.mkdir(); module.mkdir()
            host_client = host / 'scontrol'
            rscript = module / 'Rscript'
            for executable in (host_client, rscript):
                executable.write_text('#!/bin/sh\nexit 0\n')
                executable.chmod(0o700)

            def probe():
                return subprocess.run(
                    ['/bin/bash', '-c',
                     helper + '\nmm_probe_path_for_slurm "$1" "$2" "$3"',
                     '_', str(host), str(module), str(host_client)],
                    capture_output=True, text=True, timeout=5)

            good = probe()
            self.assertEqual(good.returncode, 0, good.stderr)
            combined = good.stdout.strip()
            self.assertEqual(combined, str(module) + ':' + str(host))
            for name, expected in (('scontrol', host_client), ('Rscript', rscript)):
                p = subprocess.run(
                    ['/bin/bash', '-c', 'PATH="$1"; command -v "$2"',
                     '_', combined, name], capture_output=True, text=True, timeout=5)
                self.assertEqual(p.returncode, 0)
                self.assertEqual(p.stdout.strip(), str(expected))

            # Real host-Python discovery must survive a module-injected python3
            # shim that cannot inspect the real Slurm host environment.
            import os
            import sys
            bad_python = module / 'python3'
            bad_python.write_text('#!/bin/sh\nexit 77\n')
            bad_python.chmod(0o700)
            env = dict(os.environ, PATH=combined)
            code = ('import shutil; '
                    'print(shutil.which("scontrol") or ""); '
                    'print(shutil.which("Rscript") or "")')
            observed = subprocess.run([sys.executable, '-I', '-B', '-c', code],
                                      env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(observed.returncode, 0, observed.stderr)
            self.assertEqual(observed.stdout.splitlines(),
                             [str(host_client), str(rscript)])
            wrong_interpreter = subprocess.run([str(bad_python), '-I', '-B', '-c', code],
                                               env=env, capture_output=True, timeout=5)
            self.assertEqual(wrong_interpreter.returncode, 77)

            shadow = module / 'scontrol'
            shadow.write_text('#!/bin/sh\nexit 0\n')
            shadow.chmod(0o700)
            self.assertNotEqual(probe().returncode, 0)
            shadow.unlink()
            host_client.unlink()
            self.assertNotEqual(probe().returncode, 0)

    def test_slurm_path_restored_only_after_real_module_validation(self):
        checkpoints = [
            'MM_HOST_PATH=$PATH',
            'MM_HOST_PYTHON=$(command -v python3)',
            'PHASE=ALLOCATION_AND_MEMORY_PREFLIGHT',
            'module load r-env/461',
            'R_TERRA_READY R=',
            'MM_PROBE_PATH=$(mm_probe_path_for_slurm',
            'MM_PY_SCONTROL=$(PATH="$MM_PROBE_PATH" "$MM_HOST_PYTHON" -I -B',
            'MM_PY_RSCRIPT=$(PATH="$MM_PROBE_PATH" "$MM_HOST_PYTHON" -I -B',
            'PHASE=BOUNDED_49_LAKE_READONLY_PROBE',
            'PATH="$MM_PROBE_PATH" timeout'
        ]
        positions = [self.body.index(x) for x in checkpoints]
        self.assertEqual(positions, sorted(positions))
        self.assertIn('STOP: original host scontrol unavailable or shadowed', self.body)
        self.assertIn('STOP: Slurm PATH restoration would change Rscript interpreter', self.body)
        self.assertEqual(self.body.count('--memory-preflight-only'), 1)
        self.assertEqual(self.body.count('PATH="$MM_PROBE_PATH" timeout'), 1)
        self.assertIn('STOP: host Python cannot resolve the verified scontrol', self.body)
        self.assertIn('STOP: host Python cannot resolve the verified Rscript', self.body)
        self.assertIn('"$MM_HOST_PYTHON" -I -B scripts/roihu_probe_bundle.py', self.body)

    def test_preserved_python_verifies_allocation_before_and_after_module(self):
        # Execute the launcher's actual capture/module/restore code, then the
        # real Python verifier and subprocess RPC against a PRIVATE fake client.
        # No kernel membership or real controller is queried by this fixture.
        import json
        import os
        import socket
        import sys
        import tempfile

        capture = self.body[self.body.index('MM_HOST_PATH=$PATH'):
                            self.body.index('\ncd -- "$MM_CODE_DIR"')]
        after_module = self.body[self.body.index('module load r-env/461'):
                                 self.body.index("\nprintf 'PHASE=BOUNDED_49_LAKE_READONLY_PROBE")]
        with tempfile.TemporaryDirectory(prefix='mm-batch-chain-') as temp:
            base = Path(temp)
            host, module = base / 'host', base / 'module'
            host.mkdir(); module.mkdir()
            (host / 'python3').symlink_to(sys.executable)
            import shutil
            (host / 'timeout').symlink_to(shutil.which('timeout'))
            (module / 'timeout').symlink_to(shutil.which('timeout'))
            client = host / 'scontrol'
            client.write_text('''#!/bin/sh
[ "$#" -eq 4 ] && [ "$1 $2 $3 $4" = "--oneliner show job 2357699" ] || exit 90
[ "$MM_FIXTURE_AUTH_CANARY" = inherited-host-context ] || exit 91
[ "${SLURM_CLUSTERS+x}" != x ] || exit 92
printf '%s\\n' "$MM_FIXTURE_PHASE" >> "$MM_FIXTURE_TRACE"
if [ "$MM_FIXTURE_PHASE" = after ]; then
  [ "$MM_FIXTURE_RPC_FAILURE" = 0 ] || exit 93
  printf '%s\\n' "$MM_FIXTURE_AFTER_ROW"
else
  printf '%s\\n' "$MM_FIXTURE_ROW"
fi
''')
            client.chmod(0o700)
            rscript = module / 'Rscript'
            rscript.write_text('#!/bin/sh\nprintf "R_TERRA_READY R=synthetic terra=synthetic\\n"\n')
            rscript.chmod(0o700)
            # Simulate r-env replacing python3 with an unusable container shim.
            (module / 'python3').write_text('#!/bin/sh\nexit 77\n')
            (module / 'python3').chmod(0o700)
            probe = base / 'allocation_probe.py'
            probe.write_text('''import importlib.util, json, os, shutil, subprocess, sys
spec = importlib.util.spec_from_file_location('actual_bundle', sys.argv[1])
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)
allocation = bundle.verified_slurm_allocation(
    '/system.slice/slurmstepd.scope/job_2357699/step_batch/user/task_0', {})
rscript = shutil.which('Rscript')
if os.environ['MM_FIXTURE_PHASE'] == 'after':
    ready = subprocess.run([rscript, '--vanilla', '-e', 'fixture'],
                           check=True, capture_output=True, text=True, timeout=5)
    assert 'R_TERRA_READY' in ready.stdout
print(json.dumps(dict(allocation=allocation, python=sys.executable,
                     scontrol=shutil.which('scontrol'), rscript=rscript)))
''')
            invocation = ('"$MM_HOST_PYTHON" -I -B "$MM_FIXTURE_PROBE" '
                          '"$MM_FIXTURE_BUNDLE"')
            shell = ('set -euo pipefail\n' + capture + '\n' + invocation + '''
module() {
  [[ "$*" == 'load r-env/461' ]] || return 1
  export PATH="$MM_FIXTURE_MODULE" MM_FIXTURE_PHASE=after
}
''' + after_module + '\nPATH="$MM_PROBE_PATH" ' + invocation)
            row = (f'JobId=2357699 UserId=fixture({os.getuid()}) JobState=RUNNING '
                   f'NodeList={socket.gethostname()} NumNodes=1 '
                   'AllocTRES=cpu=1,mem=32G,node=1')
            cases = [
                ('valid', row, '0', None),
                ('rpc_failure', row, '1', 'Slurm allocation query failed'),
                ('wrong_job', row.replace('JobId=2357699', 'JobId=2357700'), '0', 'mismatch'),
                ('wrong_owner', row.replace(f'({os.getuid()})', f'({os.getuid() + 1})'), '0', 'mismatch'),
                ('wrong_node', row.replace('NodeList=' + socket.gethostname(),
                                           'NodeList=fixture-other-node'), '0', 'mismatch'),
                ('not_running', row.replace('JobState=RUNNING', 'JobState=PENDING'), '0', 'mismatch'),
                ('wrong_memory', row.replace('mem=32G', 'mem=16G'), '0', 'reservation disagrees'),
            ]
            for name, after_row, failure, error in cases:
                with self.subTest(case=name):
                    trace = base / (name + '.trace')
                    env = dict(os.environ, PATH=str(host),
                               SLURM_JOB_ID='2357699', SLURM_MEM_PER_NODE='32768',
                               SLURM_CLUSTERS='must-not-reach-the-client',
                               MM_FIXTURE_AUTH_CANARY='inherited-host-context',
                               MM_FIXTURE_PHASE='before', MM_FIXTURE_ROW=row,
                               MM_FIXTURE_AFTER_ROW=after_row, MM_FIXTURE_RPC_FAILURE=failure,
                               MM_FIXTURE_MODULE=str(module), MM_FIXTURE_PROBE=str(probe),
                               MM_FIXTURE_BUNDLE=str(ROOT / 'scripts/roihu_probe_bundle.py'),
                               MM_FIXTURE_TRACE=str(trace))
                    result = subprocess.run(['/bin/bash', '-c', shell], env=env,
                                            capture_output=True, text=True, timeout=15)
                    self.assertEqual(trace.read_text().splitlines(), ['before', 'after'])
                    if error is not None:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn(error, result.stderr)
                        continue
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    records = [json.loads(line) for line in result.stdout.splitlines()
                               if line.startswith('{')]
                    self.assertEqual(len(records), 2)
                    self.assertIn('R_TERRA_READY', result.stdout)
                    for record in records:
                        self.assertEqual(record['python'], str(host / 'python3'))
                        self.assertEqual(record['scontrol'], str(client))
                        self.assertEqual(record['allocation']['reserved_bytes'], 32 * 1024**3)
                        self.assertFalse(record['allocation']['cached'])
                    self.assertIsNone(records[0]['rscript'])
                    self.assertEqual(records[1]['rscript'], str(rscript))
                    # Demonstrate that reverting to PATH-based python3 would
                    # hit the module shim instead of the verified host Python.
                    broken = shell.rsplit(invocation, 1)[0] + invocation.replace(
                        '"$MM_HOST_PYTHON"', 'python3', 1)
                    regression = subprocess.run(['/bin/bash', '-c', broken], env=env,
                                                capture_output=True, text=True, timeout=15)
                    self.assertEqual(regression.returncode, 77, regression.stderr)

    def test_report_and_data_separation(self):
        self.assertIn('/scratch/project_2004707/pienvedet/mm_mod_probe.', self.body)
        self.assertIn('/code', self.body)
        self.assertIn('/reports', self.body)
        self.assertIn('must be owner-only mode 0700 or 2700', self.body)
        self.assertNotIn('/users/asuurone', self.body)
        self.assertNotIn('mkdir -p "$HOME', self.body)


if __name__ == '__main__':
    unittest.main()
