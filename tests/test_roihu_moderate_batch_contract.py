#!/usr/bin/env python3
"""Offline contract checks for a NEW Slurm launcher. Never calls Slurm/CSC."""
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
        self.assertEqual(self.body.count('bash scripts/roihu_probe_rstudio.sh'), 2)
        self.assertIn('scripts/roihu_probe_rstudio.sh', self.body)
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
            'PHASE=ALLOCATION_AND_MEMORY_PREFLIGHT',
            'module load r-env/461',
            'R_TERRA_READY R=',
            'MM_PROBE_PATH=$(mm_probe_path_for_slurm',
            'PHASE=BOUNDED_49_LAKE_READONLY_PROBE',
            'PATH="$MM_PROBE_PATH" timeout'
        ]
        positions = [self.body.index(x) for x in checkpoints]
        self.assertEqual(positions, sorted(positions))
        self.assertIn('STOP: original host scontrol unavailable or shadowed', self.body)
        self.assertIn('STOP: Slurm PATH restoration would change Rscript interpreter', self.body)
        self.assertEqual(self.body.count('--memory-preflight-only'), 1)
        self.assertEqual(self.body.count('PATH="$MM_PROBE_PATH" timeout'), 1)

    def test_report_and_data_separation(self):
        self.assertIn('/scratch/project_2004707/pienvedet/mm_mod_probe.', self.body)
        self.assertIn('/code', self.body)
        self.assertIn('/reports', self.body)
        self.assertIn('must be owner-only mode 0700 or 2700', self.body)
        self.assertNotIn('/users/asuurone', self.body)
        self.assertNotIn('mkdir -p "$HOME', self.body)


if __name__ == '__main__':
    unittest.main()
