# S2I-B/2a — synthetic native R callback values, v2 contract

**DESIGN_ONLY / NOT_IMPLEMENTED / NO_RUN_AUTHORIZATION.** 2026-10-23.
Parent: [S2I-B/2 STOP review, draft PR #74][review], commit
`1282b87e9b934879993c56d6c3b3a9e7a3d78241`.
S2F source pin: `477c5b13d5714d618c9c9de88f5f80290b53d994` (draft PR #61).
Only this new document is delivered. No codec, adapter, loader or test is added.

```text
NATIONAL=LOCKED
MODERATE=REVIEW_REQUIRED
hydrological_validation=NOT_ASSESSED
channel_interpretation=NOT_ASSESSED
routing_authorized=false
outlet_selection=UNASSIGNED
HISTORIC_02F_EFFECTIVE_D8=NOT_ASSESSED
SOURCE_AUTHENTICATION=NOT_ASSESSED
INDEPENDENT_WITNESS=NOT_IMPLEMENTED
```

## 1. Decision and alternatives

Recommend **one new, bounded binary consumer-value format**, logical name
`maaltamerelle.synthetic-native-callback.v2`, magic `MM-S2CV\0`, version2.
Role and native R vector storage type are independent fields. It is not an
extension interpreted by the existing `MM-S2IA` version1 decoder.

| Alternative | Assessment |
| --- | --- |
| Preserve v1 role-implied Byte/Int32/Float64, project callbacks into it | Reject: integer3 and double3 collide; native WATER_CLASS NA_real_ is not Byte255. Pre-consumer substitution changes routing; post-consumer projection loses representation. |
| Relabel widened values as v1, or attach an unversioned corrective sidecar | Reject: violates strict v1 widths/tags and makes the same version ambiguous. No silent migration or fallback. |
| Transport the complete S2F R serialize(v2) object | Reject as the cross-language value contract: useful as a local seal, but Python portability and R object decoding are not established. |
| Canonical JSON with hex payloads and explicit types | Feasible as a separate format, but needs additional duplicate-key, numeric, text and canonicalization rules. Hex is acceptable for bounded diagnostic display, not the selected wire representation. |
| **New binary v2 with explicit observed types, tags and raw bytes** | **Select:** unambiguous framing; preserves role/type separation and duplicates; Python can compare integers/bytes without floating-point coercion. |

This resolves a design decision, not the previous implementation STOP. The old
v1 code, validated evidence and S2F remain frozen. Implementing v2 and integrating
it into a new synthetic harness require a later reviewed change.

## 2. Observation boundary and assurance levels

The unchanged [native 02F loop][native] requests WATER_CLASS → LAKE_ID → POINTER
for the same active-cell vector, including pointer reads on water cells.
[S2F's public callback][s2fvalues] is exactly
`s2f_synthetic_values(raster,cells) = raster$values[cells]`. Its public
[observer][s2fobserver] wraps that callback, verifies handle identity and exact
triplet queries, returns the original vector unchanged, and seals ordered calls.
The inner `observed_cell_values` closure is private and must not be replaced.

The future adapter accepts only a complete nonempty **synthetic** S2F report
after `s2f_check_transcript(report)` succeeds. It consumes the report's original
request/response encodings and values, checking that they agree; it does not
rerun routes to infer observations. Failed/unsupported/partial reports STOP.
Export occurs in that same synthetic R invocation: `report$R_version` and
`report$R_platform` must match the current runtime before capturing header fields.
Do not label a restored report with a later process's runtime or infer its origin.
Valid native empty/outside-start cases are not model errors, but this v2 profile
cannot export them as a complete nonempty observation stream.

| Claim | Evidence and maximum permitted conclusion |
| --- | --- |
| Observed consumer representation | Role, actual R integer/double storage, validity and exact raw bytes from the supplied synthetic report. Successful comparison means local representation agreement only. |
| Declared raster dtype | Optional synthetic declaration, explicitly unverified; never inferred from role, value magnitude, NA sentinel, R type or filename. No raster is opened to confirm it. |
| Authenticated source provenance | Not supplied by this protocol, S2F's local seal, a code hash, byte equality, or a caller-supplied reference. NOT_ASSESSED; independent witness NOT_IMPLEMENTED. |

Standalone parsing may return `STRUCTURALLY_WELL_FORMED`, **not** “observations
verified”. `LOCAL_OBSERVATION_MATCH` requires comparison with the entire original
sealed S2F report and the independent reference described in §6; its assurance
remains `RECORDED_UNVERIFIED`. Missing comparison material yields
`STOP/REFERENCE_UNAVAILABLE` for that comparison, not an inferred match.
No status authorizes routing or authenticates historical LOW inputs. Every API
result attaches the fixed scientific locks above; no input can override them.
Real-data or verified-provenance claims are unsupported and must STOP.

## 3. Exact binary grammar

All integers below are unsigned unless explicitly int32, and little-endian
unless UUID bytes. ASCII has no terminator except in the literal magic strings.
There is no alignment padding, implicit field, optional extension, compression,
alternate endian mode or trailing content. Lengths are checked before allocation.
The whole transcript, not an individual batch, is the unit of completion.

Header fields occur in this exact order:

| Field | Encoding / requirement |
| --- | --- |
| Magic | 8 bytes: ASCII `MM-S2CV` followed by NUL |
| Version | uint8, exactly2 |
| Scope | uint8, exactly1 = SYNTHETIC_IN_MEMORY |
| Scalar profile | uint8, exactly1 = R_INT32_IEEE_BINARY64_LE_WITH_OBSERVED_VALIDITY |
| Total byte length | uint32, includes header, every framed batch and trailer; ≤16384 |
| Synthetic run ID; attempt ID | 16 UUID bytes each, RFC UUID4 variant; distinct; canonical lowercase strings at an API boundary. These are synthetic labels, not real run authorization. |
| Grid ID | uint8 length1–32, then ASCII matching `[a-z][a-z0-9_-]{0,31}` |
| Rows; columns | uint16 each,1–9 and product≤81 |
| Declared CRS | uint32, exactly3067; a synthetic declaration, not a CRS authentication |
| X origin; Y origin | int32 each, absolute value≤100000000 |
| Cell size; row direction; index scheme | uint8 each, exactly2 metres;1=north-to-south rows;1=one-based row-major. Affine is `[x,2,0,y,0,-2]`. |
| Declared R version | uint8 length1–32 plus ASCII matching `[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}`; captured `getRversion()` text |
| Declared R platform | uint8 length1–64 plus ASCII matching `[A-Za-z0-9._-]{1,64}` |
| Declared raster dtypes | Exactly3 uint8 fields in WATER_CLASS, LAKE_ID, POINTER order:0=UNKNOWN,1=Byte,2=Int32,3=Float64. Every declaration has fixed status UNVERIFIED_DECLARATION. For S2F fixtures without such metadata use UNKNOWN, not a guessed type. |
| Batch count | uint16,3–24 inclusive and divisible by3 |
| Scalar-slot count | uint32, sum of each batch's count,≤512; counts repeated cells and roles separately |

For each batch, in original invocation order:

| Field | Encoding / requirement |
| --- | --- |
| Body length | uint16; exact byte size of following batch body, excluding this prefix |
| Sequence | uint16, contiguous1…batch_count |
| Raster role | uint8:1=WATER_CLASS,2=LAKE_ID,3=POINTER |
| Request storage type | uint8:1=R integer/int32,2=R double/binary64 |
| Response storage type | uint8:1=R integer/int32,2=R double/binary64; **independent of role** |
| Count | uint16,1–32; request and returned vector lengths must both equal it |
| Each scalar slot, repeated count times | Raw request-cell bytes of request width; uint8 response validity tag; raw response bytes of response width |

Storage is homogeneous within a vector. Every role admits both native types;
integer POINTER or double LAKE_ID is neither widened nor rejected because of
its role. For this fixed-handle S2F profile a given role's response storage type
must remain constant throughout one transcript; a change requires STOP/review.
Batch body length is exactly `7 + count*(request_width + 1 + response_width)`.

Trailer, immediately after the final batch:

| Field | Encoding / requirement |
| --- | --- |
| End magic | 8 bytes: ASCII `MM-END2` followed by NUL |
| Completed batches | uint16, equal header batch count and parsed count |
| Completed scalar slots | uint32, equal header slot count and parsed sum |

End-of-input must coincide with the declared total length. No new status field
can declare success or override failed comparisons. A final trailer and matching
counts establish framing only: removal of whole triplets with rewritten counts
is still rejected by comparison against the original report.

## 4. Types, validity and byte preservation

R integer is represented by its exact four-byte signed int32 payload; double by
its exact eight-byte IEEE754 binary64 payload. A future encoder must preserve
the existing S2F `storage_type`, validity and `little_endian_bits` as captured by
`writeBin(...,size=4 or8,endian="little")`. It must not round, call `as.numeric`
or `as.integer` to normalize responses, use Float32, replace missing values,
quiet/rebuild a NaN, discard a sign bit, or derive bytes from printed decimals.

| Tag code | Name | Structural requirements |
| --- | --- | --- |
| 1 | FINITE | Integer: any int32 except `00000080`. Double: exponent≠2047, including subnormal and either signed zero. |
| 2 | NA_INTEGER | Integer only; raw LE exactly `00000080` (−2147483648). |
| 3 | NA_REAL | Double only; exponent2047 with nonzero mantissa; **observed R validity**, see below. |
| 4 | NAN | Double only; exponent2047 with nonzero mantissa; preserve every sign/payload bit. |
| 5 | POS_INF | Double only; raw LE `000000000000f07f`. |
| 6 | NEG_INF | Double only; raw LE `000000000000f0ff`. |

All other tag/type combinations STOP. There is deliberately **no NODATA255 tag**
for native responses: an observed numeric255 is FINITE, not inferred missingness.
Native NA tags are not declarations about a source raster's NoData encoding.

NA_REAL versus NAN is the classification **observed by the pinned S2F code**
(`is.na` and `is.nan`), not a universal rule invented by Python. For these two
tags Python checks the IEEE NaN category but **does not rederive R's predicate
semantics from a single hard-coded sentinel or normalize payloads**. It compares
the exact observed tag and bytes against the R reference. A tag flip between
NA_REAL and NAN may be structurally plausible but must fail observation matching.
Without the reference that semantic agreement is NOT_ASSESSED. This explicitly
separates bit/category checks from an independently observed R classification.

Illustrative raw LE encodings (specification examples, not new measurements):
integer3=`03000000`; double3=`0000000000000840`;
canonical R NA_real_=`a20700000000f07f`; a distinct NaN payload may be
`010000000000f87f`. The protocol retains whatever NaN/NA bits were actually
captured; it does not force the illustrative canonical value. Double+0 is
`0000000000000000`, double−0=`0000000000000080`, both FINITE and unequal bytes.
Int32 lake ID16777217 remains `01000001`, never a rounded Float32 value.

Requests preserve their own integer/double storage and raw bytes too. Every
request must encode a finite integral cell1…rows*cols, never NA,0 or a rounded
fraction. Python may match double request bytes against an independently built
table of exact binary64 encodings for integers1…81; it need not unpack floats.
No request is reordered or deduplicated; identical numeric IDs with different
native request storage types are different encodings.

## 5. Complete triplets and fail-closed rules

Each sequence triple is exactly WATER_CLASS, LAKE_ID, POINTER. Requests in all
three must match **storage type and ordered raw bytes**, including duplicates.
Triplets may repeat cells; separate roles still count as separate observations.
No fictitious missing batch, filled value, reordered record or route continuation
is supplied by the adapter. A complete callback transcript may contain a native
STEP_LIMIT route; completeness does not remove route censoring or establish flow.

| Condition | Required outcome |
| --- | --- |
| v1 magic, version≠2, unknown profile/scope/type/tag/dtype declaration | STOP; no automatic v1 decoder call, widening, heuristic sniffing or migration |
| Extra bytes/fields, inconsistent total/body lengths, missing end marker, impossible counts | STOP; do not retry with a partial prefix |
| Missing/reordered/duplicated sequence or incomplete triplet | STOP |
| Wrong role or changed/permuted/deduplicated request within a triplet | STOP |
| Nonfinite/outside/fractional cell, wrong vector width, tag/bit category mismatch | STOP |
| S2F report incomplete, local seal fails, altered responses or unsupported vector objects | STOP before claiming observation match |
| Complete triplet removed, valid scalar bits or NA/NAN tag modified, counts/hash recomputed | STOP on full original-report/reference comparison; syntax alone cannot detect every such substitution |
| Reference absent or R parity check missing/failed | No LOCAL_OBSERVATION_MATCH; STOP for that verification stage |
| Limit exceeded, runtime cannot preserve required raw representation, dependency unavailable | STOP; no automatic budget expansion, coercion, fallback or dispatch |

A digest can identify bytes, not their authenticity. A future Python result may
report `synthetic_payload_sha256=SHA256(exact_complete_v2_bytes)`, labelled
SYNTHETIC_CONTENT_ID / NOT_AUTHENTICATED. It is not embedded recursively in the
wire, need not be calculated by the Base-R encoder, and cannot replace comparison
with original observations. No signature, trusted source ID or approval bit is
accepted by this grammar.

## 6. Independent Python verification and native parity

The future Python implementation uses its own bounded parser and encoder, not
R serialization or an import of an R-generated decoder. It returns immutable
records containing role, request/response native types, ordered request bytes,
response tags and raw bytes. IEEE checks use integer bit fields; equality is
exact byte equality, never Python float equality (`NaN!=NaN` is irrelevant).

The new small synthetic harness must establish separately:

1. An independent R delegation recorder calls the unchanged native function and
   returns exactly `s2f_synthetic_values(raster,cells)`. A second invocation uses
   unchanged `s2f_observe_02f`; every ordered request, response type/tag/raw byte
   and all four native result components must agree. Compare R result bytes
   locally, not by pretending Python can decode the S2F serialize seal.
2. Before export, `s2f_check_transcript` succeeds and response/request encodings
   agree with actual recorded vectors. Export copies original captured bytes;
   no additional fixture cells or source rasters are queried by the encoder.
3. Python decodes R's wire and re-encodes it byte-identically. Independently
   predeclared tiny fixtures specify expected types, cell order, raw values and
   validity; Python constructs expected frames separately from the received
   wire. Never construct the expected values by decoding the wire under test.
4. Compare the entire decoded stream with that reference and the local R call
   comparison results, including full counts and scope. Self-consistent modified
   wire plus a recomputed digest does not bypass this comparison. The R reference
   and Python fixture remain same-operator synthetic inputs, not witnesses.

Header runtime strings participate in exact equality. Python may copy their
declared text into its reference header after scope checks; this does not
independently authenticate the R runtime. Cross-runtime reproducibility is not
asserted by omitting or normalizing these fields. Native outputs/candidate rows
are checked by the local harness, **not encoded or authenticated by this
value-only format**; no historical input-to-output binding is claimed.

## 7. Resource limits and transport

| Bound | Required synthetic limit |
| --- | --- |
| Grid | Each dimension≤9;≤81 cells; one grid per transcript |
| Observations | 3–24 batches, complete triples;1–32 slots/batch;≤512 total slots |
| Raw representation | Four/eight-byte scalars only; batch body≤551 bytes |
| Binary transcript | ≤16384 bytes; no nesting/recursion; check before allocation |
| S2F report accepted by adapter | Existing≤1 MiB seal bound; reject oversized/unsupported input, never alter S2F limits |
| Future native fixture harness | ≤32 candidate rows;≤8 inspection iterations; configure public S2F limits max_calls≤24 and max_values≤512; preserve native STEP_LIMIT |
| Future process limits | Each R/Python stage:30s, TERM then KILL after2s;256 MiB enforced process-memory budget. If enforcement/capabilities unavailable, NOT_RUN/STOP rather than a claim of compliance. |

Maximum header length is206 bytes; frame overhead≤24*9 bytes; slot data≤512*17
bytes; trailer14 bytes: an accepted transcript is at most9140 bytes under these
joint limits. The16384 ceiling remains a strict defensive bound, not permission
to insert padding. These are **proposed caps**, not measured performance results.

Pure future codecs operate on bytes/in-memory records. A separate approved
synthetic harness may write one private temporary binary transport file: the
R stage must exit0, close a complete bounded file and pass local checks before
the Python stage is started. Then unload R's container and load python-geo;
never nest their wrappers. Python reads at most16385 bytes and rejects overflow.
No real raster, original LOW CSV, source-data write or CSC job is involved.
A completed file/framing marker is not tamper-proof custody or source proof.

## 8. Read-only detached S2F dependency

No merge, cherry-pick or implicit vendoring. The future test host selects exact
Git objects, not a moving branch or arbitrary working-tree file:

| Allowlisted S2F source at `477c5b13d5714d618c9c9de88f5f80290b53d994` | Required code SHA256 |
| --- | --- |
| `R/02F_water_connected_route_diagnostics.R` | `36df1b8181cb9c604f82c3c11970ec2d553bbb59385d4a693ae5f72159447ccf` |
| `diagnostics/water_connected_graph_design/s2f_synthetic_02f_observer.R` | `81e8fa53a6117facb6cd70e3c03a2c3cd79eef77b75cda074011095ad88ab9dc` |

Reviewed future mechanism:

1. User selects an already available canonical local Git object store. Verify
   exact commit and both allowlisted blobs; disable replacement objects and
   lazy fetch (`GIT_NO_REPLACE_OBJECTS=1`, `GIT_NO_LAZY_FETCH=1`). A partial clone
   missing objects or Git lacking the required offline behavior STOPs; no network
   fetch, checkout, branch switch, hook, submodule or LFS/filter invocation.
2. A bounded host selector reads raw blobs without text conversion, verifies
   their SHA256 against the table, and captures them once in memory. Require the
   native blob in the new harness's own pinned base to match too; divergence STOPs.
3. Produce a private disposable R loader containing only **hex literals of those
   verified bytes** and fixed decoding/source instructions. No unescaped source,
   data path, shell command or user field is interpolated. Decode into raw buffers
   and source those captured code texts in an isolated environment with reviewed
   standard R dependencies (including stats), preserving the functions unchanged.
   Never reread a mutable draft checkout after verifying different bytes.
4. Retain code identities in the local test receipt. Do not source the old
   75-test runner, config, pipeline, production Terra adapter or an unpinned
   helper. Delete only the harness's own temporary files; earlier checkouts and
   PR branches remain untouched.

This selector/loader is **not implemented here**. Its exact byte embedding,
missing-object/offline behavior and source-integrity negative tests are required
before integration. Private temporary code and local hashes address accidental
substitution; a malicious same-user/host administrator is outside this local
synthetic trust boundary. Code pinning is not authenticated source-data lineage,
an immutable production snapshot, or a historical consumer witness.

## 9. New acceptance matrix — entirely NOT_RUN

| New test group required before implementation acceptance | Status |
| --- | --- |
| All six role/native-type combinations, integer/double3 remaining distinct | NOT_RUN |
| NA_INTEGER, NA_REAL and NaN payload/sign preservation, ±0, subnormal and ±Inf bits | NOT_RUN |
| Native callback order, duplicate/cell-type identity, complete triplets and all-four-output parity | NOT_RUN |
| Independent Python expected frames, lossless roundtrip and whole-reference byte match | NOT_RUN |
| Unknown versions/profiles, v1 input rejection, widths/tags/lengths and trailing bytes | NOT_RUN |
| Wrong/reordered roles, cell substitutions/permutations, missing batch/triplet and complete-triplet removal | NOT_RUN |
| Bit or NA/NAN-tag alteration with valid syntax and recomputed content digest | NOT_RUN |
| Missing/altered dependency source, working-tree substitution, wrong code pin/hash, missing offline Git object and loader tampering | NOT_RUN |
| Zero observations, cap exhaustion, unsupported runtime representation and interrupted R→Python handoff | NOT_RUN |
| Unverified dtype declarations cannot coerce values or grant source/scientific approval | NOT_RUN |

For this documentation-only task: **new executable tests PASS=0, FAIL=0;
all10 planned groups NOT_RUN**. No R/Python model or codec tests ran. Prior
S2I-B/1 seven-test, S2F75-test and B/2 five-probe results retain their historical
scopes and were not repeated. Documentation reference/scope checks and
`git diff --check` are separate static checks, not executable acceptance tests.
Stop after publishing this design for review; no implementation or CSC
instruction is authorized by publication or structural agreement.

[review]: https://github.com/annasuuronen/MaaltaMerelle/blob/1282b87e9b934879993c56d6c3b3a9e7a3d78241/diagnostics/water_connected_graph_design/S2I_B2_NATIVE_02F_INTEGRATION_PLAN.md
[native]: https://github.com/annasuuronen/MaaltaMerelle/blob/477c5b13d5714d618c9c9de88f5f80290b53d994/R/02F_water_connected_route_diagnostics.R#L139-L218
[s2fvalues]: https://github.com/annasuuronen/MaaltaMerelle/blob/477c5b13d5714d618c9c9de88f5f80290b53d994/diagnostics/water_connected_graph_design/s2f_synthetic_02f_observer.R#L28-L66
[s2fobserver]: https://github.com/annasuuronen/MaaltaMerelle/blob/477c5b13d5714d618c9c9de88f5f80290b53d994/diagnostics/water_connected_graph_design/s2f_synthetic_02f_observer.R#L111-L242
