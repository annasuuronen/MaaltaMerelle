#!/usr/bin/env python3
"""Full shell -> Python -> R planner -> existing probe -> gzip bundle fixtures.

No CSC paths are read; each test executes an isolated temporary git checkout.
Only new orchestration is tested here, not the existing 64+22/WBT suites.
"""
import argparse
import csv
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('bundle', ROOT / 'scripts/roihu_probe_bundle.py')
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)
FILES = ['scripts/roihu_probe_rstudio.sh', 'scripts/roihu_probe_bundle.py',
         'scripts/plan_fill_probe_windows.R', 'scripts/probe_fill_hypotheses_readonly.R',
         'scripts/lib/classify_02d5_readiness.R', 'scripts/lib/probe_fill_hypotheses.R']


class BundleChain(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix='roihu-chain-tests-')
        cls.base = Path(cls.tmp.name)
        cls.code = cls.base / 'code'; cls.code.mkdir()
        for name in FILES:
            p = cls.code / name; p.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, p)
        def git(*args):
            return subprocess.check_output(['git', '-C', str(cls.code), *args], stderr=subprocess.DEVNULL, text=True).strip()
        git('init', '-q'); git('add', '--', 'scripts')
        git('-c', 'user.name=Synthetic fixture', '-c', 'user.email=fixture@example.invalid',
            '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Temporary synthetic fixture')
        cls.sha = git('rev-parse', 'HEAD')
        cls.fixture_data = cls.base / 'source'; cls.fixture_data.mkdir()
        p = subprocess.run(['Rscript', '--vanilla', '-e', '''
          library(terra)
          d <- commandArgs(TRUE)[1]
          w <- rast(nrows=100,ncols=100,xmin=0,xmax=200,ymin=0,ymax=200,crs="EPSG:3067")
          w[] <- 12
          l <- rast(w); l[] <- NA_real_
          at <- cellFromRowCol(w,c(51,61,65,1,71),c(51,61,65,1,71))
          l[at] <- c(101,105,105,102,103); w[at] <- 10
          writeRaster(w,file.path(d,"w.tif"),datatype="FLT8S")
          writeRaster(l,file.path(d,"id.tif"),datatype="INT4S")
        ''', str(cls.fixture_data)], capture_output=True, text=True)
        if p.returncode:
            raise RuntimeError('Synthetic raster creation failed: ' + p.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def setUp(self):
        self.d = Path(tempfile.mkdtemp(dir=self.base, prefix='case-'))
        self.data = self.d / 'inputs'; self.data.mkdir()
        for name, original in [(bundle.WATER, 'w.tif'), (bundle.LAKE, 'id.tif')]:
            p = self.data / name; p.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.fixture_data / original, p)
        self.q = self.data / bundle.SUMMARY
        self.fields = ['lake_objectid', 'n_lake_cells', 'n_raised_lake_cells', 'raised_fraction',
                       'n_depression_components', 'depression_component_ids', 'spill_raised',
                       'spill_raise_m', 'storage_raised', 'max_storage_raise_m']
        self.rows = [[101,1,0,0,0,'','TRUE',2,'FALSE',0],
                     [105,2,0,0,0,'','TRUE',2,'FALSE',0],
                     [102,1,0,0,0,'','TRUE',2,'FALSE',0],
                     [103,1,0,0,0,'','FALSE',0,'FALSE',0]]
        self.write_summary()
        self.profile = {'mode': 'synthetic', 'root': str(self.data), 'total': 4, 'positive': 3,
                        'excluded': '102', 'max_window': 250000,
                        'pins': {name: hashlib.sha256((self.data / name).read_bytes()).hexdigest()
                                 for name in (bundle.WATER, bundle.LAKE)}}
        self.config = self.d / 'fixture.json'; self.save_profile()
        self.out = self.d / 'reports'; self.out.mkdir()

    def write_summary(self):
        with self.q.open('w', newline='') as f:
            writer = csv.writer(f); writer.writerow(self.fields); writer.writerows(self.rows)

    def save_profile(self):
        self.config.write_text(json.dumps(self.profile))

    def chain(self, sha=None, real=False, env=None):
        cmd = ['bash', str(self.code / 'scripts/roihu_probe_rstudio.sh'),
               '--expected-commit', sha or self.sha, '--output-parent', str(self.out)]
        if not real:
            cmd += ['--synthetic-fixture', str(self.config)]
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=75, env=env)
        dirs = sorted(self.out.glob('fill_probe_*'))
        self.assertTrue(dirs, p.stderr)
        report = dirs[-1]
        self.assertTrue((report / 'review_bundle.tar.gz').is_file(), p.stdout + p.stderr)
        with tarfile.open(report / 'review_bundle.tar.gz', 'r:gz') as tar:
            names = tar.getnames()
            self.assertTrue(all('/' not in n and not n.endswith('.tif') for n in names))
            archived = {n: tar.extractfile(n).read() for n in names}
        state = json.loads(archived['summary.json'])
        self.assertEqual(state['MODERATE'], 'REVIEW_REQUIRED')
        self.assertEqual(state['NATIONAL'], 'LOCKED')
        self.assertFalse(state['continuation_authorized'])
        self.assertEqual(state['hydrological_success'], 'NOT_ASSESSED')
        self.assertEqual((report / 'review_bundle.sha256').read_text().split()[0],
                         hashlib.sha256((report / 'review_bundle.tar.gz').read_bytes()).hexdigest())
        return p, state, archived

    def test_complete_chain_selects_all_parts_and_keeps_global_coordinates(self):
        before = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in self.data.rglob('*') if p.is_file()}
        p, state, files = self.chain()
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr + str(state))
        self.assertEqual(state['technical_status'], 'COMPLETE')
        self.assertEqual(len(state['memory_checks']), 3)  # Initial + two windows.
        self.assertTrue(all(x['method'] == 'CGROUP_V2' and x['sufficient_for_bounded_child']
                            for x in state['memory_checks']))
        plan = list(csv.DictReader(files['windows.csv'].decode().splitlines()))
        self.assertEqual([x['lake_objectid'] for x in plan], ['101', '105'])
        self.assertTrue(all(int(x['cells']) <= 250000 for x in plan))
        lake = list(csv.DictReader(files['lake_101.csv'].decode().splitlines()))
        self.assertEqual(int(lake[0]['seed_row']), 51)
        self.assertEqual(int(lake[0]['seed_col']), 51)
        pieces = list(csv.DictReader(files['lake_105.csv'].decode().splitlines()))
        self.assertEqual(len(pieces), 2)
        self.assertTrue(all(x['full_id_cell_count_matches_report'] == 'TRUE' for x in pieces))
        self.assertEqual(before, {q: hashlib.sha256(q.read_bytes()).hexdigest() for q in before})

    def test_missing_historical_log_never_becomes_execution_proof(self):
        p, state, files = self.chain()
        self.assertEqual(p.returncode, 0)
        inv = json.loads(files['inventory.json'])
        self.assertEqual(inv[1]['state'], 'MISSING')
        self.assertEqual(inv[-1]['state'], 'NOT_CHECKED')
        self.assertEqual(state['historical_provenance'], 'INCOMPLETE')
        self.assertFalse(state['historical_attribution_authorized'])

    def test_raw_historical_logs_and_secret_canary_not_exported(self):
        (self.data / 'history.log').write_text('SECRET_CANARY_NEVER_EXPORT\nRunning WATER_STORAGE FillDepressions\ncache skipped\n')
        p, _, files = self.chain()
        self.assertEqual(p.returncode, 0)
        self.assertNotIn(b'SECRET_CANARY_NEVER_EXPORT', b''.join(files.values()))
        history = json.loads(files['inventory.json'])[1]
        self.assertEqual(history['state'], 'AVAILABLE')
        self.assertEqual(history['marker_lines']['fill_started'], [2])

    def test_wrong_code_pin_blocks_before_any_input_read(self):
        p, state, files = self.chain(sha='0' * 40)
        self.assertEqual(p.returncode, 2)
        self.assertIn('commit mismatch', state['reason'])
        self.assertNotIn('input_bindings.json', files)

    def test_fresh_clone_bootstrap_uses_exact_commit(self):
        clone = self.d / 'cloned-code'
        subprocess.run(['git', 'clone', '--quiet', '--no-hardlinks', str(self.code), str(clone)], check=True)
        subprocess.run(['git', '-C', str(clone), 'checkout', '--quiet', '--detach', self.sha], check=True)
        self.code = clone
        p, state, _ = self.chain()
        self.assertEqual(p.returncode, 0)
        self.assertEqual(state['code_commit'], self.sha)

    def test_empty_successful_r_process_cannot_report_success(self):
        fakebin = self.d / 'bin'; fakebin.mkdir()
        fake = fakebin / 'Rscript'; fake.write_text('#!/bin/sh\nexit 0\n'); fake.chmod(0o700)
        env = os.environ.copy(); env['PATH'] = str(fakebin) + ':' + env['PATH']
        p, state, files = self.chain(env=env)
        self.assertEqual(p.returncode, 2)
        self.assertEqual(state['technical_status'], 'BLOCKED')
        self.assertNotIn('lake_101.csv', files)

    def test_dirty_checkout_is_blocked(self):
        marker = self.code / 'untracked.txt'; marker.write_text('unreviewed')
        try:
            p, state, _ = self.chain()
            self.assertEqual(p.returncode, 2); self.assertIn('clean', state['reason'])
        finally:
            marker.unlink()

    def test_hash_mismatch_cannot_reach_raster_planner(self):
        (self.data / bundle.WATER).write_bytes(b'changed input')
        p, state, files = self.chain()
        self.assertEqual(p.returncode, 2); self.assertIn('hash', state['reason'])
        self.assertNotIn('planner.log', files)
        self.assertFalse(json.loads(files['input_bindings.json'])[0]['matched'])

    def test_missing_raster_has_distinct_missing_state(self):
        (self.data / bundle.LAKE).unlink()
        p, _, files = self.chain()
        self.assertEqual(p.returncode, 2)
        self.assertEqual(json.loads(files['input_bindings.json'])[-1]['state'], 'MISSING')

    def test_symlink_raster_has_distinct_unreadable_state(self):
        lake = self.data / bundle.LAKE; lake.unlink(); lake.symlink_to(self.fixture_data / 'id.tif')
        p, _, files = self.chain()
        self.assertEqual(p.returncode, 2)
        self.assertEqual(json.loads(files['input_bindings.json'])[-1]['state'], 'UNREADABLE')
        self.assertNotIn('planner.log', files)

    def test_open_failure_is_unreadable_not_available_from_stat(self):
        args = argparse.Namespace(expected_commit=self.sha, synthetic_fixture=str(self.config))
        digest = bundle.digest
        def inaccessible(p, deadline):
            if p == self.data / bundle.LAKE:
                raise PermissionError('Synthetic read denied')
            return digest(p, deadline)
        with patch.object(bundle, 'CODE', self.code), patch.object(bundle, 'digest', inaccessible):
            with self.assertRaises(PermissionError):
                bundle.run(args, self.out, {})
        binding = json.loads((self.out / 'input_bindings.json').read_text())[-1]
        self.assertEqual(binding['state'], 'UNREADABLE')
        self.assertEqual(binding['hash_status'], 'NOT_CHECKED')

    def test_unpinned_sidecar_is_blocked(self):
        Path(str(self.data / bundle.WATER) + '.aux.xml').write_text('<untrusted/>')
        p, state, files = self.chain()
        self.assertEqual(p.returncode, 2); self.assertIn('sidecar', state['reason'])
        self.assertNotIn('planner.log', files)

    def test_missing_summary_column_blocks_planner_without_probes(self):
        self.fields[1] = 'missing_count'; self.write_summary()
        p, state, files = self.chain()
        self.assertEqual(p.returncode, 2); self.assertEqual(state['technical_status'], 'BLOCKED')
        self.assertNotIn('lake_101.csv', files)

    def test_oversized_window_is_recorded_and_never_read(self):
        self.profile['max_window'] = 100; self.save_profile()
        p, state, files = self.chain()
        self.assertEqual(p.returncode, 2); self.assertEqual(state['technical_status'], 'PARTIAL')
        self.assertTrue(all(x['status'] == 'BLOCKED_WINDOW_TOO_LARGE' for x in state['steps']))
        self.assertNotIn('lake_101.csv', files)

    def test_count_mismatch_does_not_trim_disconnected_lake(self):
        self.rows[1][1] = 3; self.write_summary()
        p, state, files = self.chain()
        self.assertEqual(p.returncode, 2)
        self.assertEqual(state['steps'][1]['status'], 'BLOCKED_ID_COUNT_MISMATCH')
        self.assertNotIn('lake_105.csv', files)

    def test_invalid_real_allocation_id_blocks_without_csc_access(self):
        env = os.environ.copy(); env['SLURM_JOB_ID'] = '../2354869'
        p, state, files = self.chain(real=True, env=env)
        self.assertEqual(p.returncode, 2); self.assertIn('SLURM_JOB_ID', state['reason'])
        self.assertNotIn('inventory.json', files)

    def test_synthetic_profile_cannot_access_csc(self):
        self.profile['root'] = str(bundle.ROOT); self.save_profile()
        p, state, files = self.chain()
        self.assertEqual(p.returncode, 2); self.assertIn('temporary directory', state['reason'])
        self.assertNotIn('inventory.json', files)

    def test_memory_shortage_stops_before_input_inspection(self):
        args = argparse.Namespace(expected_commit=self.sha, synthetic_fixture=str(self.config))
        state = {}
        with patch.object(bundle, 'CODE', self.code), patch.object(bundle, 'available_memory', return_value={'available_bytes': 1}):
            with self.assertRaisesRegex(bundle.Blocked, '3 GiB'):
                bundle.run(args, self.out, state)
        self.assertFalse((self.out / 'inventory.json').exists())

    def test_source_change_during_observations_invalidates_results(self):
        args = argparse.Namespace(expected_commit=self.sha, synthetic_fixture=str(self.config))
        execute = bundle.execute
        def changing_execute(*args, **kwargs):
            execute(*args, **kwargs)
            # Simulate another process replacing the report after our snapshot.
            if not self.q.read_bytes().endswith(b'\n\n'):
                with self.q.open('ab') as f:
                    f.write(b'\n')
        with patch.object(bundle, 'CODE', self.code), patch.object(bundle, 'execute', changing_execute):
            with self.assertRaisesRegex(bundle.Blocked, 'Source summary changed'):
                bundle.run(args, self.out, {})

    def test_unsafe_paths_and_parent_symlinks_rejected(self):
        link = self.d / 'link'; link.symlink_to(self.out, target_is_directory=True)
        for p in [str(self.out) + '/../escape', str(link / 'child'), str(self.out / '*.tif'), 'relative']:
            with self.subTest(path=p), self.assertRaises(bundle.Blocked):
                bundle.safe_path(p)


if __name__ == '__main__':
    spec = importlib.util.spec_from_file_location('memory_tests', ROOT / 'tests/roihu_memory.py')
    memory = importlib.util.module_from_spec(spec); spec.loader.exec_module(memory)
    memory_suite = unittest.defaultTestLoader.loadTestsFromTestCase(memory.MemorySafety)
    chain_suite = unittest.defaultTestLoader.loadTestsFromTestCase(BundleChain)
    if not memory_suite.countTestCases() or not chain_suite.countTestCases():
        raise SystemExit('FAIL: no Roihu chain tests discovered')
    suite = unittest.TestSuite([memory_suite, chain_suite])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
