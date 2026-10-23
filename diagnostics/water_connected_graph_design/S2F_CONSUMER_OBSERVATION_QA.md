# S2F — synthetic observations at the actual 02F callback boundary

Issue #60, stacked on [S2E draft PR #59](https://github.com/annasuuronen/MaaltaMerelle/pull/59)
at `61686de88c459002a503f39cbb908a09f3743733`.
Only tiny, in-memory Base-R fixtures are used. The existing
[`trace_water_connected_candidate_routes`](../../R/02F_water_connected_route_diagnostics.R)
is sourced unchanged; no replacement routing algorithm is implemented.

Every observation/check report and typed STOP condition retains:

```text
EFFECTIVE_CONSUMER_TRANSCRIPT=OBSERVED_SYNTHETIC
INDEPENDENT_WITNESS=NOT_IMPLEMENTED
SOURCE_AUTHENTICATION=NOT_ASSESSED
historical_02f_status=STOP
NATIONAL=LOCKED
MODERATE=REVIEW_REQUIRED
hydrological_validation=NOT_ASSESSED
channel_interpretation=NOT_ASSESSED
routing_authorized=false
```

OBSERVED_SYNTHETIC is the scope tag, including failed attempts with zero reads;
`observation_status`, reason and counters distinguish completion from STOP.
COMPLETE means complete observations of the actual supported callback invocations
in that synthetic invocation, **not** hydrological approval, a complete physical
route or full-raster observation. A STEP_LIMIT route remains censored.

## 1. Observed behavior and non-invasive parity

The unmodified 02F loop calls `cell_values` in WATER_CLASS, LAKE_ID, POINTER
order for every current active cell, **before** applying water precedence.
Consequently even a cell subsequently classified as water has a recorded pointer
read. Queries may contain duplicate cells when active routes converge; those
queries are preserved rather than deduplicated. Duplicate start/origin pairs and
candidate/route ordering remain the native function's responsibility.

The supplied callback receives the exact original handle and requested vector.
The observer returns its exact numeric vector without coercion, reordered IDs,
additional routing reads, substituted pointer, correction or fallback. For
approved fixtures, raw serialized equality is checked for all four returned
components: `routes`, `edge_routes`, `group_summary` and `qa`.

Example, an explicitly synthetic 5×5 row-major grid, 13→14→15 where cell15 has
water class3; this is not a LOW observation:

| Calls | Requested cell | Actual returned values in class / lake / pointer order |
| --- | ---: | --- |
| 1,2,3 | 13 | NA_real_ / NA_integer_ / double2 |
| 4,5,6 | 14 | NA_real_ / NA_integer_ / double2 |
| 7,8,9 | 15 | double3 / NA_integer_ / double0 |

Native outcome: REACHES_RIVER_LINE, two transitions, nine callback invocations.
The observer does not invent a receiver ID for this synthetic river-line cell.

## 2. Interface and explicit source/role binding

Source only the existing 02F module and the new observer in a fresh local R
process. Neither file sources config or executes the hydrology pipeline.

```r
source("R/02F_water_connected_route_diagnostics.R")
source("diagnostics/water_connected_graph_design/s2f_synthetic_02f_observer.R")
p <- rep(0, 9L)
w <- rep(NA_real_, 9L)
l <- rep(NA_integer_, 9L)
f <- s2f_synthetic_fixture(p, w, l, 3L, 3L)
e <- data.frame(spill_group_id=1L, lake_objectid=10L,
                source_cell=1L, receiver_cell=5L)
x <- s2f_observe_02f(trace_water_connected_candidate_routes, f, e)
stopifnot(x$result$routes$route_status == "D8_ZERO_INTERIOR",
          x$observation_status == "COMPLETE", !x$routing_authorized)
stopifnot(s2f_check_transcript(x)$status == "COMPLETE")
```

- `s2f_synthetic_fixture(pointer,water_class,lake_id,nrow,ncol,nominal_name="tiny",
  data_kind="SYNTHETIC_IN_MEMORY")` accepts only plain integer/double vectors,
  without classes/attributes or file paths, of exactly the small grid length.
  It snapshots their values and constructs three distinct locked environment
  handles. Each handle explicitly binds role, synthetic scope, nominal label
  and vector. The fixture itself is locked.
- `s2f_synthetic_values(raster,cells)` is the reference synthetic callback:
  `raster$values[cells]`. It is type-preserving. The observer may delegate to
  another supplied synthetic callback only when its actual return matches this
  registered typed value contract. An integer-to-double conversion is detected
  rather than hidden, even if it might produce the same route status. This is
  not a drop-in adapter for production terra/as.numeric callbacks.
- `s2f_observe_02f(trace_fn,fixture,candidate_edges,max_steps=16L,cell_values=...,
  max_calls=192L,max_values=4096L,max_seconds=2)` runs the supplied function with
  the observational closure. Positive parity tests supply the unchanged native
  02F function. Intentional negative tests wrap its invocation or interrupt it.
- `s2f_encode_values(x)` produces a bounded typed bit representation; it is not
  a source authenticator or a raster encoder.
- `s2f_check_transcript(report,calls=report$calls,result=report$result)` checks
  ordered log structure, query/response encoding, exact finalized observations,
  result equality and the local byte seal. It never reruns/reconstructs routes.

Roles are resolved first by **environment object identity** against the explicit
registered handle map, then checked against the native call order and each
triplet's exact requested cells/types. Equal values, the same nominal source
name, a role string alone or positional coincidence do not establish identity.
A cloned/swapped handle or changed role/value binding STOPs. Registered snapshots
are checked before reads and after returned callbacks, including source mutation
during a callback. No input is repaired.

The factory's restriction is an API scope guard, not proof of data origin: a
caller could deliberately copy real values into plain vectors. Such use is not
authorized. There is no real-data mode, TIFF/CSV reader, terra/GDAL/Whitebox call,
CSC connection or Slurm submission in this implementation.

## 3. Ordered transcript, lossless encoding and finalization

Each delegated call retains:

- sequence number and explicit role;
- a copy of the requested cell-ID vector, including its scalar storage type;
- the callback's returned vector and `returned_type`;
- request/response encodings and return state.

Supported numeric encodings contain `storage_type`, length, per-value validity
tags and little-endian `writeBin` bytes: four bytes per integer or eight per
double. Tags distinguish FINITE (including zero), NA_INTEGER, NA_REAL, NAN,
POS_INF and NEG_INF. Raw value bits preserve negative zero and observed NaN
payloads. Integer lake ID16777217 is tested explicitly, beyond Float32's exact
integer range; no Float32 conversion occurs. The native 02F implementation still
uses R integer conversions where its source specifies them; this observer does
not enlarge that implementation's supported ID range or silently fix overflow.

Callback exceptions retain the delegated request with CALLBACK_ERROR and no
fabricated returned values. Unsupported response objects record only their type
and UNSUPPORTED_RESPONSE, leaving value encoding absent; their contents are not
serialized. Supported but short/altered responses are recorded before STOP.
A trace failure retains partial calls, no successful result and no completeness
claim. `s2f_check_transcript` also STOPs on incomplete reports.

`attempted_calls` counts attempted wrapper invocations, including rejected ones;
`observed_calls` counts delegations recorded. `requested_value_slots` counts
admitted scalar query slots, while `returned_value_slots` counts actual recorded
numeric response elements. A callback crash can therefore report three requested
slots and only two returned values; no unknown response is counted as observed.

The finalized payload binds runtime, synthetic source snapshot, grid, candidate
edges, step budget, counters, ordered calls, result, STOP/completion state and
scientific locks. Capturing the tiny fixture snapshot for expectation checks
is distinct from the native consumer's observed queries: it does **not** mean
02F read every fixture cell or that any real source raster was hashed.

Encoding is `serialize(payload,NULL,version=2,xdr=TRUE)`, with separate raw
little-endian value fields as above. It is labelled
`LOCAL_R_SERIALIZE_V2_WITH_LE_VALUE_BITS` and includes exact `R.version.string`
and `R.version$platform`. Elapsed time is excluded from canonical bytes so
identical successful runs in the tested runtime reproduce the same bytes.
Cross-R-version or cross-platform canonical portability is **not established**.

`LOCAL_TRANSCRIPT_ID_HEX` is the complete canonical byte string in hex, **not a
cryptographic digest**. `transcript_authentication=NOT_AUTHENTICATED`. Base R is
not given an external hashing package, shell hash command or disk hashing step;
this observer does not compute SHA256. Equality with the locally finalized byte
reference detects the tested alterations, not an independent producer identity.
No S2E VERIFIED_IN_DECLARED_SCOPE output exists or is produced.

Finalized reports are environments with locked bindings containing only value
objects; nested ordinary assignments cannot replace a list/vector binding.
The closure is sealed on return and cannot append calls after finalization.
This is ordinary-R immutability, **not protection against hostile code that can
use unlockBinding, introspect closures or forge both payload and seal**. Tests
that deliberately unlock one field demonstrate local discrepancy detection,
not a security boundary. An independent signer/witness remains unimplemented.

The caller supplies both the function and callback inside the same trusted
synthetic R session. The observer does not attest their provenance or sandbox
arbitrary R code. Hidden callback activity, coincidentally equal substituted
values or an A→B→A mutation restored before checks cannot be ruled out by this
boundary observation. The [S2D independent-observer requirements](S2D_FORWARD_PROVENANCE_CONTRACT.md)
remain separate work; no historical lineage gap is lifted.

## 4. Bounds and fail-closed behavior

Hard scope bounds are 1–9 rows/columns (81 fixture cells), 32 candidate rows,
64 native inspection iterations, 192 callback attempts, 32 requested/returned
numeric elements per call, and a default maximum4096 admitted query slots.
Limits may be lowered, not raised beyond these ceilings. Individual supported
responses remain bounded even when an erroneous callback returns too many
values; length mismatch STOPs immediately. Final serialized payload ≤1 MiB.
No recursive retry, growing window, route extension or continuation is present.

The default two-second **cooperative** budget (permitted maximum10s) is checked
before/after callbacks and after the native call. It does not preempt an R
callback that never returns or an OS stall. The test process must therefore use
the external hard deadline shown below: TERM after30s, then KILL after2s if
needed. No global R time-limit settings are changed by the observer. This is not
an unqualified hard-deadline guarantee for arbitrary in-process R code.

Typed STOP reasons include UNAPPROVED_SOURCE_KIND, UNAPPROVED_FIXTURE,
UNBOUND_HANDLE, HANDLE_BINDING_MISMATCH, SOURCE_SUBSTITUTION,
ROLE_SEQUENCE_MISMATCH, TRIPLET_QUERY_MISMATCH, CALLBACK_ERROR,
UNSUPPORTED_CALLBACK_RESPONSE, CALLBACK_RESULT_MISMATCH,
RESPONSE_LENGTH_MISMATCH, OBSERVATION_INCOMPLETE, TRACE_ERROR,
CALL_LIMIT, VALUE_LIMIT and TIME_LIMIT. Local verification separately identifies
removed/reordered/changed records, altered results and changed byte seals/IDs.
STOP reports preserve partial observations and all scientific locks; none grants
an outlet, substitutes a D8 value or infers that a raster edge reaches the sea.

## 5. Actual tests and exact results

All new fixtures are embedded in the test script. No persistent transcript,
raster or CSV fixture is written. Only named outcomes and compact totals are
printed. Each positive `pair()` case independently records the delegate's actual
requests/returns on a reference native run and on the observed native run,
compares every invocation/vector, and compares raw serialization of all four
native result components. This proves non-invasive instrumentation for those
fixtures; it is not independent validation of the native hydrological algorithm.

The 75 named cases cover all eight Whitebox directions; valid zero/negative
zero/NA/NaN/Inf; water precedence; lake IDs; cycles, step/domain limits; duplicate
starts and converging active routes; empty/outside starts; source/handle changes;
altered/incomplete/failed callbacks; query and type mismatches; partial runs;
post-finalization use and report tampering; deterministic bytes; resource limits
and preserved locks. No already-completed CSC campaign was repeated.

Local runtime: **R4.5.0 (2025-04-11)**, platform `x86_64-pc-linux-gnu`, Python3.12.14,
2026-10-23. No external R package was added. The unchanged 02F function uses
standard-distribution R functions (including stats::aggregate).

| Final batch | PASS | FAIL | NOT_RUN | Wall seconds |
| --- | ---: | ---: | ---: | ---: |
| New named Base-R S2F tests | 75 | 0 | 0 | 1.3608 |
| S2E named Python regressions | 130 | 0 | 0 | 1.4833 |
| S2A named regressions, optional R comparison enabled | 90 | 0 | 0 | 0.7653 |
| **Named tests total** | **295** | **0** | **0** | |
| Existing `tests/water_connected_route_diagnostics.R` | **1 batch** | 0 | 0 | 0.3303 |

The legacy R file reports an aggregate PASS; its unnamed `stopifnot` expressions
are not inflated into additional named unit counts. S2A's previously optional R
comparison actually ran with `MM_S2A_RSCRIPT=/tmp/mm-base-r/bin/Rscript`, using
only sparse synthetic values and the existing 02F function. No test in these
selected batches was skipped. Other GIS/accumulation campaigns were not repeated.
CSC execution, real-data lineage and R4.6.1 compatibility remain NOT_RUN, outside
these local named counts.

The first 70-case execution had **68 PASS, 2 FAIL, 0 NOT_RUN**: two deliberate
mutation setups attempted assignment through a locked parent fixture binding
before reaching the intended observer check. Holding the child environment in
a local variable corrected those setups without relaxing observer locks. The
70-case rerun passed; five final focused cases were added and all75 passed.
This is test-harness failure history, not evidence of a hydrological mismatch.

The largest child-process RSS in the final four-batch local campaign was
**66.45 MiB**, measured with Linux RUSAGE_CHILDREN. Wall times include process
startup. Neither metric supports a national scalability/resource claim.

Commands used from repository root (local R path, no CSC execution):

```sh
timeout --signal=TERM --kill-after=2s 30s /tmp/mm-base-r/bin/Rscript --vanilla diagnostics/water_connected_graph_design/test_s2f_synthetic_02f_observer.R
timeout --signal=TERM --kill-after=2s 30s /tmp/mm-base-r/bin/Rscript --vanilla tests/water_connected_route_diagnostics.R
python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_s2e_forward_provenance_schema_v1.py -v
MM_S2A_RSCRIPT=/tmp/mm-base-r/bin/Rscript python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_s2a_pure_d8_trace.py -v
```

The named Base-R runner exits nonzero on any failure or zero cases. An unavailable
Rscript would mean NOT_RUN, not PASS. Here it was present and every listed batch
exited0. The SHA256 of the unchanged **repository code file**
`R/02F_water_connected_route_diagnostics.R` is
`36df1b8181cb9c604f82c3c11970ec2d553bbb59385d4a693ae5f72159447ccf`;
this code audit is not an input-raster hash or historical producer attestation.

Only the three issue-allowlisted files are added. The R02F module, pipeline,
config, existing tests, S2D/S2E, old manifests/workflows and model data remain
unchanged. No CSC access, original pixel/report reads, new D8/accumulation,
production integration, outlet approval or merge occurred. The historical 02F
provenance STOP and all scientific locks remain in force.
