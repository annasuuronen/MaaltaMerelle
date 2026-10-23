# S2I-B/2 — native synthetic 02F interoperability: integration STOP

**PLAN_ONLY / ADAPTER_NOT_IMPLEMENTED / NO_RUN_AUTHORIZATION.** Reviewed
2026-10-23 against pinned S2I-B/1
`8f4015929772dc14b2e8af75b82a102da46ce725` and S2F draft PR #61 at
`477c5b13d5714d618c9c9de88f5f80290b53d994`.

The requested exact native-callback interoperability cannot be implemented over
the frozen v1 role/type contract without a representation decision. The user
explicitly requires: “If S2F integration requires changing previously validated
components, stop at a documented integration plan rather than improvising
changes.” This is that stop: **no adapter or revised protocol is introduced**.
No validated component or prior test evidence is modified.

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

## 1. Exact dependency and callback audit

| Component | Pinned source | Observed contract |
| --- | --- | --- |
| Native consumer | [Original 02F loop][native] | `trace_water_connected_candidate_routes()` queries `cell_values(water_class,cells)`, then lake ID, then pointer **before** applying water precedence. Land is `is.na(classes)`; 255 is not treated as missing by this function. |
| S2F callback | [Reference callback and value encoding][s2fvalues] | Public `s2f_synthetic_values(raster,cells)` returns exactly `raster$values[cells]`, without coercion. Each homogeneous vector is R integer or double; its storage type, validity tags and original 4/8-byte little-endian values are retained. |
| S2F observer entry | [Public wrapper and private callback][s2fobserver] | `s2f_observe_02f(trace_fn,fixture,candidate_edges,...,cell_values=s2f_synthetic_values)` supplies its private `observed_cell_values` closure to the unchanged native consumer. Handles are matched by identity; order, triplet requests, exact returned values and limits are checked. Complete reports expose ordered `calls` and the native `result`; incomplete observations STOP. |
| S2F original fixtures | [Existing chain and delegation recorder][s2ftests] | The land chain uses `NA_real_` WATER_CLASS, double POINTER and integer/NA LAKE_ID. The test's recording callback delegates the same `raster$values[cells]`; it is not another routing algorithm. The 75-case test script was read, not run. |
| Frozen R wire writer | [S2I-B writer][writer] | WATER_CLASS is exactly Byte/NoData255; LAKE_ID is Int32; POINTER is Float64. `s2ib_byte(NA_real_)` rejects `BYTE_VALUE`. Per-role width/tag checks cannot encode eight-byte WATER_CLASS. |
| Independent Python codec | [Role/type checks][codec]; [wire parsing][decoder] | `MM-S2IA` version1 has implicit storage type determined by role, not the R callback vector's storage type. WATER_CLASS width is one byte and its only tags are FINITE/NODATA. Wrong widths, unsupported tags, trailing bytes and invalid role sequences reject. |

The base is a separate draft lineage: `git merge-base` with S2F is
`7324f2c22b3151fffe7b172617bde4d0ef6ee821`; the exact base has **18** commits
unique to it, S2F has **5**. The S2F observer module is absent from S2I-B/1.
The native `R/02F_water_connected_route_diagnostics.R` blobs are identical in
both pins. No merge, cherry-pick, branch rewrite or copied S2F module is included
in this delivery. This new branch starts directly at the S2I-B/1 pin:
`codex/s2i-b2-native-02f-interop-review-v1`.

For the small audit probes only, three exact Git blobs were extracted to a
private disposable local directory and sourced there; no config or pipeline was
sourced. SHA256 below identifies **code**, not datasets or a trusted consumer:

| Exact code blob | SHA256 |
| --- | --- |
| Native 02F, identical at both pins | `36df1b8181cb9c604f82c3c11970ec2d553bbb59385d4a693ae5f72159447ccf` |
| S2F observer at `477c5b13…` | `81e8fa53a6117facb6cd70e3c03a2c3cd79eef77b75cda074011095ad88ab9dc` |
| S2I-B writer at `8f401592…` | `0f702c69e5bd897be28482c39ef1e6d1021d7c974bca8627d683de8ed9f3e03c` |

## 2. Blocking representation mismatch

This is **consumer representation versus declared raster storage**, not evidence
that either accepted component fails its existing contract:

- Actual land callback `NA_real_` has eight raw bytes `a20700000000f07f`, with
  S2F storage type double and tag NA_REAL. v1 WATER_CLASS permits one Byte, with
  NoData255; the R writer rejects this actual response and Python rejects its
  native width. The independently implemented codec agrees on the incompatibility.
- Replacing NA by 255 **before** the native invocation changes a land cell into
  `INVALID_WATER_CLASS`. The unchanged consumer's output therefore changes.
  The audit deliberately demonstrated this only on a second synthetic fixture;
  it did not mutate the original callback/fixture or implement such a substitution.
- Converting responses **after** the invocation can preserve routing behavior,
  but v1 does not preserve the original R storage type and raw representation.
  Actual WATER_CLASS integer3 and double3 have different 4/8-byte S2F encodings;
  projection through `s2ib_byte` produces identical wire bytes. This many-to-one
  mapping cannot establish the requested exact raw typed-value equivalence.
- A declared reversible projection for one narrowly restricted fixture would
  be a separate semantic contract, not exact raw interoperability for the
  existing S2F callback domain. S2F also permits integer POINTER and double
  LAKE_ID vectors, whereas v1 fixes those roles to Float64 and Int32 respectively.

Do not repair this by changing S2F fixtures, treating 255 as native NA, accepting
Float64 under the POINTER role for WATER_CLASS, widening v1's role table/tags, or
calling an unreviewed sidecar “v1”. A finite water-only example would not resolve
the missing native land-callback representation.

## 3. Newly relevant local audit probes actually executed

Only new compatibility probes ran: a 3×3 in-memory fixture, two distinct
origin/start identities querying the same cell, at most six callbacks per
invocation. Initial pointer5=2 leads east from land5 to water-class3 cell6.
The unmodified observer recorded triplets for `(5,5)` then `(6,6)`, preserving
duplicates, and two REACHES_RIVER_LINE results with one transition each.

| Named new probe | Result | Actual observation / expected rejection |
| --- | --- | --- |
| `native_callback_order_duplicate_cells_and_output_parity` | PASS | Six callbacks in exact WATER_CLASS → LAKE_ID → POINTER order; duplicate requests identical; all four native result components serialize identically with and without S2F; native function body unchanged. |
| `v1_writer_rejects_observed_NA_real_water_class` | PASS | Actual recorded response is double NA; raw bytes above; existing writer returns `S2IB_STOP:BYTE_VALUE`. |
| `synthetic_255_callback_substitution_changes_native_result` | PASS | Separate synthetic replacement yields INVALID_WATER_CLASS instead of REACHES_RIVER_LINE; original fixture unchanged. This confirms why substitution is prohibited. |
| `finite_integer_double_callback_types_collide_under_byte_projection` | PASS | Two actual native callback runs retain distinct R integer/double responses; their projected Byte wires collide. |
| `independent_Python_rejects_observed_water_Float64_in_v1_Byte_role` | PASS | Actual R response bytes supplied as WATER_CLASS fail Python encoding with SCALAR_WIDTH; an eight-byte R-NA payload inserted into a one-scalar v1 Byte frame fails decoding with WIRE_TRAILING_BYTES. |

**Audit total: 5 PASS, 0 FAIL, 0 NOT_RUN; no skips.** These are targeted
compatibility/blocker checks, **not five successful adapter tests**. Four ran
under local R4.5.0 (`x86_64-pc-linux-gnu`) and the fifth under Python3.12.14.
R subprocess hard limit: TERM15s/KILL after2s; outer Python subprocess timeout18s.
The observed complete audit wall time was 0.6053s. No CSC execution occurred.

The operator-accepted **S2I-B/1 R4.6.1/Python3.14.5 7 PASS, 0 FAIL, 0 SKIPPED,
TEST_EXIT=0** remains unchanged and **was not repeated**. Neither was S2F's
accepted 75-case campaign. Those results establish their original scopes, not
this integration. New-probe compatibility on R4.6.1/Python3.14.5 is NOT_RUN.

## 4. Minimum integration decision and plan, not implementation

1. **Resolve representation first.** Recommended for separate approval: design
   an explicitly versioned consumer-value extension distinguishing role from
   native integer/double storage type and preserving validity plus exact bytes.
   Keep v1 codec/writer and accepted evidence intact. Specify relation to any
   declared Byte/Int32/Float64 raster representation separately. A new version
   cannot be inferred from these notes or introduced silently.
2. **Review detached dependency loading.** For future synthetic tests, permit an
   explicitly selected read-only S2F checkout/object at exact `477c5b13…`, verify
   code blobs before sourcing, and fail if unavailable or mismatched. Load only
   its observer plus the common native module; no old test runner, config,
   pipeline, automatic fetch/merge or production Terra hook. Any later vendoring
   or branch integration needs explicit review of the minimal source delta.
3. **Use existing public boundaries.** A future pure adapter can consume the
   complete sealed `report$calls` only after `s2f_check_transcript(report)` succeeds,
   encode them in original sequence and leave `report$result` untouched. Do not
   reach into/replace S2F's private closure. Compare original callback requests,
   typed responses and all four native result components independently.
4. **Intersect, never enlarge budgets silently.** S2F admits up to192 calls/
   4096 requested slots, v1 up to24 batches/512 values; both allow ≤32 values per
   call and ≤81 fixture cells. A future adapter needs its own preregistered lower
   caps, must STOP on overrun or zero/incomplete observations, and cannot truncate
   a report and claim COMPLETE. These are source-inspected differences, not new
   large-network tests or authorization to widen existing limits.
5. **Separate R/Python stages on Roihu when later approved.** Run only the new
   targeted synthetic emitter in `r-env/461`, require exit0 and a bounded complete
   output, unload it, then run its independent Python checks under python-geo.
   Never invoke one container wrapper from inside the other. A temporary output
   supplied by the same operator is still self-reported, not authenticated.

The following required integration checks remain **NOT_RUN**, blocked by the
unresolved representation contract and absence of an implemented adapter:

| Future integration check | Required expected behavior |
| --- | --- |
| Actual callback bytes vs independent Python decoder | Exact typed native values, order, grid/run scope, cell identity and duplicates; no unrecorded normalization. |
| Reordered callbacks / wrong roles | STOP before a complete interoperable record can be claimed. |
| Substituted cells, including same-count permutations | STOP on mismatch against the original sealed requests; never repair or deduplicate them. |
| Truncated response, batch, triplet or transport | STOP; successful process exit or a partial summary cannot imply completeness. |
| Modified bytes, including valid alternate encodings | STOP against the original sealed observations. Valid wire syntax alone must not accept different consumed values. |
| Native output parity through the future adapter | All four outputs unchanged; no rerouting, fixtures changed to suit the encoder, or inferred continuation. |

## 5. Delivery boundary

One new documentation file only. The base/head pin, divergence, code equality,
source references and documentation diff are checked; no previous module or
test-result file changes. Full S2I-B/2 interoperability is **NOT_IMPLEMENTED**.
The remaining blocker is the separately reviewed native-type/wire-version
decision plus an explicit detached S2F dependency mechanism, not a request to
repeat accepted tests or run original LOW data. No new raster reads, Terra,
DEM/D8 generation, accumulation, outlet selection, CSC/Slurm jobs, merge,
verified lineage or scientific acceptance are implemented or claimed.

[native]: https://github.com/annasuuronen/MaaltaMerelle/blob/477c5b13d5714d618c9c9de88f5f80290b53d994/R/02F_water_connected_route_diagnostics.R#L139-L218
[s2fvalues]: https://github.com/annasuuronen/MaaltaMerelle/blob/477c5b13d5714d618c9c9de88f5f80290b53d994/diagnostics/water_connected_graph_design/s2f_synthetic_02f_observer.R#L28-L66
[s2fobserver]: https://github.com/annasuuronen/MaaltaMerelle/blob/477c5b13d5714d618c9c9de88f5f80290b53d994/diagnostics/water_connected_graph_design/s2f_synthetic_02f_observer.R#L111-L205
[s2ftests]: https://github.com/annasuuronen/MaaltaMerelle/blob/477c5b13d5714d618c9c9de88f5f80290b53d994/diagnostics/water_connected_graph_design/test_s2f_synthetic_02f_observer.R#L34-L74
[writer]: https://github.com/annasuuronen/MaaltaMerelle/blob/8f4015929772dc14b2e8af75b82a102da46ce725/diagnostics/water_connected_graph_design/s2i_b_synthetic_wire_writer.R#L20-L118
[codec]: https://github.com/annasuuronen/MaaltaMerelle/blob/8f4015929772dc14b2e8af75b82a102da46ce725/diagnostics/water_connected_graph_design/s2i_a_synthetic_value_protocol.py#L14-L27
[decoder]: https://github.com/annasuuronen/MaaltaMerelle/blob/8f4015929772dc14b2e8af75b82a102da46ce725/diagnostics/water_connected_graph_design/s2i_a_synthetic_value_protocol.py#L119-L233
