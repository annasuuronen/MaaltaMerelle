"""S2A synthetic tests. Locked identities are metadata, never real raster evidence."""
from contextlib import redirect_stdout
from copy import deepcopy
from dataclasses import FrozenInstanceError, replace
import io
import csv
import os
import subprocess
import json
import unittest
from unittest.mock import patch

import s2a_pure_d8_trace as s


def provenance(**changes):
    values = dict(data_kind="SYNTHETIC", pointer_id="synthetic-pointer-v1",
                  water_class_id="synthetic-mask-v1", lake_id_id="synthetic-lakes-v1",
                  evidence_version="synthetic-fixture-v1", producer_commit="a" * 40,
                  summary_sha256=s.SUMMARY_SHA256)
    values.update(changes)
    return s.Provenance(**values)


def arrays(window):
    return [[[default for _ in range(window.width)] for _ in range(window.height)]
            for default in (0, None, None)]


def supplied(changes=None, window=None, prov=None):
    window = window or s.Window(100, 100, 8, 8)
    data = arrays(window)
    for cell, triple in (changes or {}).items():
        row, col = s.row_col(cell)
        for array, value in zip(data, triple):
            array[row - window.yoff][col - window.xoff] = value
    return s.WindowData(s.Grid(), window, prov or provenance(), *data)


def c(row=102, col=102):
    return s.cell_id(row, col)


def six_fixture(with_neighbors=False):
    # Invented chain values reproduce the known starts/terminal/step structure.
    # They are NOT recovered intermediate LOW cells or the actual 02C neighbors.
    changes = {s.cell_id(r, 3318): (128, None, None) for r in range(3869, 3889)}
    changes.update({23337318: (1, None, None), 23343318: (128, None, None),
                    23343319: (64, None, None), 23343320: (32, None, None),
                    23349320: (64, None, None), 23355321: (64, None, None)})
    changes[s.TERMINAL] = (0, None, None)
    neighbors = tuple(s.Neighbor(274, s.TERMINAL, s.cell_id(r, col), 1, 1892)
                      for r, col in ((3868, 3317), (3868, 3319), (3867, 3317)))
    if with_neighbors:
        changes.update({n.water_cell: (3, 1, 1892) for n in neighbors})
    return supplied(changes, s.Window()), neighbors


class GeometryTests(unittest.TestCase):
    def test_exact_window_proof(self):
        self.assertEqual(s.prove_low_window(), s.Window(3293, 3844, 52, 73))
        self.assertEqual(s.prove_low_window().width * s.prove_low_window().height, 3796)

    def test_window_proof_is_order_independent(self):
        self.assertEqual(s.prove_low_window(tuple(reversed(s.LOCKED_SUMMARIES))), s.Window())

    def test_global_cell_conversion(self):
        for cell, rc in ((1, (0, 0)), (36000000, (5999, 5999)),
                         (23337318, (3889, 3317)), (s.TERMINAL, (3868, 3318))):
            with self.subTest(cell=cell):
                self.assertEqual(s.row_col(cell), rc)
                self.assertEqual(s.cell_id(*rc), cell)

    def test_full_grid_centers(self):
        self.assertEqual(s.center(1), (199001, 6910999))
        self.assertEqual(s.center(36000000), (210999, 6899001))
        self.assertEqual(s.center(s.TERMINAL), (205637, 6903263))

    def test_exact_window_extent(self):
        w = s.Window()
        self.assertEqual((199000 + 2*w.xoff, 199000 + 2*(w.xoff+w.width),
                          6911000 - 2*(w.yoff+w.height), 6911000 - 2*w.yoff),
                         (205586, 205690, 6903166, 6903312))

    def test_all_eight_whitebox_offsets_independently(self):
        # Literal independent table, not constructed from implementation OFFSETS.
        for code, dr, dc in ((1,-1,1), (2,0,1), (4,1,1), (8,1,0),
                             (16,1,-1), (32,0,-1), (64,-1,-1), (128,-1,0)):
            with self.subTest(code=code):
                destination = c(102+dr, 102+dc)
                t = s.trace(supplied({c(): (code, None, None)}), 1, c())
                self.assertEqual(t.entered_cells, (c(), destination))
                self.assertEqual(t.steps[0], s.Step(1, c(), code, 102+dr, 102+dc, destination, "ADVANCED"))
                self.assertEqual(t.route_status, "D8_ZERO_INTERIOR")
                self.assertEqual(t.route_steps, 1)

    def test_window_indices_are_not_full_grid_ids(self):
        data, _ = six_fixture()
        item = data.sample(23337318)
        self.assertEqual((item.row0, item.col0), (3889, 3317))
        self.assertNotEqual(item.cell_id, (3889-3844)*52 + 3317-3293+1)

    def test_bad_cell_ids_fail(self):
        for cell in (0, -1, 36000001, True, 1.0):
            with self.subTest(cell=cell), self.assertRaises(s.Stop):
                s.row_col(cell)

    def test_wrong_grid_crs(self):
        with self.assertRaises(s.Stop):
            s.Grid(epsg=4326)

    def test_wrong_grid_origin_resolution_and_size(self):
        for changes in (dict(xmin=199002), dict(ymax=6911002), dict(resolution_m=1),
                        dict(nrow=5999), dict(ncol=52), dict(grid_id="OTHER"), dict(epsg=3067.0)):
            with self.subTest(changes=changes), self.assertRaises(s.Stop):
                s.Grid(**changes)

    def test_window_bounds_cannot_expand(self):
        for changes in (dict(width=53), dict(height=74), dict(xoff=-1), dict(yoff=6000),
                        dict(xoff=5999, width=2), dict(width=True)):
            with self.subTest(changes=changes), self.assertRaises(s.Stop):
                s.Window(**changes)

    def test_low_audit_rejects_shifted_window(self):
        with self.assertRaises(s.Stop):
            s.audit_low(supplied(window=s.Window(3294, 3844, 52, 73)))

    def test_low_audit_rejects_smaller_window(self):
        with self.assertRaises(s.Stop):
            s.audit_low(supplied())


class ReplayTests(unittest.TestCase):
    def run_trace(self, triple=(0, None, None), **kwargs):
        return s.trace(supplied({c(): triple}), 1, c(), **kwargs)

    def test_land_zero(self):
        t = self.run_trace()
        self.assertEqual((t.route_status, t.terminal_cell, t.route_steps), ("D8_ZERO_INTERIOR", c(), 0))
        self.assertIsNone(t.terminal_water_class)
        self.assertIsNone(t.terminal_lake_objectid)

    def test_null_pointer_is_not_zero(self):
        t = self.run_trace((None, None, None))
        self.assertEqual(t.route_status, "D8_POINTER_NA")
        self.assertEqual(t.cells[0].pointer, s.Missing.NULL)

    def test_nan_pointer_is_not_zero(self):
        t = self.run_trace((float("nan"), None, None))
        self.assertEqual(t.route_status, "D8_POINTER_NA")
        self.assertEqual(t.cells[0].pointer, s.Missing.NAN)
        self.assertNotIn('NaN', s.canonical_json(t))

    def test_nan_water_class_matches_explicit_missing_land_semantics(self):
        self.assertEqual(self.run_trace((0, float("nan"), None)).route_status, "D8_ZERO_INTERIOR")

    def test_invalid_finite_pointer_codes(self):
        for value in (3, -1, 256, 2.5):
            with self.subTest(value=value):
                self.assertEqual(self.run_trace((value, None, None)).route_status, "D8_POINTER_INVALID")

    def test_exact_integer_float_pointer_is_supported(self):
        self.assertEqual(self.run_trace((2.0, None, None)).route_steps, 1)

    def test_invalid_water_class_precedes_pointer(self):
        t = self.run_trace((0, 4, None))
        self.assertEqual(t.route_status, "INVALID_WATER_CLASS")
        self.assertIsNone(t.terminal_water_class)
        self.assertIsNone(t.terminal_lake_objectid)

    def test_zero_water_class_is_invalid_not_land(self):
        self.assertEqual(self.run_trace((0, 0, None)).route_status, "INVALID_WATER_CLASS")

    def test_water_precedes_every_pointer_condition(self):
        for ptr in (0, None, float("nan"), 3, 128):
            with self.subTest(pointer=ptr):
                t = self.run_trace((ptr, 1, 1892))
                self.assertEqual((t.route_status, t.route_steps), ("REACHES_OTHER_LAKE", 0))
                self.assertEqual(t.steps, ())

    def test_return_to_origin_lake(self):
        self.assertEqual(self.run_trace((0, 1, 1894)).route_status, "RETURNS_TO_ORIGIN_LAKE")

    def test_other_lake_preserves_id(self):
        t = self.run_trace((0, 1, 1892.0))
        self.assertEqual((t.route_status, t.terminal_water_class, t.terminal_lake_objectid),
                         ("REACHES_OTHER_LAKE", 1, 1892))

    def test_missing_lake_id(self):
        for missing in (None, float("nan")):
            with self.subTest(missing=missing):
                self.assertEqual(self.run_trace((0, 1, missing)).route_status, "LAKE_ID_MISSING")

    def test_river_area_does_not_invent_receiver_id(self):
        t = self.run_trace((3, 2, 999))
        self.assertEqual(t.route_status, "REACHES_RIVER_AREA")
        self.assertIsNone(t.terminal_lake_objectid)
        self.assertEqual(t.cells[0].lake_id, 999)  # original value retained separately

    def test_river_line_does_not_invent_receiver_id(self):
        t = self.run_trace((None, 3, None))
        self.assertEqual(t.route_status, "REACHES_RIVER_LINE")
        self.assertIsNone(t.terminal_lake_objectid)

    def test_terminal_water_is_inspected_after_move(self):
        dest = c(102, 103)
        data = supplied({c(): (2, None, None), dest: (128, 1, 1892)})
        t = s.trace(data, 1, c())
        self.assertEqual((t.route_steps, t.terminal_cell, len(t.cells)), (1, dest, 2))
        self.assertEqual(t.route_status, "REACHES_OTHER_LAKE")

    def test_water_outgoing_pointer_invariant(self):
        dest = c(102, 103)
        results = []
        for ptr in (0, 32, None, 3):
            results.append(s.trace(supplied({c(): (2, None, None), dest: (ptr, 2, None)}), 1, c()).summary())
        self.assertEqual(results, [results[0]] * 4)

    def test_cycle_closing_attempt_does_not_increment(self):
        dest = c(102, 103)
        t = s.trace(supplied({c(): (2,None,None), dest: (32,None,None)}), 1, c())
        self.assertEqual((t.route_status, t.route_steps, t.terminal_cell), ("D8_CYCLE", 1, c()))
        self.assertEqual(t.entered_cells, (c(), dest))
        self.assertEqual(t.steps[-1].outcome, "CYCLE")
        self.assertEqual(t.steps[-1].target_cell, c())

    def test_global_edge_zero_all_four_edges(self):
        for row, col in ((0,2), (5999,2), (2,0), (2,5999)):
            w = s.Window(min(max(0,col-1),5997), min(max(0,row-1),5997), 3, 3)
            self.assertTrue(w.contains(row,col))
            with self.subTest(row=row,col=col):
                t = s.trace(supplied(window=w), 1, c(row,col))
                self.assertEqual(t.route_status, "D8_ZERO_AT_RASTER_EDGE")

    def test_window_edge_zero_is_not_global_edge(self):
        t = s.trace(supplied(), 1, c(100,100))
        self.assertEqual(t.route_status, "D8_ZERO_INTERIOR")

    def test_domain_exit_is_not_a_counted_transition(self):
        first = c(0, 2)
        t = s.trace(supplied({first:(128,None,None)}, s.Window(0,0,5,5)), 1, first)
        self.assertEqual((t.route_status,t.route_steps,t.terminal_cell), ("D8_DOMAIN_EXIT",0,first))
        self.assertIsNone(t.steps[0].target_cell)
        self.assertEqual(t.steps[0].target_row0, -1)

    def test_outside_window_stops_without_expanding(self):
        start = c(100, 100)
        t = s.trace(supplied({start:(32,None,None)}), 1, start)
        self.assertEqual(t.stop_reason, "OUTSIDE_BOUNDED_WINDOW")
        self.assertIsNone(t.route_status)
        self.assertEqual((t.route_steps,t.terminal_cell), (0,start))
        self.assertEqual(len(t.cells), 1)
        with self.assertRaises(s.Stop):
            t.summary()

    def test_start_outside_window_stops_before_sample(self):
        data = supplied()
        with patch.object(s.WindowData, "sample", side_effect=AssertionError("must not sample")):
            t = s.trace(data, 1, c(99, 100))
        self.assertEqual(t.stop_reason, "OUTSIDE_BOUNDED_WINDOW")
        self.assertEqual(t.cells, ())

    def test_step_limit_tail_is_entered_but_uninspected(self):
        dest = c(102, 103)
        t = s.trace(supplied({c():(2,None,None),dest:(0,1,1892)}), 1, c(), max_inspections=1)
        self.assertEqual((t.route_status,t.route_steps,t.terminal_cell), ("STEP_LIMIT",1,dest))
        self.assertEqual(tuple(v.cell_id for v in t.cells), (c(),))
        self.assertIsNone(t.terminal_water_class)
        self.assertIsNone(t.terminal_lake_objectid)

    def test_transition_budget_stop_is_not_fake_step_limit(self):
        t = self.run_trace((2,None,None), max_transitions=0)
        self.assertEqual(t.stop_reason, "TRANSITION_BUDGET_EXCEEDED")
        self.assertIsNone(t.route_status)
        self.assertEqual(t.route_steps, 0)

    def test_no_unbounded_iteration_or_transition_options(self):
        for kwargs in (dict(max_inspections=26),dict(max_inspections=0),dict(max_transitions=25),
                       dict(max_transitions=-1),dict(max_inspections=True)):
            with self.subTest(kwargs=kwargs), self.assertRaises(s.Stop):
                self.run_trace(**kwargs)

    def test_invalid_start_or_origin_fails(self):
        for kwargs in (dict(route_id=0,start_receiver_cell=c()),
                       dict(route_id=1,start_receiver_cell=36000001),
                       dict(route_id=1,start_receiver_cell=c(),origin_lake_objectid=True)):
            with self.subTest(kwargs=kwargs), self.assertRaises(s.Stop):
                s.trace(supplied(), **kwargs)


class SixRouteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data, cls.neighbors = six_fixture(with_neighbors=True)
        cls.audit = s.audit_low(cls.data, neighbors_02c=cls.neighbors)

    def test_all_six_summaries_match_without_renumbering(self):
        self.assertEqual(tuple(t.summary() for t in self.audit.traces), s.LOCKED_SUMMARIES)
        self.assertEqual(tuple(t.route_id for t in self.audit.traces), (11,14,15,16,18,20))
        self.assertEqual(self.audit.diagnostic_result, "PASS")
        self.assertTrue(all(not v.mismatched_fields for v in self.audit.comparisons))

    def test_independent_literal_chain_oracle(self):
        # Each prefix is specified independently, followed by a northward spine.
        spine = tuple(s.cell_id(row,3318) for row in range(3888,3867,-1))
        prefixes = ((23337318,), (23343318,23337318), (23343319,23337318),
                    (23343320,23343319,23337318), (23349320,23343319,23337318),
                    (23355321,23349320,23343319,23337318))
        for t, prefix in zip(self.audit.traces,prefixes):
            with self.subTest(route_id=t.route_id):
                self.assertEqual(t.entered_cells, prefix+spine)
                self.assertEqual(tuple(item.cell_id for item in t.cells), prefix+spine)
                self.assertEqual(len(t.steps), t.route_steps)
                self.assertEqual(len(t.cells), t.route_steps+1)

    def test_every_step_has_exact_global_geometry_and_raw_values(self):
        for t in self.audit.traces:
            for item in t.cells:
                with self.subTest(route=t.route_id,cell=item.cell_id):
                    self.assertEqual(item.cell_id, item.row0*6000+item.col0+1)
                    self.assertEqual((item.x,item.y), (199001+2*item.col0,6910999-2*item.row0))
                    self.assertEqual(item, self.data.sample(item.cell_id))
            for step, a, b in zip(t.steps,t.cells,t.cells[1:]):
                self.assertEqual((step.source_cell,step.target_cell), (a.cell_id,b.cell_id))
                self.assertEqual(step.pointer,a.pointer)
                self.assertEqual(step.outcome,"ADVANCED")

    def test_24_moves_require_25th_inspection_for_terminal(self):
        t = s.trace(self.data,20,23355321,max_inspections=24)
        self.assertEqual((t.route_steps,t.terminal_cell,t.route_status), (24,s.TERMINAL,"STEP_LIMIT"))
        self.assertNotIn(s.TERMINAL,tuple(v.cell_id for v in t.cells))
        self.assertEqual(self.audit.traces[-1].route_status,"D8_ZERO_INTERIOR")
        self.assertEqual(len(self.audit.traces[-1].cells),25)

    def test_aggregation_preserves_six_paths_and_shared_terminal(self):
        group = next(g for g in self.audit.aggregation.terminal_groups if g.cell_id==s.TERMINAL)
        self.assertEqual(len(group.route_outcomes),6)
        shared = next(g for g in self.audit.aggregation.shared_cells if g.cell_id==s.TERMINAL)
        self.assertEqual(shared.entered_route_ids,(11,14,15,16,18,20))
        self.assertEqual(shared.inspected_route_ids,shared.entered_route_ids)
        self.assertIsNone(self.audit.aggregation.independent_channel_count)

    def test_first_shared_cells_and_common_downstream_chain(self):
        pair = next(p for p in self.audit.aggregation.pairs if p.route_ids==(16,20))
        self.assertEqual(pair.first_shared_cell,23343319)
        self.assertEqual(pair.shared_observed_chain,self.audit.traces[2].entered_cells)
        self.assertEqual(pair.interpretation,"SHARED_OBSERVED_CELLS_ONLY")

    def test_censored_tail_not_extended_from_completed_route(self):
        a = s.trace(self.data,11,23337318,max_inspections=1)
        b = s.trace(self.data,14,23343318)
        grouped = s.aggregate((a,b))
        self.assertEqual(a.route_status,"STEP_LIMIT")
        self.assertEqual(len(a.entered_cells),2)
        self.assertEqual(grouped.pairs[0].shared_observed_chain,a.entered_cells)
        tail = next(g for g in grouped.shared_cells if g.cell_id==a.terminal_cell)
        self.assertEqual(tail.inspected_route_ids,(14,))
        self.assertNotEqual(a.terminal_cell,b.terminal_cell)

    def test_same_terminal_with_different_observation_status_not_collapsed(self):
        a = s.trace(self.data,11,23337318,max_inspections=21)
        b = s.trace(self.data,14,23343318)
        grouped = s.aggregate((a,b))
        self.assertEqual(grouped.terminal_groups[0].route_outcomes,
                         ((11,"STEP_LIMIT",None),(14,"D8_ZERO_INTERIOR",None)))

    def test_neighbor_parity_and_zero_terminal_do_not_authorize_water_jump(self):
        self.assertEqual(dict(self.audit.stages)["WATER_NEIGHBOR_PARITY"],"PASS")
        for t in self.audit.traces:
            self.assertEqual(t.route_status,"D8_ZERO_INTERIOR")
            self.assertIsNone(t.terminal_water_class)
            self.assertIsNone(t.terminal_lake_objectid)
            self.assertFalse(any(n.water_cell in t.entered_cells for n in self.neighbors))

    def test_neighbor_comparison_is_optional_and_not_run_without_rows(self):
        self.assertEqual(dict(s.audit_low(self.data).stages)["WATER_NEIGHBOR_PARITY"],"NOT_RUN")

    def test_contradictory_neighbor_evidence_fails_closed(self):
        pointer, water, lake = map(lambda a:[list(r) for r in a],
                                   (self.data.pointer,self.data.water_class,self.data.lake_id))
        r,col=s.row_col(self.neighbors[0].water_cell)
        lake[r-3844][col-3293]=999
        changed=s.WindowData(s.Grid(),s.Window(),provenance(),pointer,water,lake)
        result=s.audit_low(changed,neighbors_02c=self.neighbors)
        self.assertEqual(result.diagnostic_result,"FAIL")
        self.assertEqual(result.S2_RESULT,"REVIEW_REQUIRED/FAIL_CLOSED")
        self.assertEqual(dict(result.stages)["WATER_NEIGHBOR_PARITY"],"STOP")

    def test_wrong_02c_component_source_lake_and_duplicates_stop(self):
        for bad in ((self.neighbors[0],)*3,
                    (replace(self.neighbors[0],component_id=275),)+self.neighbors[1:],
                    (replace(self.neighbors[0],lake_id=1894),)+self.neighbors[1:],
                    self.neighbors[:2]):
            with self.subTest(bad=bad),self.assertRaises(s.Stop):
                s.audit_low(self.data,neighbors_02c=bad)

    def test_nonadjacent_neighbor_is_rejected(self):
        with self.assertRaises(s.Stop):
            replace(self.neighbors[0],water_cell=s.cell_id(3850,3300))

    def test_one_changed_pointer_reports_parity_disagreements(self):
        pointer=[list(r) for r in self.data.pointer]
        row,col=s.row_col(23343318)
        pointer[row-3844][col-3293]=0
        changed=s.WindowData(s.Grid(),s.Window(),provenance(),pointer,self.data.water_class,self.data.lake_id)
        result=s.audit_low(changed)
        self.assertEqual(result.diagnostic_result,"FAIL")
        mismatch=next(v for v in result.comparisons if v.route_id==14)
        self.assertEqual(set(mismatch.mismatched_fields),{"terminal_cell","route_steps"})
        self.assertEqual(sum(bool(v.mismatched_fields) for v in result.comparisons),1)
        self.assertEqual(result.comparisons[1].expected,s.LOCKED_SUMMARIES[1])

    def test_audit_preserves_transition_budget_stop_as_failed_comparison(self):
        pointer=[list(r) for r in self.data.pointer]
        row,col=s.row_col(s.TERMINAL)
        pointer[row-3844][col-3293]=128
        result=s.audit_low(s.WindowData(s.Grid(),s.Window(),provenance(),pointer,
                                       self.data.water_class,self.data.lake_id))
        self.assertEqual(result.diagnostic_result,"FAIL")
        self.assertEqual(result.S2_RESULT,"REVIEW_REQUIRED/FAIL_CLOSED")
        self.assertEqual(dict(result.stages)["RESOURCE_BOUND"],"STOP")
        self.assertEqual(result.comparisons[-1].stop_reason,"TRANSITION_BUDGET_EXCEEDED")
        self.assertIsNone(result.comparisons[-1].recovered)
        self.assertEqual(result.traces[-1].route_steps,24)
        self.assertEqual(result.comparisons[-1].expected,s.LOCKED_SUMMARIES[-1])

    def test_audit_preserves_cycle_and_all_six_identities(self):
        pointer=[list(r) for r in self.data.pointer]
        row,col=s.row_col(s.TERMINAL)
        pointer[row-3844][col-3293]=8
        result=s.audit_low(s.WindowData(s.Grid(),s.Window(),provenance(),pointer,
                                       self.data.water_class,self.data.lake_id))
        self.assertEqual(result.diagnostic_result,"FAIL")
        self.assertTrue(all(t.route_status=="D8_CYCLE" for t in result.traces))
        self.assertEqual(tuple(t.route_id for t in result.traces),(11,14,15,16,18,20))
        self.assertTrue(all("route_status" in v.mismatched_fields for v in result.comparisons))

    def test_unsupported_lake_connection_is_not_accepted_as_original_summary(self):
        water=[list(r) for r in self.data.water_class]
        lakes=[list(r) for r in self.data.lake_id]
        row,col=s.row_col(s.TERMINAL)
        water[row-3844][col-3293]=1
        lakes[row-3844][col-3293]=1892
        result=s.audit_low(s.WindowData(s.Grid(),s.Window(),provenance(),self.data.pointer,water,lakes))
        self.assertEqual(result.diagnostic_result,"FAIL")
        self.assertTrue(all(set(v.mismatched_fields)=={"route_status","terminal_water_class","terminal_lake_objectid"}
                            for v in result.comparisons))
        self.assertFalse(result.routing_authorized)

    def test_changed_original_route_steps_stop(self):
        rows=(replace(s.LOCKED_SUMMARIES[0],route_steps=20),)+s.LOCKED_SUMMARIES[1:]
        with self.assertRaises(s.Stop):
            s.audit_low(self.data,rows)

    def test_changed_original_receiver_stop(self):
        rows=(replace(s.LOCKED_SUMMARIES[0],start_receiver_cell=23337319),)+s.LOCKED_SUMMARIES[1:]
        with self.assertRaises(s.Stop):
            s.audit_low(self.data,rows)

    def test_changed_original_origin_terminal_or_water_identity_stop(self):
        for fields in (dict(origin_lake_objectid=1892),dict(terminal_cell=s.TERMINAL+1),
                       dict(terminal_water_class=1),dict(terminal_lake_objectid=1892)):
            rows=(replace(s.LOCKED_SUMMARIES[0],**fields),)+s.LOCKED_SUMMARIES[1:]
            with self.subTest(fields=fields),self.assertRaises(s.Stop):
                s.audit_low(self.data,rows)

    def test_duplicate_or_conflicting_route_ids_stop(self):
        for rows in ((s.LOCKED_SUMMARIES[0],)*6,
                     (replace(s.LOCKED_SUMMARIES[0],route_id=14),)+s.LOCKED_SUMMARIES[1:]):
            with self.subTest(rows=rows),self.assertRaises(s.Stop):
                s.audit_low(self.data,rows)

    def test_missing_or_extra_route_stop(self):
        for rows in (s.LOCKED_SUMMARIES[:5],s.LOCKED_SUMMARIES+(s.LOCKED_SUMMARIES[0],)):
            with self.subTest(n=len(rows)),self.assertRaises(s.Stop):
                s.audit_low(self.data,rows)

    def test_changed_declared_csv_version_stop(self):
        changed=replace(self.data,provenance=provenance(summary_sha256="b"*64))
        with self.assertRaises(s.Stop):
            s.audit_low(changed)

    def test_reordered_inputs_return_same_canonical_result(self):
        result=s.audit_low(self.data,tuple(reversed(s.LOCKED_SUMMARIES)),tuple(reversed(self.neighbors)))
        self.assertEqual(result,self.audit)
        self.assertEqual(s.canonical_json(result),s.canonical_json(self.audit))

    def test_resource_bound_is_explicit_and_finite(self):
        self.assertEqual(len(self.data.pointer)*len(self.data.pointer[0])*3,11388)
        self.assertLessEqual(sum(len(t.cells) for t in self.audit.traces),150)
        self.assertTrue(all(t.route_steps<=24 for t in self.audit.traces))
        self.assertEqual(dict(self.audit.stages)["RESOURCE_BOUND"],"PASS")


class AggregationTests(unittest.TestCase):
    def test_diagonal_geometric_crossing_is_not_cell_confluence(self):
        # Two X-shaped diagonal edges do not share a raster cell.
        a,b=c(102,102),c(102,103)
        data=supplied({a:(4,None,None),b:(16,None,None)})
        result=s.aggregate((s.trace(data,1,a),s.trace(data,2,b)))
        self.assertEqual(result.shared_cells,())
        self.assertIsNone(result.pairs[0].first_shared_cell)
        self.assertEqual(result.pairs[0].interpretation,"NO_SHARED_CELL")

    def test_two_incoming_paths_converge_into_same_cell(self):
        a,b,target=c(102,102),c(103,102),c(102,103)
        data=supplied({a:(2,None,None),b:(1,None,None)})
        result=s.aggregate((s.trace(data,1,a),s.trace(data,2,b)))
        self.assertEqual(result.pairs[0].first_shared_cell,target)
        self.assertEqual(result.pairs[0].shared_observed_chain,(target,))

    def test_cyclic_shared_paths_are_explicitly_ambiguous(self):
        a,b=c(),c(102,103)
        data=supplied({a:(2,None,None),b:(32,None,None)})
        result=s.aggregate((s.trace(data,1,a),s.trace(data,2,b)))
        self.assertEqual(result.pairs[0].interpretation,"CYCLIC_OR_AMBIGUOUS")
        self.assertIsNone(result.pairs[0].first_shared_cell)

    def test_duplicate_trace_is_not_independent_evidence(self):
        t=s.trace(supplied(),1,c())
        with self.assertRaises(s.Stop):
            s.aggregate((t,t))

    def test_mixed_source_provenance_stops(self):
        a=s.trace(supplied(),1,c())
        b=s.trace(supplied(prov=provenance(evidence_version="v2")),2,c())
        with self.assertRaises(s.Stop):
            s.aggregate((a,b))

    def test_contradictory_shared_values_stop_even_if_digest_claim_is_copied(self):
        data=supplied()
        a=s.trace(data,1,c())
        b=s.trace(data,2,c())
        forged=replace(b,cells=(replace(b.cells[0],pointer=3),))
        with self.assertRaises(s.Stop):
            s.aggregate((a,forged))

    def test_empty_or_oversized_aggregation_stops(self):
        t=s.trace(supplied(),1,c())
        for rows in ((),(t,)*7):
            with self.subTest(n=len(rows)),self.assertRaises(s.Stop):
                s.aggregate(rows)


class InputAndSafetyTests(unittest.TestCase):
    def test_arrays_are_detached_from_mutable_input(self):
        window=s.Window(100,100,2,2)
        values=arrays(window)
        data=s.WindowData(s.Grid(),window,provenance(),*values)
        before=data.content_sha256
        values[0][0][0]=3
        values[1].append([1,1])
        self.assertEqual(data.pointer[0][0],0)
        self.assertEqual(data.content_sha256,before)
        self.assertIsInstance(data.pointer,tuple)

    def test_wrong_array_shapes_stop(self):
        w=s.Window(100,100,2,2)
        for bad in ([],[[0]],[[0,0],[0]],[[0,0],[0,0],[0,0]],"00"):
            with self.subTest(bad=bad),self.assertRaises(s.Stop):
                s.WindowData(s.Grid(),w,provenance(),bad,[[None]*2]*2,[[None]*2]*2)

    def test_no_implicit_numeric_nodata_sentinel(self):
        with self.assertRaises(s.Stop):
            provenance(nodata_policy="NEGATIVE_9999")
        t=s.trace(supplied({c():(-9999,None,None)}),1,c())
        self.assertEqual(t.route_status,"D8_POINTER_INVALID")

    def test_nonfinite_boolean_and_string_inputs_stop(self):
        for v in (float("inf"),float("-inf"),True,"2",{},10**1000):
            with self.subTest(value_type=type(v)),self.assertRaises(s.Stop):
                supplied({c():(v,None,None)})

    def test_fractional_or_nonpositive_lake_ids_are_not_truncated(self):
        for v in (1892.5,0,-1,2147483648):
            with self.subTest(value=v),self.assertRaises(s.Stop):
                supplied({c():(0,1,v)})

    def test_nonfinite_water_class_and_lake_values_stop(self):
        for triple in ((0,float("inf"),None),(0,1,float("inf"))):
            with self.subTest(triple=triple),self.assertRaises(s.Stop):
                supplied({c():triple})

    def test_provenance_is_required_and_strict(self):
        for changes in (dict(producer_commit="bad"),dict(summary_sha256="g"*64),
                        dict(summary_sha256="a"*63),dict(pointer_id=""),
                        dict(pointer_id="same",water_class_id="same"),
                        dict(data_kind="AUTHENTICATED_CSC")):
            with self.subTest(changes=changes),self.assertRaises(s.Stop):
                provenance(**changes)

    def test_cannot_claim_verified_source_via_input(self):
        with self.assertRaises(TypeError):
            provenance(source_identity_verified=True)
        self.assertFalse(provenance().source_identity_verified)

    def test_metadata_and_value_changes_have_distinct_fingerprints(self):
        a=supplied()
        self.assertNotEqual(a.content_sha256,supplied({c():(3,None,None)}).content_sha256)
        self.assertNotEqual(a.content_sha256,supplied(prov=provenance(pointer_id="v2")).content_sha256)
        self.assertEqual(a.content_sha256,supplied().content_sha256)

    def test_null_and_nan_are_distinct_immutable_provenance_markers(self):
        a=supplied({c():(None,None,None)})
        b=supplied({c():(float("nan"),None,None)})
        self.assertNotEqual(a.content_sha256,b.content_sha256)
        self.assertEqual(s.trace(a,1,c()).route_status,s.trace(b,1,c()).route_status)

    def test_records_and_outputs_are_frozen(self):
        data,_=six_fixture()
        result=s.audit_low(data)
        for record,name,value in ((data,"pointer",()),(result,"diagnostic_result","VALIDATED"),
                                  (result.traces[0],"terminal_cell",1),
                                  (result.traces[0].cells[0],"pointer",0),
                                  (result.aggregation,"shared_cells",())):
            with self.subTest(record=type(record)),self.assertRaises(FrozenInstanceError):
                setattr(record,name,value)
        with self.assertRaises(TypeError):
            data.pointer[0][0]=3

    def test_all_returned_scientific_locks_are_preserved(self):
        data,_=six_fixture()
        result=s.audit_low(data)
        for record in (result,result.aggregation)+result.traces:
            self.assertIs(record.routing_authorized,False)
            self.assertEqual(record.outlet_selection,"UNASSIGNED")
            self.assertEqual(record.NATIONAL,"LOCKED")
            self.assertEqual(record.MODERATE,"REVIEW_REQUIRED")
            self.assertEqual(record.hydrological_validation,"NOT_ASSESSED")
            self.assertEqual(record.channel_interpretation,"NOT_ASSESSED")

    def test_authorization_cannot_be_set_in_public_api(self):
        data,_=six_fixture()
        result=s.audit_low(data)
        for record in (result,result.traces[0],result.aggregation):
            with self.subTest(record=type(record)),self.assertRaises(ValueError):
                replace(record,routing_authorized=True)
        with self.assertRaises(TypeError):
            s.audit_low(data,approved=True)

    def test_validated_and_unknown_routing_claims_are_rejected(self):
        data,_=six_fixture()
        result=s.audit_low(data)
        for status in ("VALIDATED","AUTHORIZED","OUTLET_SELECTED"):
            with self.subTest(status=status):
                with self.assertRaises(s.Stop):
                    replace(s.LOCKED_SUMMARIES[0],route_status=status)
                with self.assertRaises(s.Stop):
                    replace(result.traces[0],route_status=status)
                with self.assertRaises(s.Stop):
                    replace(result,diagnostic_result=status)

    def test_no_external_io_or_stdout_from_core(self):
        data,neighbors=six_fixture(with_neighbors=True)
        captured=io.StringIO()
        # Import is complete before denying I/O. The exercised core only sees arrays.
        with patch("builtins.open",side_effect=AssertionError("file I/O")), \
             patch("os.open",side_effect=AssertionError("OS I/O")), \
             patch("socket.socket",side_effect=AssertionError("network I/O")), \
             patch("subprocess.Popen",side_effect=AssertionError("process I/O")), \
             redirect_stdout(captured):
            result=s.audit_low(data,neighbors_02c=neighbors)
            payload=s.canonical_json(result)
        self.assertEqual(captured.getvalue(),"")
        self.assertEqual(json.loads(payload)["diagnostic_result"],"PASS")

    def test_diagnostic_pass_is_not_actual_s2_or_source_approval(self):
        data,_=six_fixture()
        result=s.audit_low(data)
        self.assertEqual(result.diagnostic_result,"PASS")
        self.assertEqual(result.S2_RESULT,"NOT_ASSESSED")
        self.assertEqual(result.real_raster_parity,"NOT_ASSESSED")
        self.assertEqual(result.source_authentication,"NOT_ASSESSED")
        self.assertEqual(dict(result.stages)["SOURCE_PROVENANCE"],"NOT_RUN")
        self.assertEqual(dict(result.stages)["GEO_REFERENCE"],"NOT_RUN")
        self.assertFalse(result.provenance.source_identity_verified)

    def test_input_is_not_mutated(self):
        data,neighbors=six_fixture(with_neighbors=True)
        before=deepcopy(data)
        s.audit_low(data,neighbors_02c=neighbors)
        self.assertEqual(data,before)
        self.assertEqual(s.LOCKED_SUMMARIES[0].route_steps,21)

    def test_unknown_report_objects_fail_closed(self):
        with self.assertRaises(s.Stop):
            s.canonical_json({"routing_authorized":True})


class ROracleTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get("MM_S2A_RSCRIPT"), "optional R 02F oracle: set MM_S2A_RSCRIPT")
    def test_original_r02f_matches_pure_python_on_synthetic_inputs(self):
        # Optional local cross-language check. Only synthetic vectors are sent to R
        # stdin. No 36-million-cell vector, raster file, terra or Whitebox is used.
        data,_=six_fixture()
        cases=[("six-25",data,s.LOCKED_SUMMARIES,25),("six-24",data,s.LOCKED_SUMMARIES,24)]
        triples=((0,None,None),(None,None,None),(float("nan"),None,None),
                 (3,None,None),(0,4,None),(0,1,None),(0,1,1894),
                 (0,1,1892),(None,2,999),(3,3,None),(0,float("nan"),None))
        for i,triple in enumerate(triples):
            cases.append((f"terminal-{i}",supplied({c():triple}),((1,c(),1894),),25))
        a,b=c(),c(102,103)
        cycle=supplied({a:(2,None,None),b:(32,None,None)})
        cases.extend((("cycle",cycle,((1,a,1894),),25),
                      ("censored",cycle,((1,a,1894),),1),
                      ("domain",supplied({c(0,2):(128,None,None)},s.Window(0,0,5,5)),((1,c(0,2),1894),),25)))
        for row,col in ((0,2),(5999,2),(2,0),(2,5999)):
            w=s.Window(min(max(0,col-1),5997),min(max(0,row-1),5997),3,3)
            cases.append((f"edge-{row}-{col}",supplied(window=w),((1,c(row,col),1894),),25))

        def rvector(values):
            return "c("+",".join("NA_real_" if s.absent(v) else str(v) for v in values)+")"

        commands=['source("R/02F_water_connected_route_diagnostics.R")',"out <- list()"]
        expected={}
        for label,window,records,limit in cases:
            starts=tuple((r.route_id,r.start_receiver_cell,r.origin_lake_objectid)
                         if type(r) is s.Summary else r for r in records)
            keys=tuple(s.cell_id(row,col) for row in range(window.window.yoff,window.window.yoff+window.window.height)
                       for col in range(window.window.xoff,window.window.xoff+window.window.width))
            commands.append("keys <- "+rvector(keys))
            for name in ("pointer","water_class","lake_id"):
                commands.append(name+" <- "+rvector(tuple(v for row in getattr(window,name) for v in row)))
            commands.append("edges <- data.frame(spill_group_id="+rvector(tuple(r[0] for r in starts))+
                            ", lake_objectid="+rvector(tuple(r[2] for r in starts))+
                            ", source_cell="+rvector(tuple(r[1] for r in starts))+
                            ", receiver_cell="+rvector(tuple(r[1] for r in starts))+")")
            commands.append("values <- function(x,cells) { ix <- match(cells,keys); "
                            "if(anyNA(ix)) stop('synthetic oracle escaped supplied window'); x[ix] }")
            commands.append("res <- trace_water_connected_candidate_routes(edges,pointer,water_class,"
                            f"lake_id,6000L,6000L,values,{limit}L)$routes")
            commands.append(f"out[[length(out)+1L]] <- data.frame(case='{label}',res)")
            for rid,start,origin in starts:
                t=s.trace(window,rid,start,origin,max_inspections=limit)
                expected[(label,start,origin)]=(t.terminal_cell,t.route_steps,t.route_status,
                                               t.terminal_water_class,t.terminal_lake_objectid)
        commands.append('write.csv(do.call(rbind,out),stdout(),row.names=FALSE,na="")')
        run=subprocess.run([os.environ["MM_S2A_RSCRIPT"],"--vanilla","-"],
                           input="\n".join(commands),text=True,capture_output=True,timeout=30)
        self.assertEqual(run.returncode,0,run.stderr)
        recovered={}
        for row in csv.DictReader(io.StringIO(run.stdout)):
            key=(row["case"],int(row["start_receiver_cell"]),int(row["origin_lake_objectid"]))
            self.assertNotIn(key,recovered)
            recovered[key]=(int(row["terminal_cell"]),int(row["route_steps"]),row["route_status"],
                            int(row["terminal_water_class"]) if row["terminal_water_class"] else None,
                            int(row["terminal_lake_objectid"]) if row["terminal_lake_objectid"] else None)
        self.assertEqual(len(expected),30)
        self.assertEqual(recovered,expected)


if __name__ == "__main__":
    unittest.main()
