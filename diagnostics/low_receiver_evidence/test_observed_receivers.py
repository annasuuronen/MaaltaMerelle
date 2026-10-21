#!/usr/bin/env python3
"""Offline checks of an operator-supplied, DISPLAY-PRECISION PR #22 observation.

No GeoTIFF reads, route traversal, network requests or filesystem writes.
The 121 reported source routes are not validated accumulation.
"""
import csv
import copy
import hashlib
import io
import json
import pathlib
import re
import sys
import unittest
from collections import defaultdict
from decimal import Decimal, InvalidOperation

HERE = pathlib.Path(__file__).resolve().parent
TARGET = HERE.parent / "land_network_topology" / "low_boundary_receivers_targets.csv"
OBSERVED = HERE / "observed_receivers_20261021.csv"
PROVENANCE = HERE / "observation_provenance.json"
TARGET_SHA256 = "965eec1ea145adc346e52413f2539ec9fe17d82eeab7cf709fafa37f7696bf57"
OBSERVED_SHA256 = "176558ec8306afdee35d7932d56faa5979313c5b8a748f2613ab11b76ee62683"
TARGET_FIELDS = ("exit_id", "exit_cell_uid", "global_row", "global_col", "d8_code",
                 "predicted_receiver_row", "predicted_receiver_col", "n_source_routes")
OBSERVED_FIELDS = ("receiver_row", "receiver_col", "cell_id", "reported_source_routes",
                   "n_exit_edges", "land_water_printed", "water_class_printed",
                   "lake_id_printed", "pointer", "receiver_class")
EXPECTED_PROVENANCE = {
    "schema_version": 1,
    "repository": "annasuuronen/MaaltaMerelle",
    "report_url": "https://github.com/annasuuronen/MaaltaMerelle/pull/22",
    "observation_date": "2026-10-21",
    "evidence_kind": "USER_REPORTED_CONSOLE_TRANSCRIPTION",
    "observation_code_commit": "effab29aa4d44ecc897efc0c91c96f3bfc1b4db6",
    "exit_inventory_code_commit": "40509d5006cbf7fb431701e7a48383dde0fdb38c",
    "observation_sha256": OBSERVED_SHA256,
    "target_sha256": TARGET_SHA256,
    "reported_original_adler32": "0f39c62a",
    "adler32_verification": "NOT_RECOMPUTED",
    "historical_d8_provenance": "INCOMPLETE",
    "historical_d8_commit": "UNKNOWN",
    "land_water_precision": "CONSOLE_PRINTED_ONLY",
    "signed_raw_artifact": False,
    "reported_geometry": {"nrow": 6000, "ncol": 6000, "epsg": 3067, "resolution_m": 2},
    "reported_read_budget": {"calls": 4, "unique_cells": 14, "returned_values": 56,
                             "downstream_steps": 0},
    "source_routes_meaning": "REPORTED_COUNTS_NOT_ACCUMULATION",
    "hydrological_validation": "NOT_ASSESSED",
    "channel_interpretation": "NOT_ASSESSED",
    "MODERATE": "REVIEW_REQUIRED", "NATIONAL": "LOCKED",
}
D8 = {1: (-1, 1), 2: (0, 1), 4: (1, 1), 8: (1, 0),
      16: (1, -1), 32: (0, -1), 64: (-1, -1), 128: (-1, 0)}
LOCKED_EXIT_RECORDS = {
    (2995,2995,32,2995,2994,5), (2995,3005,2,2995,3006,6),
    (2996,2995,32,2996,2994,5), (2996,3005,2,2996,3006,6),
    (2997,2995,32,2997,2994,4), (2997,3005,2,2997,3006,6),
    (2998,2995,32,2998,2994,4), (2998,3005,2,2998,3006,8),
    (2999,2995,32,2999,2994,3), (3000,2995,32,3000,2994,2),
    (3001,2995,64,3000,2994,18), (3005,2995,32,3005,2994,1),
    (3005,3001,4,3006,3002,4), (3005,3002,8,3006,3002,28),
    (3005,3004,8,3006,3004,16), (3005,3005,8,3006,3005,5),
}
LOCKED_OBSERVATIONS = {
    (2995, 2994): (17966994, 5, 1, "0.2210163", 64),
    (2995, 3006): (17967006, 6, 1, "0.2212425", 2),
    (2996, 2994): (17972994, 5, 1, "0.2210166", 32),
    (2996, 3006): (17973006, 6, 1, "0.2212425", 2),
    (2997, 2994): (17978994, 4, 1, "0.2210166", 32),
    (2997, 3006): (17979006, 6, 1, "0.2212425", 2),
    (2998, 2994): (17984994, 4, 1, "0.2210166", 32),
    (2998, 3006): (17985006, 8, 1, "0.2212425", 2),
    (2999, 2994): (17990994, 3, 1, "0.2210166", 64),
    (3000, 2994): (17996994, 20, 2, "0.2210169", 128),
    (3005, 2994): (18026994, 1, 1, "0.2210181", 32),
    (3006, 3002): (18033002, 32, 2, "0.2210313", 8),
    (3006, 3004): (18033004, 16, 1, "0.2210304", 8),
    (3006, 3005): (18033005, 5, 1, "0.2210304", 8),
}


def parse_csv(text, fields):
    reader = csv.DictReader(io.StringIO(text, newline=""), strict=True)
    if (not reader.fieldnames or len(reader.fieldnames) != len(set(reader.fieldnames))
            or set(reader.fieldnames) != set(fields)):
        raise ValueError("BAD_CSV_COLUMNS")
    rows = list(reader)
    check_rows(rows, fields)
    return rows


def check_rows(rows, fields):
    for row in rows:
        if (set(row) != set(fields) or any(not isinstance(x, str) or not x
                                         for x in row.values())):
            raise ValueError("BAD_CSV_RECORD")


def load(path):
    fields = TARGET_FIELDS if path.name == TARGET.name else OBSERVED_FIELDS
    return parse_csv(path.read_text(encoding="utf-8"), fields)


def positive_integer(text):
    if not isinstance(text, str) or not re.fullmatch(r"[1-9][0-9]{0,8}", text):
        raise ValueError("NONCANONICAL_INTEGER")
    return int(text)


def d8_receiver(row, col, code, nrow=6000, ncol=6000):
    # Row/column arithmetic prevents east/west wrapping in flattened IDs.
    if any(type(x) is not int for x in (row, col, code, nrow, ncol)):
        raise ValueError("INTEGER_GEOMETRY_REQUIRED")
    if not (1 <= row <= nrow and 1 <= col <= ncol) or code not in D8:
        raise ValueError("INVALID_SOURCE_OR_POINTER")
    dr, dc = D8[code]
    rr, cc = row + dr, col + dc
    if not (1 <= rr <= nrow and 1 <= cc <= ncol):
        raise ValueError("OUTSIDE_GRID")
    return rr, cc


def unique_json_pairs(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise ValueError("DUPLICATE_PROVENANCE_KEY")
        out[key] = value
    return out


def validate_provenance(data, target_bytes, observed_bytes):
    # Strict types as well as values: JSON true must not equal integer 1.
    if json.dumps(data, sort_keys=True) != json.dumps(EXPECTED_PROVENANCE, sort_keys=True):
        raise ValueError("PROVENANCE_MISMATCH")
    if (hashlib.sha256(target_bytes).hexdigest() != TARGET_SHA256 or
            hashlib.sha256(observed_bytes).hexdigest() != OBSERVED_SHA256):
        raise ValueError("EVIDENCE_BYTES_CHANGED")
    # These checks authenticate the committed transcription, NOT its external origin.
    return data


def audit_provenance():
    data = json.loads(PROVENANCE.read_text(), object_pairs_hook=unique_json_pairs)
    return validate_provenance(data, TARGET.read_bytes(), OBSERVED.read_bytes())


def validated(t, o):
    check_rows(t, TARGET_FIELDS)
    check_rows(o, OBSERVED_FIELDS)
    if len(t) != 16 or len(o) != 14:
        raise ValueError("WRONG_ROW_COUNTS")
    groups = defaultdict(list)
    exit_uids = set()
    observed_exit_records = set()
    for x in t:
        r, c, rr, cc, code, routes = (positive_integer(x[k]) for k in (
            "global_row", "global_col", "predicted_receiver_row",
            "predicted_receiver_col", "d8_code", "n_source_routes"))
        if x["exit_cell_uid"] != f"LOW-E200000-N6900000:{r}:{c}" or x["exit_id"] != "EXIT:" + x["exit_cell_uid"]:
            raise ValueError("UID_MISMATCH")
        if x["exit_cell_uid"] in exit_uids:
            raise ValueError("DUPLICATE_EXIT")
        exit_uids.add(x["exit_cell_uid"])
        if d8_receiver(r, c, code) != (rr, cc):
            raise ValueError("D8_MISMATCH")
        if not (1 <= rr <= 6000 and 1 <= cc <= 6000) or 2995 <= rr <= 3005 and 2995 <= cc <= 3005:
            raise ValueError("RECEIVER_DOMAIN_MISMATCH")
        if routes <= 0:
            raise ValueError("INVALID_ROUTE_COUNT")
        observed_exit_records.add((r,c,code,rr,cc,routes))
        groups[(rr, cc)].append(routes)
    if observed_exit_records != LOCKED_EXIT_RECORDS:
        raise ValueError("EXIT_RECORDS_DIFFER_FROM_HISTORICAL_LOCK")
    if sum(sum(v) for v in groups.values()) != 121:
        raise ValueError("REPORTED_SUM_CHANGED")
    if len(groups) != 14 or {p:len(v) for p,v in groups.items() if len(v)>1} != {(3000,2994):2, (3006,3002):2}:
        raise ValueError("GROUPING_MISMATCH")
    if {p: sum(groups[p]) for p in [(3000,2994),(3006,3002)]} != {(3000,2994):20,(3006,3002):32}:
        raise ValueError("SHARED_COUNTS_MISMATCH")
    seen = set()
    successors = {}
    for x in o:
        r,c = positive_integer(x["receiver_row"]),positive_integer(x["receiver_col"])
        key = (r,c)
        if key in seen:
            raise ValueError("DUPLICATE_OBSERVATION")
        seen.add(key)
        if key not in groups or key not in LOCKED_OBSERVATIONS:
            raise ValueError("UNLOCKED_OBSERVATION")
        cid, reported, exits, land_text, pointer = LOCKED_OBSERVATIONS[key]
        if (positive_integer(x["cell_id"]),positive_integer(x["reported_source_routes"]),
                positive_integer(x["n_exit_edges"]), x["land_water_printed"],
                positive_integer(x["pointer"])) != (cid,reported,exits,land_text,pointer):
            raise ValueError("PRINTED_OBSERVATION_MISMATCH")
        if int(x["cell_id"]) != (r-1)*6000+c or x["cell_id"] != str(cid):
            raise ValueError("CELL_ID_MISMATCH")
        if int(x["reported_source_routes"]) != sum(groups[key]) or int(x["n_exit_edges"]) != len(groups[key]):
            raise ValueError("LOCKED_LINK_MISMATCH")
        if x["water_class_printed"] != "NaN" or x["lake_id_printed"] != "NaN" or x["receiver_class"] != "LAND":
            raise ValueError("WATER_CLASS_OR_LAKE_CHANGED")
        try:
            z = Decimal(x["land_water_printed"])
        except InvalidOperation:
            raise ValueError("INVALID_PRINTED_LAND")
        if not z.is_finite():
            raise ValueError("NONFINITE_LAND")
        if int(x["pointer"]) not in D8:
            raise ValueError("INVALID_POINTER")
        successors[key] = d8_receiver(r, c, int(x["pointer"]))
    if seen != set(groups):
        raise ValueError("MISSING_RECEIVER")
    return groups, successors


class ObservationContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.targets, cls.obs = load(TARGET), load(OBSERVED)

    def check(self, targets=None, obs=None):
        return validated(self.targets if targets is None else targets,
                         self.obs if obs is None else obs)

    def test_complete_contract(self):
        groups, successors = self.check()
        self.assertEqual(len(groups), 14)
        self.assertEqual(len(successors), 14)

    def test_all_observation_rows_match_printed_transcript(self):
        for x in self.obs:
            with self.subTest(row=x["receiver_row"],col=x["receiver_col"]):
                key=(int(x["receiver_row"]),int(x["receiver_col"]))
                self.assertEqual(x["land_water_printed"],LOCKED_OBSERVATIONS[key][3])
                self.assertEqual(int(x["pointer"]),LOCKED_OBSERVATIONS[key][4])

    def test_fourteen_positions_and_no_unsupported_contacts(self):
        self.assertEqual(len(self.obs),14)
        for x in self.obs:
            with self.subTest(cell=x["cell_id"]):
                self.assertEqual(x["receiver_class"],"LAND")
                self.assertEqual(x["water_class_printed"],"NaN")
                self.assertEqual(x["lake_id_printed"],"NaN")

    def test_independent_whole_raster_indices(self):
        for x in self.obs:
            with self.subTest(cell=x["cell_id"]):
                self.assertEqual(int(x["cell_id"]),(int(x["receiver_row"])-1)*6000+int(x["receiver_col"]))

    def test_all_d8_edges_are_one_step(self):
        for x in self.targets:
            with self.subTest(exit=x["exit_id"]):
                dr,dc=D8[int(x["d8_code"])]
                self.assertEqual(int(x["predicted_receiver_row"])-int(x["global_row"]),dr)
                self.assertEqual(int(x["predicted_receiver_col"])-int(x["global_col"]),dc)

    def test_group_and_route_tallies(self):
        g,_=self.check()
        self.assertEqual(sum(len(v) for v in g.values()),16)
        self.assertEqual(sum(sum(v) for v in g.values()),121)
        self.assertEqual(sorted((k,len(v),sum(v)) for k,v in g.items() if len(v)>1),
                         [((3000,2994),2,20),((3006,3002),2,32)])

    def test_current_sample_d8_status_all_valid(self):
        self.assertTrue(all(int(x["pointer"]) in D8 for x in self.obs))

    def test_derived_one_known_link_and_no_inferred_water_contact(self):
        _,successors=self.check()
        internal={k:v for k,v in successors.items() if v in successors}
        self.assertEqual(internal,{(3000,2994):(2999,2994)})
        self.assertEqual(len(successors)-len(internal),13)

    def test_west_east_south_inventory(self):
        west=[x for x in self.obs if int(x["receiver_col"])==2994]
        east=[x for x in self.obs if int(x["receiver_col"])==3006]
        south=[x for x in self.obs if int(x["receiver_row"])==3006]
        self.assertEqual((len(west),len(east),len(south)),(7,4,3))
        self.assertEqual(tuple(sum(int(x["reported_source_routes"]) for x in z) for z in (west,east,south)),(42,26,53))

    def test_order_permutations_invariant(self):
        for k in range(1,17):
            with self.subTest(rotation=k):
                self.assertEqual({p: sorted(v) for p,v in self.check(self.targets[k:]+self.targets[:k])[0].items()},
                                 {p: sorted(v) for p,v in self.check()[0].items()})
        for k in range(1,14):
            with self.subTest(rotation=k):
                self.assertEqual(self.check(obs=self.obs[k:]+self.obs[:k])[1],self.check()[1])

    def test_reject_all_missing_target_rows(self):
        for i in range(16):
            with self.subTest(removed=i),self.assertRaises(ValueError):
                self.check(targets=self.targets[:i]+self.targets[i+1:])

    def test_reject_all_missing_observed_rows(self):
        for i in range(14):
            with self.subTest(removed=i),self.assertRaises(ValueError):
                self.check(obs=self.obs[:i]+self.obs[i+1:])

    def test_reject_duplicate_exits_and_receivers(self):
        for i in range(16):
            modified=[dict(x) for x in self.targets]
            modified[i]=dict(self.targets[(i+1)%16])
            with self.subTest(exit=i),self.assertRaises(ValueError):
                self.check(targets=modified)
        for i in range(14):
            modified=[dict(x) for x in self.obs]
            modified[i]=dict(self.obs[(i+1)%14])
            with self.subTest(receiver=i),self.assertRaises(ValueError):
                self.check(obs=modified)

    def test_reject_every_changed_observed_value(self):
        for i in range(14):
            for col,value in (("cell_id","1"),("reported_source_routes","1" if self.obs[i]["reported_source_routes"]!="1" else "2"),
                              ("land_water_printed","0.999"),("water_class_printed","1"),
                              ("lake_id_printed","999"),("pointer","3"),("receiver_class","WATER")):
                modified=[dict(x) for x in self.obs]
                modified[i][col]=value
                with self.subTest(receiver=i,col=col),self.assertRaises(ValueError):
                    self.check(obs=modified)

    def test_reject_every_changed_source_route_count_even_if_global_sum_preserved(self):
        for i in range(16):
            modified=[dict(x) for x in self.targets]
            modified[i]["n_source_routes"]=str(int(modified[i]["n_source_routes"])+1)
            j=(i+1)%16
            modified[j]["n_source_routes"]=str(int(modified[j]["n_source_routes"])-1)
            with self.subTest(changed=i), self.assertRaises(ValueError):
                self.check(targets=modified)

    def test_reject_every_changed_source_direction(self):
        for i in range(16):
            modified=[dict(x) for x in self.targets]
            modified[i]["d8_code"]="3"
            with self.subTest(exit=i),self.assertRaises(ValueError):
                self.check(targets=modified)

    def test_reject_wrong_predicted_receivers(self):
        for i in range(16):
            modified=[dict(x) for x in self.targets]
            modified[i]["predicted_receiver_col"]=str(int(modified[i]["predicted_receiver_col"])+1)
            with self.subTest(exit=i),self.assertRaises(ValueError):
                self.check(targets=modified)

    def test_reject_wrong_historical_provenance_uid(self):
        for i in range(16):
            modified=[dict(x) for x in self.targets]
            modified[i]["exit_cell_uid"]="wrong"
            with self.subTest(exit=i),self.assertRaises(ValueError):
                self.check(targets=modified)

    def test_printed_precision_must_not_be_called_raw_precision(self):
        self.assertTrue(all(Decimal(x["land_water_printed"]).is_finite() for x in self.obs))
        self.assertTrue(all(len(x["land_water_printed"].split(".")[1])<=7 for x in self.obs))

    def test_evidence_bytes_and_provenance(self):
        self.assertEqual(audit_provenance(), EXPECTED_PROVENANCE)

    def test_every_provenance_field_is_locked(self):
        for key in EXPECTED_PROVENANCE:
            for operation in ("remove", "replace"):
                data = copy.deepcopy(EXPECTED_PROVENANCE)
                if operation == "remove": del data[key]
                else: data[key] = "FORGED"
                with self.subTest(key=key, operation=operation), self.assertRaises(ValueError):
                    validate_provenance(data, TARGET.read_bytes(), OBSERVED.read_bytes())

    def test_nested_provenance_mutations(self):
        for key in ("reported_geometry", "reported_read_budget"):
            for field in EXPECTED_PROVENANCE[key]:
                data = copy.deepcopy(EXPECTED_PROVENANCE); data[key][field] += 1
                with self.subTest(key=key, field=field), self.assertRaises(ValueError):
                    validate_provenance(data, TARGET.read_bytes(), OBSERVED.read_bytes())

    def test_provenance_duplicate_unknown_keys_and_boolean_version(self):
        with self.assertRaises(ValueError):
            json.loads('{"nested":{"x":1,"x":2}}', object_pairs_hook=unique_json_pairs)
        for key, value in (("approved", True), ("schema_version", True),
                           ("signed_raw_artifact", True), ("hydrological_validation", "PASS")):
            data = copy.deepcopy(EXPECTED_PROVENANCE); data[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_provenance(data, TARGET.read_bytes(), OBSERVED.read_bytes())

    def test_transcription_and_original_target_byte_mutations(self):
        for target, obs in ((TARGET.read_bytes()+b"\n", OBSERVED.read_bytes()),
                            (TARGET.read_bytes(), OBSERVED.read_bytes()+b"\n")):
            with self.assertRaises(ValueError):
                validate_provenance(EXPECTED_PROVENANCE, target, obs)

    def test_eight_directions_against_independent_numbered_grid(self):
        # Independently enumerated 5x7 grid, centre row 3 column 4 = cell 18.
        for code, expected in ((1,12),(2,19),(4,26),(8,25),(16,24),(32,17),(64,10),(128,11)):
            with self.subTest(code=code):
                rr, cc = d8_receiver(3,4,code,5,7)
                self.assertEqual((rr-1)*7+cc, expected)

    def test_grid_edges_do_not_wrap(self):
        for row,col,code in ((1,1,128),(1,1,64),(1,1,32),(5,7,2),(5,7,4),(5,7,8)):
            with self.subTest(row=row,col=col,code=code), self.assertRaises(ValueError):
                d8_receiver(row,col,code,5,7)
        self.assertEqual(d8_receiver(1,1,4,5,7), (2,2))

    def test_invalid_direction_types_and_sources(self):
        for code in (0,3,255,-1,None,True,2.0,"2"):
            with self.subTest(code=code), self.assertRaises(ValueError): d8_receiver(3,4,code,5,7)
        for row,col in ((0,1),(1,0),(6,1),(1,8)):
            with self.assertRaises(ValueError): d8_receiver(row,col,2,5,7)

    def test_observed_pointer_changes_to_other_valid_codes(self):
        for i in range(14):
            for code in D8:
                if str(code) == self.obs[i]["pointer"]: continue
                obs = copy.deepcopy(self.obs); obs[i]["pointer"] = str(code)
                with self.subTest(i=i,code=code), self.assertRaises(ValueError): self.check(obs=obs)

    def test_nonfinite_nodata_and_noncanonical_numbers(self):
        for field, values in (("land_water_printed", ("NaN","Infinity","-Infinity","",None)),
                              ("pointer", ("0","NA","NaN","2.0","+2"," 2","02",None)),
                              ("cell_id", ("1.0","-1","+17966994","017966994",None))):
            for value in values:
                for i in range(14):
                    obs = copy.deepcopy(self.obs); obs[i][field] = value
                    with self.subTest(i=i,field=field,value=value), self.assertRaises(ValueError): self.check(obs=obs)

    def test_each_observation_coordinate_and_group_size_is_locked(self):
        for i in range(14):
            for field in ("receiver_row","receiver_col","n_exit_edges"):
                obs = copy.deepcopy(self.obs); obs[i][field] = str(int(obs[i][field])+1)
                with self.subTest(i=i,field=field), self.assertRaises(ValueError): self.check(obs=obs)

    def test_each_source_coordinate_and_both_uids_are_locked(self):
        for i in range(16):
            for field in ("global_row","global_col","exit_id","exit_cell_uid"):
                rows = copy.deepcopy(self.targets)
                rows[i][field] = (str(int(rows[i][field])+1) if field.startswith("global") else "FORGED")
                with self.subTest(i=i,field=field), self.assertRaises(ValueError): self.check(targets=rows)

    def test_extra_observation_and_concatenated_output_rejected(self):
        for obs in (self.obs+[self.obs[0]], self.obs+self.obs):
            with self.assertRaises(ValueError): self.check(obs=obs)
        with self.assertRaises(ValueError): self.check(targets=self.targets+self.targets)

    def test_csv_headers_fields_and_missing_values(self):
        text = OBSERVED.read_text()
        header, tail = text.split("\n",1)
        for bad in (header+",pointer\n"+tail, header+",extra\n"+tail,
                    header.replace("pointer", "unknown")+"\n"+tail,
                    text.replace(",64,LAND", ",64,LAND,EXTRA",1),
                    text.replace(",64,LAND", ",64",1)):
            with self.subTest(bad=bad[:80]), self.assertRaises(ValueError): parse_csv(bad, OBSERVED_FIELDS)

    def test_unknown_or_missing_in_memory_columns_rejected(self):
        for rows, field in ((self.obs,"pointer"),(self.targets,"exit_id")):
            for op in ("missing","extra"):
                bad=copy.deepcopy(rows)
                if op=="missing": del bad[0][field]
                else: bad[0]["approved"]=True
                with self.subTest(field=field,op=op), self.assertRaises(ValueError):
                    self.check(obs=bad) if rows is self.obs else self.check(targets=bad)


if __name__ == "__main__":
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(ObservationContract)
    result=unittest.TextTestRunner(verbosity=2, stream=sys.stdout).run(suite)
    failed = len(result.failures) + len(result.errors)
    print(f"SUITE_RESULT cases={result.testsRun} pass={result.testsRun-failed-len(result.skipped)} "
          f"fail={failed} not_run={len(result.skipped)}")
    sys.exit(0 if result.wasSuccessful() and result.testsRun>0 and not result.skipped else 1)
