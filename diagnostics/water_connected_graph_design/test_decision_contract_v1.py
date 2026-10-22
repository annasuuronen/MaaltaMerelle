"""Small synthetic S1 tests only. No real LOW/CSC files or hydrological runs."""
from copy import deepcopy
from dataclasses import FrozenInstanceError, replace
import itertools
import json
from pathlib import Path
import subprocess
import sys
import unittest

import decision_contract_v1 as s1


def source(sid="synthetic-mask", kind="RANTA10", role="INPUT"):
    return dict(source_path_or_id=sid,source_version="synthetic-v1",source_role=role,kind=kind,
                used_in_build_or_candidate_review=True,reference_role="INPUT",
                shared_lineage=True,verification_state="VERIFIED")


def reference():
    x=source("held-out-synthetic-reference","OTHER","INDEPENDENT_REFERENCE")
    x.update(used_in_build_or_candidate_review=False,reference_role="HELD_OUT_COMPARISON",shared_lineage=False)
    return x


def fixture():
    # Structurally LOW-shaped synthetic grid; no actual observations or rasters.
    grid=dict(grid_id="SYNTHETIC-GRID",epsg=3067,nrow=6000,ncol=6000,
              resolution_m=2,xmin=199000,xmax=211000,ymin=6899000,ymax=6911000)
    return dict(schema_version="s1.0",observation_id="observation-1",region_id="SYNTHETIC",
        grid=grid,provenance=dict(manifest_sha256="a"*64,manifest_state="CURRENT",producer_commit="b"*40,
            evidence_version="synthetic-evidence-v1",algorithm_version="synthetic-producer-v1",
            grid=deepcopy(grid),sources=[source(),source("synthetic-pointer","D8")]),
        origin_lake_id=101,component_id=17,
        evidence=dict(water_classes=[1],classification_02c="LAKE_ONLY",component_status="OBSERVED"))


def route(i=1, terminal=18003):
    x=fixture()
    x.update(observation_id=f"observation-{i}",route_id=f"route-{i}",source_cell=12002+i,
             start_receiver_cell=12003+i,terminal_cell=terminal,receiver_type="LAKE",receiver_id=202,
             route_status="REACHES_OTHER_LAKE",route_geometry="SUMMARY_ONLY",steps=3)
    x["evidence"]["directed_hypothesis"]=True
    return x


def proof(x):
    x["provenance"]["sources"].append(reference())
    x["evidence"]["impossibility"]=dict(source_path_or_id="held-out-synthetic-reference",
        evidence_id="synthetic-negative-evidence-1",criterion="EXPLICIT_PHYSICAL_CONTRADICTION",
        statement="Synthetic fixture explicitly supplies a documented physical contradiction.")
    return x


class SafetyCase(unittest.TestCase):
    def safe(self,result):
        self.assertIs(result.routing_authorized,False)
        self.assertEqual(result.outlet_selection,"UNASSIGNED")
        self.assertEqual(result.NATIONAL,"LOCKED")
        self.assertEqual(result.MODERATE,"REVIEW_REQUIRED")
        self.assertEqual(result.hydrological_validation,"NOT_ASSESSED")
        self.assertEqual(result.channel_interpretation,"NOT_ASSESSED")
        if isinstance(result,s1.Decision):
            self.assertNotEqual(result.decision_state,"VALIDATED")
            self.assertEqual(result.route_chain_assessment,"NOT_ASSESSED")
            self.assertEqual(result.independent_validation_state,"NOT_ASSESSED")
        return result

    def decide(self,x):
        before=deepcopy(x)
        result=self.safe(s1.classify(s1.validate_observation(x)))
        self.assertEqual(x,before)
        return result

    def stopped(self,x,code=None):
        with self.assertRaises(s1.SchemaStop) as caught:s1.validate_observation(x)
        self.assertTrue(str(caught.exception).startswith("SCHEMA_STOP:"))
        if code:self.assertEqual(caught.exception.reason_code,code)


class SchemaTests(SafetyCase):
    def test_6000_grid_and_reported_manifest_match(self):
        o=s1.validate_observation(fixture())
        self.assertEqual((o.grid.nrow,o.grid.ncol,o.grid.epsg,o.grid.resolution_m),(6000,6000,3067,2.0))
        self.assertEqual(o.grid,o.provenance.grid)

    def test_no_tile_name_bbox_assumption(self):
        x=fixture()
        for g in (x['grid'],x['provenance']['grid']):
            g.update(grid_id="DIFFERENT-SYNTHETIC-GRID",nrow=4,ncol=5,xmin=10,xmax=20,ymin=30,ymax=38)
        self.assertEqual(self.decide(x).observation.grid.ncol,5)

    def test_wrong_bbox_dimensions_stop(self):
        x=fixture();x['grid']['xmax']+=1;self.stopped(x,'BBOX_GRID_MISMATCH')

    def test_shifted_same_size_bbox_conflicts_with_manifest(self):
        x=fixture();x['grid']['xmin']+=2;x['grid']['xmax']+=2
        self.stopped(x,'MANIFEST_GRID_CONFLICT')

    def test_wrong_epsg_stop(self):
        x=fixture();x['grid']['epsg']=4326;self.stopped(x,'EPSG_3067_REQUIRED')

    def test_resolution_stop(self):
        x=fixture();x['grid']['resolution_m']=1;self.stopped(x,'TWO_METRE_SAFE_GRID_REQUIRED')

    def test_missing_required_identities_stop(self):
        for key in ('observation_id','region_id','grid','provenance','schema_version'):
            with self.subTest(key=key):
                x=fixture();del x[key];self.stopped(x)

    def test_missing_source_role_stop(self):
        x=fixture();del x['provenance']['sources'][0]['source_role'];self.stopped(x)

    def test_invalid_or_missing_provenance_digests_stop(self):
        for name,values in (('manifest_sha256',('bad','A'*64,None)),('producer_commit',('1234','g'*40,None))):
            for value in values:
                with self.subTest(name=name,value=value):
                    x=fixture();x['provenance'][name]=value;self.stopped(x,'INVALID_PROVENANCE_DIGEST')

    def test_stale_manifest_stop(self):
        x=fixture();x['provenance']['manifest_state']='STALE';self.stopped(x,'STALE_MANIFEST')

    def test_schema_stop_precedes_review_and_candidate_rules(self):
        x=route();x['route_status']='D8_ZERO_INTERIOR';x['evidence']['water_classes']=[1,3]
        x['provenance']['manifest_sha256']='forged'
        self.stopped(x,'INVALID_PROVENANCE_DIGEST')

    def test_missing_and_duplicate_sources_stop(self):
        for sources in ([],[source(),source()]):
            with self.subTest(sources=sources):
                x=fixture();x['provenance']['sources']=sources;self.stopped(x,'MISSING_OR_DUPLICATE_SOURCE')

    def test_input_cannot_be_relabelled_held_out(self):
        x=fixture();x['provenance']['sources'][0]['reference_role']='HELD_OUT_COMPARISON'
        self.stopped(x,'SOURCE_ROLE_OR_HOLDOUT_CONFLICT')

    def test_independent_label_cannot_hide_build_use_or_unknown_history(self):
        for reference_role in ('AUXILIARY_CONCORDANCE','REFERENCE_USE_UNKNOWN'):
            with self.subTest(role=reference_role):
                x=fixture();x['provenance']['sources'][0].update(source_role='INDEPENDENT_REFERENCE',reference_role=reference_role)
                self.stopped(x,'SOURCE_ROLE_OR_HOLDOUT_CONFLICT')

    def test_required_identity_cannot_be_unknown_placeholder(self):
        for key in ('observation_id','region_id','route_id'):
            with self.subTest(key=key):
                x=route();x[key]='UNKNOWN';self.stopped(x,'REQUIRED_IDENTITY_UNKNOWN')
        x=fixture();x['provenance']['algorithm_version']='UNKNOWN'
        self.stopped(x,'REQUIRED_IDENTITY_UNKNOWN')

    def test_impossibility_requires_explicit_documented_criterion(self):
        for key in ('criterion','evidence_id','statement','source_path_or_id'):
            with self.subTest(key=key):
                x=proof(fixture());del x['evidence']['impossibility'][key];self.stopped(x)
        x=proof(fixture());x['evidence']['impossibility']['criterion']='MAPPED_LINE_ABSENT'
        self.stopped(x,'EXPLICIT_IMPOSSIBILITY_CRITERION_REQUIRED')

    def test_sequences_are_bounded_and_ordered(self):
        x=fixture();x['evidence']['water_classes']={1,3};self.stopped(x,'BOUNDED_SEQUENCE_REQUIRED')
        with self.assertRaises(s1.SchemaStop):s1.group_routes([route()]*4097)

    def test_used_shared_or_unknown_reference_is_not_holdout(self):
        for key,value in (('used_in_build_or_candidate_review',True),('shared_lineage',True),
                          ('shared_lineage','UNKNOWN'),('source_version','UNKNOWN'),('verification_state','UNKNOWN')):
            with self.subTest(key=key,value=value):
                x=fixture();r=reference();r[key]=value;x['provenance']['sources'].append(r)
                self.stopped(x,'SOURCE_ROLE_OR_HOLDOUT_CONFLICT')

    def test_fake_independent_comparison_stop(self):
        x=fixture();x['evidence']['independence_state']='COMPARISON_REPORTED'
        self.stopped(x,'INDEPENDENCE_CLAIM_CONFLICT')

    def test_approval_and_authorization_attempts_stop(self):
        for key,value in (('decision_state','VALIDATED'),('status','APPROVED'),('outlet_selection','OUTLET_SELECTED'),
                          ('routing_authorized',True),('NATIONAL','OPEN'),('reason_codes',['APPROVE'])):
            with self.subTest(key=key):
                x=fixture();x[key]=value;self.stopped(x)
        x=route();x['route_status']='VALIDATED';self.stopped(x,'UNKNOWN_ENUM')

    def test_approval_nested_in_evidence_stop(self):
        x=fixture();x['evidence']['routing_authorized']=True;self.stopped(x)

    def test_impossible_and_fractional_cells_stop(self):
        for cell in (0,-1,36000001,1.5,12003.0,True,'12003'):
            with self.subTest(cell=cell):
                x=route();x['start_receiver_cell']=cell;self.stopped(x,'EXACT_INTEGER_REQUIRED')

    def test_ids_not_rounded_or_coerced(self):
        for value in (101.0,101.5,True,'101',0,2**53):
            with self.subTest(value=value):
                x=fixture();x['origin_lake_id']=value;self.stopped(x,'EXACT_INTEGER_REQUIRED')

    def test_nonfinite_measurements_stop(self):
        for key in ('height_difference_m','height_uncertainty_m','separation_m'):
            for value in (float('nan'),float('inf'),float('-inf'),True,'0.07',10**1000):
                with self.subTest(key=key,value=repr(value)[:25]):
                    x=fixture();x['evidence'][key]=value;self.stopped(x,'FINITE_NUMBER_REQUIRED')

    def test_negative_uncertainty_and_distance_stop(self):
        for key in ('height_uncertainty_m','separation_m'):
            with self.subTest(key=key):
                x=fixture();x['evidence'][key]=-0.1;self.stopped(x,'FINITE_NUMBER_REQUIRED')

    def test_unknown_reason_and_status_cannot_become_approval(self):
        x=fixture();x['evidence']['reason_codes']=['UNKNOWN_REASON'];self.stopped(x)
        x=route();x['route_status']='REACHES_SEA';self.stopped(x,'UNKNOWN_ENUM')

    def test_missing_route_identity_stop(self):
        for key in ('route_id','origin_lake_id','source_cell','start_receiver_cell','steps'):
            with self.subTest(key=key):
                x=route();x[key]=None;self.stopped(x,'REQUIRED_ROUTE_IDENTITY_MISSING')

    def test_directed_hypothesis_requires_canonical_start_identity(self):
        for key in ('origin_lake_id','source_cell','start_receiver_cell'):
            with self.subTest(key=key):
                x=route();x.update(route_id=None,route_status='NOT_ASSESSED',route_geometry='NOT_ASSESSED',steps=None)
                x[key]=None;self.stopped(x,'REQUIRED_HYPOTHESIS_IDENTITY_MISSING')

    def test_component_identity_conflicts_stop(self):
        x=fixture();x['component_id']=None;self.stopped(x,'IDENTITY_EVIDENCE_CONFLICT')
        x=fixture();x['evidence']['component_status']='ABSENT';self.stopped(x,'IDENTITY_EVIDENCE_CONFLICT')

    def test_unbound_receiver_claim_and_impossibility_stop(self):
        x=fixture();x['evidence']['receiver_claims']=[dict(receiver_type='LAKE',receiver_id=303,source_path_or_id='missing')]
        self.stopped(x,'UNBOUND_EVIDENCE_SOURCE')
        x=proof(fixture());x['evidence']['impossibility']['source_path_or_id']='missing'
        self.stopped(x,'UNBOUND_EVIDENCE_SOURCE')

    def test_missing_actual_source_kinds_stop(self):
        x=fixture();x['provenance']['sources']=[source('pointer','D8')];self.stopped(x,'RANTA10_SOURCE_REQUIRED')
        x=route();x['provenance']['sources']=[source()];self.stopped(x,'D8_SOURCE_REQUIRED')
        x=fixture();x['evidence']['syke_point_match']=True;self.stopped(x,'AUXILIARY_SOURCE_REQUIRED')

    def test_invalid_boolean_never_becomes_false_or_true(self):
        for value in (0,1,'TRUE',[],{}):
            with self.subTest(value=value):
                x=fixture();x['evidence']['directed_hypothesis']=value;self.stopped(x,'BOOLEAN_OR_NULL_REQUIRED')


class ClassificationTests(SafetyCase):
    def test_safe_lake_connector_remains_observation(self):
        x=fixture();x['evidence']['classification_02c']='SAFE_LAKE_CONNECTOR'
        d=self.decide(x);self.assertEqual(d.decision_state,'OBSERVED')
        self.assertEqual(d.observation.evidence.classification_02c,'SAFE_LAKE_CONNECTOR')

    def test_class1_plus_class3_is_mixed_review(self):
        x=fixture();x['evidence']['water_classes']=[1,1,1,1,3]
        d=self.decide(x);self.assertEqual(d.decision_state,'REVIEW_REQUIRED')
        self.assertIn('MIXED_WATER_NEIGHBORS',d.reason_codes)
        self.assertEqual(d.observation.evidence.water_classes,(1,1,1,1,3))

    def test_explicit_mixed_survives_missing_class_list(self):
        x=fixture();x['evidence']['water_classes']=None;x['evidence']['classification_02c']='MIXED'
        self.assertEqual(self.decide(x).decision_state,'REVIEW_REQUIRED')

    def test_interior_review_does_not_invent_mixed_water(self):
        x=fixture();x['evidence']['classification_02c']='INTERIOR_REVIEW'
        d=self.decide(x);self.assertEqual(d.decision_state,'REVIEW_REQUIRED')
        self.assertNotIn('MIXED_WATER_NEIGHBORS',d.reason_codes)
        self.assertIn('SOURCE_02C_REVIEW',d.reason_codes)

    def test_componentless_is_not_filled_or_connected(self):
        x=fixture();x['component_id']=None;x['evidence']['component_status']='ABSENT'
        d=self.decide(x);self.assertEqual(d.decision_state,'OBSERVED')
        self.assertIn('COMPONENTLESS_OBSERVATION',d.reason_codes)
        self.assertIsNone(d.observation.component_id)

    def test_footprint_only_is_not_mask_error(self):
        x=fixture();x['evidence'].update(footprint_intersects=True,center_intersects=False)
        d=self.decide(x);self.assertEqual(d.decision_state,'OBSERVED')
        self.assertIn('BOUNDARY_FOOTPRINT_ONLY',d.reason_codes)
        self.assertEqual(d.observation.evidence.water_classes,(1,))

    def test_lake_hypothesis_is_candidate_not_approved(self):
        d=self.decide(route());self.assertEqual(d.decision_state,'CANDIDATE')
        self.assertEqual(d.case_type,'LAKE_TO_LAKE_HYPOTHESIS')

    def test_gap_and_seven_cm_do_not_authorize_or_prove_direction(self):
        x=route();x['evidence'].update(separation_m=38.12,height_difference_m=0.07,mapped_line_present=False)
        d=self.decide(x);self.assertEqual(d.decision_state,'REVIEW_REQUIRED')
        self.assertTrue({'MAPPED_LINE_GAP','LOW_GRADIENT_UNCERTAIN'}<=set(d.reason_codes))

    def test_no_nationwide_numeric_threshold(self):
        outputs=[]
        for gap,height in ((0.0,0.0),(0.04,0.07),(38.12,0.07),(100000.0,-100.0)):
            x=route();x['evidence'].update(separation_m=gap,height_difference_m=height,height_uncertainty_m=1.0)
            d=self.decide(x);outputs.append((d.decision_state,d.reason_codes,d.evidence_gaps))
        self.assertTrue(all(r==outputs[0] for r in outputs))

    def test_missing_mapped_line_alone_is_not_rejection(self):
        x=fixture();x['evidence']={'mapped_line_present':False}
        d=self.decide(x);self.assertEqual(d.decision_state,'OBSERVED')
        self.assertIn('MAPPED_LINE_GAP',d.reason_codes)

    def test_missing_syke_point_is_not_rejection(self):
        x=fixture();x['evidence']={'syke_point_match':False}
        self.assertEqual(self.decide(x).decision_state,'OBSERVED')

    def test_lake_candidate_at_zero_terminal_requires_review(self):
        x=route();x['route_status']='D8_ZERO_INTERIOR'
        d=self.decide(x);self.assertEqual((d.case_type,d.decision_state),('LAKE_TO_LAKE_HYPOTHESIS','REVIEW_REQUIRED'))
        self.assertIn('LAND_D8_ZERO_TERMINAL',d.reason_codes)

    def test_raw_zero_terminal_remains_observation(self):
        x=route();x['route_status']='D8_ZERO_INTERIOR';x['evidence']['directed_hypothesis']=False
        self.assertEqual(self.decide(x).decision_state,'OBSERVED')

    def test_syke_shore_point_is_auxiliary_only(self):
        x=fixture();aux=source('syke-points','SYKE_OUTLETS','AUXILIARY')
        aux.update(reference_role='AUXILIARY_CONCORDANCE')
        x['provenance']['sources'].append(aux);x['evidence'].update(syke_point_match=True,separation_m=0.04)
        d=self.decide(x);self.assertIn('SYKE_AUXILIARY_MATCH',d.reason_codes)
        self.assertEqual(d.decision_state,'OBSERVED');self.assertIn(('syke-points','AUXILIARY'),d.source_roles)
        self.assertIn('INDEPENDENCE_UNVERIFIED',d.reason_codes)

    def test_same_catchment_not_flow_direction(self):
        x=fixture();aux=source('catchment','SYKE_CATCHMENTS','AUXILIARY');aux['reference_role']='AUXILIARY_CONCORDANCE'
        x['provenance']['sources'].append(aux);x['evidence']['same_catchment']=True
        self.assertEqual(self.decide(x).decision_state,'OBSERVED')

    def test_input_role_stays_input(self):
        d=self.decide(fixture());self.assertEqual({role for _,role in d.source_roles},{'INPUT'})

    def test_unknown_use_history_stays_unknown_not_holdout(self):
        x=fixture();aux=source('unknown-syke','SYKE_OUTLETS','AUXILIARY')
        aux.update(reference_role='REFERENCE_USE_UNKNOWN',used_in_build_or_candidate_review='UNKNOWN',
                   shared_lineage='UNKNOWN',source_version='UNKNOWN',verification_state='UNKNOWN')
        x['provenance']['sources'].append(aux)
        d=self.decide(x);self.assertIn('PROVENANCE_UNRESOLVED',d.reason_codes)
        self.assertEqual(d.provenance.sources[-1].reference_role,'REFERENCE_USE_UNKNOWN')

    def test_heldout_comparison_never_hydrological_validation(self):
        x=route();x['provenance']['sources'].append(reference());x['evidence']['independence_state']='COMPARISON_REPORTED'
        d=self.decide(x);self.assertNotIn('INDEPENDENCE_UNVERIFIED',d.reason_codes)
        self.assertEqual(d.independent_validation_state,'NOT_ASSESSED')

    def test_return_and_cycle_review(self):
        for status in ('RETURNS_TO_ORIGIN_LAKE','D8_CYCLE'):
            with self.subTest(status=status):
                x=route();x['route_status']=status;d=self.decide(x)
                self.assertEqual(d.decision_state,'REVIEW_REQUIRED');self.assertIn('CYCLE_OR_RETURN',d.reason_codes)

    def test_unverified_tile_exit_review_no_fabricated_neighbor(self):
        x=route();x['route_status']='D8_DOMAIN_EXIT';x['terminal_cell']=None
        d=self.decide(x);self.assertEqual(d.decision_state,'REVIEW_REQUIRED')
        self.assertIn('TILE_CROSSING_UNVERIFIED',d.reason_codes);self.assertIsNone(d.observation.terminal_cell)

    def test_reported_tile_verification_is_not_our_verification(self):
        x=route();x['evidence']['tile_crossing']='REPORTED_VERIFIED'
        self.assertEqual(self.decide(x).decision_state,'REVIEW_REQUIRED')

    def test_step_limit_is_censored_not_completed(self):
        x=route();x['route_status']='STEP_LIMIT';x['terminal_cell']=None
        d=self.decide(x);self.assertEqual(d.decision_state,'REVIEW_REQUIRED')
        self.assertIn('ROUTE_UNRESOLVED',d.reason_codes)

    def test_existing_02f_missing_invalid_and_edge_statuses_review(self):
        for status in ('D8_POINTER_NA','D8_POINTER_INVALID','D8_ZERO_AT_RASTER_EDGE'):
            with self.subTest(status=status):
                x=route();x['route_status']=status
                d=self.decide(x);self.assertEqual(d.decision_state,'REVIEW_REQUIRED')
                self.assertEqual(d.observation.route_status,status)

    def test_summary_does_not_supply_intermediate_chain(self):
        d=self.decide(route());self.assertIn('ROUTE_GEOMETRY_SUMMARY_ONLY',d.reason_codes)
        self.assertIn('INTERMEDIATE_CHAIN_NOT_ASSESSED',d.evidence_gaps)
        self.assertEqual(d.observation.route_geometry,'SUMMARY_ONLY')

    def test_summary_continuity_claim_reviews(self):
        x=route();x['evidence']['claims_continuous']=True
        d=self.decide(x);self.assertEqual(d.decision_state,'REVIEW_REQUIRED')
        self.assertIn('UNSUPPORTED_CONTINUITY_CLAIM',d.reason_codes)

    def test_reported_full_chain_cannot_clear_continuity_review(self):
        x=route();x['route_geometry']='FULL_CHAIN_REPORTED';x['evidence']['claims_continuous']=True
        d=self.decide(x);self.assertEqual(d.decision_state,'REVIEW_REQUIRED')
        self.assertEqual(d.route_chain_assessment,'NOT_ASSESSED')
        self.assertIn('UNSUPPORTED_CONTINUITY_CLAIM',d.reason_codes)

    def test_continuity_claim_without_route_reviews(self):
        x=fixture();x['evidence']['claims_continuous']=True
        self.assertEqual(self.decide(x).decision_state,'REVIEW_REQUIRED')

    def test_functioning_outflow_proposal_requires_review(self):
        x=route();x['evidence']['proposes_functioning_outflow']=True
        self.assertEqual(self.decide(x).decision_state,'REVIEW_REQUIRED')

    def test_unknown_uncertainty_not_zero(self):
        x=route();x['evidence']['height_difference_m']=0.07
        d=self.decide(x);self.assertEqual(d.decision_state,'REVIEW_REQUIRED')
        self.assertIsNone(d.observation.evidence.height_uncertainty_m)

    def test_explicit_zero_uncertainty_is_preserved_not_assumed(self):
        x=route();x['evidence'].update(height_difference_m=0.07,height_uncertainty_m=0.0)
        d=self.decide(x);self.assertEqual(d.observation.evidence.height_uncertainty_m,0.0)
        self.assertIn('HEIGHT_CONSTRAINTS_NOT_ASSESSED',d.evidence_gaps)

    def test_unknown_receiver_not_invented(self):
        x=route();x.update(receiver_type='UNKNOWN',receiver_id=None)
        d=self.decide(x);self.assertEqual(d.decision_state,'REVIEW_REQUIRED');self.assertIsNone(d.observation.receiver_id)

    def test_missing_river_feature_id_not_invented(self):
        x=route();x.update(receiver_type='RIVER_LINE',receiver_id=None,route_status='REACHES_RIVER_LINE')
        d=self.decide(x);self.assertEqual(d.decision_state,'CANDIDATE');self.assertIsNone(d.observation.receiver_id)
        self.assertIn('RECEIVER_FEATURE_ID_NOT_ASSESSED',d.evidence_gaps)

    def test_no_scientific_observation_is_not_assessed(self):
        x=fixture();x['component_id']=None;x['evidence']={}
        self.assertEqual(self.decide(x).decision_state,'NOT_ASSESSED')

    def test_contradictory_receivers_review(self):
        x=route();x['evidence']['receiver_claims']=[dict(receiver_type='LAKE',receiver_id=303,source_path_or_id='synthetic-mask')]
        d=self.decide(x);self.assertEqual(d.decision_state,'REVIEW_REQUIRED')
        self.assertIn('CONTRADICTORY_RECEIVERS',d.reason_codes)

    def test_explicit_bound_negative_report_can_be_rejected(self):
        x=proof(fixture());d=self.decide(x)
        self.assertEqual(d.decision_state,'REJECTED');self.assertIn('DOCUMENTED_IMPOSSIBILITY',d.reason_codes)

    def test_auxiliary_impossibility_claim_requires_review(self):
        x=proof(fixture());x['evidence']['impossibility']['source_path_or_id']='synthetic-mask'
        d=self.decide(x);self.assertEqual(d.decision_state,'REVIEW_REQUIRED')
        self.assertIn('IMPOSSIBILITY_REFERENCE_UNVERIFIED',d.reason_codes)

    def test_syke_holdout_comparison_is_not_physical_impossibility_proof(self):
        x=proof(fixture());x['provenance']['sources'][-1]['kind']='SYKE_OUTLETS'
        x['evidence']['syke_point_match']=True
        d=self.decide(x);self.assertEqual(d.decision_state,'REVIEW_REQUIRED')
        self.assertIn('SYKE_AUXILIARY_MATCH',d.reason_codes)

    def test_negative_report_against_positive_claim_reviews(self):
        d=self.decide(proof(route()));self.assertEqual(d.decision_state,'REVIEW_REQUIRED')
        self.assertIn('CONTRADICTORY_EVIDENCE',d.reason_codes)

    def test_all_simultaneous_reasons_retained(self):
        x=route();x['route_status']='D8_ZERO_INTERIOR';x['component_id']=None
        x['evidence'].update(component_status='ABSENT',water_classes=[3,1],classification_02c='MIXED',
          footprint_intersects=True,center_intersects=False,mapped_line_present=False,
          height_difference_m=0.07,claims_continuous=True,tile_crossing='UNVERIFIED')
        d=self.decide(x);self.assertEqual(d.decision_state,'REVIEW_REQUIRED')
        expected={'LAND_D8_ZERO_TERMINAL','MIXED_WATER_NEIGHBORS','COMPONENTLESS_OBSERVATION',
          'BOUNDARY_FOOTPRINT_ONLY','MAPPED_LINE_GAP','ROUTE_GEOMETRY_SUMMARY_ONLY',
          'LOW_GRADIENT_UNCERTAIN','UNSUPPORTED_CONTINUITY_CLAIM','TILE_CROSSING_UNVERIFIED','INDEPENDENCE_UNVERIFIED'}
        self.assertTrue(expected<=set(d.reason_codes))
        self.assertEqual(set(d.reason_codes),{code for code,_ in d.reason_evidence})
        self.assertTrue(all(paths for _,paths in d.reason_evidence))


class GroupingTests(SafetyCase):
    def group(self,rows):
        before=deepcopy(rows);g=self.safe(s1.group_routes(rows));self.assertEqual(rows,before)
        self.assertIsNone(g.independent_route_count);self.assertEqual(g.flow_accumulation,'NOT_COMPUTED')
        return g

    def test_six_starts_one_terminal_not_six_independent_channels(self):
        rows=[route(i) for i in range(1,7)]
        for r in rows:r['route_status']='D8_ZERO_INTERIOR'
        g=self.group(rows);self.assertEqual((g.input_record_count,g.unique_route_count,len(g.cases),len(g.terminals)),(6,6,6,1))
        self.assertEqual(g.terminals[0].route_ids,tuple(f'route-{i}' for i in range(1,7)))
        self.assertIn('MULTIPLE_STARTS_ONE_TERMINAL',g.reason_codes)
        self.assertEqual(len(g.terminals[0].case_keys),6)

    def test_exact_replay_not_new_route_or_new_terminal(self):
        a=route();g=self.group([a,deepcopy(a)])
        self.assertEqual((g.input_record_count,g.unique_route_count,len(g.cases),len(g.terminals)),(2,1,1,1))
        self.assertEqual(g.cases[0].record_count,2);self.assertNotIn('MULTIPLE_STARTS_ONE_TERMINAL',g.reason_codes)

    def test_distinct_observation_ids_keep_same_route_identity(self):
        a=route();b=deepcopy(a);b['observation_id']='second-copy'
        g=self.group([a,b]);self.assertEqual(g.unique_route_count,1)
        self.assertEqual(g.cases[0].observation_ids,('observation-1','second-copy'))

    def test_parallel_shore_edges_share_one_original_02f_route(self):
        a=route();b=deepcopy(a);b.update(observation_id='second-shore',source_cell=a['source_cell']+1)
        g=self.group([a,b]);self.assertEqual((g.input_record_count,g.unique_route_count,len(g.cases)),(2,1,1))
        self.assertEqual(g.cases[0].source_cells,(a['source_cell'],b['source_cell']))

    def test_same_trace_conflicting_hypotheses_preserved_for_review(self):
        a=route();b=deepcopy(a);b.update(observation_id='other-hypothesis',receiver_id=303)
        g=self.group([a,b]);self.assertEqual(g.unique_route_count,1)
        self.assertEqual(len(g.observations),2)
        self.assertEqual(g.cases[0].decision_state,'REVIEW_REQUIRED')

    def test_conflicting_route_identity_stops(self):
        a=route();b=deepcopy(a);b['observation_id']='other';b['start_receiver_cell']+=1
        with self.assertRaisesRegex(s1.SchemaStop,'ROUTE_ID_CONFLICT'):self.group([a,b])

    def test_conflicting_observation_id_stops(self):
        a=route();b=deepcopy(a);b['terminal_cell']+=1
        with self.assertRaisesRegex(s1.SchemaStop,'OBSERVATION_ID_CONFLICT'):self.group([a,b])

    def test_same_origin_receiver_incompatible_trace_stops(self):
        a=route();b=deepcopy(a);b.update(observation_id='other',route_id='other',terminal_cell=19000)
        with self.assertRaisesRegex(s1.SchemaStop,'ORIGIN_RECEIVER_TRACE_CONFLICT'):self.group([a,b])

    def test_same_start_distinct_report_ids_remain_one_case(self):
        a=route();b=deepcopy(a);b.update(observation_id='other',route_id='other')
        g=self.group([a,b]);self.assertEqual(len(g.cases),1);self.assertEqual(g.unique_route_count,2)
        self.assertEqual(g.cases[0].route_ids,('other','route-1'))
        self.assertNotIn('MULTIPLE_STARTS_ONE_TERMINAL',g.reason_codes)

    def test_source_versions_must_not_mix(self):
        a=route(1);b=route(2);b['provenance']['manifest_sha256']='c'*64
        with self.assertRaisesRegex(s1.SchemaStop,'SOURCE_VERSION_CONFLICT'):self.group([a,b])

    def test_same_cell_in_distinct_tiles_is_not_deduplicated(self):
        a=route();b=deepcopy(a)
        b['grid']['grid_id']='OTHER-TILE';b['provenance']['grid']['grid_id']='OTHER-TILE'
        b['evidence']['tile_crossing']='UNVERIFIED'
        g=self.group([a,b]);self.assertEqual((g.unique_route_count,len(g.cases),len(g.terminals)),(2,2,2))
        self.assertTrue(any(c.decision_state=='REVIEW_REQUIRED' for c in g.cases))

    def test_unknown_terminals_not_grouped_into_fake_common_issue(self):
        rows=[route(1,None),route(2,None)]
        for x in rows:x['route_status']='STEP_LIMIT'
        g=self.group(rows);self.assertEqual(len(g.terminals),0);self.assertEqual(len(g.unknown_terminal_route_keys),2)
        self.assertNotIn('MULTIPLE_STARTS_ONE_TERMINAL',g.reason_codes)

    def test_shared_terminal_preserves_distinct_origins(self):
        a=route(1);b=route(2);b['origin_lake_id']=303
        g=self.group([a,b]);self.assertEqual(len(g.terminals),2)

    def test_group_receiver_conflicts_review_all_ids_kept(self):
        a=route();b=deepcopy(a);b.update(observation_id='other',route_id='other',receiver_id=303)
        g=self.group([a,b]);self.assertEqual(g.cases[0].decision_state,'REVIEW_REQUIRED')
        self.assertIn('CONTRADICTORY_RECEIVERS',g.cases[0].reason_codes)
        self.assertEqual(len(g.observations),2)

    def test_group_negative_and_positive_evidence_reviews(self):
        a=proof(route());a['evidence']['directed_hypothesis']=False
        b=deepcopy(a);b.update(observation_id='positive',route_id='positive')
        b['evidence'].update(impossibility=None,directed_hypothesis=True)
        self.assertEqual(self.decide(a).decision_state,'REJECTED')
        self.assertEqual(self.decide(b).decision_state,'CANDIDATE')
        g=self.group([a,b]);self.assertEqual(g.cases[0].decision_state,'REVIEW_REQUIRED')
        self.assertIn('CONTRADICTORY_EVIDENCE',g.cases[0].reason_codes)

    def test_censored_route_is_not_completed_using_other_summary(self):
        a=route(1,None);a['route_status']='STEP_LIMIT'
        b=route(2);g=self.group([a,b])
        self.assertEqual(g.unique_route_count,2)
        self.assertIsNone(next(x for x in g.observations if x.route_id=='route-1').terminal_cell)
        self.assertEqual(len(g.unknown_terminal_route_keys),1)

    def test_empty_input_is_empty_not_validated(self):
        g=self.group([]);self.assertEqual((g.input_record_count,g.unique_route_count),(0,0))
        self.assertEqual(g.cases,())

    def test_row_order_and_replays_deterministic(self):
        rows=[route(1),route(2),route(3),route(1)]
        expected=s1.to_plain_mapping(self.group(rows))
        for permutation in itertools.permutations(rows):
            self.assertEqual(s1.to_plain_mapping(self.group(list(permutation))),expected)


class ImmutabilityAndIsolationTests(SafetyCase):
    def test_nested_input_is_detached(self):
        x=fixture();o=s1.validate_observation(x)
        x['grid']['xmin']=0;x['evidence']['water_classes'].append(3)
        x['provenance']['sources'][0]['source_role']='AUXILIARY'
        self.assertEqual((o.grid.xmin,o.evidence.water_classes,o.provenance.sources[0].source_role),(199000.0,(1,),'INPUT'))

    def test_records_and_nested_values_immutable(self):
        o=s1.validate_observation(route());d=self.safe(s1.classify(o));g=self.safe(s1.group_routes([o]))
        for obj,name,value in ((o,'route_id','changed'),(o.grid,'ncol',1),(o.provenance.sources[0],'source_role','INDEPENDENT_REFERENCE'),
                               (o.evidence,'claims_continuous',True),(d,'routing_authorized',True),(g,'NATIONAL','OPEN')):
            with self.subTest(name=name),self.assertRaises(FrozenInstanceError):setattr(obj,name,value)
        with self.assertRaises(TypeError):o.evidence.water_classes[0]=3
        with self.assertRaises(ValueError):replace(d,routing_authorized=True)

    def test_direct_dataclass_constructor_cannot_bypass_validation(self):
        o=s1.validate_observation(route());bad=replace(o,source_cell=0)
        with self.assertRaises(s1.SchemaStop):s1.classify(bad)
        with self.assertRaises(s1.SchemaStop):s1.group_routes([bad])

    def test_classifier_does_not_accept_unvalidated_mapping(self):
        with self.assertRaisesRegex(s1.SchemaStop,'VALIDATED_OBSERVATION_REQUIRED'):s1.classify(fixture())

    def test_manual_validated_decision_constructor_is_rejected(self):
        d=self.decide(route())
        with self.assertRaisesRegex(s1.SchemaStop,'UNKNOWN_ENUM'):replace(d,decision_state='VALIDATED')

    def test_serializer_will_not_export_tampered_authorization(self):
        # Deliberately bypass Python's frozen guard to test the export boundary.
        d=self.decide(route());object.__setattr__(d,'routing_authorized',True)
        with self.assertRaisesRegex(s1.SchemaStop,'OUTPUT_AUTHORIZATION_FORBIDDEN'):s1.to_plain_mapping(d)

    def test_serializer_will_not_export_tampered_validation_or_accumulation(self):
        for name,value in (('decision_state','VALIDATED'),('independent_validation_state','PASS'),('route_chain_assessment','PASS')):
            with self.subTest(field=name):
                d=self.decide(route());object.__setattr__(d,name,value)
                with self.assertRaises(s1.SchemaStop):s1.to_plain_mapping(d)
        g=self.safe(s1.group_routes([route()]));object.__setattr__(g,'independent_route_count',121)
        with self.assertRaisesRegex(s1.SchemaStop,'UNSUPPORTED_GROUP_INFERENCE'):s1.to_plain_mapping(g)

    def test_serialization_detached_stable_and_json_finite(self):
        d=self.decide(route());a=s1.to_plain_mapping(d);text=json.dumps(a,sort_keys=True,allow_nan=False)
        a['routing_authorized']=True;a['observation']['evidence']['water_classes'].append(3)
        self.assertEqual(json.dumps(s1.to_plain_mapping(d),sort_keys=True,allow_nan=False),text)
        self.assertIn('"routing_authorized": false',text)

    def test_key_order_source_order_class_order_deterministic(self):
        x=route();x['evidence'].update(water_classes=[1,3,1],mapped_line_present=False,footprint_intersects=True,center_intersects=False)
        y=deepcopy(x);y=dict(reversed(list(y.items())))
        y['provenance']['sources'].reverse();y['evidence']=dict(reversed(list(y['evidence'].items())))
        y['evidence']['water_classes'].reverse()
        self.assertEqual(self.decide(x),self.decide(y))

    def test_prior_calls_cannot_change_a_later_decision(self):
        expected=self.decide(route())
        x=fixture();x['evidence']['water_classes']=[1,3]
        self.decide(x);self.decide(proof(fixture()))
        self.assertEqual(self.decide(route()),expected)

    def test_unsupported_serialization_types_stop(self):
        for x in ({},[],float('nan'),set()):
            with self.subTest(kind=type(x)),self.assertRaises(s1.SchemaStop):s1.to_plain_mapping(x)

    def test_import_has_no_application_io_or_execution(self):
        module=Path(s1.__file__).resolve()
        code=r'''
import importlib,os,sys
sys.path.insert(0,sys.argv[1])
for name in ("dataclasses","json","math","re","collections.abc"):importlib.import_module(name)
violations=[]
def audit(event,args):
    forbidden=event.startswith(("socket.","subprocess.","os.exec","os.spawn")) or event in ("os.system","os.remove","os.rename","os.mkdir","os.rmdir")
    if event=="open":
        mode,flags=args[1],args[2]
        forbidden=forbidden or (isinstance(mode,str) and any(c in mode for c in "wax+")) or bool(flags & (os.O_WRONLY|os.O_RDWR|os.O_CREAT|os.O_TRUNC))
    if forbidden:
        violations.append(event)
        raise RuntimeError("FORBIDDEN_IMPORT_SIDE_EFFECT:"+event)
sys.addaudithook(audit)
import decision_contract_v1
assert not violations,violations
assert not any(x in sys.modules for x in ("rasterio","osgeo","numpy","requests"))
payload=__import__('json').loads(sys.argv[2])
def no_application_reads(event,args):
    if event=="open":raise RuntimeError("APPLICATION_FILE_READ_FORBIDDEN")
sys.addaudithook(no_application_reads)
o=decision_contract_v1.validate_observation(payload)
d=decision_contract_v1.classify(o)
g=decision_contract_v1.group_routes([o,o])
decision_contract_v1.to_plain_mapping(d)
assert not g.routing_authorized and g.unique_route_count==1
print("IMPORT_SIDE_EFFECTS=NONE")
'''
        p=subprocess.run([sys.executable,'-B','-c',code,str(module.parent),json.dumps(route())],capture_output=True,text=True,timeout=10)
        self.assertEqual(p.returncode,0,p.stderr);self.assertEqual(p.stdout.strip(),'IMPORT_SIDE_EFFECTS=NONE')


if __name__=='__main__':unittest.main(verbosity=2)
