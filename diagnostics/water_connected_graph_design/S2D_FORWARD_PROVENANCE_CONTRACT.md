# S2D — forward-only D8 / 02F run provenance contract v1

**DESIGN_ONLY · NOT_IMPLEMENTED · NO_RUN_AUTHORIZATION.** Issue #56;
stacked on [G5A draft PR #55](https://github.com/annasuuronen/MaaltaMerelle/pull/55),
parent `e1c94b876d5b5ed6a0a485445d011c384cdc9e5c`.
This document specifies evidence for a **future, separately authorized** run.
It adds no recorder, verifier, trusted signer, pipeline hook or execution command.
It cannot authenticate a past run or enable real-data mode in existing adapters.

`NATIONAL=LOCKED` · `MODERATE=REVIEW_REQUIRED` ·
`hydrological_validation=NOT_ASSESSED` ·
`channel_interpretation=NOT_ASSESSED` · `routing_authorized=false` ·
`outlet_selection=UNASSIGNED`.

## 1. Source inspection and available native formats

The following findings come from reading repository source at the exact parent,
not executing R/configuration, reading CSC files or accepting a directory name
as a producer commit. Source references below refer to that parent revision.

| Inspected source | Observable code contract | Provenance gap |
| --- | --- | --- |
| [`R/00_pipeline_config.R`](../../R/00_pipeline_config.R#L47) | Mode and TEST_ID are environment-dependent; EPSG:3067, 2 m, Whitebox pointer scheme, `OVERWRITE=FALSE`. SOURCE_TEST_ROOT and RUN_ROOT are independently overridable. NATIONAL explicitly stops. Sourcing config creates directories. | A default path or branch name cannot establish the historical environment, exact bytes or executing code. This inspection did not source config. |
| [`R/01_prepare_hydrology_inputs.R`](../../R/01_prepare_hydrology_inputs.R#L453) | Writes unversioned `01_input_manifest.csv`, header `key,value`, 14 native keys listed below. Paths are normalized. Writes separate `01_input_QA.csv`, header `item,value`, 14 items. Lake elevations derive from lake IDs and the RANTA10 `korkeus_m` attribute, with an existence/reuse guard. | No input digests/sizes, producer SHA, runtime object binding, D8 output identity, authenticated completion or independent witness. `pipeline_version` is not a schema version or Git commit. CSV writes do not supply an atomic signed run bundle. |
| [`R/02_build_baseline_hydrology.R`, 02A](../../R/02_build_baseline_hydrology.R#L78) | Reads prepared DEM, source lake-ID and derived lake-elevation rasters. LAND_RAW masks lake cells; LAND_FILL uses FillDepressions with `fix_flats=TRUE`; LAND_WATER covers LAND_FILL with lake elevations. STORAGE is separately filled from LAND_WATER with `fix_flats=FALSE`. Several stages reuse existing files. | These are distinct surfaces and production histories. A current LAND_WATER/STORAGE equality does not authenticate their creation. Names do not guarantee types: LAND_RAW's `_FLT8S` basename is written as FLT4S in this code. Record actual dtype rather than trusting a suffix. |
| [02B D8 producer and reader](../../R/02_build_baseline_hydrology.R#L714) | Calls `whitebox::wbt_d8_pointer(dem=f_land_water, ..., esri_pntr=FALSE)` only if the final pointer is missing or OVERWRITE. Temporary WBT output is rewritten FLT8S to `d8_pointer_land_water_FLT8S.tif` and the temporary file is deleted. Then `rast()` opens final pointer and source water_class/lake_id. | Generation, temporary WBT output, final rewritten output and consumer object are separate identities. The existence guard can reuse an older pointer. Neither output path nor present hash proves which object an old consumer used. |
| [02C neighbor evidence](../../R/02_build_baseline_hydrology.R#L1551) | Uses pointer zero cells, source water_class/lake_id and LAND_WATER elevations. Writes zero-cell and water-neighbor CSVs, including component/cell IDs and heights. | The CSVs do not independently bind those input versions or the zero-component assignment process. STORAGE is not the elevation source for these fields. |
| [02F caller](../../R/02_build_baseline_hydrology.R#L12617) and [`R/02F_water_connected_route_diagnostics.R`](../../R/02F_water_connected_route_diagnostics.R#L4) | Caller passes existing `ptr_land_water`, `water_class`, `lake_id`, DEM dimensions, `cell_values` and `max_steps=min(ncell(dem),1000000)`. The callback indexes the supplied raster object and converts values to numeric. Four 02F CSVs are written after QA. | No effective-object/content attestation occurs at the consumer boundary. File-backed terra objects can read lazily; hashing an object descriptor is not hashing values. Route QA and CSV summaries are not an authenticated read transcript or physical outlet approval. |

Native 01 manifest keys, exactly as emitted at this revision:

```text
pipeline_version, run_mode, test_id, pointer_scheme, cell_size_m,
stream_threshold_ha, dem, ranta10_gpkg, lake_id_raster, river_area_raster,
river_line_raster, water_class_raster, water_mask_raster, lake_elevation_raster
```

Native 01 QA items:

```text
dem_cols, dem_rows, dem_res_x, dem_res_y, xmin, xmax, ymin, ymax,
ranta10_lakes, ranta10_river_areas, ranta10_river_lines,
lake_heights_valid, lake_heights_missing, lake_ids_raster
```

Repository filename/content inspection found **one native 01 manifest writer**
and this QA format; no original `01_input_manifest.csv` / `01_input_QA.csv` is
tracked here. Their actual CSC contents and any untracked historical variants
were not inspected. The S2C constants and temporary fixture builder encode this
14-key/14-item format; invented fixture values are not original reports.
[S2B's `s2b.synthetic.v1` JSON](S2B_READONLY_ADAPTER.md) is a separate synthetic
binding contract, not a discovered historical 01 format. The existing
[`csc_run_manifest` JSON](../../automation/csc/run_manifest.schema.json) is an
orchestration request for `READ_EXISTING_CSC_REPORTS`, not a D8 producer ledger
or execution approval. Neither can be relabelled as S2D evidence.

An actual variant with additional/missing fields requires separate review and
an explicit schema migration. Do not append a `producer_commit` to an old 01 CSV,
silently adapt S2C's parser or replace historical metadata with a new ledger.
This contract proposes a separate, versioned forward record.

## 2. Historical STOP is permanent for the currently missing link

Retain [S2C's precise conclusion](S2C_ORIGINAL_SOURCE_PREFLIGHT.md):

```text
overall_status=STOP
RUNTIME_INPUT_LINEAGE=NOT_ASSESSED
RUNTIME_PRODUCER_COMMIT=UNKNOWN
SOURCE_AUTHENTICATION=NOT_ASSESSED
stop_reason=RUNTIME_PRODUCER_LINK_UNVERIFIED_NO_PIXEL_PERMISSION
```

No result in S2D or G5A changes these historical fields. A future run receives a
new identity and cannot overwrite, backdate or impersonate the old run.

| Claim | What surviving read-only artifacts could establish, subject to separate access approval | What remains unestablished |
| --- | --- | --- |
| A saved CSV matches an earlier recorded SHA256 | Identity of complete CSV bytes relative to that digest, if the earlier record's source is known. Native schema, selected route identities, arithmetic and reported neighbor relations can be checked. | Authentic producer, exact consumed pointer/masks or physical correctness. A copied digest is only a claim until its evidence source is authenticated. |
| Current TIFF metadata matches the reported LOW grid | Present dimensions/CRS/affine/dtype/NoData, within permitted metadata scope. | Historical TIFF contents, full pixel equality, D8 correctness or which version was read by old 02F. S2C does not hash TIFF pixels. |
| Git source describes a producer/consumer relationship | Behavior of that reviewed code; canonical commit existence and source identity can be checked independently. | That this commit actually ran, with these environment overrides, binaries and inputs, on the old job. |
| A Slurm log says COMPLETED or QA says PASS | A retained, authenticated scheduler/log record may establish job completion or the checks it actually logged. | Input lineage, full route continuity, scientific validation or accepted outlet. A job-ID alone does not establish even the log's authenticity. |
| A later small-window replay agrees with six summaries | Conditional consistency of supplied versions and those route observations, after separate pixel-read authorization. | Retrospective proof of old in-memory pointer identity; agreement is not proof of historical origin. |
| An independently authenticated old runtime record is later found | It may resolve specifically covered links after review of signatures, trust root, scope, input versions and consumer binding. Preserve it as additional evidence with a dated review. | Do not assume such a record exists. It cannot be reconstructed from today's hashes, timestamps, paths or successful reruns. |

With the artifacts currently available in this checkout, the exact historical
02F input-to-runtime binding is **NOT_ASSESSED**. No historical producer digest
is fabricated here. The historical reported 02F SHA in S2C remains a reported
CSV-version reference, not a pointer hash or producer attestation.

## 3. Four separate decisions and their chain of trust

These decisions are independent fields, not a ladder that automatically grants
the next permission:

| Field | Required evidence for a positive technical finding | What it never implies |
| --- | --- | --- |
| `checksum_status=MATCH` | Independently recomputed complete bytes match a declared SHA256 and size. Record where the declaration came from; a self-declared match is only internal consistency. | Verified producer or consumed object; scientific validity; routing permission. |
| `producer_lineage_status=VERIFIED_IN_DECLARED_SCOPE` | Independently witnessed links between pinned code, effective inputs, invocation and completed outputs, verified against a preapproved trust root and immutable record. Scope and any unverified upstream roots must be explicit. | Hydrological validation or an approved physical outlet. |
| `hydrological_validation=NOT_ASSESSED` | A future scientific assessment would require separately approved independent evidence and review criteria. | A checksum, CI PASS, scheduler completion or reproduced route cannot grant it. No automatic VALIDATED decision is specified. |
| `routing_authorized=false`, `outlet_selection=UNASSIGNED` | Physical routing/outlet acceptance belongs to a separate approval procedure, outside this contract. | Even independently verified lineage does not select a candidate, modify D8 or authorize a national run. |

**Proposed trust chain:** approved run specification and pinned trust root →
independently witnessed source/environment and immutable inputs → observed D8
producer/materialization → effective consumer binding at 02C/02F → closed output
files → verified completion attestation → independent verifier receipt. Every
arrow needs evidence; a JSON field claiming `approved=true` supplies none.

The producer and verifier must have distinct roles. A future trusted witness
must observe the approved executable/instrumentation, input snapshot IDs,
consumer binding and completion while the run occurs, and anchor these events
in storage the producer cannot rewrite. The witness signs the manifest digest,
run/attempt ID, event-chain root, approved-spec digest and observed outcome using
an identity/key whose public fingerprint and scope were approved **outside** the
producer-supplied document. The verifier checks that prior trust record, signature,
identity, event ordering, revocation/validity policy and scope independently.
A public key embedded in an untrusted manifest does not establish trust.

This can be implemented later by an independently operated attestation service
or a reviewed, isolated recorder with separately controlled signing identity and
append-only storage. An offline witness is acceptable only if its contemporaneous
observations and protected signed record provide the same bindings; a later
human signature on a producer's assertions is insufficient. **No such witness,
key enrollment, storage protection or independent verifier is implemented or
claimed available here.** Until they exist and are tested, status is
`RECORDED_UNVERIFIED` / `NOT_ASSESSED`, never verified lineage.

Threat model: detect accidental substitutions, mutable-path races, mismatched
runs and forged/self-asserted producer metadata. Verification relies on the
approved observer and immutable storage behaving as specified. It is not a claim
to defeat a compromised OS, signer or storage administrator. Loss of those trust
assumptions invalidates the technical verification and requires STOP/review.

## 4. Proposed forward record and artifact identities

A future separate JSON schema, provisionally named
`maaltamerelle.forward-provenance.v1`, must specify exact allowed keys/types,
size limits, duplicate-key rejection, canonical encoding and signature domain
separation before implementation. Unknown versions/fields STOP; no shell or
arbitrary command embedded in the manifest is executed. This Markdown is not
that schema's implemented validator.

| Record group | Mandatory proposed fields and constraints |
| --- | --- |
| Run | Globally unique `run_id` and distinct `attempt_id`; schema/version; `evidence_kind=CONTROLLED_NEW_RUN`; approved scope/test/tile/grid IDs; UTC start/end plus ordered monotonic stage events; immutable approval-spec reference and digest. Parent/reuse IDs are references, not reused run identities. |
| Source code | Canonical `annasuuronen/MaaltaMerelle` / repository ID 1407101587; exact 40-hex Git commit, verified clean checkout; full source-tree identity and SHA256 of actual scripts/config/helper files used, including dynamically sourced code. Record working directory and script/argv as structured fields. Branch names are hints only. Dirty/unpinned code STOPs. |
| Effective configuration | Allowlisted HYDRO overrides and their resolved values, SOURCE_TEST_ROOT/RUN_ROOT/DIR_01/DIR_02, mode, test ID, grid, OVERWRITE/reuse decisions, route selection, max_steps and numerical parameters. Hash a canonical resolved configuration. Do not dump credentials or the entire environment. Record config defaults actually chosen as well as overrides. |
| Environment | Host OS/architecture, R and terra/whitebox package versions, actual WBT executable resolved path/version/SHA256, module stack, GDAL/PROJ and CRS database versions, locale/time zone, thread settings, container digest if used; scheduler allocation/job/attempt identity and caps if a job was separately authorized. Package version alone does not bind the invoked binary. |
| Artifact identity | Unique role ID, source type (`SOURCE_DATASET`, `DERIVED_FILE`, `IN_MEMORY` or `EXISTING_UNVERIFIED`), declared/resolved path where applicable, immutable storage version/snapshot ID, complete byte size and SHA256, acquisition time/event, claimed expected hash plus its authority reference separately, producer-stage/run references or explicit UNKNOWN, and verification scope/status. No invented path for an in-memory object. |
| Raster interpretation | Grid/global cell identity, dimensions/bands, semantic CRS definition and axis/units plus EPSG:3067, exact six-element affine transform, extent/resolution, row/column/index bases, band dtype, scale/offset, typed NoData and masks. Bind all sidecars/dependencies that affect reads or reject them. Explicit source surface and `WHITEBOX_D8`, `esri_pntr=false`; zero is not NoData. |
| Stage links | Stage invocation ID, actual effective input IDs/digests and output IDs/digests, start/end, process exit, cache/reuse decision and authenticated predecessor records; helper code/config digest. D8 records actual WBT argv and temporary-to-final conversion. 02C/02F records the exact objects passed and reading adapter. |
| Results and review | Complete output artifact list, schema/row counts and hashes, resource observations, explicit stage verdicts/STOP reasons and NOT_RUN dependencies; observed witness event root and detached signature; independent verifier receipt referencing the complete manifest digest. Scientific/outlet fields remain locked. |

Content hashes identify complete bytes, not filenames or truncated/sampled
content. A digest record must say `NOT_RUN`, with null digest/size where unknown,
until actual measurement; never use a zero/fake hash as evidence. Metadata/stat
observations and logical-value digests are separately typed, not substitutes for
a complete file hash. For a truly in-memory argument, `file_sha256` and
`file_size_bytes` are null with reason `NO_FILE_REPRESENTATION`; a measured,
versioned `logical_stream_sha256` and `logical_stream_bytes` identify its frozen
effective values instead. Materialization creates a separately identified file
artifact and an explicit equivalence link, not a fabricated original filename.
Related multi-file datasets require a closed, ordered
member ledger (for example GeoPackage WAL/journals must be absent or captured
consistently). Undeclared sidecars or mutable aliases STOP.

For LOW, the existing documented grid is 6000×6000, EPSG:3067, 2 m, affine
`[199000,2,0,6911000,0,-2]` with 1-based row-major cell IDs. This is a documented
reference, **not a current CSC measurement**. The proposed recorder must bind and
verify the actual approved grid. Future other tiles require their own grid IDs;
this LOW origin is not a national default.

Whitebox native code mapping, as used by 02F, must be recorded explicitly:
`1=NE, 2=E, 4=SE, 8=S, 16=SW, 32=W, 64=NW, 128=N`.
Zero, NA/NoData, invalid pointers, STEP_LIMIT and domain exit remain diagnostic
outcomes; neither a raster edge nor a transfer boundary implies a coastline.

## 5. Capture points: the exact input actually consumed

Capture source identity **before** a stage can read it, effective-object identity
at the consumer boundary, and sealed output identity **after** writers close.

| Stage / role | Required input-to-output binding in a future run |
| --- | --- |
| Stage 01 | Actual DEM, RANTA10 dataset/layers and lake-ID/river-area/river-line/water-class/water-mask versions; height-field selection. Bind derived `ranta10_lake_elevation_m.tif`, original-style 01 CSV bytes and configuration to their producer. The prepared DEM is an existing input, not permission to reconstruct it. Missing upstream preparation history is recorded separately. |
| LAND_RAW / LAND_FILL / LAND_WATER | Distinct stage records, effective input hashes, actual output dtype/NoData and reuse state. Record fill tool/version/parameters, including flat treatment and attempts, only for stages actually executed. A prior trusted stage artifact may be reused; do not re-fill merely to make a new ledger. |
| D8 generation | Hash/bind actual LAND_WATER used by the WBT process, executable and native pointer convention. Capture temporary WBT pointer digest/size after close **before** conversion/deletion; link the final FLT8S pointer's byte and logical-value identities to that conversion. STORAGE must not be substituted as the routing input. |
| 02C | Bind effective pointer, water_class, lake_id, LAND_WATER elevations, zero-component selection/labeling and code/config. Hash all emitted 02C reports, particularly `02C_zero_pointer_cells.csv` and `02C_zero_pointer_water_neighbors.csv`, after close; retain component/neighbor IDs and row order, without rewriting originals. |
| 02E → 02F | Bind candidate-edge table content and schema/order, origin/receiver identities, 02E producer link, actual nrow/ncol, max_steps and callback implementation. Bind the effective pointer, water_class and lake_id **at the 02F call**, not just source filenames recorded in 01. |
| 02F completion | Hash complete `02F_water_connected_route_evidence.csv`, `02F_water_connected_candidate_route_edges.csv`, `02F_water_connected_route_summary.csv`, `02F_water_connected_route_QA.csv`; record exact headers/row counts and join keys to candidate edges. Route IDs are scoped to that output version, not globally reusable identities. |

### On-disk objects, races and reuse

A future approved runner must use explicit, immutable input versions in a new
run workspace, protected from concurrent writes/replacement through **all**
aliases. A read-only view of an immutable snapshot/versioned object is preferred.
Resolve/validate paths and version IDs before opening; reject traversal,
unapproved symlinks/hardlink aliases, special files and unlisted dependencies.
The witness binds the selected snapshot, digest and actual consumer mount/path.
Record descriptor/file identity and bounded before/after checks as additional
substitution checks; terra/GDAL lazy reopening must resolve to the same protected
version throughout the call.

Hashing a mutable pathname and later opening it is not a sufficient chain.
Neither chmod, an advisory lock, matching size/mtime nor even equal pre/post
hashes rules out an intervening A→B→A substitution. A read-only mount is also
insufficient if the underlying files remain writable elsewhere. If the approved
snapshot/immutability guarantee cannot be established, STOP verification; do not
report lineage verified from endpoint hashes alone. This protection mechanism
and its tests remain implementation work requiring separate approval.

`OVERWRITE=FALSE` is not a provenance guarantee. Reusing an existing pointer may
establish a **new** witnessed 02F-consumer-to-file binding, but its D8 producer
lineage stays NOT_ASSESSED unless an authenticated predecessor record exists.
Record these links separately. Do not force regeneration, relabel old bytes as
newly generated or silently adopt a file because it has the expected basename.

### In-memory effective rasters

A terra `SpatRaster` object may be a lazy file reference or a computed in-memory
intermediate. `serialize()` of an external-pointer descriptor, source-path list,
R variable name or digest of a different on-disk TIFF cannot prove its contents.
Record whether the actual argument is file-backed, in memory or composite, all
backing members, transformations and its effective grid/validity semantics.

The future implementation must bind a **frozen effective snapshot actually
passed to the consumer**, using one of two preregistered, tested approaches:

- Materialize the final effective values into a new run-private immutable input
  artifact, record byte and logical-value digests, reopen that exact artifact as
  the consumer input, and verify lossless logical equivalence. This is a future
  explicitly approved materialization, not permission to rewrite original D8 or
  generate a new hydrological routing solution.
- Use a reviewed instrumented in-memory reader with a frozen value snapshot,
  logical-value digest and independently witnessed call/read binding. Its read
  transcript binds ordered cell IDs and actual returned pointer/water/lake
  values to that snapshot and the resulting output. A transcript hash without
  the observed consumer link or without an inspectable retained transcript does
  not prove which values were consumed.

Define and version the logical encoding before implementation: band/row/column
order and grid header; explicit validity tags separating valid zero, R NA,
non-NA NaN and finite/invalid numbers; lossless numeric representation and exact
integer lake IDs. An explicit IEEE-754 binary64 value encoding with defined byte
order, NA tags and no rounding is a candidate, to be tested against actual terra
semantics. Preserve original byte hashes separately; re-encoding need not retain
byte equality. Generic JSON numbers, coercion to Float32, pointer rounding and
assuming missing water-class equals missing terrain are not acceptable shortcuts.

Changes after snapshot binding require a new object/stage identity. If the
consumer's effective state cannot be frozen and bound, set
`EFFECTIVE_INPUT_BINDING=NOT_ASSESSED` and STOP. A full logical-value scan/hash is
a separately budgeted future operation, not part of this documentation task or
an implicit expansion of S2C's metadata-only permission.

## 6. Publication, verification and incomplete runs

Proposed sequence, not implemented instructions:

1. Register a reviewed spec, trust root, exact code/environment/input versions,
   limits and permitted stages; independently verify the approval exists and
   matches the attempt. A valid manifest is not that approval.
2. Exclusively allocate a new run/attempt workspace and append-only ordered
   stage-event ledger. The witness retains the signed start event outside the
   producer's write authority. Existing run directories/manifests are never
   overwritten. No automatic retries or continued dispatch are implied.
3. Bind immutable inputs; record each executed or authenticated reused stage,
   effective consumer call and complete closed outputs. Keep failed/partial
   observations auditable; downstream stages are NOT_RUN when required inputs
   or limits fail. No resuming censored routes from other observations.
4. Publish a final producer manifest only after all required stages/writers have
   ended and byte identities/checks are sealed. Write a temporary file in the
   same filesystem, flush file and directory as supported, then use an atomic
   **no-replace** publication primitive. Plain rename that overwrites an existing
   manifest is forbidden. An interrupted publication is not a completed record.
5. Use a defined canonical UTF-8 representation and detached SHA256/signature;
   the signed payload excludes its own signature/hash to avoid self-reference.
   The witness binds this digest and the event-chain root to its recorded start
   and outcome. Retain signed failure records as INCOMPLETE, never successful
   manifests with missing fields. If only a start or partial ledger survives,
   completion is NOT_ASSESSED and verification STOPs.
6. An independent verifier rechecks trust/approval scope, stage linkage, sealed
   artifacts, schemas/hashes, input/output version consistency and witness
   observations, then appends a separate immutable receipt. A cryptographic
   signature alone establishes a signer's assertion, not the truth of an
   unobserved consumer binding. Producer completion is not verifier completion.

Do not edit a final record to fix an error. Publish a dated amendment linked to
its predecessor, preserving the original and marking the discrepancy; a new
attempt is needed for changed computation. Keep complete protected evidence in
approved project storage. Export only a separately approved small QA/receipt
allowlist to GitHub; no original rasters, unrestricted logs or credentials.
If a public summary redacts paths, it references the protected original's digest
and is labelled a summary, not a silently altered signed manifest.

## 7. Controlled-run acceptance and preregistered negative tests

Before any implementation or execution, a later task must specify the finite
stage set, actual input availability, approved code/binary versions and one
scientific question. It must set positive numeric caps for files/bytes hashed,
pixels/read events (if permitted), wall time, memory, CPU/threads, temporary disk
and report size; declare an interruption policy and exact acceptance criteria.
Unknown limits or unavailable versioned inputs STOP before computation. Hashing
large inputs is charged to the budget, not hidden in a login-node preflight.
Authenticated immutable cache artifacts may avoid repeated heavy stages; lack
of cache lineage is a STOP/review question, not an automatic request to rerun.
No numeric production resource estimate is invented from synthetic G5A timings.

Technical acceptance requires exact source/version and schema matches, complete
required hashes, valid ordered producer-to-consumer links, witnessed frozen
inputs, bounded resources, closed outputs and independently verified receipt.
The scope must name any upstream source-authentication gaps; verification of an
immediate stage cannot be advertised as verification of its entire ancestry.

Proposed statuses for that **future** verifier (all unimplemented):

| Condition | Safe technical outcome |
| --- | --- |
| Only digest declarations; no measurement | `checksum_status=NOT_ASSESSED`, `RECORDED_UNVERIFIED`; required verification STOP |
| Actual bytes match a declaration but no witness | `checksum_status=MATCH`, `producer_lineage_status=NOT_ASSESSED`; lineage STOP |
| New consumer binding witnessed; reused pointer's producer unknown | Consumer binding verified **for new run only**; D8 producer NOT_ASSESSED; complete producer-chain acceptance STOP |
| All scoped stage links and trust evidence independently verified | `technical_status=VERIFIED_IN_DECLARED_SCOPE`; scientific fields remain NOT_ASSESSED, routing false |
| Contradiction, substitution, invalid signature or lost immutable snapshot | STOP with specific failure and preserved evidence; dependent checks NOT_RUN |
| Missing manifest/completion/witness/input, unknown scope or resource exhaustion | `INCOMPLETE` / NOT_ASSESSED plus STOP; no success exit that enables the next stage |
| Question about a physical connection or outlet | REVIEW_REQUIRED scientific decision; no automatic graph arc or accepted outlet |

The future test plan must include the following **NOT_RUN** negative cases; they
are specifications, not assertions executed in this task:

| Adversarial case | Required observation / outcome |
| --- | --- |
| Correct path, wrong pointer version or replaced symlink/alias | Detect selected-version mismatch; STOP before consumer. |
| Same dimensions and mtime, different input bytes | Digest/snapshot mismatch; STOP. Metadata equality is insufficient. |
| A→B→A mutation during lazy reads | Immutable storage prevents it or witness invalidates the run; endpoint hashes alone cannot pass. |
| Same on-disk TIFF, modified in-memory pointer or mask | Effective logical snapshot/read binding differs; STOP; no fallback to source-file hash. |
| ESRI convention or silent Float32/ID rounding | Convention/lossless-value mismatch; STOP. |
| Missing 02F runtime manifest, start-only ledger or missing output | INCOMPLETE/STOP, dependent parity NOT_RUN. |
| Self-declared producer SHA/key or changed signer trust root | Reject untrusted lineage even if hashes match. |
| Valid signature but unobserved consumer, wrong scope/run/attempt or replayed receipt | Reject binding/replay; prior success does not authenticate this run. |
| Different WBT binary/helper/config with same package label | Executable/code/config identity mismatch; STOP. |
| Existing OVERWRITE=FALSE artifact without predecessor | Mark reuse and unverified producer; do not silently regenerate or accept lineage. |
| CSV from another run, changed unselected rows, reordered/duplicated route IDs | Whole-file hash/schema and stage/version identity checks fail; preserve both records. |
| 02C and 02F from different pointer/mask/LAND_WATER versions | Distinct stage input identities exposed; comparison STOP. |
| Unknown JSON schema, duplicate keys or hidden sidecar dependency | Reject, no guessed migration or undeclared reads. |
| Crash during final publication, pre-existing final name or two concurrent publishers | No replacement and no false completed manifest; partial evidence retained. |
| Hash/pixel/time/memory/report budget exhausted | Controlled INCOMPLETE/STOP; never substitute a sampled hash or silently skip required evidence. |
| COMPLETED, matching checksum, CI PASS or D8_ZERO_INTERIOR presented as approval | Technical fields may record observations; scientific locks/outlet state unchanged. |

A later positive control must demonstrate that an independently verifiable new
run is accepted only in its declared technical scope and that each negative
case fails safely. Test failure is not repaired by weakening provenance or
hydrological gates. NATIONAL remains blocked even with a valid technical ledger;
this plan describes eventual nationwide requirements without authorizing them.

## 8. Consequences for subsequent work

| Subsequent task | Evidence this contract would provide after implementation and independent verification | Additional gate that remains |
| --- | --- | --- |
| Real six-route S2A parity | Authenticated **new-run** pointer/water/lake versions, exact 02F/candidate identities, grid, step budget and output ledger for a reproducible comparison. | Separate bounded pixel-read approval; current S2B real-data prohibition and historical S2C STOP remain. Comparing an old CSV with new inputs is only conditional cross-version consistency, not recovered historical lineage. Existing route IDs must be checked with origin/start/output version, not assigned to changed routes. |
| Scientifically reviewed WATER_CONNECTED D8 | Reproducible technical identity of reviewed evidence and any future explicitly specified producer; visible unresolved inputs and candidate states. | Independent scientific assessment of actual terrain/water connections, direction and uncertainty; separately approved physical lake outlets and routing method. First-water contact, S1 readiness, shoreline adjacency and 02F zero/return statuses never create active edges. |
| Final multi-tile accumulation | Versioned input graph/grid/ownership and producer/run identities could be bound to future output receipts. | Approved physical graph/outlets, unique cell ownership, shared lake aggregation, halo and seam reconciliation, unknown imports resolved, global acyclicity, regional performance and independent validation. G5A proves tiny synthetic parity only; no national threshold or sea connection follows. |

This task's evidence is **source inspection and a documentation contract only**.
No original report/metadata/pixel access, runtime recorder or witness verification,
R execution, synthetic regression rerun, D8 generation, new accumulation raster,
hydrological rerun or CSC/Slurm job was performed. Runtime acceptance tests and
all scientific decisions remain NOT_RUN / NOT_ASSESSED. Existing synthetic PASS
reports retain their original scope and are not claimed as new lineage evidence.

Only this new Markdown file is delivered. Pipeline modules, existing source
manifests, tests, archives, rasters, prior PR branches and scientific locks are
unchanged. Implementation of capture hooks, effective-value encoding, immutable
storage, signer enrollment, independent verification and a separately approved
controlled run are subsequent work, not capabilities implemented by this PR.
