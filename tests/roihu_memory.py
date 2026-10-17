#!/usr/bin/env python3
"""Synthetic kernel/Slurm observations only; no real controller or CSC reads."""
from contextlib import ExitStack
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('memory_bundle', ROOT / 'scripts/roihu_probe_bundle.py')
bundle = importlib.util.module_from_spec(spec); spec.loader.exec_module(bundle)
GIB = bundle.GIB
CGROUP = '/system.slice/slurmstepd.scope/job_2357699/step_batch/user/task_0'
CGROOT = Path('/sys/fs/cgroup')


class MemorySafety(unittest.TestCase):
    def setUp(self):
        # Only job ID, reservation and cgroup string are actual reported Roihu
        # observations. ALL meminfo/controller values below are synthetic.
        self.env = {'SLURM_JOB_ID': '2357699', 'SLURM_MEM_PER_NODE': '32768'}
        self.membership = '0::' + CGROUP + '\n'
        self.total = 64 * GIB; self.free = 56 * GIB; self.available = 58 * GIB
        self.files = {}; self.reads = []
        self.slurm = ('JobId=2357699 UserId=fixture(777) JobState=RUNNING '
                      'NodeList=r01 NumNodes=1 AllocTRES=cpu=8,mem=32G,node=1')
        self.context = {'allow_slurm': True}
        self.stack = ExitStack(); self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.dict(os.environ, self.env))
        self.stack.enter_context(patch.object(bundle.os, 'getuid', return_value=777))
        self.stack.enter_context(patch.object(bundle.socket, 'gethostname', return_value='r01.local'))
        self.stack.enter_context(patch.object(bundle, 'kernel_text', side_effect=self.kernel))
        self.query = self.stack.enter_context(patch.object(bundle, 'query_slurm_job', side_effect=lambda _: self.slurm))

    def kernel(self, path, cap=65536):
        self.reads.append(str(path))
        if path == Path('/proc/meminfo'):
            return f'MemTotal: {self.total // 1024} kB\nMemFree: {self.free // 1024} kB\nMemAvailable: {self.available // 1024} kB\n'
        if path == Path('/proc/self/cgroup'):
            return self.membership
        if str(path) in self.files:
            value = self.files[str(path)]
            if isinstance(value, Exception): raise value
            return value
        # Matches the reported hidden cgroup files, including the mount root.
        raise PermissionError('Synthetic cgroup unreadable')

    def measured(self):
        return bundle.available_memory(self.context)

    def current_pair(self, limit, usage):
        self.files[str(CGROOT / CGROUP.lstrip('/') / 'memory.max')] = str(limit)
        self.files[str(CGROOT / CGROUP.lstrip('/') / 'memory.current')] = usage if isinstance(usage, Exception) else str(usage)

    def missing_other_job_files(self):
        p = CGROOT / CGROUP.lstrip('/')
        while 'job_2357699' in p.parts:
            for name in ('memory.max', 'memory.current'):
                self.files.setdefault(str(p / name), FileNotFoundError())
            p = p.parent

    def test_exact_reported_roihu_environment_uses_verified_fallback(self):
        r = self.measured()
        self.assertEqual(self.reads[2], str(CGROOT / CGROUP.lstrip('/') / 'memory.max'))
        self.assertIn(str(CGROOT / 'memory.current'), self.reads)
        self.assertEqual(r['method'], 'SLURM_VERIFIED_NODE_BOUND')
        self.assertEqual(r['allocation']['job_id'], '2357699')
        self.assertEqual(r['allocation']['reserved_bytes'], 32 * GIB)
        self.assertEqual(r['node_used_upper_bytes'], 8 * GIB)
        self.assertEqual(r['available_bytes'], 22 * GIB)  # NOT 32 GiB free.
        self.assertFalse(r['job_usage_measured'])
        self.assertTrue(r['sufficient_for_bounded_child'])
        self.assertTrue(all(x['state'] == 'UNREADABLE' for x in r['cgroup_checks']))
        self.query.assert_called_once_with('2357699')

    def test_real_job_path_precedes_unreadable_mount_root(self):
        self.current_pair(32 * GIB, 5 * GIB); self.missing_other_job_files()
        r = self.measured()
        self.assertEqual(r['method'], 'CGROUP_V2'); self.assertEqual(r['available_bytes'], 27 * GIB)
        self.query.assert_not_called()

    def test_readable_root_alone_cannot_hide_unknown_job_quota(self):
        self.files[str(CGROOT / 'memory.max')] = str(64 * GIB)
        self.files[str(CGROOT / 'memory.current')] = str(8 * GIB)
        r = self.measured()
        self.assertEqual(r['method'], 'SLURM_VERIFIED_NODE_BOUND')
        self.assertEqual(r['available_bytes'], 22 * GIB)

    def test_busy_node_blocks_despite_32_gib_reservation(self):
        self.free = 33 * GIB
        r = self.measured()
        self.assertEqual(r['available_bytes'], 0); self.assertFalse(r['sufficient_for_bounded_child'])

    def test_low_physical_availability_is_not_overridden(self):
        for value in (0, GIB):
            with self.subTest(available=value):
                self.available = value
                r = self.measured()
                self.assertEqual(r['available_bytes'], value); self.assertFalse(r['sufficient_for_bounded_child'])

    def test_known_partial_cgroup_limit_still_caps_fallback(self):
        self.current_pair(8 * GIB, PermissionError())
        r = self.measured()
        self.assertEqual(r['budget_limit_bytes'], 8 * GIB)
        self.assertEqual(r['available_bytes'], 0)

    def test_measured_job_quota_is_never_replaced_by_slurm_reservation(self):
        self.current_pair(32 * GIB, 31 * GIB); self.missing_other_job_files()
        r = self.measured()
        self.assertEqual(r['method'], 'CGROUP_V2'); self.assertEqual(r['available_bytes'], GIB)
        self.query.assert_not_called()

    def test_unverified_environment_alone_is_insufficient(self):
        self.query.side_effect = bundle.Blocked('scontrol unavailable')
        with self.assertRaisesRegex(bundle.Blocked, 'unavailable'): self.measured()
        r = self.context['observations'][-1]
        self.assertEqual(r['status'], 'BLOCKED'); self.assertNotIn('available_bytes', r)

    def test_slurm_identity_state_node_and_memory_must_all_agree(self):
        for old, new in [('2357699', '2357700'), ('fixture(777)', 'fixture(778)'),
                         ('RUNNING', 'COMPLETED'), ('r01', 'r02'), ('NumNodes=1', 'NumNodes=2'),
                         ('mem=32G', 'mem=64G'), ('mem=32G', 'mem=unknown'),
                         ('mem=32G', 'cpu=4'), ('mem=32G', 'mem=32G,mem=32G')]:
            with self.subTest(change=new):
                text = self.slurm
                try:
                    self.slurm = text.replace(old, new)
                    with self.assertRaises(bundle.Blocked): self.measured()
                finally: self.slurm = text

    def test_missing_and_duplicate_controller_fields_block(self):
        for text in [self.slurm.replace(' JobState=RUNNING', ''), self.slurm + ' JobId=2357699']:
            with self.subTest(text=text), patch.object(bundle, 'query_slurm_job', return_value=text):
                with self.assertRaises(bundle.Blocked): self.measured()

    def test_bad_environment_job_ids_and_memory_block_before_rpc(self):
        for key, value in [('SLURM_JOB_ID', '../2357699'), ('SLURM_JOB_ID', ''),
                           ('SLURM_MEM_PER_NODE', ''), ('SLURM_MEM_PER_NODE', '-1')]:
            with self.subTest(key=key, value=value), patch.dict(os.environ, {key: value}):
                with self.assertRaises(bundle.Blocked): self.measured()
        self.query.assert_not_called()

    def test_job_cgroup_membership_cannot_be_forged_by_environment(self):
        self.membership = '0::' + CGROUP.replace('2357699', '2357700')
        with self.assertRaisesRegex(bundle.Blocked, 'kernel cgroup'): self.measured()
        self.query.assert_not_called()

    def test_traversal_never_reads_outside_cgroup_mount(self):
        self.membership = '0::/../escape/job_2357699'
        with self.assertRaises(bundle.Blocked): self.measured()
        self.assertTrue(all(p.startswith('/proc/') or p.startswith('/sys/fs/cgroup/') for p in self.reads))
        self.assertFalse(any('/../' in p for p in self.reads)); self.query.assert_not_called()

    def test_symlink_in_cgroup_path_is_rejected(self):
        original = bundle.safe_path
        def linked(p):
            if str(p).startswith(str(CGROOT / CGROUP.lstrip('/'))):
                raise bundle.Blocked('Symbolic link refused')
            return original(p)
        with patch.object(bundle, 'safe_path', side_effect=linked):
            with self.assertRaisesRegex(bundle.Blocked, 'Symbolic'): self.measured()
        self.query.assert_not_called()

    def test_corrupt_cgroup_values_do_not_trigger_fallback(self):
        self.current_pair('garbage', 0)
        with self.assertRaisesRegex(bundle.Blocked, 'Invalid cgroup'): self.measured()
        self.query.assert_not_called()

    def test_missing_or_inconsistent_physical_memory_is_blocked(self):
        for text in ['MemAvailable: 1 kB\n', 'MemTotal: 1 kB\nMemFree: 2 kB\nMemAvailable: 2 kB\n']:
            with patch.object(bundle, 'kernel_text', return_value=text):
                with self.assertRaises(bundle.Blocked): self.measured()
        self.query.assert_not_called()

    def test_short_allocation_cache_never_caches_free_memory(self):
        r = self.measured(); self.free = 33 * GIB
        second = self.measured()
        self.assertEqual(r['available_bytes'], 22 * GIB)
        self.assertEqual(second['available_bytes'], 0)
        self.assertTrue(second['allocation']['cached']); self.query.assert_called_once()

    def test_expired_cache_requires_live_allocation_verification(self):
        self.measured()
        key, when, value = self.context['_allocation']
        self.context['_allocation'] = (key, when - 31, value)
        self.slurm = self.slurm.replace('RUNNING', 'COMPLETED')
        with self.assertRaises(bundle.Blocked): self.measured()
        self.assertEqual(self.query.call_count, 2)

    def test_blocked_memory_observations_are_preserved_in_real_bundle(self):
        with tempfile.TemporaryDirectory(prefix='memory-bundle-') as name:
            d = Path(name); code = d / 'code'; code.mkdir(); out = d / 'reports'; out.mkdir(mode=0o700)
            subprocess.run(['git', '-C', str(code), 'init', '-q'], check=True)
            (code / 'fixture.txt').write_text('Synthetic reviewed fixture\n')
            subprocess.run(['git', '-C', str(code), 'add', 'fixture.txt'], check=True)
            subprocess.run(['git', '-C', str(code), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                            '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Synthetic memory fixture'], check=True)
            sha = subprocess.check_output(['git', '-C', str(code), 'rev-parse', 'HEAD'], text=True).strip()
            self.free = 33 * GIB
            argv = ['bundle', '--expected-commit', sha, '--output-parent', str(out)]
            with patch.object(bundle, 'CODE', code), patch.object(bundle, 'ROOT', d / 'absent-inputs'), \
                    patch.object(bundle.sys, 'argv', argv), patch.object(bundle, 'execute') as execute:
                self.assertEqual(bundle.main(), 2)
                execute.assert_not_called()
            import tarfile
            archive = next(out.glob('fill_probe_*/review_bundle.tar.gz'))
            with tarfile.open(archive, 'r:gz') as tar:
                r = json.load(tar.extractfile('summary.json'))
                self.assertNotIn('inventory.json', tar.getnames())
            self.assertEqual(r['technical_status'], 'BLOCKED')
            self.assertEqual(r['historical_provenance'], 'NOT_CHECKED')
            self.assertEqual(r['memory_checks'][0]['method'], 'SLURM_VERIFIED_NODE_BOUND')
            self.assertEqual(r['memory_checks'][0]['available_bytes'], 0)
            self.assertEqual(r['MODERATE'], 'REVIEW_REQUIRED'); self.assertEqual(r['NATIONAL'], 'LOCKED')

    def test_query_uses_bounded_structured_read_only_command(self):
        def process(argv, **kwargs):
            kwargs['stdout'].write(self.slurm.encode())
            self.assertEqual(argv, ['/fixture/scontrol', '--oneliner', 'show', 'job', '2357699'])
            self.assertNotIn('shell', kwargs)
            self.assertEqual(kwargs['preexec_fn'], bundle.child_limits)
            return Mock(wait=Mock(return_value=0))
        # QUERY holds the original function; its process is replaced below.
        with patch.object(bundle.shutil, 'which', return_value='/fixture/scontrol'), \
                patch.object(bundle.subprocess, 'Popen', side_effect=process):
            text = QUERY('2357699')
        self.assertEqual(text, self.slurm)

    def test_query_missing_executable_and_timeout_are_blocking(self):
        with patch.object(bundle.shutil, 'which', return_value=None):
            with self.assertRaises(bundle.Blocked): QUERY('2357699')
        p = Mock(pid=999999, wait=Mock(side_effect=[subprocess.TimeoutExpired('fixture', 5), 0]))
        with patch.object(bundle.shutil, 'which', return_value='/fixture/scontrol'), \
                patch.object(bundle.subprocess, 'Popen', return_value=p), patch.object(bundle.os, 'killpg') as kill:
            with self.assertRaisesRegex(bundle.Blocked, 'timed out'): QUERY('2357699')
            kill.assert_called_once()


QUERY = bundle.query_slurm_job

if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(MemorySafety)
    if suite.countTestCases() == 0: raise SystemExit('FAIL: no memory tests found')
    raise SystemExit(0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1)
