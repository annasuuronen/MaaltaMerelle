"""S2I-A bounded offline tests. No original CSC or raster access."""
import ast
import json
from dataclasses import FrozenInstanceError, replace
import math
import os
from pathlib import Path
import struct
import unittest
from unittest.mock import patch

import s2i_a_synthetic_value_protocol as m

RUN = "13d6f4e9-582b-48e7-a46f-9a817e84d12f"
ATTEMPT = "eecf7530-fb99-4a9c-a701-4979a9b398fd"
OTHER = "084d0238-2f38-47da-b87e-544151ff09a6"
GRID = m.Grid("tiny", 3, 3, 199000, 6911000)


def scalar(role, value, tag=None):
    if role == "POINTER":
        if isinstance(value, bytes):
            raw = value
        else:
            raw = struct.pack("<d", value)
        bits = int.from_bytes(raw, "little")
        ex = (bits >> 52) & 2047
        frac = bits & ((1 << 52)-1)
        automatic = ("FINITE" if ex != 2047 else
                     "NEG_INF" if bits >> 63 and frac == 0 else
                     "POS_INF" if frac == 0 else
                     "R_NA" if bits == m.NA_REAL_BITS else "NAN")
    elif role == "LAKE_ID":
        raw = struct.pack("<i", value)
        automatic = "NA_INTEGER" if value == -2147483648 else "FINITE"
    else:
        raw = struct.pack("<B", value)
        automatic = "NODATA" if value == 255 else "FINITE"
    return m.Scalar(tag or automatic, raw)


def batch(seq=1, role="WATER_CLASS", cells=(4,4), vals=(1,255), grid=GRID,
          run=RUN, attempt=ATTEMPT):
    return m.Batch(run, attempt, grid, seq, role, tuple(cells),
                   tuple(scalar(role, x) for x in vals))


def triple(cells=(4,4), values=None, grid=GRID, run=RUN, attempt=ATTEMPT):
    vals = values or ((1, 255), (16777217, -2147483648), (2.0, -0.0))
    return tuple(m.encode_batch(batch(i, role, cells, xs, grid, run, attempt)).data
                 for i,(role,xs) in enumerate(zip(("WATER_CLASS","LAKE_ID","POINTER"), vals),1))


def claim_bytes(data):
    return json.dumps(data,sort_keys=True,separators=(",",":"),ensure_ascii=True).encode("ascii")


def change_claim(raw, **updates):
    data=json.loads(raw)
    data.update(updates)
    return claim_bytes(data)


class WirePositive(unittest.TestCase):
    def test_magic_is_domain_separated_and_versioned(self):
        out=m.encode_batch(batch())
        self.assertEqual(out.data[:8],m.MAGIC)
        self.assertEqual(out.data[8],1)
        self.assertEqual(out.evidence_scope,"SYNTHETIC_ONLY")

    def test_bytes_are_deterministic(self):
        self.assertEqual(m.encode_batch(batch()),m.encode_batch(batch()))

    def test_run_attempt_and_grid_roundtrip(self):
        b=batch()
        self.assertEqual(m.decode_batch(m.encode_batch(b).data),b)

    def test_duplicate_cell_requests_preserved(self):
        b=batch(cells=(3,3),vals=(0,1))
        self.assertEqual(m.decode_batch(m.encode_batch(b).data).requested_cells,(3,3))

    def test_row_major_first_and_last_cell(self):
        b=batch(cells=(1,9),vals=(1,3))
        self.assertEqual(m.decode_batch(m.encode_batch(b).data).requested_cells,(1,9))

    def test_requested_cell_order_preserved(self):
        b=batch(cells=(9,1),vals=(1,3))
        self.assertEqual(m.decode_batch(m.encode_batch(b).data).requested_cells,(9,1))
        self.assertNotEqual(m.encode_batch(b).synthetic_sha256,
                            m.encode_batch(batch(cells=(1,9),vals=(1,3))).synthetic_sha256)

    def test_byte_zero_is_finite_not_nodata(self):
        b=batch(cells=(1,2),vals=(0,255))
        self.assertEqual(tuple(v.tag for v in m.decode_batch(m.encode_batch(b).data).values),
                         ("FINITE","NODATA"))

    def test_large_integer_above_float32_integer_precision(self):
        b=batch(2,"LAKE_ID",(4,5),(16777217,2147483647))
        self.assertEqual(m.decode_batch(m.encode_batch(b).data),b)

    def test_int32_min_is_reserved_na_integer(self):
        b=batch(2,"LAKE_ID",(4,5),(-2147483648,-2147483647))
        self.assertEqual(m.decode_batch(m.encode_batch(b).data).values[0].tag,"NA_INTEGER")

    def test_pointer_negative_zero_preserves_bits(self):
        b=batch(3,"POINTER",(4,5),(-0.0,0.0))
        rt=m.decode_batch(m.encode_batch(b).data)
        self.assertNotEqual(rt.values[0].raw_le,rt.values[1].raw_le)
        self.assertEqual(int.from_bytes(rt.values[0].raw_le,"little"),1<<63)

    def test_finite_pointer_all_eight_whitebox_codes(self):
        for v in (1,2,4,8,16,32,64,128):
            with self.subTest(v=v):
                b=batch(3,"POINTER",(4,),(float(v),))
                self.assertEqual(m.decode_batch(m.encode_batch(b).data),b)

    def test_nan_payload_preserved_not_normalized(self):
        raw=struct.pack("<Q",0x7ff80000000000ab)
        b=m.Batch(RUN,ATTEMPT,GRID,3,"POINTER",(4,),(scalar("POINTER",raw),))
        rt=m.decode_batch(m.encode_batch(b).data)
        self.assertEqual(rt.values[0].raw_le,raw)
        self.assertEqual(rt.values[0].tag,"NAN")

    def test_distinct_nan_payloads_get_distinct_hashes(self):
        def one(bits):
            b=m.Batch(RUN,ATTEMPT,GRID,3,"POINTER",(4,),
                      (scalar("POINTER",struct.pack("<Q",bits)),))
            return m.encode_batch(b).synthetic_sha256
        self.assertNotEqual(one(0x7ff8000000000001),one(0x7ff8000000000002))

    def test_r_na_tag_is_distinct_from_nan(self):
        b=m.Batch(RUN,ATTEMPT,GRID,3,"POINTER",(4,),
                  (scalar("POINTER",struct.pack("<Q",m.NA_REAL_BITS)),))
        self.assertEqual(m.decode_batch(m.encode_batch(b).data).values[0].tag,"R_NA")

    def test_positive_and_negative_infinity(self):
        b=batch(3,"POINTER",(4,5),(float("inf"),float("-inf")))
        self.assertEqual([v.tag for v in m.decode_batch(m.encode_batch(b).data).values],
                         ["POS_INF","NEG_INF"])

    def test_encoding_contains_no_absolute_source_path(self):
        self.assertNotIn(b"scratch", m.encode_batch(batch()).data)

    def test_frozen_result_rejects_field_reassignment(self):
        x=m.encode_batch(batch())
        with self.assertRaises(FrozenInstanceError):x.synthetic_sha256="forged"

    def test_sha256_is_exact_digest_of_synthetic_bytes(self):
        from hashlib import sha256
        x=m.encode_batch(batch())
        self.assertEqual(x.synthetic_sha256,sha256(x.data).hexdigest())


class WireRejections(unittest.TestCase):
    def reject(self,b,part):
        with self.assertRaisesRegex(m.ProtocolError,part):m.encode_batch(b)

    def test_bad_role_rejected(self):
        self.reject(replace(batch(),role="REAL_DATA"),"ROLE")

    def test_invalid_uuid_version_rejected(self):
        self.reject(replace(batch(),run_id="00000000-0000-0000-0000-000000000000"),"RUN_ID_FORMAT")

    def test_run_and_attempt_must_differ(self):
        self.reject(replace(batch(),attempt_id=RUN),"ATTEMPT_EQUALS_RUN")

    def test_noncanonical_uuid_rejected(self):
        self.reject(replace(batch(),run_id=RUN.upper()),"RUN_ID_FORMAT")

    def test_bool_cell_rejected(self):
        self.reject(replace(batch(),requested_cells=(True,4)),"CELL_ID_OUT_OF_GRID")

    def test_zero_and_outside_cells_rejected(self):
        for c in (0,10,-1):
            with self.subTest(c=c):
                self.reject(replace(batch(),requested_cells=(c,4)),"CELL_ID_OUT_OF_GRID")

    def test_non_tuple_immutable_cell_vector_rejected(self):
        self.reject(replace(batch(),requested_cells=[4,4]),"CELL_VALUE_COUNT")

    def test_cell_count_mismatch_rejected(self):
        self.reject(replace(batch(),requested_cells=(4,)),"CELL_VALUE_COUNT")

    def test_value_count_budget_rejected(self):
        b=batch(cells=(1,)*33,vals=(1,)*33)
        self.reject(b,"CELL_VALUE_COUNT")

    def test_grid_area_budget_rejected(self):
        self.reject(replace(batch(),grid=m.Grid("tiny",10,10,0,0)),"SYNTHETIC_GRID_LIMIT")

    def test_grid_bad_unicode_rejected(self):
        self.reject(replace(batch(),grid=m.Grid("järvi",3,3,0,0)),"GRID_ID")

    def test_grid_boolean_dimension_rejected(self):
        self.reject(replace(batch(),grid=m.Grid("tiny",True,3,0,0)),"GRID_TYPES")

    def test_sequence_over_limit_rejected(self):
        self.reject(replace(batch(),sequence=25),"SEQUENCE_LIMIT")

    def test_bad_scalar_raw_width_rejected(self):
        self.reject(replace(batch(),values=(m.Scalar("FINITE",b""),batch().values[1])),"SCALAR_WIDTH")

    def test_byte_sentinel_must_have_nodata_tag(self):
        self.reject(replace(batch(),values=(m.Scalar("FINITE",b"\xff"),batch().values[1])),
                    "BYTE_NODATA_TAG")

    def test_int32_na_sentinel_requires_tag(self):
        b=batch(2,"LAKE_ID",(1,),(1,))
        self.reject(replace(b,values=(m.Scalar("FINITE",m.NA_INTEGER_BYTES),)),"INT32_NA_TAG")

    def test_float64_bits_cannot_be_mislabeled(self):
        b=batch(3,"POINTER",(1,),(1.0,))
        self.reject(replace(b,values=(m.Scalar("NAN",struct.pack("<d",1.0)),)),
                    "FLOAT64_BITS_TAG_MISMATCH")

    def test_r_na_tag_requires_r_bits(self):
        b=batch(3,"POINTER",(1,),(1.0,))
        self.reject(replace(b,values=(m.Scalar("R_NA",struct.pack("<Q",0x7ff8000000000001)),)),
                    "FLOAT64_BITS_TAG_MISMATCH")

    def test_wire_unknown_version_rejected(self):
        x=bytearray(m.encode_batch(batch()).data);x[8]=9
        with self.assertRaisesRegex(m.ProtocolError,"WIRE_VERSION"):m.decode_batch(bytes(x))

    def test_wire_truncation_and_extra_suffix_rejected(self):
        x=m.encode_batch(batch()).data
        with self.assertRaisesRegex(m.ProtocolError,"WIRE_TRUNCATED"):m.decode_batch(x[:-1])
        with self.assertRaisesRegex(m.ProtocolError,"WIRE_TRAILING_BYTES"):m.decode_batch(x+b"x")

    def test_wire_wrong_magic_rejected(self):
        x=bytearray(m.encode_batch(batch()).data);x[0]=0
        with self.assertRaisesRegex(m.ProtocolError,"WIRE_MAGIC"):m.decode_batch(bytes(x))

    def test_wire_invalid_tag_rejected(self):
        x=bytearray(m.encode_batch(batch()).data)
        x[-2]=0xff  # corrupt last Byte scalar's tag
        with self.assertRaises(m.ProtocolError):m.decode_batch(bytes(x))


class Claims(unittest.TestCase):
    def setUp(self):
        self.observed=triple()
        self.raw=m.make_synthetic_claim(self.observed)

    def test_complete_synthetic_claim_is_not_authenticated(self):
        r=m.verify_synthetic_claim(self.raw,self.observed)
        self.assertEqual(r.disposition,"RECORDED_UNVERIFIED")
        self.assertEqual(r.producer_lineage_status,"NOT_ASSESSED")
        self.assertEqual(r.historical_02f_status,"STOP")
        self.assertFalse(r.routing_authorized)

    def test_claim_has_no_external_witness(self):
        self.assertIsNone(json.loads(self.raw)["witness"])

    def test_claim_is_canonical_ascii(self):
        self.assertEqual(self.raw,claim_bytes(json.loads(self.raw)))

    def test_noncanonical_json_whitespace_is_rejected(self):
        raw=self.raw.replace(b',', b', ', 1)
        self.assertEqual(m.verify_synthetic_claim(raw,self.observed).reason,
                         "CLAIM_NONCANONICAL")

    def test_duplicate_batch_role_claim_rejected(self):
        duplicate=self.observed[:1]+self.observed[:1]+self.observed[2:]
        self.assertEqual(m.verify_synthetic_claim(self.raw,duplicate).disposition,"STOP")

    def test_overdeep_json_fails_safely(self):
        raw=(b"["*1500)+(b"0")+(b"]"*1500)
        self.assertEqual(m.verify_synthetic_claim(raw,self.observed).disposition,"STOP")

    def test_ordered_roles_class_lake_pointer(self):
        self.assertEqual([m.decode_batch(x).role for x in self.observed],
                         ["WATER_CLASS","LAKE_ID","POINTER"])

    def test_incomplete_claim_cannot_pass(self):
        raw=m.make_synthetic_claim(self.observed,declared_status="INCOMPLETE")
        self.assertEqual(m.verify_synthetic_claim(raw,self.observed).disposition,"STOP")

    def test_truncated_triplet_cannot_pass(self):
        observed=self.observed[:2]
        raw=m.make_synthetic_claim(observed)
        self.assertEqual(m.verify_synthetic_claim(raw,observed).disposition,"STOP")

    def test_swapped_read_order_stops(self):
        switched=self.observed[:1]+(self.observed[2],self.observed[1])
        self.assertEqual(m.verify_synthetic_claim(self.raw,switched).disposition,"STOP")

    def test_duplicate_sequence_stops(self):
        obs=self.observed[:1]+(self.observed[0],)+self.observed[2:]
        self.assertEqual(m.verify_synthetic_claim(self.raw,obs).disposition,"STOP")

    def test_mismatching_triplet_query_cells_stops(self):
        b=batch(2,"LAKE_ID",(4,5),(16777217,-2147483648))
        obs=(self.observed[0],m.encode_batch(b).data,self.observed[2])
        self.assertEqual(m.verify_synthetic_claim(self.raw,obs).disposition,"STOP")

    def test_cross_run_batch_stops(self):
        b=batch(2,"LAKE_ID",(4,4),(16777217,-2147483648),run=OTHER)
        obs=(self.observed[0],m.encode_batch(b).data,self.observed[2])
        self.assertEqual(m.verify_synthetic_claim(self.raw,obs).disposition,"STOP")

    def test_cross_attempt_batch_stops(self):
        b=batch(2,"LAKE_ID",(4,4),(16777217,-2147483648),attempt=OTHER)
        obs=(self.observed[0],m.encode_batch(b).data,self.observed[2])
        self.assertEqual(m.verify_synthetic_claim(self.raw,obs).disposition,"STOP")

    def test_forced_verified_science_fails_closed(self):
        for key,value in (("NATIONAL","UNLOCKED"),("routing_authorized",True),
                          ("hydrological_validation","VALIDATED"),
                          ("SOURCE_AUTHENTICATION","VERIFIED")):
            with self.subTest(key=key):
                raw=change_claim(self.raw,**{key:value})
                self.assertEqual(m.verify_synthetic_claim(raw,self.observed).disposition,"STOP")

    def test_forged_witness_claim_is_rejected(self):
        raw=change_claim(self.raw,witness={"signature":"self-signed"})
        self.assertEqual(m.verify_synthetic_claim(raw,self.observed).disposition,"STOP")

    def test_real_scope_claim_is_rejected(self):
        raw=change_claim(self.raw,evidence_kind="CONTROLLED_NEW_RUN")
        self.assertEqual(m.verify_synthetic_claim(raw,self.observed).disposition,"STOP")

    def test_unknown_schema_and_key_rejected(self):
        for raw in (change_claim(self.raw,schema_version="v2"),
                    change_claim(self.raw,approved=True)):
            self.assertEqual(m.verify_synthetic_claim(raw,self.observed).disposition,"STOP")

    def test_duplicate_json_key_rejected(self):
        raw=self.raw[:-1]+b',"evidence_kind":"SYNTHETIC"}'
        self.assertEqual(m.verify_synthetic_claim(raw,self.observed).reason,"DUPLICATE_JSON_KEY")

    def test_json_nan_and_unicode_rejected(self):
        for raw in (self.raw[:-1]+b',"x":NaN}', self.raw[:-1]+',"x":"é"}'.encode()):
            self.assertEqual(m.verify_synthetic_claim(raw,self.observed).disposition,"STOP")

    def test_reordered_digest_claim_stops(self):
        v=json.loads(self.raw);v["batch_sha256"].reverse()
        self.assertEqual(m.verify_synthetic_claim(claim_bytes(v),self.observed).disposition,"STOP")

    def test_modified_values_with_old_digest_stop(self):
        obs=triple(values=((1,255),(16777217,-2147483648),(4.0,-0.0)))
        self.assertEqual(m.verify_synthetic_claim(self.raw,obs).disposition,"STOP")

    def test_changed_run_id_in_claim_stops(self):
        self.assertEqual(m.verify_synthetic_claim(change_claim(self.raw,run_id=OTHER),self.observed).disposition,"STOP")

    def test_report_signature_cannot_be_claimed(self):
        x=change_claim(self.raw,producer_lineage_status="VERIFIED_IN_DECLARED_SCOPE")
        self.assertEqual(m.verify_synthetic_claim(x,self.observed).disposition,"STOP")

    def test_empty_and_oversized_observed_stops(self):
        self.assertEqual(m.verify_synthetic_claim(self.raw,()).disposition,"STOP")
        self.assertEqual(m.verify_synthetic_claim(self.raw,(self.observed[0],)*25).disposition,"STOP")

    def test_wrong_boolean_type_in_lock_stops(self):
        x=change_claim(self.raw,routing_authorized=0)
        self.assertEqual(m.verify_synthetic_claim(x,self.observed).disposition,"STOP")

    def test_invalid_json_and_empty_bytes_stop(self):
        for raw in (b"",b"[",b"[]",b"null",b"{"*200):
            with self.subTest(raw=raw[:10]):
                self.assertEqual(m.verify_synthetic_claim(raw,self.observed).disposition,"STOP")

    def test_claim_length_limit(self):
        self.assertEqual(m.verify_synthetic_claim(b" "*8193,self.observed).reason,"CLAIM_SIZE")

    def test_many_triplets_preserve_order(self):
        vals=((1,255),(16777217,-2147483648),(2.0,-0.0))
        obs=[]
        for i in range(1,10):
            role=("WATER_CLASS","LAKE_ID","POINTER")[(i-1)%3]
            x=vals[(i-1)%3]
            obs.append(m.encode_batch(batch(i,role,(4,4),x)).data)
        obs=tuple(obs)
        self.assertEqual(m.verify_synthetic_claim(m.make_synthetic_claim(obs),obs).disposition,
                         "RECORDED_UNVERIFIED")

    def test_no_disk_network_raster_or_process_dependencies(self):
        p=Path(m.__file__)
        tree=ast.parse(p.read_text())
        modules={n.module for n in ast.walk(tree) if isinstance(n,ast.ImportFrom)}
        modules|={a.name for n in ast.walk(tree) if isinstance(n,ast.Import) for a in n.names}
        self.assertFalse(modules & {"os","pathlib","subprocess","socket","urllib","requests",
                                    "rasterio","terra","numpy","osgeo","pickle","shutil","tempfile"})
        forbidden={"open","exec","eval","compile","__import__"}
        calls={n.func.id for n in ast.walk(tree) if isinstance(n,ast.Call) and isinstance(n.func,ast.Name)}
        self.assertFalse(calls & forbidden)

    def test_verifier_uses_no_io_and_prints_no_secrets(self):
        import contextlib,io,builtins
        with patch.object(builtins,"open",side_effect=AssertionError("IO attempted")), \
             patch("subprocess.run",side_effect=AssertionError("process attempted")), \
             patch("socket.socket",side_effect=AssertionError("network attempted")):
            stdout=io.StringIO()
            with contextlib.redirect_stdout(stdout):
                answer=m.verify_synthetic_claim(self.raw,self.observed)
            self.assertEqual(answer.disposition,"RECORDED_UNVERIFIED")
            self.assertEqual(stdout.getvalue(),"")


if __name__ == "__main__":
    unittest.main()