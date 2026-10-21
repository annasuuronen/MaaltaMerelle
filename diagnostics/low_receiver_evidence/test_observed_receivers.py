#!/usr/bin/env python3
"""Offline checks of an operator-supplied, DISPLAY-PRECISION PR #22 observation.

No GeoTIFF reads, route traversal, network requests or filesystem writes.
The 121 reported source routes are not validated accumulation.
"""
import csv
import pathlib
import sys
import unittest
from collections import defaultdict
from decimal import Decimal, InvalidOperation

HERE = pathlib.Path(__file__).resolve().parent
TARGET = HERE.parent / "land_network_topology" / "low_boundary_receivers_targets.csv"
OBSERVED = HERE / "observed_receivers_20261021.csv"
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


def load(path):
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames or len(reader.fieldnames) != len(set(reader.fieldnames)):
            raise ValueError("BAD_CSV_COLUMNS")
        rows = list(reader)
        if any(None in r for r in rows):
            raise ValueError("EXTRA_FIELDS")
        return rows


def validated(t, o):
    if len(t) != 16 or len(o) != 14:
        raise ValueError("WRONG_ROW_COUNTS")
    groups = defaultdict(list)
    exit_uids = set()
    observed_exit_records = set()
    for x in t:
        r, c, rr, cc, code, routes = (int(x[k]) for k in (
            "global_row", "global_col", "predicted_receiver_row",
            "predicted_receiver_col", "d8_code", "n_source_routes"))
        if x["exit_cell_uid"] != f"LOW-E200000-N6900000:{r}:{c}" or x["exit_id"] != "EXIT:" + x["exit_cell_uid"]:
            raise ValueError("UID_MISMATCH")
        if x["exit_cell_uid"] in exit_uids:
            raise ValueError("DUPLICATE_EXIT")
        exit_uids.add(x["exit_cell_uid"])
        if code not in D8 or (rr-r, cc-c) != D8[code]:
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
        r,c = int(x["receiver_row"]),int(x["receiver_col"])
        key = (r,c)
        if key in seen:
            raise ValueError("DUPLICATE_OBSERVATION")
        seen.add(key)
        if key not in groups or key not in LOCKED_OBSERVATIONS:
            raise ValueError("UNLOCKED_OBSERVATION")
        cid, reported, exits, land_text, pointer = LOCKED_OBSERVATIONS[key]
        if (int(x["cell_id"]),int(x["reported_source_routes"]),int(x["n_exit_edges"]),
                x["land_water_printed"],int(x["pointer"])) != (cid,reported,exits,land_text,pointer):
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
        dr,dc = D8[int(x["pointer"])]
        successors[key] = (r+dr,c+dc)
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


if __name__ == "__main__":
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(ObservationContract)
    result=unittest.TextTestRunner(verbosity=2, stream=sys.stdout).run(suite)
    print(f"PR22_OFFLINE_TESTS={result.testsRun} FAIL={len(result.failures)} ERRORS={len(result.errors)}")
    sys.exit(0 if result.wasSuccessful() and result.testsRun>=18 else 1)
