#!/usr/bin/env python3
"""Synthetic-only regression/rejection tests for CSV evidence inventory."""
import csv
import hashlib
import json
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from inventory_existing_evidence import (
    FILES, FIELDS, EvidenceError, evaluate, execute, geom, number, read_csv,
)

def ident(r,c): return (r-1)*6000+c

def fixture():
    base = dict(spill_level_m="12.175",outlet_selection="UNASSIGNED")
    g = [
        dict(base,spill_group_id="241",lake_objectid="1847",
             has_external_evidence="TRUE",needs_review="FALSE",evidence_status="EXTERNAL_EVIDENCE"),
        dict(base,spill_group_id="242",lake_objectid="1847",
             has_external_evidence="FALSE",needs_review="TRUE",evidence_status="REVIEW_REQUIRED"),
        dict(base,spill_group_id="243",lake_objectid="1848",
             has_external_evidence="FALSE",needs_review="FALSE",evidence_status="NO_EXTERNAL_EVIDENCE"),
        dict(base,spill_group_id="244",lake_objectid="1847",
             has_external_evidence="TRUE",needs_review="FALSE",evidence_status="EXTERNAL_EVIDENCE"),
    ]
    shore = [
        dict(spill_group_id="241",lake_objectid="1847",source_cell=str(ident(100,200)),
             receiver_cell=str(ident(100,201)),storage_step_level_m="12.175",receiver_type="RIVER_LINE"),
        dict(spill_group_id="242",lake_objectid="1847",source_cell=str(ident(100,210)),
             receiver_cell=str(ident(100,211)),storage_step_level_m="12.175",receiver_type="LAND"),
        dict(spill_group_id="243",lake_objectid="1848",source_cell=str(ident(200,200)),
             receiver_cell=str(ident(200,201)),storage_step_level_m="12.175",receiver_type="LAND"),
        dict(spill_group_id="244",lake_objectid="1847",source_cell=str(ident(101,210)),
             receiver_cell=str(ident(100,210)),storage_step_level_m="12.175",receiver_type="LAND"),
    ]
    candidates = []
    for x in g:
        z = dict(x)
        include = x["evidence_status"] == "EXTERNAL_EVIDENCE"
        z["candidate_included"] = str(include).upper()
        z["water_connected_candidate_status"] = (
            "INCLUDED_PARALLEL_CANDIDATE" if include else x["evidence_status"])
        candidates.append(z)
    eligible = [dict(x) for x in shore if x["spill_group_id"] in ("241","244")]
    routes = [
        dict(eligible[0],route_id="1",route_status="REACHES_RIVER_LINE",
             route_terminal_cell=eligible[0]["receiver_cell"],
             terminal_water_class="3",terminal_lake_objectid="NA"),
        dict(eligible[1],route_id="2",route_status="RETURNS_TO_ORIGIN_LAKE",
             route_terminal_cell=str(ident(100,200)),
             terminal_water_class="1",terminal_lake_objectid="1847"),
    ]
    return dict(groups=g,shore=shore,candidates=candidates,candidate_edges=eligible,routes=routes)

def save_fixture(data, folder):
    for role,name in FILES.items():
        rows=data[role]
        with (folder/name).open("w",newline="",encoding="utf-8") as f:
            w=csv.DictWriter(f,fieldnames=list(rows[0]))
            w.writeheader();w.writerows(rows)

class EvidenceInventoryTests(unittest.TestCase):
    def setUp(self):
        self.data=fixture()
    def check_stop(self,tag,func=None):
        if func is not None:func()
        with self.assertRaisesRegex(EvidenceError,tag):
            evaluate(self.data)
    def test_happy_path_all_groups_preserved(self):
        groups,lakes,r=evaluate(self.data)
        self.assertEqual(len(groups),4)
        self.assertEqual(len(lakes),2)
        self.assertEqual(r["n_candidate_edges"],2)
        self.assertEqual(r["n_first_water_contact_edge_routes"],1)
        self.assertEqual(r["n_not_first_water_contact_edge_routes"],1)
        self.assertEqual(r["outlets_selected"],0)
        self.assertEqual(r["flow_accumulation"],"NOT_COMPUTED")
    def test_no_promotion_after_first_water(self):
        groups,_,_=evaluate(self.data)
        self.assertEqual(groups[0]["inventory_case"],"FIRST_WATER_CONTACT_ONLY")
        self.assertEqual(groups[-1]["inventory_case"],"MIXED_OR_UNRESOLVED_FIRST_WATER")
        self.assertTrue(all(x["outlet_selection"]=="UNASSIGNED" for x in groups))
        self.assertTrue(all(x["fully_connected_to_sea"]=="NOT_ASSESSED" for x in groups))
    def test_lake_summary_alternative_groups(self):
        _,lakes,r=evaluate(self.data)
        a=next(x for x in lakes if x["lake_objectid"]==1847)
        self.assertEqual(a["n_spill_groups"],3)
        self.assertEqual(a["n_included_candidate_groups"],2)
        self.assertEqual(a["n_review_groups"],1)
        self.assertEqual(r["n_lakes_with_multiple_included_candidate_groups"],1)
    def test_diagonal_and_cardinal_not_equivalent_to_vector_corner(self):
        self.assertFalse(geom(ident(100,100),ident(100,101)))
        self.assertTrue(geom(ident(100,100),ident(101,101)))
        self.assertEqual(evaluate(self.data)[2]["n_diagonal_shore_edges"],0)
    def test_cross_row_id_wrap_rejected(self):
        self.check_stop("NON_ADJACENT_SHORE_EDGE",
                        lambda: self.data["shore"][0].update(
                            source_cell=str(ident(100,6000)),receiver_cell=str(ident(101,1))))
    def test_duplicate_group_rejected(self):
        self.data["groups"].append(dict(self.data["groups"][0]))
        self.check_stop("DUPLICATE_GROUP")
    def test_duplicate_edge_rejected(self):
        self.data["shore"].append(dict(self.data["shore"][0]))
        self.check_stop("DUPLICATE_EDGE")
    def test_missing_group_in_candidates_rejected(self):
        self.data["candidates"].pop()
        self.check_stop("MISSING_02E_GROUPS")
    def test_candidate_included_status_lie_rejected(self):
        self.data["candidates"][0]["candidate_included"]="FALSE"
        self.check_stop("CANDIDATE_FLAG_MISMATCH")
    def test_real_outlet_selection_rejected(self):
        self.data["groups"][0]["outlet_selection"]="ACCEPTED"
        self.check_stop("REAL_OUTLET_SELECTION_FORBIDDEN")
    def test_group_flags_mismatch_rejected(self):
        self.data["groups"][1]["evidence_status"]="EXTERNAL_EVIDENCE"
        self.check_stop("GROUP_STATUS_INCONSISTENT")
    def test_bad_boolean_rejected(self):
        self.data["groups"][1]["needs_review"]="NA"
        self.check_stop("INVALID_BOOLEAN")
    def test_candidate_level_changed_rejected(self):
        self.data["candidates"][0]["spill_level_m"]="12.180"
        self.check_stop("CANDIDATE_LEVEL_MISMATCH")
    def test_candidate_edge_group_rejected(self):
        self.data["candidate_edges"][0]["spill_group_id"]="242"
        self.check_stop("INELIGIBLE_CANDIDATE_EDGE")
    def test_missing_02e_edge_rejected(self):
        self.data["candidate_edges"].pop()
        self.check_stop("CANDIDATE_EDGE_COVERAGE_MISMATCH")
    def test_missing_02f_edge_rejected(self):
        self.data["routes"].pop()
        self.check_stop("MISSING_02F_ROUTE_EDGES")
    def test_route_duplicate_rejected(self):
        self.data["routes"].append(dict(self.data["routes"][0]))
        self.check_stop("ROUTE_EDGE_COVERAGE_OR_DUPLICATE")
    def test_no_unknown_route_status_silently_accepted(self):
        self.data["routes"][0]["route_status"]="REACHES_SEA"
        self.check_stop("UNKNOWN_ROUTE_STATUS")
    def test_water_class_receiver_rejected(self):
        self.data["routes"][0]["terminal_water_class"]="2"
        self.check_stop("TERMINAL_WATER_CLASS_MISMATCH")
    def test_wrong_origin_lake_terminal_rejected(self):
        self.data["routes"][1]["terminal_lake_objectid"]="1848"
        self.check_stop("TERMINAL_LAKE_RELATION")
    def test_malformed_coordinate_id_rejected(self):
        self.data["shore"][0]["source_cell"]="0"
        self.check_stop("INVALID_ID")
    def test_orphan_edge_lake_rejected(self):
        self.data["shore"][0]["lake_objectid"]="9999"
        self.check_stop("EDGE_GROUP_OR_LAKE_MISMATCH")
    def test_same_receiver_must_yield_same_diagnostic(self):
        # Two distinct source shore edges to the same receiver/origin share one 02F trace.
        x=self.data["shore"][0]
        e=dict(x,source_cell=str(ident(101,201)))
        self.data["shore"].append(e)
        self.data["candidate_edges"].append(dict(e))
        z=dict(e,route_id="9",route_status="REACHES_RIVER_LINE",
               route_terminal_cell=x["receiver_cell"],terminal_water_class="3",
               terminal_lake_objectid="NA")
        self.data["routes"].append(z)
        self.check_stop("SAME_RECEIVER_DIFFERENT_TRACE")
        self.data["routes"][-1]["route_id"]="1"
        self.assertEqual(evaluate(self.data)[2]["n_unique_02f_origin_receiver_traces"],2)
    def test_counts_for_duplicate_receiver_not_accumulation(self):
        x=self.data["shore"][0]
        e=dict(x,source_cell=str(ident(101,201)))
        self.data["shore"].append(e);self.data["candidate_edges"].append(dict(e))
        self.data["routes"].append(dict(e,route_id="1",
            route_status="REACHES_RIVER_LINE",route_terminal_cell=x["receiver_cell"],
            terminal_water_class="3",terminal_lake_objectid="NA"))
        r=evaluate(self.data)[2]
        self.assertEqual(r["n_02f_edge_routes"],3)
        self.assertEqual(r["n_unique_02f_origin_receiver_traces"],2)
        self.assertEqual(r["flow_accumulation"],"NOT_COMPUTED")
    def test_file_headers_and_hashes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);save_fixture(self.data,root)
            rows,hashval=read_csv(root/FILES["groups"],FIELDS["groups"])
            self.assertEqual(len(rows),4)
            self.assertEqual(hashval,hashlib.sha256((root/FILES["groups"]).read_bytes()).hexdigest())
    def test_missing_input_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(EvidenceError,"MISSING_OR_SYMLINK"):
                read_csv(Path(tmp)/"missing.csv",FIELDS["groups"])
    def test_header_mutation_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/"bad.csv";p.write_text("spill_group_id,lake_objectid\n1,2\n")
            with self.assertRaisesRegex(EvidenceError,"CSV_SCHEMA"):
                read_csv(p,FIELDS["groups"])
    def test_extra_csv_field_allowed(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.data["groups"][0]["future_extra"]="optional"
            for row in self.data["groups"][1:]:
                row["future_extra"]="NA"
            root=Path(tmp)
            save_fixture(self.data,root)
            rows,_=read_csv(root/FILES["groups"],FIELDS["groups"])
            self.assertEqual(len(rows),4)
            self.assertEqual(rows[0]["future_extra"],"optional")
    def test_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);p=root/"a.csv";p.write_text("x")
            (root/"b.csv").symlink_to(p)
            with self.assertRaisesRegex(EvidenceError,"MISSING_OR_SYMLINK"):
                read_csv(root/"b.csv",FIELDS["groups"])
    def test_oversized_csv_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/"huge.csv"
            with p.open("wb") as f: f.truncate(15_000_001)
            with self.assertRaisesRegex(EvidenceError,"FILE_SIZE_LIMIT"):
                read_csv(p,FIELDS["groups"])
    def test_output_isolated_and_sha_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);inp=root/"inputs";inp.mkdir()
            save_fixture(self.data,inp)
            before={x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in inp.iterdir()}
            out=root/"outputs"
            report=execute(inp,out,"CSC_PROVENANCE_UNVERIFIED")
            self.assertEqual(report["n_spill_groups"],4)
            self.assertEqual(sorted(x.name for x in out.iterdir()),
                             ["lake_inventory.csv","spill_group_inventory.csv","summary.json"])
            self.assertEqual(before,{x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in inp.iterdir()})
            self.assertEqual(json.loads((out/"summary.json").read_text())["n_candidate_edges"],2)
            with self.assertRaisesRegex(EvidenceError,"OUTPUT_EXISTS"):
                execute(inp,out,"CSC_PROVENANCE_UNVERIFIED")
    def test_no_empty_evidence(self):
        self.data["groups"]=[]
        self.check_stop("EMPTY_GROUP_EVIDENCE")
    def test_no_approval_can_be_inferred_from_status(self):
        groups,_,summary=evaluate(self.data)
        self.assertEqual(summary["verified_outlet_count"],"NOT_ASSESSED")
        self.assertTrue(all(x["fully_connected_to_sea"]=="NOT_ASSESSED" for x in groups))

if __name__=="__main__":
    unittest.main(verbosity=2)
