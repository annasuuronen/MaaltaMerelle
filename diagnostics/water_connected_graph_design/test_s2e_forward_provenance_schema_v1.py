"""S2E: embedded synthetic claims only; no disk fixtures or original data."""
import ast
from copy import deepcopy
from dataclasses import FrozenInstanceError, replace
from hashlib import sha256
import io
import json
from pathlib import Path
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

import s2e_forward_provenance_schema_v1 as s

RUN = "00000000-0000-4000-8000-000000000001"
ATTEMPT = "00000000-0000-4000-8000-000000000002"
OLD_RUN = "00000000-0000-4000-8000-000000000003"
OLD_ATTEMPT = "00000000-0000-4000-8000-000000000004"


def measurement(tag, state="MEASURED_SIMULATED"):
    if state in {"NOT_RUN", "NO_FILE_REPRESENTATION"}:
        return dict(state=state, sha256=None, size_bytes=None)
    payload = ("SYNTHETIC_LABEL_ONLY:" + tag).encode("ascii")
    return dict(state=state, sha256=sha256(payload).hexdigest(), size_bytes=len(payload))


def artifact(key, role, produced=False):
    raster = None
    if role in s.RASTERS:
        dtype = "Int32" if role == "LAKE_ID" else "Float64"
        nd = -2147483648 if role == "LAKE_ID" else -9999
        raster = dict(grid_id="grid-low", dtype=dtype, nodata=dict(kind="FINITE", value=nd),
                      logical_encoding="synthetic.logical.v1")
    return dict(artifact_id=key, run_id=RUN, attempt_id=ATTEMPT, role=role,
                source_type="DERIVED_FILE" if produced else "SOURCE_DATASET",
                production="PRODUCED" if produced else "SOURCE",
                producer_event_id=("evt-d8" if role == "POINTER" else "evt-02f") if produced else None,
                predecessor=None, uri="synthetic:/" + key + (".tif" if raster else ".csv"),
                file=measurement(key + ":file"),
                logical=measurement(key + ":logical", "MEASURED_SIMULATED" if raster else "NOT_RUN"),
                raster=raster)


def binding(a):
    return dict(artifact_id=a["artifact_id"], logical_sha256=a["logical"]["sha256"],
                logical_size_bytes=a["logical"]["size_bytes"], snapshot_id="snap-" + a["artifact_id"],
                guard="SNAPSHOT_CLAIM", before_sha256=None, after_sha256=None)


def fixture():
    roles = (("land", "LAND_WATER"), ("water", "WATER_CLASS"), ("lake", "LAKE_ID"),
             ("candidates", "CANDIDATE_EDGES"), ("pointer", "POINTER"),
             ("routes", "02F_ROUTES"), ("edges", "02F_EDGES"), ("summary", "02F_SUMMARY"), ("qa", "02F_QA"))
    artifacts = [artifact(k, r, i >= 4) for i, (k, r) in enumerate(roles)]
    d8 = dict(event_id="evt-d8", run_id=RUN, attempt_id=ATTEMPT, sequence=1,
              role="PRODUCE_D8", status="COMPLETE", started_tick=0, ended_tick=1,
              inputs=["land"], outputs=["pointer"], depends_on=[], bindings=[binding(artifacts[0])])
    trace = dict(event_id="evt-02f", run_id=RUN, attempt_id=ATTEMPT, sequence=2,
                 role="TRACE_02F", status="COMPLETE", started_tick=2, ended_tick=3,
                 inputs=["pointer", "water", "lake", "candidates"], outputs=["routes", "edges", "summary", "qa"],
                 depends_on=["evt-d8"], bindings=[binding(artifacts[i]) for i in (4, 1, 2)])
    return dict(schema_version=s.SCHEMA, evidence_kind="SYNTHETIC", repository="annasuuronen/MaaltaMerelle",
                commit_sha="a" * 40, run_id=RUN, attempt_id=ATTEMPT, status="COMPLETE",
                grid=dict(grid_id="grid-low", epsg=3067, rows=3, cols=4,
                          geotransform=[199000, 2, 0, 6911000, 0, -2], cell_index_base=1,
                          row_col_index_base=0, pointer_scheme="WHITEBOX_D8", esri_pntr=False),
                artifacts=artifacts, events=[d8, trace], witness=None, **s.LOCKS)


def reuse_fixture(predecessor=True):
    x = fixture()
    x["artifacts"] = [a for a in x["artifacts"] if a["role"] != "LAND_WATER"]
    p = next(a for a in x["artifacts"] if a["role"] == "POINTER")
    p.update(source_type="EXISTING_UNVERIFIED", production="REUSED", producer_event_id=None,
             predecessor=dict(run_id=OLD_RUN, attempt_id=OLD_ATTEMPT, event_id="old-d8",
                              manifest_sha256="b" * 64) if predecessor else None)
    x["events"][0].update(role="REUSE_POINTER", inputs=["pointer"], outputs=[], bindings=[binding(p)])
    return x


class S2ETests(unittest.TestCase):
    def stopped(self, value, code, *, raw=False, **kw):
        r = s.validate_json(value, **kw) if raw else s.validate_record(value, **kw)
        self.assertEqual(r.disposition, "STOP", r)
        self.assertIn(code, [reason.code for reason in r.reasons], r)
        self.assertEqual(r.producer_lineage_status, "NOT_ASSESSED")
        self.assertEqual(r.historical_02f_status, "STOP")
        self.assertFalse(r.routing_authorized)
        self.assertTrue(all(type(reason) is s.Reason for reason in r.reasons))
        return r

    def test_complete_synthetic_record_is_only_recorded_unverified(self):
        r = s.validate_record(fixture())
        self.assertEqual((r.schema_status, r.disposition, r.completeness_status),
                         ("SCHEMA_VALID", "RECORDED_UNVERIFIED", "COMPLETE_CLAIM"))
        self.assertEqual(r.checksum_status, "SIMULATED_MEASUREMENTS_RECORDED")
        self.assertEqual(r.source_authentication, "NOT_ASSESSED")

    def test_canonical_round_trip(self):
        a = s.validate_record(fixture())
        self.assertEqual(a, s.validate_json(a.record.canonical_json))
        self.assertEqual(a.record.content_sha256, sha256(a.record.canonical_json).hexdigest())

    def test_mapping_key_permutations_have_same_canonical_bytes(self):
        def reverse(x):
            if type(x) is dict:return {k: reverse(v) for k, v in reversed(list(x.items()))}
            if type(x) is list:return [reverse(v) for v in x]
            return x
        a, b = s.validate_record(fixture()), s.validate_record(reverse(fixture()))
        self.assertEqual(a, b)

    def test_json_whitespace_does_not_change_identifier(self):
        self.assertEqual(s.validate_record(fixture()), s.validate_json(json.dumps(fixture(), indent=2)))

    def test_unicode_escape_of_ascii_has_one_canonical_form(self):
        raw = json.dumps(fixture()).replace('"run_id"', '"\\u0072un_id"')
        self.assertEqual(s.validate_record(fixture()), s.validate_json(raw))

    def test_changed_commit_changes_local_content_id_not_authenticity(self):
        x = fixture();a = s.validate_record(x);x["commit_sha"] = "b" * 40;b = s.validate_record(x)
        self.assertNotEqual(a.record.content_sha256, b.record.content_sha256)
        self.assertEqual(b.producer_lineage_status, "NOT_ASSESSED")

    def test_result_and_record_are_frozen(self):
        r = s.validate_record(fixture())
        with self.assertRaises(FrozenInstanceError):r.disposition = "AUTHENTICATED"
        with self.assertRaises(FrozenInstanceError):r.record.canonical_json = b"bad"
        with self.assertRaises(FrozenInstanceError):r.reasons = ()
        self.assertIs(type(r.record.canonical_json), bytes)
        self.assertIs(type(r.record.event_ids), tuple)

    def test_input_is_unchanged_and_detached(self):
        x = fixture();before = deepcopy(x);r = s.validate_record(x)
        self.assertEqual(x, before)
        raw = r.record.canonical_json
        x["events"][1]["bindings"][0]["logical_sha256"] = "c" * 64
        self.assertEqual(r.record.canonical_json, raw)

    def test_duplicate_top_level_json_key(self):
        raw = json.dumps(fixture())
        self.stopped(raw[:-1] + ',"run_id":"' + RUN + '"}', "DUPLICATE_JSON_KEY", raw=True)

    def test_duplicate_nested_json_key_even_with_same_value(self):
        raw = json.dumps(fixture()).replace('"epsg": 3067', '"epsg":3067,"epsg":3067')
        self.stopped(raw, "DUPLICATE_JSON_KEY", raw=True)

    def test_unknown_schema_version(self):
        x = fixture();x["schema_version"] += ".2";self.stopped(x, "UNKNOWN_SCHEMA_VERSION")

    def test_unknown_top_level_command(self):
        x = fixture();x["command"] = "sbatch evil";self.stopped(x, "MISSING_OR_UNKNOWN_FIELDS")

    def test_nested_unknown_field(self):
        x = fixture();x["artifacts"][0]["mtime"] = 123;self.stopped(x, "MISSING_OR_UNKNOWN_FIELDS")

    def test_missing_required_field(self):
        x = fixture();del x["attempt_id"];self.stopped(x, "MISSING_OR_UNKNOWN_FIELDS")

    def test_nan_and_infinity_literals_are_rejected(self):
        raw = json.dumps(fixture())
        for val in ("NaN", "Infinity", "-Infinity"):
            with self.subTest(val=val):
                self.stopped(raw.replace('"rows": 3', '"rows": ' + val), "NONFINITE_JSON_NUMBER", raw=True)

    def test_float_json_id_is_rejected_without_integer_coercion(self):
        raw = json.dumps(fixture()).replace('"sequence": 1', '"sequence": 1.0')
        self.stopped(raw, "UNSUPPORTED_JSON_VALUE", raw=True)

    def test_float_in_memory_no_data_is_rejected(self):
        x = fixture();x["artifacts"][0]["raster"]["nodata"]["value"] = -9999.0
        self.stopped(x, "UNSUPPORTED_JSON_VALUE")

    def test_boolean_is_not_an_integer_grid_dimension(self):
        x = fixture();x["grid"]["rows"] = True;self.stopped(x, "EXACT_INTEGER_REQUIRED")

    def test_invalid_utf8(self):
        self.stopped(b'\xff', "INVALID_UTF8", raw=True)

    def test_invalid_json_trailing_data(self):
        self.stopped(json.dumps(fixture()) + '{}', "INVALID_JSON", raw=True)

    def test_non_ascii_confusable_identifier(self):
        x = fixture();x["artifacts"][0]["artifact_id"] = "l\u0430nd";self.stopped(x, "NONCANONICAL_TEXT")

    def test_nfd_combining_text_is_rejected_not_silently_normalized(self):
        x = fixture();x["artifacts"][0]["uri"] = "synthetic:/e\u0301.tif";self.stopped(x, "NONCANONICAL_TEXT")

    def test_embedded_control_characters(self):
        x = fixture();x["artifacts"][0]["uri"] = "synthetic:/a\n.tif";self.stopped(x, "NONCANONICAL_TEXT")

    def test_malformed_or_uppercase_commit(self):
        for val in ("bad", "A" * 40, "0" * 40):
            with self.subTest(val=val):
                x = fixture();x["commit_sha"] = val;self.stopped(x, "INVALID_DIGEST")

    def test_run_and_attempt_cannot_reuse_identity(self):
        x = fixture();x["attempt_id"] = RUN;self.stopped(x, "RUN_ID_REUSE")

    def test_known_prior_run_cannot_be_reused(self):
        self.stopped(fixture(), "RUN_ID_REUSE", used_run_ids=(RUN,))

    def test_attempt_cannot_reuse_known_prior_id(self):
        self.stopped(fixture(), "RUN_ID_REUSE", used_run_ids=(ATTEMPT,))

    def test_new_run_with_unrelated_prior_context_stays_unverified(self):
        r = s.validate_record(fixture(), used_run_ids=(OLD_RUN,))
        self.assertEqual(r.disposition, "RECORDED_UNVERIFIED")

    def test_invalid_prior_id_context(self):
        self.stopped(fixture(), "INVALID_PRIOR_ID_CONTEXT", used_run_ids=[OLD_RUN])

    def test_malformed_uuid(self):
        x = fixture();x["run_id"] = "old-run";self.stopped(x, "INVALID_UUID4")

    def test_wrong_event_run_scope(self):
        x = fixture();x["events"][1]["run_id"] = OLD_RUN;self.stopped(x, "RUN_SCOPE_MISMATCH")

    def test_wrong_artifact_attempt_scope(self):
        x = fixture();x["artifacts"][4]["attempt_id"] = OLD_ATTEMPT;self.stopped(x, "RUN_SCOPE_MISMATCH")

    def test_duplicate_artifact_id(self):
        x = fixture();x["artifacts"].append(deepcopy(x["artifacts"][0]));self.stopped(x, "DUPLICATE_ID")

    def test_duplicate_event_id(self):
        x = fixture();x["events"][1]["event_id"] = "evt-d8";self.stopped(x, "DUPLICATE_ID")

    def test_artifact_event_namespace_collision(self):
        x = fixture();x["artifacts"][0]["artifact_id"] = "evt-d8";self.stopped(x, "DUPLICATE_ID")

    def test_alias_uri_for_two_artifacts(self):
        x = fixture();x["artifacts"][0]["uri"] = x["artifacts"][1]["uri"];self.stopped(x, "ARTIFACT_URI_ALIAS")

    def test_real_scratch_uri_is_not_supported(self):
        x = fixture();x["artifacts"][0]["uri"] = "/scratch/project_2004707/a.tif"
        self.stopped(x, "SYNTHETIC_URI_REQUIRED")

    def test_traversal_uri(self):
        x = fixture();x["artifacts"][0]["uri"] = "synthetic:/../a.tif";self.stopped(x, "UNSAFE_URI")

    def test_executable_uri_payload(self):
        x = fixture();x["artifacts"][0]["uri"] = "synthetic:/$(touch_pwn).tif";self.stopped(x, "UNSAFE_URI")

    def test_wrong_pointer_scheme(self):
        x = fixture();x["grid"]["pointer_scheme"] = "ESRI_D8";self.stopped(x, "POINTER_CONVENTION")

    def test_esri_flag_cannot_be_true_or_integer_zero(self):
        for val in (True, 0):
            with self.subTest(val=val):
                x = fixture();x["grid"]["esri_pntr"] = val;self.stopped(x, "POINTER_CONVENTION")

    def test_wrong_grid_affine_rotation_or_resolution(self):
        x = fixture();x["grid"]["geotransform"][1] = 4;self.stopped(x, "INVALID_GRID")
        x = fixture();x["grid"]["geotransform"][2] = 1;self.stopped(x, "INVALID_GRID")

    def test_wrong_grid_crs(self):
        x = fixture();x["grid"]["epsg"] = 4326;self.stopped(x, "INVALID_CONSTANT")

    def test_artifact_wrong_grid_identity(self):
        x = fixture();x["artifacts"][4]["raster"]["grid_id"] = "other-grid";self.stopped(x, "GRID_SCOPE_MISMATCH")

    def test_pointer_float32_cannot_hide_rounding(self):
        x = fixture();x["artifacts"][4]["raster"]["dtype"] = "Float32";self.stopped(x, "POINTER_DTYPE")

    def test_zero_cannot_be_pointer_nodata(self):
        x = fixture();x["artifacts"][4]["raster"]["nodata"]["value"] = 0;self.stopped(x, "INVALID_NODATA")

    def test_water_class_cannot_mask_known_water(self):
        x = fixture();x["artifacts"][1]["raster"]["nodata"]["value"] = 1;self.stopped(x, "INVALID_NODATA")

    def test_positive_lake_id_cannot_be_nodata(self):
        x = fixture();x["artifacts"][2]["raster"]["nodata"]["value"] = 1892;self.stopped(x, "INVALID_NODATA")

    def test_valid_zero_nodata_for_water_is_not_missing_value(self):
        x = fixture();x["artifacts"][1]["raster"]["nodata"]["value"] = 0
        r = s.validate_record(x)
        self.assertEqual(r.disposition, "RECORDED_UNVERIFIED")
        self.assertIn(b'"kind":"FINITE","value":0', r.record.canonical_json)

    def test_explicit_r_na_and_nan_tags_are_distinct(self):
        x = fixture();x["artifacts"][4]["raster"]["nodata"] = dict(kind="R_NA", value=None)
        a = s.validate_record(x);x["artifacts"][4]["raster"]["nodata"]["kind"] = "NAN";b = s.validate_record(x)
        self.assertEqual((a.disposition, b.disposition), ("RECORDED_UNVERIFIED",) * 2)
        self.assertNotEqual(a.record.content_sha256, b.record.content_sha256)

    def test_integer_band_cannot_claim_nan_nodata(self):
        x = fixture();x["artifacts"][2]["raster"]["nodata"] = dict(kind="NAN", value=None)
        self.stopped(x, "INVALID_NODATA")

    def test_dtype_nodata_range(self):
        x = fixture();x["artifacts"][2]["raster"]["nodata"]["value"] = -2**31 - 1
        self.stopped(x, "EXACT_INTEGER_REQUIRED")

    def test_measured_hash_cannot_be_placeholder_zero(self):
        x = fixture();x["artifacts"][0]["file"]["sha256"] = "0" * 64;self.stopped(x, "INVALID_DIGEST")

    def test_unknown_hash_and_size_are_null_not_zero(self):
        x = fixture();x["artifacts"][0]["file"] = dict(state="NOT_RUN", sha256="0" * 64, size_bytes=0)
        self.stopped(x, "UNKNOWN_IS_NOT_ZERO")

    def test_measured_size_cannot_be_zero(self):
        x = fixture();x["artifacts"][0]["file"]["size_bytes"] = 0;self.stopped(x, "EXACT_INTEGER_REQUIRED")

    def test_real_measured_label_is_not_supported(self):
        x = fixture();x["artifacts"][0]["file"]["state"] = "MEASURED";self.stopped(x, "UNSUPPORTED_ENUM")

    def test_declared_hashes_are_only_claims(self):
        x = fixture()
        for a in x["artifacts"]:
            for key in ("file", "logical"):
                if a[key]["state"] == "MEASURED_SIMULATED":a[key]["state"] = "DECLARED"
        r = s.validate_record(x)
        self.assertEqual((r.disposition, r.checksum_status, r.producer_lineage_status),
                         ("RECORDED_UNVERIFIED", "CLAIMS_ONLY", "NOT_ASSESSED"))

    def test_present_metadata_does_not_authenticate_historical_02f(self):
        x = fixture();x["evidence_kind"] = "HISTORICAL_02F";self.stopped(x, "SYNTHETIC_ONLY")

    def test_attempt_to_upgrade_producer_lineage_rejected(self):
        x = fixture();x["producer_lineage_status"] = "VERIFIED_IN_DECLARED_SCOPE"
        self.stopped(x, "FORBIDDEN_SCIENCE_OR_AUTHENTICATION_CLAIM")

    def test_attempt_to_authenticate_source_rejected(self):
        x = fixture();x["source_authentication"] = "VERIFIED";self.stopped(x, "FORBIDDEN_SCIENCE_OR_AUTHENTICATION_CLAIM")

    def test_fake_embedded_witness_key_and_signature_rejected(self):
        x = fixture();x["witness"] = dict(public_key="fake", signature="fake", verified=True)
        self.stopped(x, "EXTERNAL_WITNESS_NOT_IMPLEMENTED")

    def test_separate_signature_field_is_not_an_authentication_api(self):
        x = fixture();x["signature"] = "self-signed";self.stopped(x, "MISSING_OR_UNKNOWN_FIELDS")

    def test_science_validated_decision_rejected(self):
        for field in ("hydrological_validation", "channel_interpretation"):
            with self.subTest(field=field):
                x = fixture();x[field] = "VALIDATED";self.stopped(x, "FORBIDDEN_SCIENCE_OR_AUTHENTICATION_CLAIM")

    def test_routing_authorized_true_rejected(self):
        x = fixture();x["routing_authorized"] = True;self.stopped(x, "FORBIDDEN_SCIENCE_OR_AUTHENTICATION_CLAIM")

    def test_outlet_assignment_rejected(self):
        x = fixture();x["outlet_selection"] = "ACCEPTED";self.stopped(x, "FORBIDDEN_SCIENCE_OR_AUTHENTICATION_CLAIM")

    def test_national_and_moderate_unlock_rejected(self):
        for field in ("NATIONAL", "MODERATE"):
            with self.subTest(field=field):
                x = fixture();x[field] = "UNLOCKED";self.stopped(x, "FORBIDDEN_SCIENCE_OR_AUTHENTICATION_CLAIM")

    def test_unknown_approval_boolean_rejected(self):
        x = fixture();x["approved"] = True;self.stopped(x, "MISSING_OR_UNKNOWN_FIELDS")

    def test_missing_effective_pointer_binding_is_stop_not_complete(self):
        x = fixture();x["events"][1]["bindings"] = x["events"][1]["bindings"][1:]
        r = self.stopped(x, "EFFECTIVE_INPUT_BINDING_MISSING")
        self.assertEqual((r.schema_status, r.declared_status, r.completeness_status),
                         ("SCHEMA_VALID", "COMPLETE", "INCOMPLETE"))

    def test_pointer_binding_substitution(self):
        x = fixture();x["events"][1]["bindings"][0]["logical_sha256"] = "f" * 64
        self.stopped(x, "EFFECTIVE_INPUT_MISMATCH")

    def test_pointer_binding_size_substitution(self):
        x = fixture();x["events"][1]["bindings"][0]["logical_size_bytes"] += 1
        self.stopped(x, "EFFECTIVE_INPUT_MISMATCH")

    def test_binding_to_another_artifact_not_an_input(self):
        x = fixture();x["events"][1]["bindings"][0]["artifact_id"] = "routes"
        self.stopped(x, "BINDING_ARTIFACT_MISMATCH")

    def test_duplicate_binding(self):
        x = fixture();x["events"][1]["bindings"][1] = deepcopy(x["events"][1]["bindings"][0])
        self.stopped(x, "BINDING_ARTIFACT_MISMATCH")

    def test_in_memory_input_has_no_fabricated_file_identity(self):
        x = fixture();a = x["artifacts"][4]
        a.update(source_type="IN_MEMORY", uri=None, file=measurement("none", "NO_FILE_REPRESENTATION"))
        r = s.validate_record(x)
        self.assertEqual(r.disposition, "RECORDED_UNVERIFIED")
        self.assertIn(b'"NO_FILE_REPRESENTATION"', r.record.canonical_json)

    def test_file_hash_cannot_stand_for_memory_values(self):
        x = fixture();x["artifacts"][4]["source_type"] = "IN_MEMORY"
        self.stopped(x, "MEMORY_IS_NOT_FILE")

    def test_memory_missing_logical_identity_cannot_complete(self):
        x = fixture();a = x["artifacts"][4]
        a.update(source_type="IN_MEMORY", uri=None, file=measurement("none", "NO_FILE_REPRESENTATION"),
                 logical=measurement("none", "NOT_RUN"))
        self.stopped(x, "EFFECTIVE_INPUT_MISMATCH")

    def test_memory_endpoint_claims_use_logical_not_former_file_digest(self):
        x = fixture();a = x["artifacts"][4];old_file_digest = a["file"]["sha256"]
        a.update(source_type="IN_MEMORY", uri=None, file=measurement("none", "NO_FILE_REPRESENTATION"))
        b = x["events"][1]["bindings"][0]
        b.update(before_sha256=old_file_digest, after_sha256=old_file_digest)
        self.stopped(x, "SOURCE_VERSION_MISMATCH")
        b.update(before_sha256=a["logical"]["sha256"], after_sha256=a["logical"]["sha256"])
        self.assertEqual(s.validate_record(x).disposition, "RECORDED_UNVERIFIED")

    def test_equal_before_after_hashes_do_not_exclude_a_b_a(self):
        x = fixture();b = x["events"][1]["bindings"][0]
        digest = x["artifacts"][4]["file"]["sha256"]
        b.update(guard="ENDPOINT_HASHES_ONLY", snapshot_id=None, before_sha256=digest, after_sha256=digest)
        r = self.stopped(x, "IMMUTABLE_BINDING_NOT_RECORDED")
        self.assertEqual(r.schema_status, "SCHEMA_VALID")

    def test_different_before_after_hashes_are_contradictory_claims(self):
        x = fixture();b = x["events"][1]["bindings"][0]
        b.update(before_sha256="b" * 64, after_sha256="c" * 64)
        self.stopped(x, "SOURCE_MUTATION_CLAIM")

    def test_equal_endpoint_hashes_cannot_reference_another_file_version(self):
        x = fixture();b = x["events"][1]["bindings"][0]
        b.update(before_sha256="b" * 64, after_sha256="b" * 64)
        self.stopped(x, "SOURCE_VERSION_MISMATCH")

    def test_single_endpoint_hash_is_bound_to_declared_source(self):
        x = fixture();x["events"][1]["bindings"][0]["before_sha256"] = "b" * 64
        self.stopped(x, "SOURCE_VERSION_MISMATCH")

    def test_matching_snapshot_endpoint_claims_still_do_not_authenticate(self):
        x = fixture();b = x["events"][1]["bindings"][0];digest = x["artifacts"][4]["file"]["sha256"]
        b.update(before_sha256=digest, after_sha256=digest)
        self.assertEqual(s.validate_record(x).disposition, "RECORDED_UNVERIFIED")

    def test_unknown_guard_not_forged_by_snapshot_name(self):
        x = fixture();x["events"][1]["bindings"][0]["guard"] = "NOT_ASSESSED"
        self.stopped(x, "GUARD_SNAPSHOT_MISMATCH")

    def test_snapshot_claim_is_not_a_witness(self):
        r = s.validate_record(fixture())
        self.assertEqual(r.disposition, "RECORDED_UNVERIFIED")
        self.assertEqual((r.source_authentication, r.producer_lineage_status), ("NOT_ASSESSED",) * 2)

    def test_event_reordering_is_rejected_not_canonically_sorted_away(self):
        x = fixture();x["events"].reverse();self.stopped(x, "EVENT_SEQUENCE")

    def test_renumbering_reordered_events_still_breaks_dependency(self):
        x = fixture();x["events"].reverse()
        for i, e in enumerate(x["events"], 1):e["sequence"] = i
        self.stopped(x, "DEPENDENCY_ORDER")

    def test_cyclic_dependency_is_rejected(self):
        x = fixture();x["events"][0]["depends_on"] = ["evt-02f"];self.stopped(x, "DEPENDENCY_ORDER")

    def test_self_dependency_is_rejected(self):
        x = fixture();x["events"][0]["depends_on"] = ["evt-d8"];self.stopped(x, "DEPENDENCY_ORDER")

    def test_consumer_without_producer_dependency(self):
        x = fixture();x["events"][1]["depends_on"] = [];self.stopped(x, "PRODUCER_LINK_MISMATCH")

    def test_missing_artifact_reference(self):
        x = fixture();x["events"][1]["inputs"][0] = "missing";self.stopped(x, "MISSING_ARTIFACT")

    def test_role_swapped_pointer_and_water_cannot_hide_as_input(self):
        x = fixture();x["artifacts"][4]["role"] = "WATER_CLASS";self.stopped(x, "PRODUCTION_ROLE_MISMATCH")

    def test_consumer_cannot_treat_pointer_as_unproduced_source(self):
        x = fixture();a = x["artifacts"][4]
        a.update(production="SOURCE", source_type="SOURCE_DATASET", producer_event_id=None)
        self.stopped(x, "PRODUCTION_ROLE_MISMATCH")

    def test_source_cannot_be_claimed_as_produced_output(self):
        x = fixture();x["artifacts"][5]["source_type"] = "SOURCE_DATASET"
        self.stopped(x, "PRODUCTION_ROLE_MISMATCH")

    def test_wrong_producer_event_identity(self):
        x = fixture();x["artifacts"][5]["producer_event_id"] = "evt-d8";self.stopped(x, "PRODUCER_LINK_MISMATCH")

    def test_output_cannot_also_be_input_in_same_event(self):
        x = fixture();x["events"][1]["outputs"][0] = "pointer";self.stopped(x, "DOUBLE_PRODUCTION")

    def test_missing_one_required_02f_output(self):
        x = fixture();x["events"][1]["outputs"].remove("qa");self.stopped(x, "STAGE_ROLE_MISMATCH")

    def test_output_identity_missing_prevents_complete(self):
        x = fixture();x["artifacts"][5]["file"] = measurement("none", "NOT_RUN")
        self.stopped(x, "ARTIFACT_IDENTITY_MISSING")

    def test_missing_runtime_stages_cannot_complete(self):
        x = fixture();x.update(events=[], artifacts=[]);self.stopped(x, "REQUIRED_STAGE_MISSING")

    def test_unreferenced_artifact_is_not_hidden_evidence(self):
        x = reuse_fixture();x["artifacts"].append(artifact("orphan", "LAND_WATER"));self.stopped(x, "ORPHAN_ARTIFACT")

    def test_duplicate_source_role_cannot_hide_a_second_input_version(self):
        x = fixture();x["artifacts"].append(artifact("other-water", "WATER_CLASS"))
        self.stopped(x, "CONFLICTING_ARTIFACT_ROLE")

    def test_reused_existing_pointer_without_lineage_stops(self):
        r = self.stopped(reuse_fixture(False), "MISSING_CLAIMED_PRODUCER_LINK")
        self.assertEqual(r.schema_status, "SCHEMA_VALID")
        self.assertEqual(r.producer_lineage_status, "NOT_ASSESSED")

    def test_reused_pointer_with_claimed_predecessor_is_still_unverified(self):
        r = s.validate_record(reuse_fixture())
        self.assertEqual(r.disposition, "RECORDED_UNVERIFIED")
        self.assertEqual(r.historical_02f_status, "STOP")

    def test_reuse_is_not_relabelled_as_new_generation(self):
        x = reuse_fixture();x["artifacts"][3]["production"] = "PRODUCED"
        self.stopped(x, "PRODUCTION_ROLE_MISMATCH")

    def test_reused_pointer_requires_reuse_event(self):
        x = reuse_fixture();x["events"][1]["depends_on"] = [];self.stopped(x, "REUSE_LINK_MISSING")

    def test_predecessor_scope_cannot_impersonate_current_run(self):
        x = reuse_fixture();x["artifacts"][3]["predecessor"]["run_id"] = RUN
        self.stopped(x, "RUN_SCOPE_MISMATCH")

    def test_reused_predecessor_claim_cannot_embed_verified_flag(self):
        x = reuse_fixture();x["artifacts"][3]["predecessor"]["verified"] = True
        self.stopped(x, "MISSING_OR_UNKNOWN_FIELDS")

    def test_backwards_stage_lifecycle(self):
        x = fixture();x["events"][1]["ended_tick"] = 1;self.stopped(x, "LIFECYCLE_ORDER")

    def test_overlapping_sequential_stages_rejected(self):
        x = fixture();x["events"][1]["started_tick"] = 0;self.stopped(x, "LIFECYCLE_ORDER")

    def test_complete_event_requires_ending(self):
        x = fixture();x["events"][1]["ended_tick"] = None;self.stopped(x, "LIFECYCLE_ORDER")

    def test_not_run_event_cannot_claim_an_execution(self):
        x = fixture();x["events"][1]["status"] = "NOT_RUN";self.stopped(x, "LIFECYCLE_ORDER")

    def test_not_run_incomplete_and_stop_are_distinct(self):
        for status in ("NOT_RUN", "INCOMPLETE", "STOP"):
            with self.subTest(status=status):
                x = fixture();x.update(status=status, events=[], artifacts=[])
                r = self.stopped(x, "RUN_" + status)
                self.assertEqual((r.schema_status, r.declared_status, r.completeness_status),
                                 ("SCHEMA_VALID", status, status))

    def test_failed_then_not_run_stages_preserve_partial_record(self):
        x = fixture();x["status"] = "INCOMPLETE"
        x["events"][0]["status"] = "STOP"
        x["events"][1].update(status="NOT_RUN", started_tick=None, ended_tick=None, bindings=[])
        for a in x["artifacts"]:
            if a["production"] == "PRODUCED":
                a["file"] = measurement("none", "NOT_RUN")
                a["logical"] = measurement("none", "NOT_RUN")
        r = self.stopped(x, "RUN_INCOMPLETE")
        self.assertEqual(r.schema_status, "SCHEMA_VALID")
        decoded = json.loads(r.record.canonical_json)
        self.assertEqual([e["status"] for e in decoded["events"]], ["STOP", "NOT_RUN"])

    def test_complete_consumer_cannot_depend_on_failed_producer(self):
        x = fixture();x["status"] = "INCOMPLETE";x["events"][0]["status"] = "STOP"
        x["artifacts"][4]["file"] = measurement("none", "NOT_RUN")
        x["artifacts"][4]["logical"] = measurement("none", "NOT_RUN")
        self.stopped(x, "INCOMPLETE_DEPENDENCY")

    def test_failed_producer_cannot_claim_closed_measured_output(self):
        x = fixture();x["status"] = "INCOMPLETE";x["events"][0]["status"] = "STOP"
        self.stopped(x, "UNFINISHED_OUTPUT_MEASURED")

    def test_no_data_kind_with_fabricated_numeric_value(self):
        x = fixture();x["artifacts"][0]["raster"]["nodata"] = dict(kind="R_NA", value=0)
        self.stopped(x, "INVALID_NODATA")

    def test_source_role_is_explicit_not_inferred_from_path(self):
        x = fixture();x["artifacts"][0]["source_type"] = "ORIGINAL_PAİTULI_DEM"
        self.stopped(x, "NONCANONICAL_TEXT")
        x = fixture();x["artifacts"][0]["source_type"] = "UNKNOWN_DEM"
        self.stopped(x, "UNSUPPORTED_ENUM")

    def test_optional_02c_event_records_both_outputs_and_same_inputs(self):
        x = fixture()
        added = [artifact("zeros", "02C_ZERO_CELLS", True), artifact("neighbors", "02C_WATER_NEIGHBORS", True)]
        for a in added:a["producer_event_id"] = "evt-02c"
        x["artifacts"].extend(added)
        x["events"].append(dict(event_id="evt-02c", run_id=RUN, attempt_id=ATTEMPT, sequence=3,
                                role="AUDIT_02C", status="COMPLETE", started_tick=4, ended_tick=5,
                                inputs=["pointer", "water", "lake", "land"], outputs=["zeros", "neighbors"],
                                depends_on=["evt-d8"], bindings=[binding(x["artifacts"][i]) for i in (4, 1, 2, 0)]))
        r = s.validate_record(x)
        self.assertEqual(r.disposition, "RECORDED_UNVERIFIED")
        self.assertEqual(r.record.event_ids, ("evt-d8", "evt-02f", "evt-02c"))

    def test_preregistry_identity_strings_are_bounded(self):
        self.stopped(fixture(), "INVALID_UUID4", used_run_ids=("x" * 10000,))

    def test_all_scientific_locks_in_every_result(self):
        for x in (fixture(), {}, dict(fixture(), status="INCOMPLETE")):
            with self.subTest(x=x):
                r = s.validate_record(x)
                self.assertEqual((r.NATIONAL, r.MODERATE, r.hydrological_validation,
                                  r.channel_interpretation, r.routing_authorized, r.outlet_selection),
                                 ("LOCKED", "REVIEW_REQUIRED", "NOT_ASSESSED", "NOT_ASSESSED", False, "UNASSIGNED"))

    def test_authentication_cannot_be_constructor_or_replace_override(self):
        r = s.validate_record(fixture())
        with self.assertRaises(TypeError):s.ValidationResult("SCHEMA_VALID", "OK", producer_lineage_status="VERIFIED")
        with self.assertRaises(ValueError):replace(r, routing_authorized=True)

    def test_large_json_text(self):
        self.stopped(" " * s.MAX_BYTES + "{}", "RESOURCE_LIMIT", raw=True)

    def test_excessive_text_field(self):
        x = fixture();x["repository"] = "a" * 513;self.stopped(x, "NONCANONICAL_TEXT")

    def test_deep_json_guard_precedes_recursive_parser(self):
        self.stopped("[" * 1000 + "]" * 1000, "RESOURCE_LIMIT", raw=True)

    def test_in_memory_cycle_is_bounded(self):
        x = [];x.append(x);self.stopped(x, "RESOURCE_LIMIT")

    def test_fanout_resource_limit(self):
        x = fixture();x["payload"] = [[0] * 128 for _ in range(128)];self.stopped(x, "RESOURCE_LIMIT")

    def test_artifact_cardinality_limit(self):
        x = fixture();x["artifacts"] *= 4;self.stopped(x, "COLLECTION_LIMIT_OR_TYPE")

    def test_event_cardinality_limit(self):
        x = fixture();x["events"] *= 5;self.stopped(x, "COLLECTION_LIMIT_OR_TYPE")

    def test_custom_objects_and_tuples_not_json(self):
        for bad in (object(), (), {"bad": object()}):
            with self.subTest(bad=bad):self.stopped(bad, "UNSUPPORTED_JSON_VALUE")

    def test_nested_field_type_mutations_return_locked_typed_results(self):
        original = fixture()
        paths = []
        def visit(value, path=()):
            paths.append(path)
            if type(value) is dict:
                for key, child in value.items():visit(child, path + (key,))
            elif type(value) is list:
                for i, child in enumerate(value):visit(child, path + (i,))
        visit(original)
        for path in paths:
            for replacement in (None, False, 7, "bad", [], {}):
                with self.subTest(path=path, replacement=replacement):
                    data = deepcopy(original)
                    if not path:
                        data = replacement
                    else:
                        parent = data
                        for key in path[:-1]:parent = parent[key]
                        parent[path[-1]] = replacement
                    result = s.validate_record(data)
                    self.assertIs(type(result), s.ValidationResult)
                    self.assertFalse(result.routing_authorized)
                    self.assertEqual(result.producer_lineage_status, "NOT_ASSESSED")
                    self.assertEqual(result.historical_02f_status, "STOP")

    def test_no_files_process_network_or_stdout_side_effects(self):
        data = fixture();output = io.StringIO()
        with patch("builtins.open", side_effect=AssertionError("I/O")), \
             patch("os.open", side_effect=AssertionError("I/O")), \
             patch("subprocess.run", side_effect=AssertionError("process")), \
             patch("socket.socket", side_effect=AssertionError("network")), redirect_stdout(output):
            self.assertEqual(s.validate_json(json.dumps(data)).disposition, "RECORDED_UNVERIFIED")
            self.assertEqual(s.validate_record(data).disposition, "RECORDED_UNVERIFIED")
        self.assertEqual(output.getvalue(), "")

    def test_component_imports_only_allowlisted_pure_stdlib(self):
        tree = ast.parse(Path(s.__file__).read_text())
        modules = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):modules.update(alias.name for alias in node.names)
            elif isinstance(node, ast.ImportFrom):modules.add(node.module)
        self.assertEqual(modules, {"__future__", "dataclasses", "hashlib", "json", "re", "uuid"})
        calls = {n.func.id for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)}
        self.assertFalse(calls & {"open", "eval", "exec", "compile", "__import__"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
