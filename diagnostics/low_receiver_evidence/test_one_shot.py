#!/usr/bin/env python3
"""Supervisor regression tests. Temporary fixtures never contact CSC/GitHub."""
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock
import run_one_shot as runner


class Supervisor(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='mm-offline-unit-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def process(self, code, seconds=3, memory=runner.MEMORY_BYTES):
        return runner.bounded([sys.executable,'-B','-c',code],self.root/'child.log',
                              self.root,seconds,time.monotonic()+5,memory)

    def test_success(self):
        r=self.process('print("small offline child")')
        self.assertEqual(r['status'],'PASS')

    def test_nonzero_is_failure(self):
        self.assertEqual(self.process('raise SystemExit(7)')['reason'],'NONZERO_EXIT')

    def test_timeout(self):
        self.assertEqual(self.process('import time;time.sleep(5)',0.08)['reason'],'TIME_LIMIT')

    def test_memory_limit(self):
        self.assertEqual(self.process('import time;x=bytearray(32*1024**2);time.sleep(2)',
                                      memory=1024**2)['reason'],'MEMORY_LIMIT')

    def test_log_limit(self):
        with mock.patch.object(runner,'MAX_LOG_BYTES',1024):
            self.assertEqual(self.process('import time;print("x"*8192,flush=True);time.sleep(2)')['reason'],'LOG_LIMIT')

    def test_missing_executable(self):
        r=runner.bounded([str(self.root/'absent')],self.root/'absent.log',self.root,
                         1,time.monotonic()+2)
        self.assertEqual(r['reason'],'DEPENDENCY_EXEC_FAILED')

    def test_timeout_cleans_descendants(self):
        pidfile=self.root/'child.pid'
        code=('import subprocess,time;from pathlib import Path;'
              'p=subprocess.Popen(["'+sys.executable+'","-c","import time;time.sleep(20)"]);'
              'Path('+repr(str(pidfile))+').write_text(str(p.pid));time.sleep(20)')
        self.process(code,0.5)
        pid=int(pidfile.read_text())
        # A killed child may remain a zombie until the container reaps it.
        p=Path('/proc')/str(pid)/'stat'
        self.assertTrue(not p.exists() or p.read_text().rsplit(')',1)[1].split()[0]=='Z')

    def test_memory_accounts_for_child_in_another_session(self):
        code=('import subprocess,time;subprocess.Popen(["'+sys.executable+'","-c",'
              '"import time;x=bytearray(24*1024**2);time.sleep(5)"],start_new_session=True);time.sleep(5)')
        r=self.process(code,memory=20*1024**2)
        self.assertEqual(r['reason'],'MEMORY_LIMIT')

    def test_global_deadline_overrides_suite_budget(self):
        r=runner.bounded([sys.executable,'-c','import time;time.sleep(5)'],
                         self.root/'deadline.log',self.root,10,time.monotonic()+0.08)
        self.assertEqual(r['reason'],'TIME_LIMIT')

    def test_git_refuses_after_whole_package_deadline(self):
        with mock.patch.object(runner,'ACTIVE_DEADLINE',time.monotonic()-1):
            with self.assertRaisesRegex(runner.Stop,'TOTAL_TIME_LIMIT'):
                runner.git(self.root,'status')

    def test_no_overwrite_existing_log(self):
        p=self.root/'child.log';p.write_text('original')
        with self.assertRaises(FileExistsError): self.process('print(1)')
        self.assertEqual(p.read_text(),'original')

    def test_positive_summary(self):
        self.assertEqual(runner.require_summary('SUITE_RESULT cases=2 pass=2 fail=0 not_run=0\n')['pass'],2)

    def test_zero_fail_skip_duplicate_or_missing_summary(self):
        for text in ('','SUITE_RESULT cases=0 pass=0 fail=0 not_run=0',
                     'SUITE_RESULT cases=2 pass=1 fail=1 not_run=0',
                     'SUITE_RESULT cases=2 pass=1 fail=0 not_run=1',
                     'SUITE_RESULT cases=2 pass=3 fail=0 not_run=0',
                     'SUITE_RESULT cases=1 pass=1 fail=0 not_run=0\n'*2):
            with self.subTest(text=text),self.assertRaises(runner.Stop): runner.require_summary(text)

    def test_pr32_exact_pinned_summary(self):
        text='RESULT n=27 scenario=complete_dag cases=15 checks=739 stop_cases=53 status=PASS'
        self.assertEqual(runner.require_pr32_summary(text)['expected_stops'],53)
        for bad in ('',text+'\n'+text,text.replace('739','738'),text.replace('PASS','FAIL')):
            with self.subTest(bad=bad),self.assertRaises(runner.Stop):runner.require_pr32_summary(bad)

    def fixture_repo(self):
        repo=self.root/'code';repo.mkdir()
        def git(*args):
            return subprocess.check_output(['git','-C',str(repo),*args],stderr=subprocess.STDOUT).decode().strip()
        git('init','--quiet','--initial-branch='+runner.BRANCH)
        git('remote','add','origin',runner.ORIGIN)
        (repo/'source.txt').write_text('fixture only')
        git('add','source.txt')
        git('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','--quiet','-m','fixture')
        return repo,git('rev-parse','HEAD'),git

    def test_clean_git_fixture(self):
        repo,pin,_=self.fixture_repo()
        self.assertEqual(set(runner.checkout(repo,pin,runner.BRANCH)),{'source.txt'})

    def test_wrong_commit_origin_and_branch(self):
        repo,pin,git=self.fixture_repo()
        for bad in ('',pin[:8],'0'*40):
            with self.subTest(pin=bad),self.assertRaises(runner.Stop): runner.checkout(repo,bad,runner.BRANCH)
        with self.assertRaisesRegex(runner.Stop,'WRONG_BRANCH'):runner.checkout(repo,pin,'wrong')
        git('remote','set-url','origin','https://example.invalid/wrong')
        with self.assertRaisesRegex(runner.Stop,'ORIGIN'):runner.checkout(repo,pin,runner.BRANCH)

    def test_dirty_tracked_untracked_and_ignored(self):
        repo,pin,git=self.fixture_repo()
        (repo/'source.txt').write_text('changed')
        with self.assertRaisesRegex(runner.Stop,'DIRTY'):runner.checkout(repo,pin,runner.BRANCH)
        (repo/'source.txt').write_text('fixture only')
        (repo/'extra').write_text('untracked')
        with self.assertRaisesRegex(runner.Stop,'DIRTY'):runner.checkout(repo,pin,runner.BRANCH)
        (repo/'extra').unlink()
        (repo/'.git/info/exclude').write_text('extra\n')
        (repo/'extra').write_text('ignored')
        with self.assertRaisesRegex(runner.Stop,'DIRTY'):runner.checkout(repo,pin,runner.BRANCH)

    def test_content_snapshot_detects_change(self):
        repo,pin,_=self.fixture_repo(); before=runner.snapshot(repo)
        (repo/'source.txt').write_text('changed')
        self.assertNotEqual(before,runner.snapshot(repo))

    def test_symlink_source_rejected(self):
        repo,pin,_=self.fixture_repo();(repo/'source.txt').unlink()
        (repo/'source.txt').symlink_to('/dev/null')
        with self.assertRaisesRegex(runner.Stop,'REGULAR'):runner.snapshot(repo)

    def simulated_run(self, mode='pass'):
        # Deliberately fake suite programs exercise orchestration, not the real
        # receiver/R/PR32 tests. Real end-to-end execution is reported separately.
        repo=self.root/'simulated';here=repo/'diagnostics/low_receiver_evidence';here.mkdir(parents=True)
        for name in ('test_observed_receivers.py','test_one_shot.py'):
            fail=(mode=='suite_failure' and name=='test_observed_receivers.py')
            (here/name).write_text('print("SUITE_RESULT cases=1 pass=1 fail=0 not_run=0");raise SystemExit('+str(int(fail))+')')
        r=self.root/'fake_Rscript'
        r.write_text('#!'+sys.executable+'\nimport sys\n'
          'if "-e" in sys.argv: print("R_VERSION=FAKE TERRA_VERSION=FAKE")\n'
          'elif "test_count_core.R" in sys.argv[-1]: print("RESULT n=27 scenario=complete_dag cases=15 checks='+('738' if mode=='pr32_bad_summary' else '739')+' stop_cases=53 status=PASS")\n'
          'else: print("SUITE_RESULT cases=1 pass=1 fail=0 not_run=0")\n')
        r.chmod(0o700)
        separate=self.root/'pr32';separate.mkdir()
        output=self.root/'reports'
        if mode=='existing_output': output.mkdir();(output/'summary.json').write_text('old')
        if mode=='inside_output': output=repo/'reports'
        if mode=='symlink_output':
            parent=self.root/'linked';parent.symlink_to(repo, target_is_directory=True);output=parent/'reports'
        args=['--expected-commit','a'*40,'--report-dir',str(output),'--pr32-repo',str(separate)]
        if mode=='no_pr32':args=args[:-2]
        if mode=='missing_pin':args=args[2:]
        if mode=='version_mismatch':args+=['--expected-r-version','4.6.1','--expected-terra-version','1.9.34']
        def check(*args):
            if mode=='post_change' and check.calls>=2:raise runner.Stop('DIRTY_CHECKOUT')
            check.calls+=1;return {'file':'digest'}
        check.calls=0
        with mock.patch.object(runner,'HERE',here),mock.patch.object(runner,'checkout',side_effect=check), \
             mock.patch.object(runner,'git',return_value=runner.PR22), \
             mock.patch.object(runner,'prepare_pr32',return_value=self.root/'pr32-copy'), \
             mock.patch.object(runner.shutil,'which',return_value=None if mode=='no_R' else str(r)), \
             (mock.patch.object(Path,'write_text',side_effect=OSError('fixture full disk'))
              if mode=='report_failure' else contextlib.nullcontext()):
            text=io.StringIO()
            with contextlib.redirect_stdout(text): rc=runner.main(args)
        transcript=text.getvalue()
        self.assertEqual(transcript.count('TULOKSET ALKAVAT'),1)
        summary=json.loads(transcript.split('SUMMARY=',1)[1].split('\n',1)[0])
        return rc,summary,output

    def test_simulated_all_phases_pass(self):
        rc,s,_=self.simulated_run();self.assertEqual(rc,0);self.assertEqual(s['suite_counts'],{'PASS':4,'FAIL':0,'NOT_RUN':0})

    def test_simulated_failure_keeps_independent_tests(self):
        rc,s,_=self.simulated_run('suite_failure');self.assertEqual(rc,1)
        self.assertEqual(s['suite_counts'],{'PASS':3,'FAIL':1,'NOT_RUN':0})

    def test_missing_R_is_not_run_not_pass(self):
        rc,s,_=self.simulated_run('no_R');self.assertEqual(rc,1)
        self.assertEqual(s['suite_counts'],{'PASS':2,'FAIL':0,'NOT_RUN':2})

    def test_missing_separate_checkout_is_not_run(self):
        rc,s,_=self.simulated_run('no_pr32');self.assertEqual(rc,1)
        self.assertEqual(s['suites']['pr32_separate_dag']['status'],'NOT_RUN')

    def test_missing_pin_stops_all_suites(self):
        rc,s,_=self.simulated_run('missing_pin');self.assertEqual(rc,1)
        self.assertEqual(s['suite_counts']['NOT_RUN'],4)

    def test_output_not_overwritten(self):
        rc,s,p=self.simulated_run('existing_output');self.assertEqual(rc,1)
        self.assertEqual((p/'summary.json').read_text(),'old')

    def test_post_run_mutation_prevents_pass(self):
        rc,s,_=self.simulated_run('post_change');self.assertEqual(rc,1)
        self.assertIn('POST_TEST_SOURCE_CHECK',s['stop_reason'])

    def test_output_inside_source_is_rejected(self):
        rc,s,_=self.simulated_run('inside_output');self.assertEqual(rc,1)
        self.assertEqual(s['suite_counts']['NOT_RUN'],4)
        self.assertIn('EXTERNAL_AND_UNLINKED',s['stop_reason'])

    def test_symlink_output_is_rejected(self):
        rc,s,_=self.simulated_run('symlink_output');self.assertEqual(rc,1)
        self.assertIn('EXTERNAL_AND_UNLINKED',s['stop_reason'])

    def test_mutated_evidence_stops_before_any_suite(self):
        with mock.patch('test_observed_receivers.audit_provenance',side_effect=ValueError('EVIDENCE_BYTES_CHANGED')):
            rc,s,_=self.simulated_run()
        self.assertEqual(rc,1);self.assertEqual(s['suite_counts']['NOT_RUN'],4)

    def test_wrong_R_environment_cannot_pass(self):
        rc,s,_=self.simulated_run('version_mismatch')
        self.assertEqual(rc,1);self.assertIn('R_VERSION_MISMATCH',s['stop_reason'])

    def test_report_write_failure_still_emits_failed_summary(self):
        rc,s,_=self.simulated_run('report_failure')
        self.assertEqual(rc,1);self.assertIn('REPORT_WRITE_FAILED',s['stop_reason'])

    def test_pr32_summary_mismatch_is_failure(self):
        rc,s,_=self.simulated_run('pr32_bad_summary')
        self.assertEqual(rc,1);self.assertEqual(s['suites']['pr32_separate_dag']['status'],'FAIL')


if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2,stream=sys.stdout).run(unittest.defaultTestLoader.loadTestsFromTestCase(Supervisor))
    failed=len(result.failures)+len(result.errors)
    print(f'SUITE_RESULT cases={result.testsRun} pass={result.testsRun-failed-len(result.skipped)} fail={failed} not_run={len(result.skipped)}')
    sys.exit(0 if result.wasSuccessful() and result.testsRun and not result.skipped else 1)
