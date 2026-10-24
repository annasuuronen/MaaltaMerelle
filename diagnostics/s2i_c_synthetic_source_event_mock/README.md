# Stream E — S2I-C synthetic source/event mock, issue #79

**SYNTHETIC_MOCK / RECORDED_UNVERIFIED / NO_RUN_AUTHORIZATION.** Parent:
`4ab77b99f88c70055073e4b3b09ba0f7658a6264`, S2I preparation draft #69.
This is an isolated, pure Python in-memory interface exercise. It implements
neither immutable storage nor an independent observer, trust root or verifier.
No previously accepted code or evidence changes.

```text
NATIONAL=LOCKED
MODERATE=REVIEW_REQUIRED
hydrological_validation=NOT_ASSESSED
channel_interpretation=NOT_ASSESSED
routing_authorized=false
outlet_selection=UNASSIGNED
HISTORIC_02F_EFFECTIVE_D8=NOT_ASSESSED
historical_02f_status=STOP
```

## Source review and explicit integration STOP

Read the pinned preparation document
`diagnostics/water_connected_graph_design/S2I_FORWARD_LINEAGE_IMPLEMENTATION_READINESS.md`
(especially §§3,4,6,7), S2D contract at
`eb09f39238dc8852d768ffc7a45cd3365e80d7a2` and S2E implementation/QA at
`61686de88c459002a503f39cbb908a09f3743733` using read-only Git inspection.
S2D/S2E are divergent draft dependencies, not modules in this branch. No import,
copy of their accepted implementation, merge or cherry-pick is performed.

S2E already checks synthetic **claims** and local record digests. This increment
adds a different, explicitly simulated comparison: supplied tiny immutable Python
`bytes` at three declared mock stages versus separately supplied synthetic
expectations. It does not reproduce the S2E130-test campaign, S2F75 or any v1/v2
codec test. This branch has no v2/S2F integration.

The preparation §6 requires a reviewed real snapshot/storage isolation model
before an actual S2I-C recorder. That model, private source/member layout and
external resource/trust authority remain unavailable. **Actual source recorder
integration is STOP.** The separate mock contract below makes no choice of
filesystem, snapshot provider, Terra hook, witness, credentials or real-run API.

## Pure interface and mock grammar

```python
review_mock(record, *, reference: MockReference, used_ids=()) -> Receipt
```

`SourceVersion` and `MockReference` are frozen dataclasses containing only
synthetic expectations supplied by the caller. A reference is not a trust root:
the same operator can replace both reference and record, which the positive
result still labels RECORDED_UNVERIFIED. The function never obtains its own
source, opens a file, runs a command, makes a network request or emits output.
There is no CLI, executor, signer, publisher or actual capture callback.

The top-level record has exactly:

```text
schema="mm.s2ic.synthetic-source-event-mock.v1"
evidence_kind="SYNTHETIC_MOCK"
run_id, attempt_id             # distinct, canonical UUID4 strings
declared_status="SIMULATED_COMPLETE"
witness=null
sources, events, event_count=5, transcript_sha256, locks
```

Four unique sources in fixed order: WATER_CLASS, LAKE_ID, POINTER,
CANDIDATE_EDGES. Each claim has exactly `role, source_id, version_id, generation,
declared_sha256, declared_size, mutable_alias=false,
immutability="SIMULATED_ONLY"`. Labels are bounded ASCII identifiers; reserved
mutable aliases such as `current/latest` reject. Source/version/event IDs have
disjoint local namespaces. Each nonempty raw value is an immutable `bytes`
object. SHA256 and byte count are recomputed from these **supplied synthetic
octets**, never from an actual dataset. No raster interpretation is assigned.

Exactly five mock events are required, in order:

1. MOCK_START
2. MOCK_FREEZE
3. MOCK_CONSUME
4. MOCK_CLOSE_OUTPUTS
5. MOCK_FINISH

These are toy simulated stages, not S2D production stage IDs and not evidence
that native 02F executed or any output was written. An event has exactly
`event_id, sequence, stage, run_id, attempt_id, tick, observed_sources`.
IDs must equal the reference's distinct expected IDs; sequence1..5 and tick0..4
must match exactly. The middle three stages each contain all four observations
with `role, source_id, version_id, generation, raw`; start/finish contain none.
Every supplied observation must match the reference's generation/version and
raw bytes. Missing, repeated or reordered stages/sources reject rather than
silently completing or deduplicating them.

The declared transcript SHA256 must match canonical bytes of the entire ordered
event list. This local mock grammar uses sorted compact ASCII JSON with bytes
represented as `{"$mock_octets":"<hex>"}`. It is **not** MM-S2CV, an R value
encoding or an input-file identity. A producer may recompute a self-declared
digest; comparison to the supplied reference still catches inconsistent changed
bytes. Replacing both reference and record remains unverified, not forbidden
by an imagined independent authority.

`used_ids` is a bounded caller-supplied tuple, not a durable/global registry.
Duplicate context IDs, or reuse of the run or attempt ID in that context, STOP.
No claim of global identity uniqueness is made. COMPLETE, VERIFIED, real-run,
independent-witness, storage-guarantee or science-approval claims reject; unknown
fields, including commands/auto-approval, reject at every schema level.

The frozen receipt contains immutable canonical record bytes, local record hash
and supplied-source hashes. Positive disposition is only RECORDED_UNVERIFIED,
`mock_transcript_status=SIMULATED_CLOSED`; runtime completion, source/producer
authentication and historical effective D8 remain NOT_ASSESSED. Failed review
returns STOP with a specific reason and no accepted canonical record. Neither
receipt grants real access or execution permission.

## Bounds and new tests

Fixed scope: four sources, five events, twelve middle-stage source observations,
1–256 raw bytes/source, generation1..1000, ≤128 prior identities. Input walk
limits: depth8,3000 values,32 entries/container,128 ASCII characters/string,
exact integers within ±(2^31−1); custom/subclass containers, bytearray, floats,
cycles and bool-as-integer values reject. Canonical record/event buffers each
cap at16384 bytes. The traversal bound is checked before canonicalization.
No external allocation or production resource estimate is inferred.

Only the new test file was executed:

```sh
PYTHONDONTWRITEBYTECODE=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 \
  timeout --signal=TERM --kill-after=2s 30s prlimit --as=268435456 -- \
  python3 -B -m unittest discover \
  -s diagnostics/s2i_c_synthetic_source_event_mock -p test_source_event_mock.py -v
```

Actual local results, 2026-10-24, Python3.12.14:

| Scope | PASS | FAIL/errors | NOT_RUN/skipped |
| --- | ---: | ---: | ---: |
| New source/event mock unit cases | 74 | 0 | 0 |

Measured harness wall time0.064947s and peak RSS18.957MiB. Hard execution limits
were30s TERM /2s KILL and256MiB address space. No failures occurred in this new
campaign. An initial73-case run also passed; review then froze the policy-lock
mapping and added one immutability test before this final74-case run. A zero-test
suite is a failure in the measurement harness. Old
accepted campaigns were not imported or run. `git diff --check` is a separate
static check, not an additional unit-test PASS.

Tests cover independent expected canonical bytes/hashes, detached immutable
receipts, canonical key order, all locks, bounded byte/generation values,
missing/mutable/unexpected sources, changed version/generation/raw bytes,
A→B→A **supplied middle-stage substitution**, missing middle observations,
producer digest recomputation, stage/ID/sequence collisions, transcript changes,
run/attempt replay, false witness/completion/storage/authorization claims,
unknown fields and hostile resource/type inputs. A public-validation test
blocks file/process/socket interfaces while positive and STOP cases execute.

The A→B→A test detects the changed **supplied** middle observation. It does not
detect an unreported mutation between observations, protect a mutable real
source, or make endpoint digests a substitute for an immutable snapshot.
That unresolved threat is exactly why actual recorder integration remains STOP.

## Remaining dependencies and deferred Roihu manifest

No additional Roihu minitest is presently required for this pure stdlib mock:
all new code is locally exercised and has no R, Terra, GDAL, container, Slurm or
CSC-specific boundary. Exclude this suite from the consolidated required batch
unless a separately reviewed change introduces a genuinely new target-runtime
hypothesis. Roihu execution is NOT_RUN; it is not counted as a skipped unit test
or silently claimed PASS. Real storage races, trust enrollment, independent
witnesses, protected custody, producer/consumer capture and real-run verification
are NOT_IMPLEMENTED / NOT_RUN, not synthetic compatibility gaps to solve by
requesting a CSC hydrological job.

Before any actual S2I-C recorder: separately review storage isolation and all
aliases/member dependencies, effective consumer binding, new-run scope/quotas,
trust authority and custody; integration with divergent modules needs an exact
reviewed source delta. Real data access and a controlled pilot need separate
user/CSC authorization. No keys, signatures, source snapshots, native02F run,
raster access, D8/DEM recomputation, accumulation, outlet decision or merge is
implemented or performed here. Historical STOP and all scientific locks stay.
