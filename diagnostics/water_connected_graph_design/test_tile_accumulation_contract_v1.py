"""Tiny in-memory G5A fixtures; no CSC, rasters, GIS or production calls."""
import ast
import random
import unittest
from dataclasses import FrozenInstanceError, replace
from fractions import Fraction as F
from pathlib import Path
from unittest.mock import patch

import tile_accumulation_contract_v1 as qa
from tile_accumulation_contract_v1 import (
    Fixture, FlowArc, Halo, OwnedNode, Status, Tile, Transfer, Upstream, reconcile,
)


def serial():
    return Fixture(
        tiles=(Tile("A", (1,)), Tile("B", (2,))),
        nodes=(OwnedNode("a", "LAND", "A", (1,)), OwnedNode("b", "LAND", "B", (2,)),
               OwnedNode("end", "BOUNDARY", "B", terminal_role="SYNTHETIC_TERMINAL")),
        arcs=(FlowArc("a", "b", "LAND_D8"), FlowArc("b", "end", "BOUNDARY_EXIT")),
        transfers=(Transfer("ab", "A", "B", "a", "b", 1, 2),))


def single():
    f = serial()
    return replace(f, tiles=(Tile("A", (1, 2)),),
                   nodes=tuple(replace(n, owner_tile="A") for n in f.nodes), transfers=())


def confluence():
    f = serial()
    return replace(f, tiles=(Tile("A", (1, 3)), Tile("B", (2,))),
                   nodes=f.nodes + (OwnedNode("c", "LAND", "A", (3,)),),
                   arcs=f.arcs + (FlowArc("c", "b", "LAND_D8"),),
                   transfers=f.transfers + (Transfer("cb", "A", "B", "c", "b", 3, 2),))


def lake_split(left=F(1, 4), right=F(3, 4)):
    return Fixture(
        tiles=(Tile("A", (1, 2)), Tile("B", (3, 4, 5))),
        nodes=(OwnedNode("lake", "LAKE", "A", (1, 2)),
               OwnedNode("left", "RIVER_REACH", "B", (3,)),
               OwnedNode("right", "RIVER_REACH", "B", (4,)),
               OwnedNode("join", "RIVER_REACH", "B", (5,)),
               OwnedNode("end", "BOUNDARY", "B", terminal_role="SYNTHETIC_TERMINAL")),
        arcs=(FlowArc("lake", "left", "LAKE_OUTLET", left),
              FlowArc("lake", "right", "LAKE_OUTLET", right),
              FlowArc("left", "join", "RIVER_LINK"), FlowArc("right", "join", "RIVER_LINK"),
              FlowArc("join", "end", "BOUNDARY_EXIT")),
        transfers=(Transfer("ll", "A", "B", "lake", "left", 1, 3),
                   Transfer("lr", "A", "B", "lake", "right", 2, 4)), split_mode=True)


class G5ATests(unittest.TestCase):
    def stopped(self, fixture, code):
        result = reconcile(fixture)
        self.assertEqual(result.status, Status.STOP, result)
        self.assertIn(code, [x.code for x in result.findings])
        self.assertIsNone(result.complete_area_m2)
        self.assertEqual(result.oracle_received_m2, ())
        self.assertFalse(result.routing_authorized)
        return result

    def change_transfer(self, **kw):
        f = serial()
        return replace(f, transfers=(replace(f.transfers[0], **kw),))

    def test_single_tile_global_oracle_parity(self):
        r = reconcile(single())
        self.assertEqual(r.status, Status.PASS)
        self.assertEqual(dict(r.path_received_m2), {"a": F(4), "b": F(8), "end": F(8)})
        self.assertEqual(r.oracle_received_m2, r.path_received_m2)

    def test_two_tile_serial_transfer_once(self):
        r = reconcile(serial())
        self.assertEqual(r.status, Status.PASS)
        self.assertEqual((r.owned_area_m2, r.terminal_area_m2), (F(8), F(8)))
        self.assertEqual(r.receipts[0].area_m2, F(4))
        self.assertEqual(dict(r.path_received_m2)["b"], F(8))

    def test_confluence_from_two_sources(self):
        r = reconcile(confluence())
        self.assertEqual(r.status, Status.PASS)
        self.assertEqual(dict(r.path_received_m2)["b"], F(12))
        self.assertEqual([t.area_m2 for t in r.receipts], [F(4), F(4)])
        self.assertEqual(r.terminal_area_m2, F(12))

    def test_each_tile_balances_own_in_out_and_terminal(self):
        r = reconcile(serial())
        a, b = r.tile_balances
        self.assertEqual((a.owned_area_m2, a.incoming_m2, a.outgoing_m2, a.terminal_m2),
                         (F(4), F(0), F(4), F(0)))
        self.assertEqual((b.owned_area_m2, b.incoming_m2, b.outgoing_m2, b.terminal_m2),
                         (F(4), F(4), F(0), F(8)))

    def test_halo_references_add_no_area(self):
        f = serial()
        f = replace(f, tiles=(replace(f.tiles[0], halos=(Halo(2, "b", "B"),)),
                              replace(f.tiles[1], halos=(Halo(1, "a", "A"),))))
        r = reconcile(f)
        self.assertEqual(r.status, Status.PASS)
        self.assertEqual(r.owned_area_m2, F(8))
        self.assertEqual(r.path_received_m2, reconcile(serial()).path_received_m2)

    def test_duplicate_halo_reference_rejected(self):
        f = serial()
        self.stopped(replace(f, tiles=(replace(f.tiles[0], halos=(Halo(2, "b", "B"),) * 2),
                                      f.tiles[1])), "DUPLICATE_HALO")

    def test_halo_cannot_be_local_owned_cell(self):
        f = serial()
        self.stopped(replace(f, tiles=(replace(f.tiles[0], halos=(Halo(1, "a", "A"),)),
                                      f.tiles[1])), "HALO_OWNERSHIP_MISMATCH")

    def test_halo_wrong_node_rejected(self):
        f = serial()
        self.stopped(replace(f, tiles=(replace(f.tiles[0], halos=(Halo(2, "a", "B"),)),
                                      f.tiles[1])), "HALO_OWNERSHIP_MISMATCH")

    def test_halo_absent_owner_rejected(self):
        f = serial()
        self.stopped(replace(f, tiles=(replace(f.tiles[0], halos=(Halo(9, "missing", "B"),)),
                                      f.tiles[1])), "HALO_OWNERSHIP_MISMATCH")

    def test_duplicate_cell_owners_across_nodes(self):
        f = serial()
        self.stopped(replace(f, nodes=f.nodes + (OwnedNode("copy", "LAKE", "B", (1,)),)),
                     "DUPLICATE_CELL_OWNERSHIP")

    def test_duplicate_pixel_in_one_node(self):
        f = serial()
        self.stopped(replace(f, nodes=(replace(f.nodes[0], cells=(1, 1)),) + f.nodes[1:]),
                     "DUPLICATE_CELL_OWNERSHIP")

    def test_duplicate_mask_owners_across_tiles(self):
        f = serial()
        self.stopped(replace(f, tiles=(f.tiles[0], Tile("B", (1, 2)))),
                     "DUPLICATE_CELL_OWNERSHIP")

    def test_mask_missing_owned_cell(self):
        f = serial()
        self.stopped(replace(f, tiles=(Tile("A", ()), f.tiles[1])), "MASK_OWNERSHIP_MISMATCH")

    def test_mask_extra_cell(self):
        f = serial()
        self.stopped(replace(f, tiles=(Tile("A", (1, 8)), f.tiles[1])), "MASK_OWNERSHIP_MISMATCH")

    def test_mask_wrong_tile(self):
        f = serial()
        self.stopped(replace(f, tiles=(Tile("A", (2,)), Tile("B", (1,)))), "MASK_OWNERSHIP_MISMATCH")

    def test_lake_multiple_pixels_and_remote_halos_count_once(self):
        f = lake_split()
        f = replace(f, tiles=(f.tiles[0], replace(f.tiles[1], halos=(Halo(1, "lake", "A"),
                                                                       Halo(2, "lake", "A")))))
        r = reconcile(f)
        self.assertEqual(r.status, Status.PASS)
        self.assertEqual(dict(r.path_received_m2)["lake"], F(8))
        self.assertEqual(r.owned_area_m2, F(20))
        self.assertEqual(dict(r.path_received_m2)["join"], F(20))

    def test_split_quarter_three_quarters_conserves(self):
        r = reconcile(lake_split())
        self.assertEqual(r.status, Status.PASS)
        self.assertEqual([t.area_m2 for t in r.receipts], [F(2), F(6)])
        self.assertEqual(r.terminal_area_m2, F(20))

    def test_split_reconvergence_does_not_duplicate_upstream(self):
        r = reconcile(lake_split())
        self.assertEqual(dict(r.path_received_m2),
                         {"lake": F(8), "left": F(6), "right": F(10), "join": F(20), "end": F(20)})

    def test_split_quarter_quarter_stops(self):
        self.stopped(lake_split(F(1, 4), F(1, 4)), "INVALID_FLOW_SPLIT")

    def test_split_without_fractions_stops(self):
        self.stopped(lake_split(F(1), F(1)), "INVALID_FLOW_SPLIT")

    def test_split_without_explicit_mode_stops(self):
        self.stopped(replace(lake_split(), split_mode=False), "INVALID_FLOW_SPLIT")

    def test_split_missing_fraction_stops(self):
        self.stopped(lake_split(None, F(1)), "INVALID_FLOW_SPLIT")

    def test_split_from_land_is_forbidden(self):
        f = lake_split()
        f = replace(f, nodes=(replace(f.nodes[0], kind="LAND"),) + f.nodes[1:],
                    arcs=tuple(replace(a, kind="LAND_D8") if a.source == "lake" else a for a in f.arcs))
        self.stopped(f, "INVALID_FLOW_SPLIT")

    def test_float_fraction_rejected_even_when_exact_in_binary(self):
        self.stopped(lake_split(0.25, 0.75), "INVALID_FLOW_SPLIT")

    def test_high_precision_fraction_is_not_rounded(self):
        x = F(1, 10**40 + 3)
        r = reconcile(lake_split(x, 1 - x))
        self.assertEqual(r.status, Status.PASS)
        self.assertEqual(r.receipts[0].area_m2, 8 * x)
        self.assertEqual(r.receipts[1].area_m2, 8 * (1 - x))
        self.assertEqual(r.terminal_area_m2, F(20))

    def test_negative_fraction_stops(self):
        self.stopped(lake_split(F(-1), F(2)), "INVALID_FLOW_SPLIT")

    def test_zero_fraction_stops(self):
        self.stopped(lake_split(F(0), F(1)), "INVALID_FLOW_SPLIT")

    def test_single_outlet_partial_fraction_stops(self):
        f = serial()
        self.stopped(replace(f, arcs=(replace(f.arcs[0], fraction=F(1, 2)), f.arcs[1])),
                     "INVALID_FLOW_SPLIT")

    def test_missing_transfer_stops(self):
        self.stopped(replace(serial(), transfers=()), "MISSING_OR_DUPLICATE_TRANSFER")

    def test_duplicate_transfer_identity_stops(self):
        f = serial()
        self.stopped(replace(f, transfers=f.transfers * 2), "MISSING_OR_DUPLICATE_TRANSFER")

    def test_same_arc_new_transfer_id_is_still_duplicate(self):
        f = serial()
        self.stopped(replace(f, transfers=f.transfers + (replace(f.transfers[0], transfer_id="copy"),)),
                     "MISSING_OR_DUPLICATE_TRANSFER")

    def test_conflicting_receiver_stops(self):
        self.stopped(self.change_transfer(to_node="end"), "MISSING_OR_DUPLICATE_TRANSFER")

    def test_source_cell_ownership_mismatch(self):
        self.stopped(self.change_transfer(from_cell=2), "OWNERSHIP_MISMATCH")

    def test_receiver_cell_ownership_mismatch(self):
        self.stopped(self.change_transfer(to_cell=1), "OWNERSHIP_MISMATCH")

    def test_source_tile_ownership_mismatch(self):
        self.stopped(self.change_transfer(upstream_tile="B"), "OWNERSHIP_MISMATCH")

    def test_receiver_tile_ownership_mismatch(self):
        self.stopped(self.change_transfer(downstream_tile="A"), "OWNERSHIP_MISMATCH")

    def test_double_seam_injection_rejected(self):
        self.stopped(self.change_transfer(injected_area_m2=F(4)), "SHARED_UPSTREAM_COUNTED_TWICE")

    def test_negative_seam_injection_is_not_loss_model(self):
        self.stopped(self.change_transfer(injected_area_m2=F(-4)), "SHARED_UPSTREAM_COUNTED_TWICE")

    def test_wrong_claimed_seam_area_rejected(self):
        self.stopped(self.change_transfer(claimed_area_m2=F(8)), "TRANSFER_AREA_MISMATCH")

    def test_matching_seam_claim_is_verified(self):
        self.assertEqual(reconcile(self.change_transfer(claimed_area_m2=F(4))).status, Status.PASS)

    def test_negative_transfer_claim_rejected(self):
        self.stopped(self.change_transfer(claimed_area_m2=F(-1)), "INVALID_TRANSFER")

    def test_float_transfer_claim_rejected(self):
        self.stopped(self.change_transfer(claimed_area_m2=4.0), "INVALID_TRANSFER")

    def test_open_upstream_unknown_not_complete(self):
        r = reconcile(replace(serial(), upstream=(Upstream("a"),)))
        self.assertEqual(r.status, Status.UNKNOWN)
        self.assertIn("UPSTREAM_UNKNOWN", [x.code for x in r.findings])
        self.assertIsNone(r.complete_area_m2)
        self.assertEqual(r.terminal_area_m2, F(8))  # represented area only

    def test_owned_cells_cannot_reappear_as_external_flux(self):
        self.stopped(replace(serial(), upstream=(Upstream("b", (1,), F(4)),)),
                     "SHARED_UPSTREAM_COUNTED_TWICE")

    def test_numeric_external_flux_not_supported(self):
        self.stopped(replace(serial(), upstream=(Upstream("a", (), F(4)),)),
                     "EXTERNAL_AREA_NOT_SUPPORTED")

    def test_unknown_upstream_target_rejected(self):
        self.stopped(replace(serial(), upstream=(Upstream("absent"),)), "MISSING_ENDPOINT")

    def test_tile_boundary_is_not_coast(self):
        f = serial()
        r = reconcile(replace(f, nodes=f.nodes[:-1] + (replace(f.nodes[-1], terminal_role="TILE_BOUNDARY"),)))
        self.assertEqual(r.status, Status.UNKNOWN)
        self.assertEqual(r.boundary_roles, (("end", "TILE_BOUNDARY"),))
        self.assertEqual({x.code for x in r.findings}, {"BOUNDARY_NOT_COAST", "TILE_BOUNDARY_UNRESOLVED"})
        self.assertIsNone(r.complete_area_m2)

    def test_unlabelled_boundary_stays_unknown(self):
        f = serial()
        r = reconcile(replace(f, nodes=f.nodes[:-1] + (replace(f.nodes[-1], terminal_role=None),)))
        self.assertEqual(r.status, Status.UNKNOWN)
        self.assertEqual(r.boundary_roles, (("end", None),))

    def test_explicit_synthetic_coast_label_never_approves_hydrology(self):
        f = serial()
        r = reconcile(replace(f, nodes=f.nodes[:-1] + (replace(f.nodes[-1], terminal_role="COAST"),)))
        self.assertEqual(r.status, Status.PASS)
        self.assertEqual(r.boundary_roles, (("end", "COAST"),))
        self.assertFalse(r.routing_authorized)
        self.assertEqual(r.hydrological_validation, "NOT_ASSESSED")

    def test_missing_outlet_retains_unknown(self):
        f = serial()
        r = reconcile(replace(f, arcs=f.arcs[:1]))
        self.assertEqual(r.status, Status.UNKNOWN)
        self.assertIn("MISSING_OUTLET", [x.code for x in r.findings])
        self.assertIsNone(r.complete_area_m2)

    def test_global_cycle_when_each_tile_is_locally_acyclic(self):
        f = serial()
        f = replace(f, nodes=f.nodes[:2], arcs=(f.arcs[0], FlowArc("b", "a", "LAND_D8")),
                    transfers=f.transfers + (Transfer("ba", "B", "A", "b", "a", 2, 1),))
        self.stopped(f, "CROSS_TILE_CYCLE")

    def test_local_cycle_is_distinguished(self):
        f = single()
        self.stopped(replace(f, nodes=f.nodes[:2],
                             arcs=(f.arcs[0], FlowArc("b", "a", "LAND_D8"))), "GRAPH_CYCLE")

    def test_self_loop_stops(self):
        f = single()
        self.stopped(replace(f, arcs=(FlowArc("a", "a", "LAND_D8"), f.arcs[1])), "GRAPH_CYCLE")

    def test_acyclic_path_can_cross_back_to_first_tile(self):
        f = serial()
        f = replace(f, tiles=(Tile("A", (1, 3)), Tile("B", (2,))),
                    nodes=f.nodes[:2] + (OwnedNode("c", "LAND", "A", (3,)),
                                         replace(f.nodes[2], owner_tile="A")),
                    arcs=(f.arcs[0], FlowArc("b", "c", "LAND_D8"), FlowArc("c", "end", "BOUNDARY_EXIT")),
                    transfers=f.transfers + (Transfer("bc", "B", "A", "b", "c", 2, 3),))
        r = reconcile(f)
        self.assertEqual(r.status, Status.PASS)
        self.assertEqual([t.area_m2 for t in r.receipts], [F(4), F(8)])
        self.assertEqual(r.terminal_area_m2, F(12))

    def test_arc_order_does_not_change_result(self):
        f = lake_split()
        self.assertEqual(reconcile(f), reconcile(replace(f, arcs=tuple(reversed(f.arcs)))))

    def test_tile_node_cell_transfer_order_deterministic(self):
        f = lake_split()
        permuted = replace(f, tiles=tuple(replace(t, mask_cells=tuple(reversed(t.mask_cells))) for t in reversed(f.tiles)),
                           nodes=tuple(replace(n, cells=tuple(reversed(n.cells))) for n in reversed(f.nodes)),
                           transfers=tuple(reversed(f.transfers)))
        self.assertEqual(reconcile(f), reconcile(permuted))

    def test_unknown_finding_order_deterministic(self):
        f = replace(serial(), upstream=(Upstream("b"), Upstream("a")))
        self.assertEqual(reconcile(f), reconcile(replace(f, upstream=tuple(reversed(f.upstream)))))

    def test_s1_candidate_not_an_active_edge(self):
        f = serial()
        self.stopped(replace(f, arcs=(replace(f.arcs[0], provenance_status="S1_CANDIDATE"), f.arcs[1])),
                     "UNSUPPORTED_ROUTING_EVIDENCE")

    def test_02f_zero_interior_not_an_active_edge(self):
        f = serial()
        self.stopped(replace(f, arcs=(replace(f.arcs[0], provenance_status="D8_ZERO_INTERIOR"), f.arcs[1])),
                     "UNSUPPORTED_ROUTING_EVIDENCE")

    def test_return_to_origin_not_an_active_edge(self):
        f = serial()
        self.stopped(replace(f, arcs=(replace(f.arcs[0], provenance_status="RETURNS_TO_ORIGIN_LAKE"), f.arcs[1])),
                     "UNSUPPORTED_ROUTING_EVIDENCE")

    def test_step_limit_not_an_active_edge(self):
        f = serial()
        self.stopped(replace(f, arcs=(replace(f.arcs[0], provenance_status="STEP_LIMIT"), f.arcs[1])),
                     "UNSUPPORTED_ROUTING_EVIDENCE")

    def test_unknown_transfer_provenance_stops(self):
        self.stopped(self.change_transfer(provenance_status="UNKNOWN"), "UNSUPPORTED_ROUTING_EVIDENCE")

    def test_result_and_nested_receipts_are_immutable(self):
        r = reconcile(serial())
        with self.assertRaises(FrozenInstanceError):
            r.status = Status.PASS
        with self.assertRaises(FrozenInstanceError):
            r.receipts[0].area_m2 = F(100)
        with self.assertRaises(TypeError):
            r.oracle_received_m2[0] = ("a", F(0))

    def test_input_records_are_immutable(self):
        f = serial()
        with self.assertRaises(FrozenInstanceError):
            f.nodes[0].cells = (9,)
        with self.assertRaises(FrozenInstanceError):
            f.tiles[0].mask_cells = (9,)

    def test_all_scientific_locks_preserved_in_every_status(self):
        for f in (serial(), replace(serial(), upstream=(Upstream("a"),)),
                  replace(serial(), transfers=())):
            with self.subTest(f=f):
                r = reconcile(f)
                self.assertEqual((r.NATIONAL, r.MODERATE, r.hydrological_validation,
                                  r.channel_interpretation, r.routing_authorized),
                                 ("LOCKED", "REVIEW_REQUIRED", "NOT_ASSESSED", "NOT_ASSESSED", False))

    def test_area_normalization_two_m_is_four_square_m(self):
        r = reconcile(serial())
        self.assertEqual(r.owned_area_m2, F(4 * 2))
        self.assertIs(type(r.owned_area_m2), F)

    def test_other_resolution_is_not_silently_normalized(self):
        self.stopped(replace(serial(), resolution_m=F(1)), "INVALID_RESOLUTION")

    def test_float_resolution_rejected(self):
        self.stopped(replace(serial(), resolution_m=2.0), "INVALID_RESOLUTION")

    def test_fixture_node_resource_limit(self):
        f = serial()
        self.stopped(replace(f, nodes=f.nodes * 7), "RESOURCE_LIMIT")

    def test_fixture_cell_resource_limit(self):
        f = single()
        self.stopped(replace(f, tiles=(Tile("A", tuple(range(1, 66))),)), "RESOURCE_LIMIT")

    def test_fixture_arc_resource_limit(self):
        f = serial()
        self.stopped(replace(f, arcs=f.arcs * 33), "RESOURCE_LIMIT")

    def test_path_enumeration_work_bound_stops(self):
        with patch.object(qa, "MAX_PATH_STATES", 1):
            self.stopped(serial(), "RESOURCE_LIMIT")

    def test_fraction_bit_resource_bound(self):
        self.stopped(lake_split(F(1, 2**300), 1 - F(1, 2**300)), "INVALID_FLOW_SPLIT")

    def test_real_default_path_budget_on_dense_tiny_dag(self):
        n = 19
        nodes = tuple(OwnedNode(str(i), "LAKE", "A", (i + 1,)) for i in range(n))
        nodes += (OwnedNode("end", "BOUNDARY", "A", terminal_role="SYNTHETIC_TERMINAL"),)
        arcs = []
        for i in range(n - 1):
            targets = tuple(range(i + 1, min(i + 3, n)))
            arcs.extend(FlowArc(str(i), str(t), "LAKE_OUTLET", F(1, len(targets))) for t in targets)
        arcs.append(FlowArc(str(n - 1), "end", "LAKE_OUTLET"))
        self.stopped(Fixture((Tile("A", tuple(range(1, n + 1))),), nodes,
                             tuple(arcs), split_mode=True), "RESOURCE_LIMIT")

    def test_no_owned_pixels_cannot_claim_vacuous_complete_area(self):
        f = Fixture((Tile("A", ()),),
                    (OwnedNode("end", "BOUNDARY", "A", terminal_role="SYNTHETIC_TERMINAL"),), ())
        self.stopped(f, "OWNERSHIP_MISMATCH")

    def test_two_terminal_fractions_are_exact_without_rejoining(self):
        f = lake_split(F(1, 3), F(2, 3))
        f = replace(f, nodes=f.nodes[:3] +
                    (OwnedNode("end1", "BOUNDARY", "B", terminal_role="SYNTHETIC_TERMINAL"),
                     OwnedNode("end2", "BOUNDARY", "B", terminal_role="SYNTHETIC_TERMINAL")),
                    tiles=(f.tiles[0], Tile("B", (3, 4))),
                    arcs=f.arcs[:2] + (FlowArc("left", "end1", "RIVER_LINK"),
                                       FlowArc("right", "end2", "RIVER_LINK")))
        r = reconcile(f)
        self.assertEqual(r.status, Status.PASS)
        self.assertEqual(dict(r.path_received_m2)["end1"], F(20, 3))
        self.assertEqual(dict(r.path_received_m2)["end2"], F(28, 3))
        self.assertEqual(r.terminal_area_m2, F(16))

    def test_boundary_reference_in_other_tile_cannot_fake_cell_endpoint(self):
        f = serial()
        f = replace(f, nodes=(f.nodes[0], f.nodes[1], replace(f.nodes[-1], owner_tile="A")),
                    transfers=f.transfers + (Transfer("end", "B", "A", "b", "end", 2, 1),))
        self.stopped(f, "OWNERSHIP_MISMATCH")

    def test_no_more_than_two_partitions_supported(self):
        f = serial()
        self.stopped(replace(f, tiles=f.tiles + (Tile("C", ()),)), "RESOURCE_LIMIT")

    def test_boolean_split_flag_rejects_truthy_string(self):
        self.stopped(replace(lake_split(), split_mode="true"), "INVALID_SCHEMA")

    def test_boundary_cannot_emit_flow(self):
        f = single()
        self.stopped(replace(f, arcs=f.arcs + (FlowArc("end", "a", "BOUNDARY_EXIT"),)), "INVALID_ARC")

    def test_mutable_collection_is_not_accepted(self):
        self.stopped(replace(serial(), nodes=list(serial().nodes)), "INVALID_SCHEMA")

    def test_wrong_fixture_type_returns_stop(self):
        self.stopped({"nodes": []}, "INVALID_SCHEMA")

    def test_invalid_record_type_returns_stop(self):
        self.stopped(replace(serial(), arcs=("shell command",)), "INVALID_SCHEMA")

    def test_empty_graph_returns_stop(self):
        self.stopped(Fixture((), (), ()), "INVALID_SCHEMA")

    def test_boolean_cell_id_not_an_integer_id(self):
        f = serial()
        self.stopped(replace(f, tiles=(Tile("A", (True,)), f.tiles[1])), "INVALID_CELL")

    def test_negative_transfer_cell_rejected(self):
        self.stopped(self.change_transfer(from_cell=-1), "INVALID_TRANSFER")

    def test_duplicate_node_id_rejected(self):
        f = serial()
        self.stopped(replace(f, nodes=f.nodes + (f.nodes[0],)), "INVALID_NODE")

    def test_unknown_node_owner_tile_rejected(self):
        f = serial()
        self.stopped(replace(f, nodes=(replace(f.nodes[0], owner_tile="C"),) + f.nodes[1:]),
                     "OWNERSHIP_MISMATCH")

    def test_boundary_cannot_own_area(self):
        f = serial()
        self.stopped(replace(f, nodes=f.nodes[:-1] + (replace(f.nodes[-1], cells=(3,)),)),
                     "BOUNDARY_OWNS_AREA")

    def test_duplicate_arc_rejected(self):
        f = serial()
        self.stopped(replace(f, arcs=f.arcs + (f.arcs[0],)), "DUPLICATE_ARC")

    def test_missing_arc_endpoint_rejected(self):
        f = serial()
        self.stopped(replace(f, arcs=(replace(f.arcs[0], target="missing"), f.arcs[1])), "MISSING_ENDPOINT")

    def test_wrong_arc_kind_rejected(self):
        f = serial()
        self.stopped(replace(f, arcs=(replace(f.arcs[0], kind="LAKE_OUTLET"), f.arcs[1])), "INVALID_ARC")

    def test_oracle_is_reused_once_not_reimplemented(self):
        with patch.object(qa, "synthetic_accumulation", wraps=qa.synthetic_accumulation) as oracle:
            self.assertEqual(reconcile(serial()).status, Status.PASS)
            self.assertEqual(oracle.call_count, 1)

    def test_independent_paths_detect_corrupted_oracle_node_result(self):
        original = qa.synthetic_accumulation
        def broken(*args, **kwargs):
            result = original(*args, **kwargs)
            result["received_area_m2"]["b"] += 1
            return result
        with patch.object(qa, "synthetic_accumulation", side_effect=broken):
            self.stopped(serial(), "PARITY_MISMATCH")

    def test_independent_total_detects_corrupted_oracle_terminal_sum(self):
        original = qa.synthetic_accumulation
        def broken(*args, **kwargs):
            return {**original(*args, **kwargs), "terminal_area_m2": F(999)}
        with patch.object(qa, "synthetic_accumulation", side_effect=broken):
            self.stopped(serial(), "AREA_CONSERVATION_FAILURE")

    def test_no_io_or_process_imports_in_component(self):
        tree = ast.parse(Path(qa.__file__).read_text())
        imports = {n.module for n in ast.walk(tree) if isinstance(n, ast.ImportFrom)}
        self.assertEqual(imports, {"__future__", "dataclasses", "enum", "fractions", "graph_oracle"})
        self.assertFalse(any(isinstance(n, ast.Import) for n in ast.walk(tree)))
        calls = {n.func.id for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)}
        self.assertFalse(calls & {"open", "exec", "eval", "__import__", "compile"})

    def test_seeded_tiny_dags_weighted_path_oracle(self):
        rng = random.Random(540053)
        for case in range(24):
            with self.subTest(case=case):
                n = rng.randint(4, 12)
                tile_of = {i: ("A" if i % 2 == 0 else "B") for i in range(n)}
                tile_of[n - 1] = "B"
                nodes = tuple(OwnedNode(str(i), "LAKE", tile_of[i], (i + 1,)) for i in range(n))
                nodes += (OwnedNode("end", "BOUNDARY", "B", terminal_role="SYNTHETIC_TERMINAL"),)
                arcs = []
                transfers = []
                for i in range(n - 1):
                    targets = rng.sample(range(i + 1, n), min(rng.randint(1, 2), n - i - 1))
                    fractions = [F(1)] if len(targets) == 1 else [F(1, 4), F(3, 4)]
                    for target, fraction in zip(targets, fractions):
                        arcs.append(FlowArc(str(i), str(target), "LAKE_OUTLET", fraction))
                        if tile_of[i] != tile_of[target]:
                            transfers.append(Transfer(f"t{i}-{target}", tile_of[i], tile_of[target],
                                                      str(i), str(target), i + 1, target + 1))
                arcs.append(FlowArc(str(n - 1), "end", "LAKE_OUTLET"))
                tiles = tuple(Tile(t, tuple(i + 1 for i in range(n) if tile_of[i] == t)) for t in ("A", "B"))
                f = Fixture(tiles, nodes, tuple(arcs), tuple(transfers), split_mode=True)
                r = reconcile(f)
                self.assertEqual(r.status, Status.PASS)
                self.assertEqual(r.oracle_received_m2, r.path_received_m2)
                self.assertEqual(r.terminal_area_m2, F(4 * n))
                for balance in r.tile_balances:
                    self.assertEqual(balance.owned_area_m2 + balance.incoming_m2 - balance.outgoing_m2,
                                     balance.terminal_m2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
