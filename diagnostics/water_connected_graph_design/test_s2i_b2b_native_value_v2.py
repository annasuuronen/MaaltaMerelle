"""New standalone v2 tests only. No native 02F/S2F or accepted campaign imports.

For separate stages, supply MM_S2CV_R_OUTPUT pointing to the new R test stdout.
No Python-to-R subprocess or CSC container wrapper is used by these tests.
"""
import ast
from dataclasses import FrozenInstanceError, replace
import os
from pathlib import Path
import re
import stat
import struct
import unittest

from s2i_b2b_native_value_v2 import (
    Batch, Header, Request, Values, Transcript, Safety, Stop,
    encode, decode, compare_synthetic_reference,
)


ROOT = Path(__file__).resolve().parent
RUN = "123e4567-e89b-42d3-a456-426614174000"
ATTEMPT = "123e4567-e89b-42d3-a456-426614174001"
ROLES = ("WATER_CLASS", "LAKE_ID", "POINTER")
NA = "a20700000000f07f"
QNAN = "010000000000f87f"
NEG_NAN = "010000000000f8ff"
PZERO = "0000000000000000"
NZERO = "0000000000000080"
INF = "000000000000f07f"
NINF = "000000000000f0ff"


def header(**kw):
    # These strings are intentionally synthetic declarations, not runtime claims.
    h = Header(RUN, ATTEMPT, "tiny", 3, 3, 0, 0, "0.0.1", "synthetic-fixture")
    return replace(h, **kw)


def request(storage, cells):
    fmt = "<i" if storage == "INTEGER" else "<d"
    return Request(storage, b"".join(struct.pack(fmt, n) for n in cells))


def ints(values):
    return Values("INTEGER", tuple("NA_INTEGER" if n is None else "FINITE" for n in values),
                  b"".join(struct.pack("<i", -2147483648 if n is None else n) for n in values))


def doubles(*items):
    return Values("DOUBLE", tuple(t for t, _ in items), bytes.fromhex("".join(h for _, h in items)))


def triplet(req, responses, start=1):
    return tuple(Batch(start + i, role, req, v) for i, (role, v) in enumerate(zip(ROLES, responses)))


def fixtures():
    minimum = Transcript(header(), triplet(request("INTEGER", (5,)),
                         (ints((3,)), ints((None,)), doubles(("FINITE", NZERO)))))
    mixed = Transcript(header(), triplet(request("INTEGER", (5, 5, 9)), (
        doubles(("NA_REAL", NA), ("FINITE", PZERO), ("FINITE", NZERO)),
        ints((16777217, None, -123)),
        doubles(("NAN", QNAN), ("POS_INF", INF), ("NEG_INF", NINF)))))
    flipped = Transcript(header(), triplet(request("DOUBLE", (1, 1, 9)), (
        ints((None, 3, 255)),
        doubles(("NA_REAL", NA), ("FINITE", NZERO), ("FINITE", "0100000000000000")),
        ints((0, 128, -2147483647)))))
    extremes = Transcript(header(), triplet(request("DOUBLE", (2, 2, 8)), (
        doubles(("NAN", NEG_NAN), ("FINITE", "00000000000004c0"), ("FINITE", "0000000000e06f40")),
        ints((-2147483647, 2147483647, 0)),
        doubles(("FINITE", "0100000000000000"), ("FINITE", "ffffffffffffef7f"),
                ("FINITE", "ffffffffffffefff")))))
    many = []
    for n in (32, 32, 32, 32, 32, 4, 3, 3):
        req = request("DOUBLE", (1,) * n)
        val = doubles(*(("FINITE", PZERO),) * n)
        many.extend(triplet(req, (val, val, val), len(many) + 1))
    large = Transcript(header(), tuple(many))  # 24 batches, 510 slots, still 3x3.
    text = replace(minimum, header=header(grid_id="g" + "x" * 31, rows=9, cols=9,
        x_origin=-100000000, y_origin=100000000, r_version="999.999.999", r_platform="p" * 64),
        batches=triplet(request("INTEGER", (81,)),
                        (ints((3,)), ints((None,)), doubles(("FINITE", NZERO)))))
    return dict(minimum=minimum, mixed=mixed, flipped=flipped, extremes=extremes,
                declared=replace(flipped, header=header(declared_dtypes=(1, 2, 3))),
                many=large, max_header=text)


def oracle(t):
    """Independent field-by-field construction: never calls the codec or decoder."""
    h = t.header
    def text(s):
        b = s.encode("ascii")
        return struct.pack("<B", len(b)) + b
    # Separate literal tables from the encoder's tables, following the reviewed grammar.
    type_ids = {"INTEGER": 1, "DOUBLE": 2}
    widths = {"INTEGER": 4, "DOUBLE": 8}
    tag_ids = {"FINITE": 1, "NA_INTEGER": 2, "NA_REAL": 3, "NAN": 4, "POS_INF": 5, "NEG_INF": 6}
    frames = []
    for b in t.batches:
        count = len(b.response.validity)
        fields = [struct.pack("<H", b.sequence), bytes((ROLES.index(b.role) + 1,)),
                  bytes((type_ids[b.request.storage_type], type_ids[b.response.storage_type])),
                  struct.pack("<H", count)]
        for i in range(count):
            a, z = widths[b.request.storage_type], widths[b.response.storage_type]
            fields += [b.request.raw_le[i*a:(i+1)*a], bytes((tag_ids[b.response.validity[i]],)),
                       b.response.raw_le[i*z:(i+1)*z]]
        body = b"".join(fields)
        frames.append(struct.pack("<H", len(body)) + body)
    slots = sum(len(b.response.validity) for b in t.batches)
    suffix = (bytes.fromhex(h.run_id.replace("-", "")) + bytes.fromhex(h.attempt_id.replace("-", ""))
              + text(h.grid_id) + struct.pack("<HH", h.rows, h.cols) + struct.pack("<I", 3067)
              + struct.pack("<ii", h.x_origin, h.y_origin) + bytes((2, 1, 1))
              + text(h.r_version) + text(h.r_platform) + bytes(h.declared_dtypes)
              + struct.pack("<HI", len(t.batches), slots) + b"".join(frames)
              + b"MM-END2\0" + struct.pack("<HI", len(t.batches), slots))
    return b"MM-S2CV\0" + bytes((2, 1, 1)) + struct.pack("<I", 15 + len(suffix)) + suffix


# Literal, hand-laid-out minimal 176-byte transcript, independent of either implementation.
GOLDEN = bytes.fromhex(
    "4d4d2d5332435600020101b0000000"
    "123e4567e89b42d3a456426614174000123e4567e89b42d3a456426614174001"
    "0474696e7903000300fb0b00000000000000000000020101"
    "05302e302e311173796e7468657469632d66697874757265000000030003000000"
    "100001000101010100050000000103000000"
    "100002000201010100050000000200000080"
    "14000300030102010005000000010000000000000080"
    "4d4d2d454e443200030003000000")


def offsets(t):
    h = t.header
    rows = 48 + len(h.grid_id)
    version = rows + 19
    platform = version + 1 + len(h.r_version)
    dtypes = platform + 1 + len(h.r_platform)
    pos = dtypes + 9
    fs = []
    for b in t.batches:
        rw = 4 if b.request.storage_type == "INTEGER" else 8
        vw = 4 if b.response.storage_type == "INTEGER" else 8
        n = len(b.response.validity)
        fs.append(dict(length=pos, seq=pos+2, role=pos+4, req_type=pos+5, val_type=pos+6,
                       count=pos+7, cell=pos+9, tag=pos+9+rw, value=pos+10+rw,
                       stride=rw+1+vw))
        pos += 9 + n*(rw+1+vw)
    return dict(rows=rows, cols=rows+2, crs=rows+4, x=rows+8, y=rows+12,
                size=rows+16, direction=rows+17, indexing=rows+18,
                version=version, platform=platform, dtypes=dtypes,
                batches=dtypes+3, slots=dtypes+5, frames=fs, end=pos)


def changed(raw, at, payload):
    return raw[:at] + payload + raw[at+len(payload):]


class PositiveTests(unittest.TestCase):
    def test_literal_golden_length_and_offsets(self):
        t = fixtures()["minimum"]
        self.assertEqual(len(GOLDEN), 176)
        self.assertEqual(GOLDEN, oracle(t))
        self.assertEqual(GOLDEN[11:15], bytes.fromhex("b0000000"))
        self.assertEqual(encode(t).data, GOLDEN)

    def test_seven_independent_field_layout_oracles(self):
        for name, t in fixtures().items():
            with self.subTest(name=name):
                self.assertEqual(encode(t).data, oracle(t))
                self.assertEqual(decode(oracle(t)).transcript, t)

    def test_decoder_encoder_roundtrip_all_fixtures(self):
        for name, t in fixtures().items():
            with self.subTest(name=name):
                raw = oracle(t)
                self.assertEqual(encode(decode(raw).transcript).data, raw)

    def test_all_six_role_native_types(self):
        pairs = {(b.role, b.response.storage_type) for t in fixtures().values() for b in t.batches}
        self.assertEqual(pairs, {(r, s) for r in ROLES for s in ("INTEGER", "DOUBLE")})

    def test_actual_observed_storage_never_comes_from_declared_dtype(self):
        a, b = fixtures()["flipped"], fixtures()["declared"]
        self.assertEqual(decode(oracle(a)).transcript.batches, decode(oracle(b)).transcript.batches)
        self.assertNotEqual(oracle(a), oracle(b))

    def test_integer_double_three_have_distinct_payloads_and_wires(self):
        t = fixtures()["minimum"]
        b = replace(t.batches[0], response=doubles(("FINITE", "0000000000000840")))
        other = replace(t, batches=(b,) + t.batches[1:])
        self.assertNotEqual(encode(t).data, encode(other).data)
        self.assertEqual(decode(encode(other).data).transcript.batches[0].response.raw_le,
                         bytes.fromhex("0000000000000840"))

    def test_double_signed_zero_and_NA_payloads_preserved(self):
        t = decode(oracle(fixtures()["mixed"])).transcript
        self.assertEqual(t.batches[0].response.raw_le, bytes.fromhex(NA+PZERO+NZERO))
        self.assertEqual(t.batches[2].response.raw_le, bytes.fromhex(QNAN+INF+NINF))

    def test_negative_nan_subnormal_and_maximum_finite_preserved(self):
        t = decode(oracle(fixtures()["extremes"])).transcript
        self.assertTrue(t.batches[0].response.raw_le.startswith(bytes.fromhex(NEG_NAN)))
        self.assertEqual(t.batches[2].response.validity, ("FINITE",)*3)

    def test_exact_large_and_negative_integer_ID_bytes(self):
        v = decode(oracle(fixtures()["mixed"])).transcript.batches[1].response
        self.assertEqual(v.raw_le, bytes.fromhex("010000010000008085ffffff"))

    def test_duplicate_request_order_is_not_deduplicated(self):
        r = decode(oracle(fixtures()["mixed"])).transcript.batches[0].request
        self.assertEqual(r.raw_le, bytes.fromhex("050000000500000009000000"))

    def test_integer_double_request_encodings_are_distinct(self):
        t = fixtures()["minimum"]
        other = replace(t, batches=tuple(replace(b, request=request("DOUBLE", (5,))) for b in t.batches))
        self.assertNotEqual(oracle(t), oracle(other))
        self.assertEqual(decode(oracle(other)).transcript, other)

    def test_byte_255_is_an_ordinary_finite_native_integer(self):
        v = decode(oracle(fixtures()["flipped"])).transcript.batches[0].response
        self.assertEqual(v.validity[-1], "FINITE")
        self.assertEqual(v.raw_le[-4:], b"\xff\0\0\0")

    def test_cap_accepts_24_batches_and_510_slots(self):
        t = fixtures()["many"]
        out = encode(t)
        self.assertEqual(len(t.batches), 24)
        self.assertEqual(sum(len(b.response.validity) for b in t.batches), 510)
        self.assertLessEqual(len(out.data), 9140)
        self.assertEqual(decode(out.data).transcript, t)

    def test_maximum_grid_and_text_fields(self):
        t = fixtures()["max_header"]
        self.assertEqual(decode(oracle(t)).transcript, t)

    def test_NA_REAL_NAN_tags_are_preserved_not_rederived(self):
        t = fixtures()["mixed"]
        v = replace(t.batches[0].response, validity=("NAN", "FINITE", "FINITE"))
        other = replace(t, batches=(replace(t.batches[0], response=v),)+t.batches[1:])
        self.assertEqual(decode(oracle(other)).transcript, other)
        self.assertNotEqual(oracle(t), oracle(other))
        with self.assertRaisesRegex(Stop, "REFERENCE_BYTES_MISMATCH"):
            compare_synthetic_reference(oracle(other), oracle(t))

    def test_valid_changed_value_requires_reference_rejection(self):
        t = fixtures()["minimum"]
        b = replace(t.batches[0], response=ints((2,)))
        raw = oracle(replace(t, batches=(b,)+t.batches[1:]))
        self.assertEqual(decode(raw).disposition, "STRUCTURALLY_WELL_FORMED")
        with self.assertRaisesRegex(Stop, "REFERENCE_BYTES_MISMATCH"):
            compare_synthetic_reference(raw, oracle(t))

    def test_whole_triplet_removal_with_repaired_counts_is_not_a_reference_match(self):
        t = fixtures()["many"]
        short = replace(t, batches=t.batches[:-3])
        self.assertEqual(decode(oracle(short)).transcript, short)
        with self.assertRaisesRegex(Stop, "REFERENCE_BYTES_MISMATCH"):
            compare_synthetic_reference(oracle(short), oracle(t))

    def test_consistent_cell_substitution_is_not_a_reference_match(self):
        t = fixtures()["minimum"]
        altered = replace(t, batches=tuple(replace(b, request=request("INTEGER", (6,))) for b in t.batches))
        self.assertEqual(decode(oracle(altered)).transcript, altered)
        with self.assertRaisesRegex(Stop, "REFERENCE_BYTES_MISMATCH"):
            compare_synthetic_reference(oracle(altered), oracle(t))

    def test_deduplicated_triplet_is_rejected_against_full_reference(self):
        t=fixtures()["mixed"];bs=[]
        for b in t.batches:
            width=4 if b.response.storage_type=="INTEGER" else 8
            v=Values(b.response.storage_type,tuple(b.response.validity[i] for i in (0,2)),
                     b"".join(b.response.raw_le[i*width:(i+1)*width] for i in (0,2)))
            bs.append(replace(b,request=request("INTEGER",(5,9)),response=v))
        short=replace(t,batches=tuple(bs))
        self.assertEqual(decode(oracle(short)).transcript,short)
        with self.assertRaisesRegex(Stop,"REFERENCE_BYTES_MISMATCH"):
            compare_synthetic_reference(oracle(short),oracle(t))

    def test_reference_unavailable_is_STOP(self):
        with self.assertRaisesRegex(Stop, "REFERENCE_UNAVAILABLE"):
            compare_synthetic_reference(GOLDEN, None)

    def test_matching_reference_is_self_reported_only(self):
        x = compare_synthetic_reference(GOLDEN, GOLDEN)
        self.assertEqual(x.disposition, "RECORDED_UNVERIFIED")
        self.assertEqual(x.LOCAL_OBSERVATION_MATCH, "NOT_ASSESSED")
        self.assertEqual(x.safety.SOURCE_AUTHENTICATION, "NOT_ASSESSED")

    def test_results_and_errors_keep_fixed_scientific_locks(self):
        objects = [header(), request("INTEGER", (5,)), ints((1,)), fixtures()["minimum"],
                   encode(fixtures()["minimum"]), decode(GOLDEN), Stop("TEST")]
        for obj in objects:
            self.assertEqual(obj.safety, Safety())
            self.assertFalse(obj.safety.routing_authorized)
            self.assertEqual(obj.safety.HISTORIC_02F_EFFECTIVE_D8, "NOT_ASSESSED")

    def test_frozen_records_have_no_mutable_value_containers(self):
        x = decode(GOLDEN).transcript
        with self.assertRaises(FrozenInstanceError):
            x.header.rows = 9
        self.assertIs(type(x.batches), tuple)
        self.assertIs(type(x.batches[0].response.raw_le), bytes)

    def test_every_single_byte_truncation_rejects(self):
        for n in range(len(GOLDEN)):
            with self.subTest(length=n), self.assertRaises(Stop):
                decode(GOLDEN[:n])

    def test_module_has_no_external_IO_or_legacy_dependencies(self):
        tree = ast.parse((ROOT / "s2i_b2b_native_value_v2.py").read_text())
        allowed = {"dataclasses", "hashlib", "re", "struct", "uuid"}
        for n in ast.walk(tree):
            if isinstance(n, ast.Import):
                self.assertTrue(all(a.name in allowed for a in n.names))
            if isinstance(n, ast.ImportFrom):
                self.assertIn(n.module, allowed)
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Name):
                self.assertNotIn(n.func.id, {"open", "eval", "exec", "compile", "__import__"})
        r = (ROOT / "s2i_b2b_native_value_v2.R").read_text()
        forbidden_call=r"(?<![A-Za-z0-9_.])(?:source|sys\.source|system|system2|file|readLines|writeLines|readRDS|saveRDS|load|save|download\.file)\s*\("
        self.assertNotRegex(r,forbidden_call)
        for example in ("file('x')","base::source ('x')","system2('x')"):
            self.assertRegex(example,forbidden_call)
        self.assertNotRegex(".s2cv_native_profile()",forbidden_call)
        for namespace in ("terra::", "whitebox::"):
            self.assertNotIn(namespace,r)


def wire_negative_cases():
    cases = []
    t = fixtures()["minimum"]
    raw, o = oracle(t), offsets(t)
    def add(name, at, value, code):
        cases.append((name, changed(raw, at, value), code))
    for name, at, value, code in (
        ("magic_v1", 0, b"MM-S2IA\0", "MAGIC"),
        ("version_1", 8, b"\x01", "VERSION"), ("version_255", 8, b"\xff", "VERSION"),
        ("scope_real", 9, b"\x02", "SCOPE"), ("profile_unknown", 10, b"\x00", "PROFILE"),
        ("total_length", 11, struct.pack("<I", len(raw)+1), "TOTAL_LENGTH"),
        ("uuid_version", 21, b"\x52", "UUID4"), ("uuid_variant", 23, b"\x04", "UUID4"),
        ("same_run_attempt", 31, raw[15:31], "ATTEMPT_EQUALS_RUN"),
        ("empty_grid_label", 47, b"\0", "TEXT_LENGTH"),
        ("oversize_grid_label", 47, b"\x21", "TEXT_LENGTH"),
        ("grid_uppercase", 48, b"T", "GRID_ID"),
        ("rows_zero", o["rows"], b"\0\0", "GRID_ROWS"),
        ("cols_ten", o["cols"], b"\x0a\0", "GRID_COLS"),
        ("crs_not_3067", o["crs"], struct.pack("<I", 4326), "GRID_PROFILE"),
        ("origin_over_bound", o["x"], struct.pack("<i", 100000001), "GRID_ORIGIN"),
        ("wrong_cell_size", o["size"], b"\x04", "GRID_PROFILE"),
        ("wrong_row_direction", o["direction"], b"\0", "GRID_PROFILE"),
        ("wrong_index_base", o["indexing"], b"\0", "GRID_PROFILE"),
        ("version_text", o["version"]+1, b"x", "R_VERSION"),
        ("version_text_length", o["version"], b"\x21", "TEXT_LENGTH"),
        ("platform_ascii", o["platform"]+1, b"\xff", "ASCII"),
        ("platform_newline", o["platform"]+1, b"\n", "R_PLATFORM"),
        ("platform_oversize", o["platform"], b"\x41", "TEXT_LENGTH"),
        ("dtype_unknown", o["dtypes"], b"\x04", "DTYPE_DECLARATIONS"),
        ("batches_zero", o["batches"], b"\0\0", "COMPLETE_TRIPLETS"),
        ("batches_two", o["batches"], b"\x02\0", "COMPLETE_TRIPLETS"),
        ("batches_27", o["batches"], b"\x1b\0", "COMPLETE_TRIPLETS"),
        ("slots_zero", o["slots"], b"\0\0\0\0", "SLOT_LIMIT"),
        ("slots_513", o["slots"], struct.pack("<I", 513), "SLOT_LIMIT"),
        ("slots_disagree", o["slots"], struct.pack("<I", 6), "SLOT_COUNT"),
        ("end_magic", o["end"], b"X", "END_MAGIC"),
        ("end_batch_count", o["end"]+8, b"\x06\0", "END_COUNTS"),
        ("end_slot_count", o["end"]+10, b"\x06\0\0\0", "END_COUNTS")):
        add(name, at, value, code)
    f = o["frames"][0]
    for name, at, value, code in (
        ("frame_zero", f["length"], b"\0\0", "BODY_LENGTH"),
        ("frame_552", f["length"], struct.pack("<H", 552), "BODY_LENGTH"),
        ("frame_inconsistent", f["length"], b"\x11\0", "BODY_LENGTH"),
        ("sequence_skip", f["seq"], b"\x02\0", "SEQUENCE"),
        ("role_unknown", f["role"], b"\x04", "ROLE"),
        ("role_reordered", f["role"], b"\x02", "ROLE_SEQUENCE"),
        ("request_type_unknown", f["req_type"], b"\0", "NATIVE_TYPE"),
        ("response_type_unknown", f["val_type"], b"\x03", "NATIVE_TYPE"),
        ("count_zero", f["count"], b"\0\0", "VALUE_COUNT"),
        ("count_33", f["count"], b"\x21\0", "VALUE_COUNT"),
        ("validity_unknown", f["tag"], b"\x07", "VALIDITY_TAG"),
        ("integer_nan_tag", f["tag"], b"\x04", "TAG_BITS"),
        ("integer_NA_finite_tag", f["value"], bytes.fromhex("00000080"), "TAG_BITS"),
        ("request_zero", f["cell"], b"\0\0\0\0", "REQUEST_CELL"),
        ("request_outside", f["cell"], struct.pack("<i", 10), "REQUEST_CELL"),
        ("request_negative", f["cell"], struct.pack("<i", -1), "REQUEST_CELL"),
        ("request_NA_integer", f["cell"], bytes.fromhex("00000080"), "REQUEST_CELL")):
        add(name, at, value, code)
    last = o["frames"][2]
    add("double_infinity_finite_tag", last["value"], bytes.fromhex(INF), "TAG_BITS")
    add("double_finite_NA_tag", last["tag"], b"\x03", "TAG_BITS")
    add("triplet_cell_substitution", o["frames"][1]["cell"], struct.pack("<i", 6), "TRIPLET_REQUEST")
    t = fixtures()["flipped"]
    a = offsets(t)["frames"][0]["cell"]
    for label, bits in (("fraction", struct.pack("<d", 1.5)), ("NaN", bytes.fromhex(QNAN)),
                        ("Inf", bytes.fromhex(INF)), ("negative_zero", bytes.fromhex(NZERO))):
        cases.append(("double_request_"+label, changed(oracle(t), a, bits), "REQUEST_CELL"))
    raw = oracle(fixtures()["minimum"])
    trailing = changed(raw+b"x", 11, struct.pack("<I", len(raw)+1))
    cases += [("trailing_byte_repaired_size", trailing, "TRAILING_BYTES"),
              ("oversize_transport", b"x"*16385, "WIRE_SIZE")]
    large=fixtures()["many"];large_raw=oracle(large);at=offsets(large)["slots"]
    for count in (511,512):
        cases.append(("non_triplet_slot_count_"+str(count),
                      changed(large_raw,at,struct.pack("<I",count)),"SLOT_COUNT"))
    t=fixtures()["mixed"]
    reordered=replace(t,batches=(t.batches[0],replace(t.batches[1],
        request=request("INTEGER",(9,5,5))),t.batches[2]))
    cases.append(("triplet_cell_permutation",oracle(reordered),"TRIPLET_REQUEST"))
    return cases


class MalformedWireTests(unittest.TestCase):
    pass


def _wire_test(raw, reason):
    def test(self):
        with self.assertRaisesRegex(Stop, "^"+reason+"$"):
            decode(raw)
    return test


for _name, _raw, _reason in wire_negative_cases():
    setattr(MalformedWireTests, "test_"+_name, _wire_test(_raw, _reason))


def encoder_negative_cases():
    t = fixtures()["minimum"]
    cases = []
    for key, value, reason in (
        ("rows", True, "GRID_ROWS"), ("cols", 10, "GRID_COLS"),
        ("grid_id", "bad\n", "GRID_ID"), ("grid_id", "ää", "GRID_ID"),
        ("run_id", RUN.upper(), "UUID4"), ("attempt_id", RUN, "ATTEMPT_EQUALS_RUN"),
        ("r_version", "4.6.1\n", "R_VERSION"), ("r_platform", "x"*65, "R_PLATFORM"),
        ("declared_dtypes", [0,0,0], "DTYPE_DECLARATIONS"),
        ("declared_dtypes", (0,True,0), "DTYPE_DECLARATIONS")):
        cases.append(("header_"+key+"_"+str(len(cases)), replace(t, header=replace(t.header, **{key:value})), reason))
    for label, bs in (("zero", ()), ("one", t.batches[:1]), ("two", t.batches[:2]),
                      ("list", list(t.batches)), ("27", t.batches*9)):
        cases.append(("batch_count_"+label, replace(t,batches=bs), "COMPLETE_TRIPLETS"))
    v = t.batches[0].response
    for label, val, reason in (
        ("mutable_bytes", replace(v,raw_le=bytearray(v.raw_le)), "VALUE_WIDTH"),
        ("wrong_width", replace(v,raw_le=b"x"*3), "VALUE_WIDTH"),
        ("list_tags", replace(v,validity=["FINITE"]), "VALUE_COUNT"),
        ("bool_type", replace(v,storage_type=True), "NATIVE_TYPE"),
        ("empty", replace(v,validity=(),raw_le=b""), "VALUE_COUNT"),
        ("33", ints((1,)*33), "VALUE_COUNT"),
        ("bad_tag", replace(v,validity=("NODATA",)), "VALIDITY_TAG")):
        cases.append(("response_"+label, replace(t,batches=(replace(t.batches[0],response=val),)+t.batches[1:]),reason))
    for label,val,reason in (
        ("oversize_tag",replace(v,validity=("F"*100000,)),"VALIDITY_TAG"),
        ("oversize_type",replace(v,storage_type="D"*100000),"NATIVE_TYPE")):
        cases.append(("response_"+label,replace(t,batches=(replace(t.batches[0],response=val),)+t.batches[1:]),reason))
    for label, req, reason in (
        ("short", Request("INTEGER", b"\x01"), "REQUEST_WIDTH"),
        ("mutable", Request("INTEGER", bytearray(b"\x01\0\0\0")), "REQUEST_WIDTH"),
        ("storage", Request("FLOAT32", b"\x01\0\0\0"), "NATIVE_TYPE")):
        cases.append(("request_"+label, replace(t,batches=(replace(t.batches[0],request=req),)+t.batches[1:]),reason))
    second = tuple(replace(b,sequence=b.sequence+3) for b in t.batches)
    altered = replace(second[0],response=doubles(("FINITE", PZERO)))
    cases.append(("role_storage_change", replace(t,batches=t.batches+(altered,)+second[1:]),"ROLE_STORAGE_CHANGED"))
    req = request("DOUBLE", (5,))
    cases.append(("triplet_request_type_change",replace(t,batches=(t.batches[0],replace(t.batches[1],request=req),t.batches[2])),"TRIPLET_REQUEST"))
    # 171 observations per role => 513 slots, with otherwise valid complete triplets.
    bs = list(fixtures()["many"].batches)
    for i in (21,22,23):
        b=bs[i];bs[i]=replace(b,request=request("DOUBLE",(1,)*4),
                              response=doubles(*(("FINITE",PZERO),)*4))
    cases.append(("slot_513",replace(t,batches=tuple(bs)),"SLOT_LIMIT"))
    return cases


class MalformedInputTests(unittest.TestCase):
    def test_nonbytes_decoder_inputs_reject(self):
        for raw in (bytearray(GOLDEN),memoryview(GOLDEN),"wire",None):
            with self.subTest(type=type(raw)), self.assertRaisesRegex(Stop,"WIRE_SIZE"):
                decode(raw)

    def test_extra_approval_or_command_fields_cannot_be_constructed(self):
        with self.assertRaises(TypeError):
            Header(RUN,ATTEMPT,"tiny",3,3,0,0,"0.0.1","fixture",approved=True)
        with self.assertRaises(TypeError):
            Values("INTEGER",("FINITE",),b"\x01\0\0\0",shell="true")


def _input_test(t, reason):
    def test(self):
        with self.assertRaisesRegex(Stop,"^"+reason+"$"):
            encode(t)
    return test


for _name, _t, _reason in encoder_negative_cases():
    setattr(MalformedInputTests,"test_"+_name,_input_test(_t,_reason))


@unittest.skipUnless(os.environ.get("MM_S2CV_R_OUTPUT"), "NOT_RUN: separate R stage output not supplied")
class REquivalenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        p=Path(os.environ["MM_S2CV_R_OUTPUT"])
        info=p.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_size>65536:
            raise AssertionError("R_STAGE_TRANSPORT_STOP")
        with p.open("rb") as stream:
            raw=stream.read(65537)
        if len(raw)>65536:
            raise AssertionError("R_STAGE_TRANSPORT_STOP")
        cls.wires={};summaries=[];passed=[]
        for line in raw.decode("ascii").splitlines():
            if re.fullmatch(r"PASS [A-Za-z0-9_]+",line):
                passed.append(line);continue
            m=re.fullmatch(r"V2_CASE=([a-z_]+)\|WIRE=([0-9a-f]+)",line)
            if m:
                name,wire=m.groups()
                if name in cls.wires:raise AssertionError("DUPLICATE_R_CASE")
                cls.wires[name]=bytes.fromhex(wire)
                continue
            if re.fullmatch(r"R_V2_SUMMARY PASS=58 FAIL=0 NOT_RUN=0 R=[0-9.]+",line):
                summaries.append(line);continue
            raise AssertionError("INVALID_R_STAGE_OUTPUT:"+line[:100])
        if len(summaries)!=1 or len(passed)!=58 or len(set(passed))!=58 or set(cls.wires)!=set(fixtures()):
            raise AssertionError("INCOMPLETE_R_STAGE_OUTPUT")

    def test_all_R_wires_match_separate_Python_layout_expectations(self):
        for name,t in fixtures().items():
            with self.subTest(name=name):self.assertEqual(self.wires[name],oracle(t))

    def test_all_R_wires_match_Python_encoder(self):
        for name,t in fixtures().items():
            with self.subTest(name=name):self.assertEqual(self.wires[name],encode(t).data)

    def test_R_minimum_matches_hand_literal(self):
        self.assertEqual(self.wires["minimum"],GOLDEN)

    def test_R_wires_decode_exactly_and_roundtrip(self):
        for name,t in fixtures().items():
            with self.subTest(name=name):
                self.assertEqual(decode(self.wires[name]).transcript,t)
                self.assertEqual(encode(decode(self.wires[name]).transcript).data,self.wires[name])

    def test_R_modified_native_value_is_rejected_against_reference(self):
        t=fixtures()["minimum"];o=offsets(t)
        altered=changed(self.wires["minimum"],o["frames"][0]["value"],struct.pack("<i",2))
        self.assertEqual(decode(altered).disposition,"STRUCTURALLY_WELL_FORMED")
        with self.assertRaisesRegex(Stop,"REFERENCE_BYTES_MISMATCH"):
            compare_synthetic_reference(altered,self.wires["minimum"])


if __name__=="__main__":
    unittest.main()
