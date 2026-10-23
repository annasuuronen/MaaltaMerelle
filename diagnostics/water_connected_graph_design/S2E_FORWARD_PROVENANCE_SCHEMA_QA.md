# S2E — pure forward-provenance schema v1

Issue #58; parent [S2D design PR #57](https://github.com/annasuuronen/MaaltaMerelle/pull/57)
at `eb09f39238dc8852d768ffc7a45cd3365e80d7a2`.
Implements only a bounded, **synthetic-only, in-memory structural subset** of
[S2D](S2D_FORWARD_PROVENANCE_CONTRACT.md). No recorder, source reader, independent
observer, signer, signature verifier, R hook or filesystem publisher is included.

`NATIONAL=LOCKED` · `MODERATE=REVIEW_REQUIRED` ·
`hydrological_validation=NOT_ASSESSED` ·
`channel_interpretation=NOT_ASSESSED` · `routing_authorized=false` ·
`outlet_selection=UNASSIGNED`.

## 1. Public interface and guarantees

```python
validate_record(value, *, used_run_ids=()) -> ValidationResult
validate_json(raw, *, used_run_ids=()) -> ValidationResult
```

`value` is a JSON-shaped tree of exact built-in dict/list/string/int/bool/null
values. `raw` is an in-memory UTF-8 JSON string or bytes, **never a filename**.
There is no CLI and no IO. No real TIFF/CSV, metadata or original raster digest
is consumed. `used_run_ids` is a tuple of previously used UUID4 identities supplied
in memory; it detects reuse against that supplied context, not against a global
registry. This pure module cannot establish global run-ID uniqueness.

`ValidationResult`, `Record` and `Reason` are frozen dataclasses. The returned
record contains immutable canonical JSON bytes, its local SHA256, run/attempt
identity, declared status and tuple snapshots of artifact/event IDs. It retains
all supplied claims in canonical bytes, without exposing a mutable nested tree.
It is detached from caller mutations. Record construction or possession does
not establish authority; only the validation functions perform the checks.

| Result | Interpretation |
| --- | --- |
| `schema_status=STOP`, `disposition=STOP`, no record | Malformed schema, unsupported version/type, contradictory identity/link/order or forbidden claim. Exact `Reason(code,path)` retained. |
| `SCHEMA_VALID`, `disposition=STOP`, record retained | Representable partial claims, missing effective binding/identity/producer claim, unsupported immutability claim, or explicit INCOMPLETE/STOP/NOT_RUN. Retaining canonical bytes does not accept the missing evidence. |
| `SCHEMA_VALID`, `RECORDED_UNVERIFIED`, `completeness_status=COMPLETE_CLAIM` | Internally consistent and complete **claims** for this subset. No independently witnessed event or source authentication is established. |

`declared_status` retains a well-formed input's COMPLETE/INCOMPLETE/STOP/NOT_RUN.
A purported COMPLETE record with absent required evidence has disposition STOP
and `completeness_status=INCOMPLETE`; it is never successful COMPLETE evidence.
NOT_ASSESSED is distinct from NOT_RUN and remains the immutable producer/source
and scientific assessment status. A valid structured record is not a completed
job, an execution permission or a verified producer lineage.

Checksum reporting is `SIMULATED_MEASUREMENTS_RECORDED`, `CLAIMS_ONLY` or
`NOT_ASSESSED`. It never says that actual dataset bytes were independently
measured or matched. The only digest the module computes is SHA256 of the
canonical **record bytes**. That is a local content identifier, not an attestation.
Every result, including invalid inputs, keeps source/producer authentication
NOT_ASSESSED, `historical_02f_status=STOP` and
`RUNTIME_INPUT_LINEAGE=NOT_ASSESSED`. There is no positive authentication path.

## 2. Exact allowlisted record schema

All keys below are required, including explicitly null values. Extra/missing
keys at every level STOP. Containers and strings are bounded as specified in §5.
This is the implemented Python schema; no additional JSON-schema file is needed
or permitted by the issue's three-file scope.

### Top level

```text
schema_version: "maaltamerelle.forward-provenance.v1"
evidence_kind: "SYNTHETIC"
repository: "annasuuronen/MaaltaMerelle"
commit_sha: nonzero 40-lowercase-hex claim
run_id, attempt_id: distinct canonical UUID4 strings
status: COMPLETE | INCOMPLETE | STOP | NOT_RUN
grid: Grid
artifacts: [Artifact, ...]
events: [Event, ...]  # semantically ordered
witness: null
NATIONAL: "LOCKED"
MODERATE: "REVIEW_REQUIRED"
hydrological_validation: "NOT_ASSESSED"
channel_interpretation: "NOT_ASSESSED"
routing_authorized: false
outlet_selection: "UNASSIGNED"
producer_lineage_status: "NOT_ASSESSED"
source_authentication: "NOT_ASSESSED"
```

`CONTROLLED_NEW_RUN`, historical evidence kinds, VERIFIED/VALIDATED claims,
`approved=true`, executable command fields and self-embedded key/signature objects
are rejected. A future real-record schema/observer API needs a separately reviewed
extension, not relabelling of S2E synthetic data. Bool false is not integer zero.

### Grid and raster claims

Grid keys are exactly `grid_id,epsg,rows,cols,geotransform,cell_index_base,
row_col_index_base,pointer_scheme,esri_pntr`. Require EPSG integer3067;
1–6000 rows/columns; six integer affine coefficients `[x,2,0,y,0,-2]`, with
coefficient magnitude ≤100,000,000; 1-based cells, 0-based rows/columns;
`WHITEBOX_D8` and boolean `esri_pntr=false`. No LOW origin is silently defaulted
and a tile/raster edge is not a coastline. This checks declared geometry shape,
not actual CRS semantics, grid location or raster contents.

A raster claim has exactly `grid_id,dtype,nodata,logical_encoding` and must match
the record's grid ID. Encoding is the explicit marker `synthetic.logical.v1`;
**no real logical raster encoder is implemented**. Supported dtypes are Float64,
Float32, Int32, UInt16 and Byte; POINTER must be Float64. NoData has exactly
`kind,value`: FINITE with an exact integer sentinel fitting the dtype, or R_NA /
NAN / NONE with null value. R_NA and NAN require a float band and remain distinct.
Finite float sentinels are restricted to integer values within ±2^24 for Float32
and ±(2^53−1) for Float64. Arbitrary fractional sentinels are outside this small
schema. Byte/UInt16/Int32 bounds are enforced exactly. Pointer NoData cannot be
zero; water NoData cannot mask classes1/2/3; a positive lake-ID NoData is rejected.
No actual cell value or direction is inferred from any of these declarations.

### Artifact and measurement

Artifact keys are exactly:

```text
artifact_id, run_id, attempt_id, role, source_type, production,
producer_event_id, predecessor, uri, file, logical, raster
```

Local artifact run/attempt IDs must match the top level. IDs use
`[a-z][a-z0-9_-]{0,47}`. All local event/artifact IDs share a unique namespace and
cannot alias the run/attempt identities. This one-grid/one-attempt subset permits
one artifact per role; two versions of a mask/pointer cannot be mixed between
02C and 02F in one record. File URIs must be unique safe
`synthetic:/segment/.../name` labels (≤256 characters); they are not opened or
resolved. Traversal, empty segments and shell punctuation are rejected.

| source_type / production | Allowed artifact roles and linkage |
| --- | --- |
| SOURCE_DATASET / SOURCE | LAND_WATER, WATER_CLASS, LAKE_ID, CANDIDATE_EDGES; no local producer/predecessor. These are declared roots, not independently authenticated datasets. |
| DERIVED_FILE / PRODUCED | POINTER, 02F_ROUTES/EDGES/SUMMARY/QA, 02C_ZERO_CELLS/WATER_NEIGHBORS; producer_event_id must identify the event that lists this output, no predecessor. |
| IN_MEMORY / SOURCE or PRODUCED | Raster roles permitted by the corresponding SOURCE/PRODUCED rule. `uri=null`, file measurement NO_FILE_REPRESENTATION; effective identity uses the logical measurement. |
| EXISTING_UNVERIFIED / REUSED | POINTER only; no local producer. REUSE_POINTER event records reuse, not generation. Optional predecessor claim described below. |

`file` and `logical` each contain exactly `state,sha256,size_bytes`:

- NOT_RUN or NO_FILE_REPRESENTATION: both digest and size are null. NO_FILE is
  permitted only for the file identity of IN_MEMORY; logical identity never uses it.
- DECLARED or MEASURED_SIMULATED: nonzero 64-lowercase-hex digest and positive
  integer size ≤2^40. Unknown values cannot be fabricated as zero/default hashes
  or byte counts. Neither label is evidence that this module measured a dataset.

Only raster roles have a raster claim; CSV roles use `raster=null` and logical
NOT_RUN. A consumed IN_MEMORY raster needs its logical identity and matching
binding; a file hash cannot stand in for its effective values. File-backed
consumed rasters need both a file identity and the binding's logical identity.
All declared artifacts must be referenced by event inputs/outputs; unused hidden
artifacts are rejected. No implicit external member/sidecar dependency exists.

`predecessor` is null or exactly `run_id,attempt_id,event_id,manifest_sha256`.
Its distinct prior run/attempt UUID4 IDs cannot equal either current identity;
its manifest hash and event ID remain **claims only**, never authenticated.
A reused pointer without this claimed producer link yields
`MISSING_CLAIMED_PRODUCER_LINK` and STOP. With it, the best result remains
RECORDED_UNVERIFIED. No old pointer is reclassified as newly produced.

### Event and effective binding

Event keys are exactly `event_id,run_id,attempt_id,sequence,role,status,
started_tick,ended_tick,inputs,outputs,depends_on,bindings`.
Event sequence must be exactly 1..N **in supplied order**. Run/attempt scope must
match. Roles are unique; PRODUCE_D8 and REUSE_POINTER are mutually exclusive.

| Event role | Exact input role set | Exact output role set |
| --- | --- | --- |
| PRODUCE_D8 | LAND_WATER | POINTER |
| REUSE_POINTER | POINTER | empty |
| TRACE_02F | POINTER, WATER_CLASS, LAKE_ID, CANDIDATE_EDGES | 02F_ROUTES, 02F_EDGES, 02F_SUMMARY, 02F_QA |
| AUDIT_02C | POINTER, WATER_CLASS, LAKE_ID, LAND_WATER | 02C_ZERO_CELLS, 02C_WATER_NEIGHBORS |

Each role appears once within that event's inputs/outputs. Outputs have one
producer; input/output overlap is forbidden. Produced inputs require an explicit
dependency on their already recorded producer. Reused pointers require the
explicit reuse event. Dependencies must name earlier events, excluding cycles,
self/forward references. A COMPLETE event cannot depend on a non-COMPLETE one.
Complete runs need TRACE_02F and a producer or reuse event.

Ticks are exact nonnegative monotonic integers. Executed events need start;
COMPLETE needs end≥start. This small schema accepts sequential stages without
overlap of known end/start ticks. NOT_RUN has null start/end and no bindings.
Non-COMPLETE outputs cannot claim measured/declared complete identities. Partial
stage observations are retained; they do not create a successful final record.

Each binding has exactly `artifact_id,logical_sha256,logical_size_bytes,
snapshot_id,guard,before_sha256,after_sha256`. It must uniquely identify a raster
input and exactly match that artifact's logical digest and size. COMPLETE events
require every raster input to be bound, with no guessed pointer/mask substitute.

`guard=SNAPSHOT_CLAIM` needs an explicit snapshot ID. This is merely a claim, not
an observed immutable mount or frozen in-memory argument. ENDPOINT_HASHES_ONLY
or NOT_ASSESSED requires a null snapshot and yields STOP. Optional before/after
hash claims must be well formed; unequal values are contradictory and STOP.
Each supplied endpoint hash must also match the declared file version, or the
logical version for IN_MEMORY. Equal values never establish that no A→B→A
mutation happened. These records do
not implement the immutability guarantee specified by S2D.

## 3. Canonical encoding, limits and reason codes

Canonical encoding is sorted dictionary keys, compact separators, ASCII JSON
and no floats, encoded as bytes without BOM or trailing newline. All arrays,
particularly events, retain their order. Equivalent decoded ASCII escapes and
JSON whitespace/key permutations produce the same bytes. Event reordering is
not normalized away. No claim of general RFC8785/foreign numeric equivalence
is made; this restricted integer-only JSON domain is explicitly defined here.

Reject duplicate JSON keys before constructing dictionaries, unknown fields,
non-finite literals, all floats (including float-valued IDs), non-ASCII/confusable
or combining text, controls, tuples, custom objects and implicit coercions.
There is no Unicode normalization that could hide a changed identifier.

Bounds: input/canonical JSON64 KiB; nesting depth10; traversed tree4096 values
(including dictionary keys); string512 characters; dictionary32 keys; list128
items; 32 artifacts; 8 events; 8 event inputs/outputs/dependencies; 4 bindings;
128 prior IDs. Scalars are exact integers within ±(2^53−1), with narrower field
limits. JSON depth is scanned before recursive parsing. In-memory trees are
bounded before canonicalization; cycles hit the depth/work guard. UUID parsing
checks length first, including caller-supplied prior IDs. No external registry
lookup or automatic recovery is attempted.

`Reason` keeps a machine code and bounded schema path. Codes include
DUPLICATE_JSON_KEY, UNKNOWN_SCHEMA_VERSION, MISSING_OR_UNKNOWN_FIELDS,
NONFINITE_JSON_NUMBER, UNSUPPORTED_JSON_VALUE, NONCANONICAL_TEXT, RUN_ID_REUSE,
RUN_SCOPE_MISMATCH, EVENT_SEQUENCE, DEPENDENCY_ORDER, PRODUCER_LINK_MISMATCH,
PRODUCTION_ROLE_MISMATCH, EFFECTIVE_INPUT_MISMATCH,
EFFECTIVE_INPUT_BINDING_MISSING, ARTIFACT_IDENTITY_MISSING,
MISSING_CLAIMED_PRODUCER_LINK, IMMUTABLE_BINDING_NOT_RECORDED,
SOURCE_MUTATION_CLAIM, SOURCE_VERSION_MISMATCH, CONFLICTING_ARTIFACT_ROLE,
EXTERNAL_WITNESS_NOT_IMPLEMENTED,
FORBIDDEN_SCIENCE_OR_AUTHENTICATION_CLAIM and RESOURCE_LIMIT.
Schema errors return the first encountered invariant; completeness reasons are
sorted/deduplicated. Unexpected implementation exceptions propagate as errors,
not a fabricated acceptance. No input or scientific status is rewritten.

## 4. Actual synthetic verification

Run from the repository root:

```sh
python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_s2e_forward_provenance_schema_v1.py -v
```

All new fixture records and small byte labels are constructed in the test module;
no on-disk fixture is created. MEASURED_SIMULATED digests hash **synthetic labels**,
not TIFFs, real logical pixel streams or original CSVs. Tests verify consistency
of claims; they do not establish actual raster-encoding or source truth.

The 130 named tests cover positive round trips; immutable/detached results;
key-order determinism; preserved event order; duplicate keys/IDs; scope/reuse;
D8 convention and typed NoData; memory/file separation; substitutions and partial
lifecycles; missing output/runtime identities; A→B→A endpoint claims; fake
witnesses; forbidden scientific decisions; resource and executable-payload
rejections. An additional systematic nested-field type-mutation test checks
that malformed JSON-shaped values return typed, locked results without uncaught
exceptions. It is one of the 130 named tests, not extra counted unit tests.

The IO safety test blocks file opens, process execution and sockets during both
validation APIs and checks no stdout. Static import/call checks exclude IO,
process/network and dynamic execution interfaces. The test's AST inspection
reads only this module's repository source. Existing S2B/S2C regression batches
use their own temporary synthetic fixtures; they never access original CSC data.

Final local run, 2026-10-23, Python3.12.14:

| Batch | PASS | FAIL/errors | NOT_RUN/skipped | Measured seconds |
| --- | ---: | ---: | ---: | ---: |
| New S2E | 130 | 0 | 0 | 1.7384 |
| S1 decision/provenance regressions | 101 | 0 | 0 | 0.1335 |
| S2A pure trace/provenance regressions | 89 | 0 | 1 | 0.1523 |
| S2B adapter regressions | 82 | 0 | 7 | 0.7987 |
| S2C metadata/lineage regressions | 71 | 0 | 2 | 0.3918 |
| **Total** | **473** | **0** | **10** | |

The optional R02F comparison was NOT_RUN (`MM_S2A_RSCRIPT` unset). Seven S2B
and two S2C actual GDAL synthetic fixture tests were NOT_RUN: their opt-in flags
were unset and host GDAL3.10.3 does not meet their pinned3.12.2 requirement.
No skipped test is counted PASS. The runner fails on zero discovered tests or
any failure/error. There were no observed failing executions in this package.
Graph/G5A accumulation campaigns were not repeated because their code was
unchanged and this task introduces no accumulation algorithm or integration.

The combined five-batch process peaked at **40.69 MiB RSS** (Linux ru_maxrss).
This is a measured local process peak, not a promised real/national resource
requirement. Other batch commands use the same discovery syntax with
`test_decision_contract_v1.py`, `test_s2a_pure_d8_trace.py`,
`test_s2b_readonly_window_adapter.py`, `test_s2c_original_source_preflight.py`.

## 5. Remaining gates and possible next stage

The historical S2C STOP remains unchanged. A present hash or metadata match,
well-formed commit, internal producer link, reused predecessor claim, synthetic
PASS or COMPLETE_CLAIM cannot authenticate the pointer consumed by old 02F.
No public function can return VERIFIED_IN_DECLARED_SCOPE or VALIDATED.

S2E deliberately omits the rest of the S2D runtime contract: actual source paths
and bytes, environment/binary attestation, authenticated code checkout, real
logical-value encoding, atomic no-replace publication, durable run-ID registry,
enrolled independent observer and cryptographic verification. Its grid/type
checks do not replace S2C's real metadata protocol or permit S2B real-data mode.
A proposed next task could define a separately reviewed recorder/observer
interface and its synthetic trust-boundary tests, with external trust enrollment
and scope specified before implementation. No observer or capture hook is
activated here. A future controlled run still needs separate execution and
pixel-read approval, immutable inputs and independently verified consumer links.

Scientific validation and physical outlet decisions remain independent work.
No source substitution is repaired, no missing route is continued, no national
threshold is inferred, and no raster boundary is treated as a coastline.
Only the three issue-allowlisted files are added. R pipeline, prior modules and
tests, S2D/S2C documents, old manifests, workflows and model data are untouched.
No CSC/Slurm jobs, original-data reads/hashes, hydrological reruns or accumulation
rasters occurred. Nothing is merged and no hydrological connection is approved.
