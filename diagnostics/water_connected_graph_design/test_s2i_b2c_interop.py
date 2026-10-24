"""Only new detached-loader / actual synthetic native02F-to-v2 tests.

The R stage is separate. Accepted v2/S2F test modules are never imported.
"""
import ast
from dataclasses import replace
import json
import os
from pathlib import Path
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

import s2i_b2c_pinned_sources as loader
from s2i_b2b_native_value_v2 import (
    Header, Request, Values, Batch, Transcript, encode, decode, compare_synthetic_reference, Stop,
)

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
RUN = "123e4567-e89b-42d3-a456-426614174000"
ATTEMPT = "123e4567-e89b-42d3-a456-426614174001"
NA = bytes.fromhex("a20700000000f07f")
QNAN = bytes.fromhex("010000000000f87f")


def integers(xs):
    return Values("INTEGER",tuple("NA_INTEGER" if x is None else "FINITE" for x in xs),
                  b"".join(struct.pack("<i",-2147483648 if x is None else x) for x in xs))


def doubles(xs):
    tags=[];raw=[]
    for x in xs:
        if x is None:tags.append("NA_REAL");raw.append(NA)
        elif x is QNAN:tags.append("NAN");raw.append(QNAN)
        elif x==float("inf"):tags.append("POS_INF");raw.append(struct.pack("<d",x))
        elif x==float("-inf"):tags.append("NEG_INF");raw.append(struct.pack("<d",x))
        else:tags.append("FINITE");raw.append(struct.pack("<d",x))
    return Values("DOUBLE",tuple(tags),b"".join(raw))


def expected_observations(version,platform):
    """Independent declared tiny fixtures + explicit observed-cell expectations.

    No chain reconstruction or expected values derived from R wire under test.
    """
    cases={}
    def build(name,size,steps):
        batches=[]
        for cells,water,lake,pointer in steps:
            req=Request("INTEGER",b"".join(struct.pack("<i",n) for n in cells))
            for role,val in zip(("WATER_CLASS","LAKE_ID","POINTER"),(water,lake,pointer)):
                batches.append(Batch(len(batches)+1,role,req,val))
        cases[name]=Transcript(Header(RUN,ATTEMPT,"tiny",size,size,0,0,version,platform),tuple(batches))
    build("chain",3,[((5,5),doubles((None,None)),integers((None,None)),doubles((2,2))),
                     ((6,6),doubles((3,3)),integers((None,None)),doubles((0,0)))])
    build("convergence",5,[((6,7),integers((None,None)),doubles((None,None)),doubles((4,8))),
        ((12,12),integers((None,None)),doubles((None,None)),doubles((8,8))),
        ((17,17),integers((2,2)),doubles((16777217,16777217)),doubles((-0.0,-0.0)))])
    build("lake",3,[((5,),doubles((None,)),integers((None,)),integers((2,))),
                    ((6,),doubles((1,)),integers((16777217,)),integers((0,)))])
    build("special",3,[(tuple(range(1,10)),doubles((None,)*9),integers((None,)*9),
        doubles((None,QNAN,float("inf"),float("-inf"),0.0,-0.0,3,0.25,128)))])
    build("work_limit",5,[((13,),doubles((None,)),integers((None,)),integers((2,)))])
    return cases


class LoaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.blobs={r:loader.git_read(REPO,("show","--no-textconv",p+":"+f),time.monotonic()+5)
                   for r,p,f,_ in loader.SOURCES}

    def test_real_offline_selector_and_hex_loader(self):
        data=loader.build_bootstrap(REPO)
        self.assertLessEqual(len(data),262144)
        for raw in self.blobs.values():self.assertIn(raw.hex().encode("ascii"),data)
        self.assertNotIn(str(REPO).encode(),data)

    def test_source_corruption_rejects_each_role(self):
        for role,raw in self.blobs.items():
            with self.subTest(role=role),self.assertRaisesRegex(loader.Stop,"SOURCE_BYTES_MISMATCH"):
                loader.verify_blob(role,raw[:-1]+bytes((raw[-1]^1,)))

    def test_missing_extra_or_unknown_blob_scope_rejects(self):
        for b in ({},dict(self.blobs,extra=b"x")):
            with self.assertRaisesRegex(loader.Stop,"SOURCE_SET"):loader.render(b)
        with self.assertRaisesRegex(loader.Stop,"BLOB_SCOPE"):loader.verify_blob("unknown",b"x")

    def test_oversized_blob_rejected_before_hashing(self):
        with self.assertRaisesRegex(loader.Stop,"BLOB_SCOPE"):
            loader.verify_blob("native",b"x"*32769)

    def test_environment_disables_fetch_replace_transports_and_overrides(self):
        with mock.patch.dict(os.environ,{"GIT_DIR":"wrong","GIT_OBJECT_DIRECTORY":"wrong",
                                        "GIT_CONFIG_COUNT":"1","GIT_TRACE":"secret-path"}):
            env=loader.git_environment()
        self.assertEqual(env["GIT_NO_LAZY_FETCH"],"1")
        self.assertEqual(env["GIT_NO_REPLACE_OBJECTS"],"1")
        self.assertEqual(env["GIT_ALLOW_PROTOCOL"],"")
        self.assertEqual(env["GIT_TERMINAL_PROMPT"],"0")
        for key in ("GIT_DIR","GIT_OBJECT_DIRECTORY","GIT_CONFIG_COUNT","GIT_TRACE"):
            self.assertNotIn(key,env)

    def empty_repo(self,path):
        subprocess.run(["git","init","--quiet",str(path)],check=True,env=loader.git_environment())
        subprocess.run(["git","-C",str(path),"config","remote.origin.url",loader.ORIGIN],check=True)

    def test_empty_repo_missing_pin_stops_without_creating_output(self):
        with tempfile.TemporaryDirectory(prefix="mm-s2c-empty-") as d:
            repo=Path(d)/"repo";self.empty_repo(repo)
            with self.assertRaisesRegex(loader.Stop,"GIT_READ_STOP"):
                loader.build_bootstrap(repo)

    def test_missing_promisor_object_does_not_launch_fetch(self):
        with tempfile.TemporaryDirectory(prefix="mm-s2c-promisor-") as d:
            repo=Path(d)/"repo";self.empty_repo(repo)
            subprocess.run(["git","-C",str(repo),"config","core.repositoryformatversion","1"],check=True)
            subprocess.run(["git","-C",str(repo),"config","extensions.partialclone","origin"],check=True)
            subprocess.run(["git","-C",str(repo),"config","remote.origin.promisor","true"],check=True)
            trace=Path(d)/"trace.json";real=loader.git_environment
            def traced():
                env=real();env["GIT_TRACE2_EVENT"]=str(trace);return env
            with mock.patch.object(loader,"git_environment",side_effect=traced),self.assertRaises(loader.Stop):
                loader.build_bootstrap(repo)
            events=[json.loads(line) for line in trace.read_text().splitlines()]
            self.assertFalse(any(e.get("event")=="child_start" and "fetch" in e.get("argv",[])
                                 for e in events))

    def test_other_origin_stops_before_any_blob_read(self):
        with tempfile.TemporaryDirectory(prefix="mm-s2c-origin-") as d:
            repo=Path(d)/"repo";self.empty_repo(repo)
            subprocess.run(["git","-C",str(repo),"config","remote.origin.url","https://example.invalid/other"],check=True)
            with self.assertRaisesRegex(loader.Stop,"CANONICAL_ORIGIN_REQUIRED"):
                loader.build_bootstrap(repo)

    def test_base_native_divergence_stops(self):
        real=loader.git_read
        def altered(repo,args,deadline,limit=loader.MAX_BLOB):
            if args==("show","--no-textconv",loader.BASE_PIN+":"+loader.SOURCES[0][2]):return b"altered"
            return real(repo,args,deadline,limit)
        with mock.patch.object(loader,"git_read",side_effect=altered),self.assertRaisesRegex(loader.Stop,"NATIVE_BASE_DIVERGED"):
            loader.build_bootstrap(REPO)

    def test_private_output_is_fresh_and_never_overwrites(self):
        with tempfile.TemporaryDirectory(prefix="mm-s2c-private-") as d:
            path=Path(d)/"loader.R";loader.write_new_private(path,b"fixed")
            self.assertEqual(stat.S_IMODE(path.stat().st_mode),0o600)
            with self.assertRaises(FileExistsError):loader.write_new_private(path,b"other")
            self.assertEqual(path.read_bytes(),b"fixed")

    def test_output_parent_must_be_private(self):
        with tempfile.TemporaryDirectory(prefix="mm-s2c-mode-") as d:
            Path(d).chmod(0o755)
            with self.assertRaisesRegex(loader.Stop,"PRIVATE_OUTPUT_DIRECTORY"):
                loader.write_new_private(Path(d)/"bad.R",b"fixed")

    def test_output_symlink_parent_rejects(self):
        with tempfile.TemporaryDirectory(prefix="mm-s2c-link-") as d:
            actual=Path(d)/"actual";actual.mkdir(mode=0o700)
            alias=Path(d)/"alias";alias.symlink_to(actual,target_is_directory=True)
            with self.assertRaisesRegex(loader.Stop,"OUTPUT_SYMLINK_PARENT"):
                loader.write_new_private(alias/"bad.R",b"fixed")

    def fake_git(self,path,body):
        path.write_text("#!"+sys.executable+"\n"+body)
        path.chmod(0o700);return str(path)

    def test_fake_git_reuses_running_interpreter_not_path_wrapper(self):
        with tempfile.TemporaryDirectory(prefix="mm-s2c-python-wrapper-") as d:
            wrapper=Path(d)/"python3"
            wrapper.write_text("#!/bin/sh\nexit 93\n")
            wrapper.chmod(0o700)
            with mock.patch.dict(os.environ,{"PATH":d+os.pathsep+os.environ.get("PATH","")}):
                self.assertEqual(shutil.which("python3"),str(wrapper))
                binary=self.fake_git(Path(d)/"git","print('CURRENT_INTERPRETER_ONLY')\n")
                result=subprocess.run([binary],capture_output=True,text=True,timeout=2,check=False)
            self.assertEqual(result.returncode,0)
            self.assertEqual(result.stdout,"CURRENT_INTERPRETER_ONLY\n")
            self.assertEqual(result.stderr,"")

    def test_git_stdout_is_bounded(self):
        with tempfile.TemporaryDirectory(prefix="mm-s2c-budget-") as d:
            binary=self.fake_git(Path(d)/"git","import sys\nsys.stdout.write('x'*40000)\n")
            with mock.patch.object(loader.shutil,"which",return_value=binary),self.assertRaisesRegex(loader.Stop,"GIT_OUTPUT_LIMIT"):
                loader.git_read(REPO,(),time.monotonic()+5)

    def test_git_timeout_is_STOP(self):
        with tempfile.TemporaryDirectory(prefix="mm-s2c-timeout-") as d:
            binary=self.fake_git(Path(d)/"git","import time\ntime.sleep(2)\n")
            with mock.patch.object(loader.shutil,"which",return_value=binary),self.assertRaises(loader.Stop):
                loader.git_read(REPO,(),time.monotonic()+0.15)

    def test_loader_has_no_R_execution_or_git_mutation_path(self):
        tree=ast.parse((ROOT/"s2i_b2c_pinned_sources.py").read_text())
        calls=[n for n in ast.walk(tree) if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute)
               and n.func.attr=="Popen"]
        self.assertEqual(len(calls),1)
        src=(ROOT/"s2i_b2c_pinned_sources.py").read_text()
        self.assertNotIn('"fetch",',src)
        self.assertNotIn('"checkout",',src)
        self.assertNotIn('"merge",',src)


@unittest.skipUnless(os.environ.get("MM_S2C_R_OUTPUT"),"NOT_RUN: separate new R stage not supplied")
class NativeInteropTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        p=Path(os.environ["MM_S2C_R_OUTPUT"]);info=p.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_size>65536:raise AssertionError("R_OUTPUT_BUDGET")
        with p.open("rb") as f:raw=f.read(65537)
        if len(raw)>65536:raise AssertionError("R_OUTPUT_BUDGET")
        cls.wires={};summaries=[];passes=[];pins=[]
        for line in raw.decode("ascii").splitlines():
            if re.fullmatch(r"PASS [A-Za-z0-9_]+",line):passes.append(line);continue
            m=re.fullmatch(r"S2C_CASE=([a-z_]+)\|WIRE=([0-9a-f]+)",line)
            if m:
                name,wire=m.groups()
                if name in cls.wires:raise AssertionError("DUPLICATE_R_CASE")
                cls.wires[name]=bytes.fromhex(wire);continue
            m=re.fullmatch(r"R_S2C_SUMMARY PASS=([1-9][0-9]*) FAIL=0 NOT_RUN=0 R=([0-9.]+) PLATFORM=([A-Za-z0-9._-]+)",line)
            if m:summaries.append(m.groups());continue
            if line=="S2C_SOURCE_PIN="+loader.S2F_PIN+"|V2_PIN="+loader.BASE_PIN:pins.append(line);continue
            raise AssertionError("R_STAGE_INCOMPLETE_OR_INVALID:"+line[:120])
        if len(summaries)!=1 or len(pins)!=1 or len(set(passes))!=len(passes):raise AssertionError("R_STAGE_INCOMPLETE")
        count,version,platform=summaries[0]
        if len(passes)!=int(count) or int(count)!=42:raise AssertionError("R_TEST_COUNT")
        cls.expected=expected_observations(version,platform)
        if set(cls.wires)!=set(cls.expected):raise AssertionError("R_CASE_COVERAGE")

    def test_independent_expected_observations_match_every_R_wire_byte(self):
        for name,t in self.expected.items():
            with self.subTest(name=name):self.assertEqual(self.wires[name],encode(t).data)

    def test_every_decoded_request_type_tag_and_raw_response_matches(self):
        for name,t in self.expected.items():
            with self.subTest(name=name):self.assertEqual(decode(self.wires[name]).transcript,t)

    def test_each_complete_stream_roundtrips_without_coercion(self):
        for name,raw in self.wires.items():
            with self.subTest(name=name):self.assertEqual(encode(decode(raw).transcript).data,raw)

    def test_converging_paths_preserve_duplicate_downstream_requests(self):
        t=decode(self.wires["convergence"]).transcript
        self.assertEqual(t.batches[3].request.raw_le,struct.pack("<ii",12,12))
        self.assertEqual(t.batches[6].request.raw_le,struct.pack("<ii",17,17))

    def test_special_pointer_bits_and_tags_come_from_the_native_callback(self):
        p=decode(self.wires["special"]).transcript.batches[2].response
        self.assertEqual(p.validity,("NA_REAL","NAN","POS_INF","NEG_INF")+("FINITE",)*5)
        self.assertEqual(p.raw_le[8:16],QNAN)
        self.assertEqual(p.raw_le[40:48],bytes.fromhex("0000000000000080"))

    def test_large_native_lake_ID_remains_Int32(self):
        v=decode(self.wires["lake"]).transcript.batches[4].response
        self.assertEqual(v.storage_type,"INTEGER")
        self.assertEqual(v.raw_le,bytes.fromhex("01000001"))

    def test_all_six_role_storage_combinations_match_the_observations(self):
        pairs={(b.role,b.response.storage_type) for w in self.wires.values()
               for b in decode(w).transcript.batches}
        self.assertEqual(pairs,{(r,s) for r in ("WATER_CLASS","LAKE_ID","POINTER") for s in ("INTEGER","DOUBLE")})

    def test_step_limit_stream_has_only_the_actual_three_queries(self):
        t=decode(self.wires["work_limit"]).transcript
        self.assertEqual(len(t.batches),3)
        self.assertEqual(t.batches[0].request.raw_le,struct.pack("<i",13))

    def test_valid_modified_values_fail_reference(self):
        t=self.expected["chain"]
        v=replace(t.batches[2].response,raw_le=struct.pack("<dd",4,4))
        changed=replace(t,batches=t.batches[:2]+(replace(t.batches[2],response=v),)+t.batches[3:])
        with self.assertRaisesRegex(Stop,"REFERENCE_BYTES_MISMATCH"):
            compare_synthetic_reference(encode(changed).data,self.wires["chain"])

    def test_missing_complete_triplet_cannot_claim_reference_equivalence(self):
        t=self.expected["chain"]
        shorter=replace(t,batches=t.batches[:3])
        with self.assertRaisesRegex(Stop,"REFERENCE_BYTES_MISMATCH"):
            compare_synthetic_reference(encode(shorter).data,self.wires["chain"])

    def test_transport_truncation_is_STOP(self):
        with self.assertRaises(Stop):decode(self.wires["chain"][:-1])

    def test_byte_equivalence_does_not_authenticate_or_authorize(self):
        r=compare_synthetic_reference(self.wires["chain"],encode(self.expected["chain"]).data)
        self.assertEqual(r.disposition,"RECORDED_UNVERIFIED")
        self.assertEqual(r.safety.NATIONAL,"LOCKED")
        self.assertFalse(r.safety.routing_authorized)
        self.assertEqual(r.safety.HISTORIC_02F_EFFECTIVE_D8,"NOT_ASSESSED")


if __name__=="__main__":
    unittest.main()
