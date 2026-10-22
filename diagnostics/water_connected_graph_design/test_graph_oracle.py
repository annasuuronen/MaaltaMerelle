#!/usr/bin/env python3
"""Synthetic independent candidate graph and accumulation contracts; no CSC I/O."""
import unittest
from dataclasses import replace
from fractions import Fraction
from graph_oracle import Arc, Candidate, GraphContractError, Node, candidate_preflight, synthetic_accumulation


def qualified(**kwargs):
    return Candidate(lake_id=1847,spill_group_id=241,source_cell=11158308,
                     receiver_cell=11152307,evidence_status="EXTERNAL_EVIDENCE",
                     route_status="REACHES_RIVER_LINE",geometry_reviewed=True,
                     provenance_verified=True,full_downstream_verified=True,**kwargs)


def baseline():
    nodes=[Node('land:A','LAND',(1,)),Node('land:B','LAND',(2,)),
           Node('lake:1847','LAKE',(3,4)),Node('river:reach-1','RIVER_REACH',(5,)),
           Node('boundary:LOW-E','BOUNDARY')]
    arcs=[Arc('land:A','lake:1847','LAND_D8'),Arc('land:B','lake:1847','LAND_D8'),
          Arc('lake:1847','river:reach-1','LAKE_OUTLET'),
          Arc('river:reach-1','boundary:LOW-E','RIVER_LINK')]
    return nodes, arcs


class CandidatePreflightTests(unittest.TestCase):
    def test_first_water_only_is_not_enough(self):
        state,why=candidate_preflight(replace(qualified(),full_downstream_verified=False))
        self.assertEqual(state,'REVIEW_REQUIRED')
        self.assertIn('FIRST_WATER_IS_NOT_FULL_CONNECTION',why)
    def test_parallel_candidates_are_not_selected(self):
        a=qualified();b=replace(a,spill_group_id=242,source_cell=11158309)
        self.assertEqual(candidate_preflight(a)[0],'READY_FOR_SEPARATE_APPROVAL')
        self.assertEqual(candidate_preflight(b)[0],'READY_FOR_SEPARATE_APPROVAL')
        self.assertEqual((a.outlet_selection,b.outlet_selection),('UNASSIGNED','UNASSIGNED'))
    def test_corner_contact_requires_review(self):
        state,why=candidate_preflight(replace(qualified(),corner_only_contact=True))
        self.assertIn('CORNER_ONLY_CONTACT',why)
        self.assertEqual(state,'REVIEW_REQUIRED')
    def test_return_to_origin_rejected(self):
        state,why=candidate_preflight(replace(qualified(),route_status='RETURNS_TO_ORIGIN_LAKE'))
        self.assertIn('RETURN_OR_CYCLE',why)
        self.assertEqual(state,'REVIEW_REQUIRED')
    def test_cycle_rejected(self):
        self.assertIn('RETURN_OR_CYCLE',candidate_preflight(replace(qualified(),route_status='D8_CYCLE'))[1])
    def test_no_external_evidence_blocks(self):
        self.assertIn('NO_CLEAR_EXTERNAL_EVIDENCE',candidate_preflight(replace(qualified(),evidence_status='NO_EXTERNAL_EVIDENCE'))[1])
    def test_review_required_blocks(self):
        self.assertIn('SOURCE_REVIEW_REQUIRED',candidate_preflight(qualified(needs_review=True))[1])
    def test_unknown_provenance_blocks(self):
        self.assertIn('UNVERIFIED_PROVENANCE',candidate_preflight(replace(qualified(),provenance_verified=False))[1])
    def test_geometry_unverified_blocks(self):
        self.assertIn('UNREVIEWED_RANTA10_GEOMETRY',candidate_preflight(replace(qualified(),geometry_reviewed=False))[1])
    def test_unapproved_status_cannot_be_written_into_02e(self):
        with self.assertRaises(GraphContractError):candidate_preflight(replace(qualified(),outlet_selection='ACCEPTED'))
    def test_unverified_boundary_or_step_limit(self):
        for status in ('D8_DOMAIN_EXIT','STEP_LIMIT','D8_ZERO_INTERIOR','LAKE_ID_MISSING'):
            with self.subTest(status=status):
                self.assertIn('INCOMPLETE_OR_INVALID_ROUTE',candidate_preflight(replace(qualified(),route_status=status))[1])
    def test_missing_identifier_is_invalid(self):
        with self.assertRaises(GraphContractError):candidate_preflight(replace(qualified(),spill_group_id=0))


class SyntheticMassBalanceTests(unittest.TestCase):
    def test_confluence_and_lake_area_counted_once(self):
        n,e=baseline();result=synthetic_accumulation(n,e)
        self.assertEqual(result['n_cells'],5)
        self.assertEqual(result['received_area_m2']['lake:1847'],16)
        self.assertEqual(result['terminal_area_m2'],20)
    def test_shared_river_receiver_not_double_counted(self):
        n,e=baseline();e.insert(2,Arc('land:B','river:reach-1','LAND_D8'))
        with self.assertRaises(GraphContractError):synthetic_accumulation(n,e)
    def test_duplicate_arc_rejected(self):
        n,e=baseline();e.append(e[2])
        with self.assertRaises(GraphContractError):synthetic_accumulation(n,e)
    def test_duplicate_cell_ownership_rejected(self):
        n,e=baseline();n[2]=Node('lake:1847','LAKE',(2,4))
        with self.assertRaises(GraphContractError):synthetic_accumulation(n,e)
    def test_unassigned_lake_outlet_cannot_be_called_complete(self):
        n,e=baseline();e=[x for x in e if x.kind!='LAKE_OUTLET']
        with self.assertRaises(GraphContractError):synthetic_accumulation(n,e)
    def test_nonboundary_terminal_can_only_be_provisional(self):
        n,e=baseline();e=[x for x in e if x.kind!='LAKE_OUTLET']
        result=synthetic_accumulation(n,e,enforce_boundary_terminals=False)
        self.assertEqual(result['scope'],'SYNTHETIC_LOCAL_ONLY_NO_EXTERNAL_INFLOW')
    def test_waterbody_cycle_rejected(self):
        n,e=baseline();e[-1]=Arc('river:reach-1','lake:1847','RIVER_LINK')
        with self.assertRaises(GraphContractError):synthetic_accumulation(n,e)
    def test_multiple_outlets_without_split_rejected(self):
        n,e=baseline();n.append(Node('river:reach-2','RIVER_REACH'))
        e.append(Arc('lake:1847','river:reach-2','LAKE_OUTLET'))
        with self.assertRaises(GraphContractError):synthetic_accumulation(n,e)
    def test_explicit_two_outlet_fraction_conserves_mass(self):
        n,e=baseline();n.append(Node('boundary:LOW-W','BOUNDARY'))
        e[2]=Arc('lake:1847','river:reach-1','LAKE_OUTLET',Fraction(1,4))
        e.append(Arc('lake:1847','boundary:LOW-W','LAKE_OUTLET',Fraction(3,4)))
        r=synthetic_accumulation(n,e,split_mode=True)
        self.assertEqual(r['terminal_area_m2'],20)
        self.assertEqual(r['received_area_m2']['boundary:LOW-W'],12)
        self.assertEqual(r['received_area_m2']['boundary:LOW-E'],8)
    def test_split_fractions_must_sum_to_one(self):
        n,e=baseline();n.append(Node('boundary:LOW-W','BOUNDARY'))
        e[2]=Arc('lake:1847','river:reach-1','LAKE_OUTLET',Fraction(1,4))
        e.append(Arc('lake:1847','boundary:LOW-W','LAKE_OUTLET',Fraction(1,4)))
        with self.assertRaises(GraphContractError):synthetic_accumulation(n,e,split_mode=True)
    def test_split_from_land_not_allowed(self):
        n,e=baseline();e.insert(0,Arc('land:A','river:reach-1','LAND_D8',Fraction(1,2)))
        e[1]=Arc('land:A','lake:1847','LAND_D8',Fraction(1,2))
        with self.assertRaises(GraphContractError):synthetic_accumulation(n,e,split_mode=True)
    def test_unknown_node_rejected(self):
        n,e=baseline();e.append(Arc('lake:1847','unknown','LAKE_OUTLET'))
        with self.assertRaises(GraphContractError):synthetic_accumulation(n,e)
    def test_invalid_edge_semantics_rejected(self):
        n,e=baseline();e[2]=Arc('lake:1847','river:reach-1','LAND_D8')
        with self.assertRaises(GraphContractError):synthetic_accumulation(n,e)
    def test_multiple_outlet_from_one_lake_counted_once_after_join(self):
        n,e=baseline()
        n.append(Node('river:reach-2','RIVER_REACH'))
        e[2]=Arc('lake:1847','river:reach-1','LAKE_OUTLET',Fraction(1,2))
        e.append(Arc('lake:1847','river:reach-2','LAKE_OUTLET',Fraction(1,2)))
        e.append(Arc('river:reach-2','boundary:LOW-E','RIVER_LINK'))
        r=synthetic_accumulation(n,e,split_mode=True)
        self.assertEqual(r['terminal_area_m2'],20)
        self.assertEqual(r['received_area_m2']['boundary:LOW-E'],20)

if __name__=='__main__':unittest.main(verbosity=2)