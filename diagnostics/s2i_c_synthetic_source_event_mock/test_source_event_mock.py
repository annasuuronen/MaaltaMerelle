"""Only new tiny mock contract tests; no accepted S2E/S2F/v2 tests imported."""
from copy import deepcopy
from dataclasses import FrozenInstanceError, replace
import builtins
import hashlib
import json
import socket
import subprocess
import unittest
from unittest.mock import patch

from source_event_mock import (
    MockReference, SourceVersion, Receipt, LOCKS, ROLES, SCHEMA, STAGES, review_mock,
)

RUN = "123e4567-e89b-42d3-a456-426614174000"
ATTEMPT = "123e4567-e89b-42d3-a456-426614174001"
PRIOR = "123e4567-e89b-42d3-a456-426614174002"


def reference():
    return MockReference(RUN, ATTEMPT, tuple(
        SourceVersion(role, "source_" + str(i), "version_" + str(i), 1, bytes((i, 0, 255)))
        for i, role in enumerate(ROLES)), tuple("event_" + str(i) for i in range(5)))


def normalized(x):
    # Independent explicit mock reference encoding, not the v1/v2 typed wire.
    if isinstance(x, bytes):
        return {"$mock_octets": x.hex()}
    if isinstance(x, list):
        return [normalized(v) for v in x]
    if isinstance(x, dict):
        return {k: normalized(v) for k, v in x.items()}
    return x


def expected_bytes(value):
    return json.dumps(normalized(value), sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("ascii")


def record(ref=None):
    ref = reference() if ref is None else ref
    claims = [dict(role=s.role, source_id=s.source_id, version_id=s.version_id, generation=s.generation,
                   declared_sha256=hashlib.sha256(s.raw).hexdigest(), declared_size=len(s.raw),
                   mutable_alias=False, immutability="SIMULATED_ONLY") for s in ref.sources]
    events = [dict(event_id=event_id, sequence=i+1, stage=stage, run_id=ref.run_id,
                   attempt_id=ref.attempt_id, tick=i, observed_sources=[
                       dict(role=s.role, source_id=s.source_id, version_id=s.version_id,
                            generation=s.generation, raw=s.raw) for s in ref.sources
                   ] if 1 <= i <= 3 else [])
              for i, (event_id, stage) in enumerate(zip(ref.event_ids, STAGES))]
    return dict(schema=SCHEMA, evidence_kind="SYNTHETIC_MOCK", run_id=ref.run_id,
                attempt_id=ref.attempt_id, declared_status="SIMULATED_COMPLETE", witness=None,
                sources=claims, events=events, event_count=5,
                transcript_sha256=hashlib.sha256(expected_bytes(events)).hexdigest(), locks=dict(LOCKS))


class MockTests(unittest.TestCase):
    def stop(self, obj, code, ref=None, used=()):
        verdict = review_mock(obj, reference=reference() if ref is None else ref, used_ids=used)
        self.assertEqual(verdict.disposition, "STOP")
        self.assertEqual(verdict.reason, code)
        self.assertEqual(verdict.canonical_record, b"")
        self.locks(verdict)

    def locks(self, verdict):
        for k, v in LOCKS.items():
            self.assertEqual(getattr(verdict, k), v)
            self.assertIs(type(getattr(verdict, k)), type(v))
        self.assertEqual(verdict.producer_lineage_status, "NOT_ASSESSED")
        self.assertEqual(verdict.source_authentication, "NOT_ASSESSED")
        self.assertEqual(verdict.independent_witness, "NOT_IMPLEMENTED")
        self.assertEqual(verdict.runtime_completion, "NOT_ASSESSED")
        self.assertEqual(verdict.historical_02f_status, "STOP")

    def test_positive_supplied_bytes_are_only_recorded_unverified(self):
        result = review_mock(record(), reference=reference())
        self.assertEqual(result.disposition, "RECORDED_UNVERIFIED")
        self.assertEqual(result.mock_transcript_status, "SIMULATED_CLOSED")
        self.assertEqual(result.checksum_status, "SUPPLIED_SYNTHETIC_BYTES_ONLY")
        self.locks(result)

    def test_policy_lock_mapping_is_immutable(self):
        with self.assertRaises(TypeError):
            LOCKS["NATIONAL"] = "UNLOCKED"

    def test_independent_canonical_record_bytes_and_digest(self):
        r = record()
        result = review_mock(r, reference=reference())
        self.assertEqual(result.canonical_record, expected_bytes(r))
        self.assertEqual(result.content_sha256, hashlib.sha256(expected_bytes(r)).hexdigest())

    def test_deterministic_dictionary_order_does_not_normalize_events(self):
        r = record()
        permuted = dict(reversed(list(r.items())))
        self.assertEqual(review_mock(r, reference=reference()), review_mock(permuted, reference=reference()))

    def test_reference_and_receipt_are_frozen_and_detached(self):
        ref = reference()
        r = record(ref)
        out = review_mock(r, reference=ref)
        before = out.canonical_record
        r["events"][1]["observed_sources"][0]["raw"] = b"changed"
        self.assertEqual(out.canonical_record, before)
        with self.assertRaises(FrozenInstanceError):
            out.disposition = "VERIFIED"
        with self.assertRaises(FrozenInstanceError):
            ref.sources[0].raw = b"changed"

    def test_per_source_hashes_measure_supplied_synthetic_octets(self):
        ref = reference()
        out = review_mock(record(ref), reference=ref)
        self.assertEqual(out.observed_source_sha256,
                         tuple((s.role, hashlib.sha256(s.raw).hexdigest()) for s in ref.sources))

    def test_positive_prior_distinct_identity_is_not_global_registry(self):
        self.assertEqual(review_mock(record(), reference=reference(), used_ids=(PRIOR,)).disposition,
                         "RECORDED_UNVERIFIED")

    def test_source_byte_boundary_256(self):
        ref = reference()
        ref = replace(ref, sources=(replace(ref.sources[0], raw=bytes(range(256))),) + ref.sources[1:])
        self.assertEqual(review_mock(record(ref), reference=ref).disposition, "RECORDED_UNVERIFIED")

    def test_generation_boundary_1000(self):
        ref = reference()
        ref = replace(ref, sources=(replace(ref.sources[0], generation=1000),) + ref.sources[1:])
        self.assertEqual(review_mock(record(ref), reference=ref).disposition, "RECORDED_UNVERIFIED")

    def test_zero_and_ff_octets_are_not_nodata_or_raster_interpretation(self):
        ref = reference()
        out = review_mock(record(ref), reference=ref)
        self.assertIn(b"0000ff", out.canonical_record)
        self.assertNotIn(b"raster_dtype", out.canonical_record)

    def test_all_public_validation_has_no_IO_or_process_or_network(self):
        r = record()
        def forbidden(*args, **kwargs):
            raise AssertionError("IO attempted")
        with patch.object(builtins, "open", forbidden), patch.object(socket, "socket", forbidden), \
             patch.object(subprocess, "Popen", forbidden):
            self.assertEqual(review_mock(r, reference=reference()).disposition, "RECORDED_UNVERIFIED")
            self.assertEqual(review_mock({}, reference=reference()).disposition, "STOP")

    def test_reference_missing_STOP(self):
        self.stop(record(), "MOCK_REFERENCE_REQUIRED", ref={})

    def test_reference_wrong_role_order_STOP(self):
        ref = reference()
        self.stop(record(), "REFERENCE_ROLE_ORDER", replace(ref, sources=tuple(reversed(ref.sources))))

    def test_reference_source_alias_STOP(self):
        ref = reference()
        sources = (replace(ref.sources[0], source_id=ref.sources[1].source_id),) + ref.sources[1:]
        self.stop(record(), "REFERENCE_ALIAS", replace(ref, sources=sources))

    def test_reference_version_alias_STOP(self):
        ref = reference()
        sources = (replace(ref.sources[0], version_id=ref.sources[1].version_id),) + ref.sources[1:]
        self.stop(record(), "REFERENCE_ALIAS", replace(ref, sources=sources))

    def test_reference_source_version_namespace_alias_STOP(self):
        ref = reference()
        sources = (replace(ref.sources[0], version_id=ref.sources[1].source_id),) + ref.sources[1:]
        self.stop(record(), "REFERENCE_ALIAS", replace(ref, sources=sources))

    def test_reference_event_namespace_collision_STOP(self):
        ref = reference()
        ids = (ref.sources[0].source_id,) + ref.event_ids[1:]
        self.stop(record(), "REFERENCE_ALIAS", replace(ref, event_ids=ids))

    def test_reference_current_alias_STOP(self):
        ref = reference()
        sources = (replace(ref.sources[0], version_id="current"),) + ref.sources[1:]
        self.stop(record(), "MUTABLE_ALIAS", replace(ref, sources=sources))

    def test_reference_oversized_source_STOP(self):
        ref = reference()
        self.stop(record(), "SOURCE_BYTE_BUDGET",
                  replace(ref, sources=(replace(ref.sources[0], raw=b"a"*257),) + ref.sources[1:]))

    def test_reference_bytearray_is_mutable_not_snapshot_STOP(self):
        ref = reference()
        self.stop(record(), "SOURCE_BYTE_BUDGET",
                  replace(ref, sources=(replace(ref.sources[0], raw=bytearray(b"a")),) + ref.sources[1:]))

    def test_reference_generation_bool_STOP(self):
        ref = reference()
        self.stop(record(), "GENERATION_SCOPE",
                  replace(ref, sources=(replace(ref.sources[0], generation=True),) + ref.sources[1:]))

    def test_reference_generation_over_budget_STOP(self):
        ref = reference()
        self.stop(record(), "GENERATION_SCOPE",
                  replace(ref, sources=(replace(ref.sources[0], generation=1001),) + ref.sources[1:]))

    def test_reference_source_count_STOP(self):
        ref = reference()
        self.stop(record(), "REFERENCE_SOURCE_SCOPE", replace(ref, sources=ref.sources[:-1]))

    def test_reference_duplicate_events_STOP(self):
        ref = reference()
        self.stop(record(), "REFERENCE_ALIAS", replace(ref, event_ids=("same",)*5))

    def test_reference_run_attempt_collision_STOP(self):
        self.stop(record(), "RUN_ATTEMPT_COLLISION", replace(reference(), attempt_id=RUN))

    def test_reference_noncanonical_uuid_STOP(self):
        self.stop(record(), "INVALID_UUID4", replace(reference(), run_id=RUN.upper()))

    def test_reference_ambiguous_uuid_version_STOP(self):
        self.stop(record(), "INVALID_UUID4", replace(reference(), run_id="123e4567-e89b-12d3-a456-426614174000"))

    def test_run_replay_STOP(self):
        self.stop(record(), "REUSED_ID", used=(RUN,))

    def test_attempt_replay_STOP(self):
        self.stop(record(), "REUSED_ID", used=(ATTEMPT,))

    def test_prior_identity_duplicate_STOP(self):
        self.stop(record(), "AMBIGUOUS_PRIOR_IDS", used=(PRIOR, PRIOR))

    def test_prior_registry_over_budget_STOP(self):
        self.stop(record(), "PRIOR_ID_BUDGET", used=(PRIOR,)*129)

    def test_record_nonbuiltin_object_STOP(self):
        self.stop(object(), "EXACT_BUILTIN_TYPES_REQUIRED")

    def test_cyclic_record_is_bounded_STOP(self):
        r = record()
        r["events"].append(r)
        self.stop(r, "TREE_BUDGET")

    def test_nested_extra_fields_are_not_executable(self):
        r = record()
        r["command"] = "sbatch evil"
        self.stop(r, "MISSING_OR_UNKNOWN_FIELDS")

    def test_event_count_array_over_budget_STOP(self):
        r = record()
        r["events"] *= 7
        self.stop(r, "TREE_BUDGET")

    def test_unicode_id_STOP(self):
        r = record()
        r["sources"][0]["version_id"] = "versiön"
        self.stop(r, "STRING_BUDGET_OR_ENCODING")

    def test_changed_complete_transcript_digest_STOP(self):
        r = record()
        r["transcript_sha256"] = "a"*64
        self.stop(r, "CHANGED_TRANSCRIPT")

    def test_A_B_A_change_between_equal_endpoint_snapshots_STOP(self):
        r = record()
        r["events"][2]["observed_sources"][0]["raw"] = b"substitution"
        r["transcript_sha256"] = hashlib.sha256(expected_bytes(r["events"])).hexdigest()
        self.stop(r, "OBSERVED_BYTES_SUBSTITUTION")

    def test_changed_bytes_and_producer_digest_together_still_STOP(self):
        r = record()
        r["sources"][0]["declared_sha256"] = hashlib.sha256(b"new").hexdigest()
        for e in r["events"][1:4]:
            e["observed_sources"][0]["raw"] = b"new"
        self.stop(r, "DECLARED_DIGEST_MISMATCH")

    def test_missing_consumer_observation_is_not_endpoint_proof_STOP(self):
        r = record()
        r["events"][2]["observed_sources"] = []
        self.stop(r, "SOURCE_OBSERVATION_MISSING_OR_EXTRA")

    def test_changed_reference_and_record_is_only_mock_not_authentication(self):
        ref = reference()
        ref = replace(ref, sources=(replace(ref.sources[0], raw=b"new"),) + ref.sources[1:])
        result = review_mock(record(ref), reference=ref)
        self.assertEqual(result.disposition, "RECORDED_UNVERIFIED")
        self.locks(result)


def altered_test(name, edit, code):
    def test(self):
        r = record()
        edit(r)
        self.stop(r, code)
    test.__name__ = name
    setattr(MockTests, name, test)


CASES = (
    ("unknown_schema", lambda r: r.update(schema=SCHEMA+".next"), "UNKNOWN_SCHEMA"),
    ("controlled_run_claim", lambda r: r.update(evidence_kind="CONTROLLED_NEW_RUN"), "REAL_RUN_FORBIDDEN"),
    ("false_COMPLETE", lambda r: r.update(declared_status="COMPLETE"), "FALSE_COMPLETION_CLAIM"),
    ("false_VERIFIED", lambda r: r.update(declared_status="VERIFIED"), "FALSE_COMPLETION_CLAIM"),
    ("self_witness", lambda r: r.update(witness={"claimed": True}), "WITNESS_NOT_IMPLEMENTED"),
    ("swapped_run", lambda r: r.update(run_id=ATTEMPT), "RUN_SCOPE"),
    ("swapped_attempt", lambda r: r.update(attempt_id=RUN), "ATTEMPT_SCOPE"),
    ("mutable_alias", lambda r: r["sources"][0].update(mutable_alias=True), "MUTABLE_ALIAS"),
    ("false_snapshot_guarantee", lambda r: r["sources"][0].update(immutability="IMMUTABLE"), "FALSE_STORAGE_GUARANTEE"),
    ("wrong_declared_digest", lambda r: r["sources"][0].update(declared_sha256="0"*64), "DECLARED_DIGEST_MISMATCH"),
    ("wrong_declared_size", lambda r: r["sources"][0].update(declared_size=2), "DECLARED_SIZE_MISMATCH"),
    ("missing_source", lambda r: r["sources"].pop(), "SOURCE_SCOPE"),
    ("unexpected_source", lambda r: r["sources"].append(deepcopy(r["sources"][0])), "SOURCE_SCOPE"),
    ("source_version_changed", lambda r: r["sources"][0].update(version_id="version_new"), "DECLARED_SOURCE_SUBSTITUTION"),
    ("stale_snapshot", lambda r: r["events"][2]["observed_sources"][0].update(generation=0), "SOURCE_VERSION_SUBSTITUTION"),
    ("unexpected_observed_role", lambda r: r["events"][2]["observed_sources"][0].update(role="STORAGE"), "SOURCE_VERSION_SUBSTITUTION"),
    ("wrong_source_same_bits", lambda r: r["events"][2]["observed_sources"][0].update(source_id="other"), "SOURCE_VERSION_SUBSTITUTION"),
    ("truncated_observed_bytes", lambda r: r["events"][2]["observed_sources"][0].update(raw=b"\0"), "OBSERVED_BYTES_SUBSTITUTION"),
    ("observed_bytes_oversized", lambda r: r["events"][2]["observed_sources"][0].update(raw=b"x"*257), "SOURCE_BYTE_BUDGET"),
    ("missing_finish", lambda r: r["events"].pop(), "INCOMPLETE_EVENT_TRANSCRIPT"),
    ("duplicate_event", lambda r: r["events"].append(deepcopy(r["events"][0])), "INCOMPLETE_EVENT_TRANSCRIPT"),
    ("event_id_collision", lambda r: r["events"][2].update(event_id="event_1"), "EVENT_ID_COLLISION_OR_SUBSTITUTION"),
    ("sequence_collision", lambda r: r["events"][2].update(sequence=2), "EVENT_SEQUENCE"),
    ("stage_reordered", lambda r: r["events"][1].update(stage="MOCK_CONSUME"), "STAGE_ORDER"),
    ("tick_stale", lambda r: r["events"][2].update(tick=0), "MOCK_TICK_SEQUENCE"),
    ("wrong_event_run", lambda r: r["events"][2].update(run_id=PRIOR), "RUN_SCOPE"),
    ("count_bool", lambda r: r.update(event_count=True), "EVENT_COUNT"),
    ("source_count_bool", lambda r: r["sources"][0].update(declared_size=True), "DECLARED_SIZE_MISMATCH"),
    ("event_role_hidden_fields", lambda r: r["events"][2].update(approved=True), "MISSING_OR_UNKNOWN_FIELDS"),
    ("auto_authorization", lambda r: r["locks"].update(routing_authorized=True), "FORBIDDEN_SCIENTIFIC_CLAIM"),
    ("NATIONAL_unlock", lambda r: r["locks"].update(NATIONAL="UNLOCKED"), "FORBIDDEN_SCIENTIFIC_CLAIM"),
    ("MODERATE_acceptance", lambda r: r["locks"].update(MODERATE="PASS"), "FORBIDDEN_SCIENTIFIC_CLAIM"),
    ("historical_proof", lambda r: r["locks"].update(HISTORIC_02F_EFFECTIVE_D8="VERIFIED"), "FORBIDDEN_SCIENTIFIC_CLAIM"),
)
for name, edit, code in CASES:
    altered_test("test_"+name+"_STOP", edit, code)


if __name__ == "__main__":
    unittest.main()
