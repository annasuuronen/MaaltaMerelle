"""S2I-B: opt-in actual R writer vs independent Python S2I-A byte-equivalence.

This test never reads original raster/CSV or invokes 02F production pipeline.
Enable with MM_S2IB_RSCRIPT=/path/to/Rscript in an approved synthetic environment.
"""
import ast
import os
from pathlib import Path
import re
import struct
import subprocess
import unittest

from s2i_a_synthetic_value_protocol import (
    Batch, Grid, Scalar, decode_batch, encode_batch,
    make_synthetic_claim, verify_synthetic_claim,
)

ROOT = Path(__file__).resolve().parent
R_WRITER = ROOT / 's2i_b_synthetic_wire_writer.R'
R_EMITTER = ROOT / 'test_s2i_b_synthetic_emit.R'
RUN = '123e4567-e89b-42d3-a456-426614174000'
ATTEMPT = '123e4567-e89b-42d3-a456-426614174001'
GRID = Grid('tiny', 3, 3, 199000, 6911000)
SCALAR_TAGS = {'WATER_CLASS': ('FINITE','NODATA'), 'LAKE_ID': ('FINITE','NA_INTEGER'),
               'POINTER': ('FINITE','R_NA','NAN','POS_INF','NEG_INF')}


def byte(v):
    return Scalar('NODATA' if v == 255 else 'FINITE', bytes((v,)))


def int32(v):
    return Scalar('NA_INTEGER' if v is None else 'FINITE',
                  struct.pack('<i', -2147483648 if v is None else v))


def double(v, tag='FINITE'):
    if isinstance(v, bytes):
        return Scalar(tag, v)
    return Scalar(tag, struct.pack('<d',v))


def expected():
    na = bytes.fromhex('a20700000000f07f')
    qnan = bytes.fromhex('010000000000f87f')
    scenarios = [
      ('core',(5,5,9),
       (byte(1),byte(255),byte(0)),
       (int32(16777217),int32(None),int32(-123)),
       (double(-0.0),double(na,'R_NA'),double(qnan,'NAN'))),
      ('special',(1,3,8),
       tuple(map(byte,(3,2,1))),
       tuple(map(int32,(0,2147483647,-2147483647))),
       (double(float('inf'),'POS_INF'),double(float('-inf'),'NEG_INF'),double(0.25))),
      ('directions', tuple(range(1,9)),
       tuple(byte(0) for _ in range(8)),
       tuple(int32(100+i) for i in range(8)),
       tuple(double(float(v)) for v in (1,2,4,8,16,32,64,128)))
    ]
    return {(case, role, i): encode_batch(Batch(RUN,ATTEMPT,GRID,i,role,cells,vals)).data
            for case,cells,w,l,p in scenarios
            for i,(role,vals) in enumerate((('WATER_CLASS',w),('LAKE_ID',l),('POINTER',p)),1)}


def find_rscript():
    return os.environ.get('MM_S2IB_RSCRIPT') or None


def find_r_fixture_file():
    return os.environ.get('MM_S2IB_R_FIXTURE_FILE') or None


def actual_r_lines():
    script = find_rscript()
    fixture = find_r_fixture_file()
    if script and fixture:
        raise AssertionError('S2IB_STOP: choose either Rscript or an R fixture file')
    if fixture:
        # CSC r-env and python-geo use separate, non-nestable containers.
        # Read only explicit opt-in R stdout; no Python-to-R subprocess.
        with open(fixture, 'rb') as stream:
            raw = stream.read(65537)
        if len(raw) > 65536:
            raise AssertionError('S2IB_STOP: R fixture output exceeds 64 KiB')
        return raw.decode('ascii').splitlines()
    if script is None:
        raise unittest.SkipTest('NOT_RUN: set MM_S2IB_RSCRIPT or MM_S2IB_R_FIXTURE_FILE')
    # Named binary directly, never shell; no setup/install/network and 15s hard bound.
    proc = subprocess.run([script,'--vanilla',str(R_EMITTER)],
                          cwd=str(ROOT), text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=15, check=False,
                          env={**os.environ, 'LC_ALL':'C', 'TZ':'UTC'})
    if proc.returncode:
        raise AssertionError(
            f'R fixture failed rc={proc.returncode}; '
            f'stdout={proc.stdout[-2000:]!r}; stderr={proc.stderr[-2000:]!r}'
        )
    return proc.stdout.splitlines()


class ProtocolStaticContractTests(unittest.TestCase):
    def test_reference_covers_nine_exact_role_batches(self):
        d=expected()
        self.assertEqual(len(d), 9)
        self.assertEqual([key[1] for key in d if key[0]=='core'],
                         ['WATER_CLASS','LAKE_ID','POINTER'])
        for key, raw in d.items():
            b=decode_batch(raw)
            self.assertEqual((b.role,b.sequence),(key[1],key[2]))
            self.assertEqual(encode_batch(b).data,raw)

    def test_reference_all_scenarios_remain_self_attested(self):
        d=expected()
        for case in ('core','special','directions'):
            raw=tuple(d[(case,role,i)] for i,role in enumerate(
                ('WATER_CLASS','LAKE_ID','POINTER'),1))
            claim=make_synthetic_claim(raw)
            review=verify_synthetic_claim(claim,raw)
            self.assertEqual(review.disposition,'RECORDED_UNVERIFIED')
            self.assertEqual(review.source_authentication,'NOT_ASSESSED')
            self.assertEqual(review.historical_02f_status,'STOP')

    def test_unsafe_python_modules_not_added(self):
        # R writer itself is Base R and source-only; no production modules present.
        for p in (R_WRITER,R_EMITTER):
            src=p.read_text(encoding='utf-8')
            self.assertNotIn('terra::',src)
            self.assertNotIn('whitebox::',src)
            self.assertNotIn('02_build_baseline_hydrology',src)
            self.assertNotIn('source("R/',src)
        tree=ast.parse(Path(__file__).read_text(encoding='utf-8'))
        self.assertFalse(any(isinstance(n,ast.ImportFrom) and n.module in
                     ('osgeo','rasterio','terra') for n in ast.walk(tree)))


@unittest.skipUnless(find_rscript() or find_r_fixture_file(),
                     'NOT_RUN: MM_S2IB_RSCRIPT or MM_S2IB_R_FIXTURE_FILE not set')
class ActualRInteroperabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lines=actual_r_lines()
        if cls.lines.count('R_SYNTHETIC_NEGATIVE_PASS=4') != 1:
            raise AssertionError('S2IB_STOP: expected exactly one R negative PASS marker')
        cls.expected=expected()
        cls.received={}
        for line in cls.lines:
            if line=='R_SYNTHETIC_NEGATIVE_PASS=4':
                continue
            match=re.fullmatch(r'CASE=(core|special|directions)\|ROLE=(WATER_CLASS|LAKE_ID|POINTER)\|SEQ=([123])\|WIRE=([0-9a-f]+)',line)
            if not match:
                raise AssertionError(f'R emitted unexpected text: {line[:150]}')
            case,role,index,wire=match.groups()
            key=(case,role,int(index))
            if key in cls.received:
                raise AssertionError('R emitted duplicate key '+str(key))
            cls.received[key]=bytes.fromhex(wire)

    def test_all_nine_R_generated_byte_strings_match_Python(self):
        self.assertEqual(set(self.received),set(self.expected))
        for key,exp in self.expected.items():
            with self.subTest(case=key):
                self.assertEqual(self.received[key],exp)

    def test_R_wire_decode_and_roundtrip_for_all_cases(self):
        for key,raw in self.received.items():
            with self.subTest(case=key):
                b=decode_batch(raw)
                self.assertEqual((b.role,b.sequence),(key[1],key[2]))
                self.assertEqual(encode_batch(b).data,raw)

    def test_R_core_uses_exact_NaN_NA_and_negative_zero_bits(self):
        raw=decode_batch(self.received[('core','POINTER',3)])
        self.assertEqual(tuple(s.tag for s in raw.values),('FINITE','R_NA','NAN'))
        self.assertEqual(raw.values[0].raw_le,bytes.fromhex('0000000000000080'))
        self.assertEqual(raw.values[1].raw_le,bytes.fromhex('a20700000000f07f'))
        self.assertEqual(raw.values[2].raw_le,bytes.fromhex('010000000000f87f'))

    def test_R_contains_four_negative_STOP_checks(self):
        self.assertIn('R_SYNTHETIC_NEGATIVE_PASS=4',self.lines)


if __name__=='__main__':
    unittest.main()