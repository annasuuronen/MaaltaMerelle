"""New cross-contract scope checks only; no accepted test modules imported."""
from dataclasses import FrozenInstanceError, replace
from fractions import Fraction
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"water_connected_graph_design"))
from tile_accumulation_contract_v1 import (
    Fixture, FlowArc, OwnedNode, Tile, Transfer, Upstream,
)
from bridge_scope import LocalCount, Reference, compare_declared_reference


def common_prefix():
    # New explicit abstract graph, not a real D8 map or full 02G cell census.
    # Hand source memberships: a={1}, b={2}, c={1,2,3}, end={1,2,3}.
    fixture = Fixture(
        (Tile("A", (1, 2)), Tile("B", (3,))),
        (OwnedNode("a", "LAND", "A", (1,)), OwnedNode("b", "LAND", "A", (2,)),
         OwnedNode("c", "LAND", "B", (3,)),
         OwnedNode("end", "BOUNDARY", "B", terminal_role="TILE_BOUNDARY")),
        (FlowArc("a", "c", "LAND_D8"), FlowArc("b", "c", "LAND_D8"),
         FlowArc("c", "end", "BOUNDARY_EXIT")),
        (Transfer("ac", "A", "B", "a", "c", 1, 3),
         Transfer("bc", "A", "B", "b", "c", 2, 3)))
    reference = Reference((1, 2, 3), tuple(LocalCount(k, n) for k, n in
                                          (("a", 1), ("b", 1), ("c", 3), ("end", 3))))
    return fixture, reference


class ScopeTests(unittest.TestCase):
    def check_stop(self, fixture, reference, reason):
        out = compare_declared_reference(fixture, reference)
        self.assertEqual((out.status, out.reason), ("STOP", reason))
        self.assertEqual(out.local_areas_m2, ())
        self.assertIsNone(out.total_upstream_count)
        return out

    def test_hand_source_memberships_match_4m2_local_count(self):
        f, r = common_prefix();out = compare_declared_reference(f, r)
        # The expectation is explicitly enumerated source identities, not G5A.
        sources = {"a": {1}, "b": {2}, "c": {1, 2, 3}, "end": {1, 2, 3}}
        self.assertEqual(dict(out.local_areas_m2), {k: Fraction(4*len(v)) for k, v in sources.items()})
        self.assertEqual(out.status, "LOCAL_COMPATIBLE_EXTERNAL_UNKNOWN")

    def test_mathematical_local_match_never_supplies_global_total(self):
        f, r = common_prefix();out = compare_declared_reference(f, r)
        self.assertEqual(out.external_import, "UNKNOWN")
        self.assertIsNone(out.total_upstream_count)
        self.assertIsNone(out.total_upstream_area_m2)
        self.assertEqual(out.actual_02g_invocation, "NOT_RUN")

    def test_even_g5a_closed_synthetic_PASS_cannot_close_02g_imports(self):
        f, r = common_prefix()
        nodes=f.nodes[:-1]+(replace(f.nodes[-1], terminal_role="SYNTHETIC_TERMINAL"),)
        out=compare_declared_reference(replace(f,nodes=nodes),r)
        self.assertEqual(out.underlying_g5a_status,"PASS")
        self.assertEqual(out.status,"LOCAL_COMPATIBLE_EXTERNAL_UNKNOWN")
        self.assertIsNone(out.total_upstream_area_m2)

    def test_external_unknown_keeps_same_owned_lower_bound(self):
        f,r=common_prefix();out=compare_declared_reference(replace(f,upstream=(Upstream("a"),)),r)
        self.assertEqual(out.underlying_g5a_status,"UNKNOWN")
        self.assertEqual(dict(out.local_areas_m2)["end"],Fraction(12))
        self.assertIsNone(out.total_upstream_area_m2)

    def test_zero_external_claim_is_not_equivalent_to_UNKNOWN(self):
        f,r=common_prefix();self.check_stop(f,replace(r,external_import="ZERO"),"UNKNOWN_IMPORT_NOT_ZERO_OR_TOTAL")

    def test_global_total_claim_is_rejected_even_when_numerically_local(self):
        f,r=common_prefix();self.check_stop(f,replace(r,total_upstream_count=3),"UNKNOWN_IMPORT_NOT_ZERO_OR_TOTAL")

    def test_water_own_area_cannot_masquerade_as_02g_land_contribution(self):
        f,r=common_prefix()
        nodes=f.nodes[:2]+(replace(f.nodes[2],kind="LAKE"),f.nodes[3])
        arcs=f.arcs[:2]+(FlowArc("c","end","BOUNDARY_EXIT"),)
        self.check_stop(replace(f,nodes=nodes,arcs=arcs),r,"NONLAND_OWNERSHIP_OR_ROUTING_NEEDS_REVIEW")

    def test_fractional_lake_output_not_promoted_to_integer_source_count(self):
        f,r=common_prefix()
        # The accepted G5A semantics support fractions; common 02G scope does not.
        nodes=(replace(f.nodes[0],kind="LAKE"),)+f.nodes[1:]
        arcs=(FlowArc("a","b","LAKE_OUTLET",Fraction(1,2)),
              FlowArc("a","c","LAKE_OUTLET",Fraction(1,2)))+f.arcs[1:]
        self.check_stop(replace(f,nodes=nodes,arcs=arcs,split_mode=True),r,
                        "NONLAND_OWNERSHIP_OR_ROUTING_NEEDS_REVIEW")

    def test_local_reference_order_does_not_change_crosswalk(self):
        f,r=common_prefix();a=compare_declared_reference(f,r)
        b=compare_declared_reference(f,replace(r,source_cells=tuple(reversed(r.source_cells)),counts=tuple(reversed(r.counts))))
        self.assertEqual(a,b)

    def test_changed_local_count_cannot_be_hidden_by_total_conservation(self):
        f,r=common_prefix();counts=r.counts[:-1]+(LocalCount("end",2),)
        self.check_stop(f,replace(r,counts=counts),"LAND_COUNT_AREA_MISMATCH")

    def test_count_unit_collision_is_STOP(self):
        f,r=common_prefix()
        for unit in (Fraction(1),Fraction(40000),4,4.0):
            with self.subTest(unit=unit):self.check_stop(f,replace(r,count_unit_area_m2=unit),"EXACT_SOURCE_WEIGHT_4_REQUIRED")

    def test_bool_fractional_and_nonfinite_reference_counts_reject(self):
        f,r=common_prefix()
        for count in (True,1.5,float("nan"),float("inf"),-1,4):
            with self.subTest(count=count):self.check_stop(f,replace(r,counts=(LocalCount("end",count),)),"REFERENCE_COUNTS")

    def test_source_scope_AND_origin_cannot_claim_observed_R_output(self):
        f,r=common_prefix()
        self.check_stop(f,replace(r,source_scope="ALL_OWNED_CELLS"),"REFERENCE_OR_SCOPE")
        self.check_stop(f,replace(r,origin="OBSERVED_02G_RESULT"),"REFERENCE_OR_SCOPE")

    def test_reference_cannot_duplicate_owned_sources_or_add_water_sources(self):
        f,r=common_prefix()
        self.check_stop(f,replace(r,source_cells=(1,2,2)),"REFERENCE_SOURCES")
        self.check_stop(f,replace(r,source_cells=(1,2,3,4)),"SOURCE_POPULATION_MISMATCH")

    def test_local_count_reference_requires_unique_known_nonempty_nodes(self):
        f,r=common_prefix()
        self.check_stop(f,replace(r,counts=()),"REFERENCE_COUNTS")
        self.check_stop(f,replace(r,counts=(LocalCount("c",3),LocalCount("c",3))),"REFERENCE_COUNTS")
        self.check_stop(f,replace(r,counts=(LocalCount("invented_water",3),)),"REFERENCE_NODE_MISSING")

    def test_old27_11_contract_not_silently_enlarged(self):
        f,r=common_prefix()
        self.check_stop(f,replace(r,source_cells=tuple(range(1,13))),"REFERENCE_SOURCES")

    def test_mutable_reference_and_missing_fixture_do_not_export(self):
        f,r=common_prefix()
        self.check_stop(None,r,"REFERENCE_SCHEMA")
        self.check_stop(f,replace(r,counts=list(r.counts)),"REFERENCE_COUNTS")

    def test_receipt_is_immutable_and_never_authorizes(self):
        f,r=common_prefix();out=compare_declared_reference(f,r)
        with self.assertRaises(FrozenInstanceError):out.status="VALIDATED"
        self.assertEqual(out.NATIONAL,"LOCKED");self.assertEqual(out.MODERATE,"REVIEW_REQUIRED")
        self.assertFalse(out.routing_authorized)
        self.assertEqual(out.outlet_selection,"UNASSIGNED")
        self.assertEqual(out.hydrological_validation,"NOT_ASSESSED")
        self.assertEqual(out.channel_interpretation,"NOT_ASSESSED")
        self.assertEqual(out.HISTORIC_02F_EFFECTIVE_D8,"NOT_ASSESSED")
        self.assertEqual(out.reference_authentication,"NOT_ASSESSED")


if __name__ == "__main__":
    unittest.main()
