# S2H — historical 02F effective D8: GitHub evidence audit

**Decision: STOP; `HISTORIC_02F_EFFECTIVE_D8=NOT_ASSESSED`.**
Issue [#66][issue66], reviewed 2026-10-23. No independently verifiable,
contemporaneous producer-to-effective-consumer binding was found in the scoped
GitHub material below. The search adds **no new historical runtime evidence**
beyond S2D and the previously reported operator receipts. It does not establish
that such evidence is absent from inaccessible storage.

Base verified against the canonical remote:
`codex/s2c1-proj-data-env-metadata-v1` at
`332da2852b994e2441c22d66f4d438e0e787c7a0`; initial worktree clean.
Only this new Markdown file is added on
`codex/s2h-historic-02f-github-evidence-v1`, for a draft PR based on #65.

```text
overall_status=STOP
HISTORIC_02F_EFFECTIVE_D8=NOT_ASSESSED
RUNTIME_INPUT_LINEAGE=NOT_ASSESSED
RUNTIME_PRODUCER_COMMIT=UNKNOWN
SOURCE_AUTHENTICATION=NOT_ASSESSED
stop_reason=RUNTIME_PRODUCER_LINK_UNVERIFIED_NO_PIXEL_PERMISSION
TRUE_02F_CONTINUITY=NOT_RUN
NATIONAL=LOCKED
MODERATE=REVIEW_REQUIRED
hydrological_validation=NOT_ASSESSED
channel_interpretation=NOT_ASSESSED
routing_authorized=false
outlet_selection=UNASSIGNED
```

## Scope and evidence classes

Inspected the four R caller/consumer/config/input modules at reported historical
code commit `4bbf22bb39181c8a4c27ebc3e2769766043115b8`; their blobs are unchanged
at the pinned S2C.1 base. That establishes source identity, **not execution**.
Inspected tracked file inventories, relevant artifact-path history and provenance
references in that base, plus these explicitly referenced draft revisions:

| Draft | Pinned revision inspected | Relevant retained material |
| --- | --- | --- |
| S2C #52 | `7324f2c22b3151fffe7b172617bde4d0ef6ee821` | Original metadata preflight and QA |
| S2C.1 #65 | `332da2852b994e2441c22d66f4d438e0e787c7a0` | Isolated PROJ correction; historical STOP unchanged |
| S2D #57 | `eb09f39238dc8852d768ffc7a45cd3365e80d7a2` | Existing forward-only contract, reused without redesign |
| S2F #61 | `477c5b13d5714d618c9c9de88f5f80290b53d994` | Synthetic consumer observations and QA |
| S2G #63 | `99c852e5f6d5d6abb25ece372f74326c79765e64` | Prepared operator gates; later outcomes in discussions |
| LOW #12 | `cd9612aa1cb4dd39bc6b33d825302202b28ef09e` | Existing LOW diagnostics and reported CSC findings |

Also read available bodies/comments of issues #10, #62, #64, #66 and PRs
#12, #52, #57, #61, #63, #65, and the referenced offline CI run below.
No other repository, CSC connection or original data was accessed. GitHub blob
links below pin commits and line ranges. Discussion anchors identify the
particular claim but remain editable records, **not immutable attestations**.
No authenticated API artifact inventory was available; private, deleted/expired
or unlinked artifact contents were not inspected. Conclusions are bounded to
these accessible sources, not an exhaustive claim about all past storage.

`SOURCE_CODE_OBSERVED` means reviewed code; `COMMITTED_ARTIFACT` means a retained
document/fixture exists at that commit, without authenticating its assertions;
`OPERATOR_REPORTED` means a recorded execution claim; `INFERENCE` means a limited
deduction; `MISSING_OR_UNVERIFIED` means the required evidence was not located or
cannot be verified. These classes are not hydrological acceptance levels.

## Source-to-consumer inventory

| Source | Immutable reference / discussion locator | Factual observation or quoted claim | Inference boundary | Evidence class | Next action |
| --- | --- | --- | --- | --- | --- |
| Effective configuration | [Config defaults][config]; [path overrides][paths] | `OVERWRITE <- FALSE`; Whitebox scheme; source/run roots independently overridable. | Defaults and `csc_validation_4bbf22b` directory name do not establish historical settings or executing commit. | SOURCE_CODE_OBSERVED | Keep historical runtime configuration unverified. |
| Native input manifest / QA | [01 writer][manifest] | Unversioned 14-key `key,value` manifest records input paths, including water/lake rasters; QA records grid/counts. | No D8 digest, runtime producer/consumer binding or independent completion witness. Native CSV bytes are not tracked in the inspected trees/history. | SOURCE_CODE_OBSERVED | Do not backfill the old manifest with inferred provenance. |
| D8 producer | [02B generation][producer] | `wbt_d8_pointer(dem=f_land_water, esri_pntr=FALSE)` writes a temporary pointer. | This describes the reviewed producer, not proof it ran for the old 02F. LAND_WATER is the routing source; STORAGE is a separate diagnostic surface. | SOURCE_CODE_OBSERVED | Reuse S2D's stage distinctions; no new generation. |
| Reused pointer / conversion | [Existence guard, FLT8S rewrite and deletion][producer] | Generation is conditional; temporary WBT output is rewritten to final FLT8S and deleted. | A pre-existing final pointer can be reused. Neither reuse decision, temporary bytes, final bytes nor their equivalence is witnessed for the historical invocation. | SOURCE_CODE_OBSERVED | Preserve separate producer/reuse/conversion uncertainties. |
| Raster object passed to 02F | [Final raster opens][opens]; [callback][callback]; [02F caller][caller] | `ptr_land_water <- rast(f_ptr_land_water)`; caller supplies that symbol with water/lake objects; callback indexes `r[cells]` and returns `as.numeric(z)`. | Symbol/path identity does not seal effective values across file-backed/lazy reads. No historical consumer snapshot or read transcript is attached. | SOURCE_CODE_OBSERVED | Keep effective pointer values/version NOT_ASSESSED. |
| Actual consumer boundary and outputs | [02F reads][consumer]; [CSV writes][outputs] | Consumer queries class, lake ID and pointer for active cells; caller writes four result CSVs after diagnostic QA. | Eight-column route summaries retain endpoints/status/steps, not intermediate consumed pointer values or an authenticated input ledger. | SOURCE_CODE_OBSERVED | Do not infer missing chain bytes from summaries. |
| Historical output identity | [Committed operator hash quotation][hashquote]; [S2C expected identities][identities] | Recorded 02F SHA256 is `402fdbf16cb41eaa6a3ad2180cc4d3af8534e32cff299d73eacec8dc5c187db5`; six fixed lake1894 summaries end at cell23211319. | The document explicitly says historical provenance was not independently checked. This is a **CSV** identity claim, not a D8 pointer checksum or proof of producer. | OPERATOR_REPORTED | Retain the digest and original route identities without upgrading their authority. |
| Original LOW diagnostics | [Issue #10][oldissue]; [PR #12 receipt][oldreceipt] | Reports code pin `4bbf22bb…`, 101 routes / 41 zero-terminal routes / seven terminals; later read-only comparisons are reported. | Later checks, matching counts and scheduler completion do not attest the old consumer. No contemporaneous independently verified pointer-to-output receipt appears in these discussions. | OPERATOR_REPORTED | Preserve findings in their original observational scope; do not repeat Slurm2345102. |
| Archived CSC materials | [Archive evidence status][archive]; [digest distinctions][archivedigests] | Archive explicitly records missing run logs/QA/manifest evidence at archival time. `816f6c1b…` is an expected D8-test digest in MODERATE resume scripts; script hashes identify scripts. | Neither an expected experimental pointer digest nor a measured script hash binds historical LOW 02F inputs. The dated archive is not the latest S2C.1 result. | COMMITTED_ARTIFACT | Do not substitute MODERATE experiment identity for LOW lineage. |
| Receipt prototype / examples | [Receipt scope][receiptprototype]; [synthetic fixture notice][fixtures] | Host-message receipt verification is a synthetic prototype; fixtures explicitly are not CSC logs/evidence. | Its presence in Git does not establish deployment, a historical witness or effective D8 consumption. | COMMITTED_ARTIFACT | Do not relabel fixture signatures or request manifests as runtime evidence. |
| Accepted S2C.1 / S2G Gate B | [Exact operator metadata receipt][metadatareceipt]; [78-test receipt][testreceipt] | At pinned `332da285…`: `metadata_status=PASS`, `historic_02f_sha256_match=True`, `raster_pixel_reads=0`, `S2C_EXIT=2`; all seven preceding stages PASS, lineage STOP. | Python3.14.5/GDAL3.12.2 checks concern current small CSVs and three raster metadata sources, not old effective pixel values. Source authentication remains NOT_ASSESSED. | OPERATOR_REPORTED | Accept the scoped result; do not rerun or convert overall STOP to PASS. |
| Accepted S2F / S2G Gate A | [S2F scope and seal limits][s2flimits]; [R4.6.1 operator receipt][rreceipt] | S2F is synthetic-only; Gate A reports `SUMMARY PASS=75 FAIL=0 NOT_RUN=0 NAMED_TESTS=75 R=4.6.1`. | A local transcript seal is not an independent witness; no production raster or old call was observed. | OPERATOR_REPORTED | Reuse compatibility evidence; no repeat test campaign. |
| Workflow evidence | [Offline inventory workflow][offlineci]; [referenced run39743899249][cirun]; [LOW CI context][lowci] and [upload scope][lowupload] | Offline run's public summary shows success and Artifacts “–”; reviewed workflow has no upload step. LOW transfer upload configuration belongs to a separate LOCAL_TEST fixture run. | No historical CSC consumer receipt is supplied by that summary or workflow source. Unexamined CI artifact bytes are not evidence of their contents. | INFERENCE | Keep CI and historical CSC lineage separate; no workflow dispatch or artifact regeneration. |
| Required historical witness | Inventory and search scope above; [S2D's existing historical rule][s2dhistorical] | No independently verifiable contemporaneous producer → exact effective pointer → original 02F output binding was found. | Absence in searched material does not prove no record ever existed. Self-declared digests, timestamps, branch HEAD or run IDs cannot supply the missing observation. | MISSING_OR_UNVERIFIED | Retain STOP; review a genuinely surviving independent record only if later supplied. |

The Gate B receipt reports present pointer **Float64 / NaN**, water_class
**Byte / 255**, lake_id **Int32 / −2147483648**. These are accepted metadata
observations attributed to the operator, not pixel readings made in this audit.
The older S2C.1/S2G committed notes still describe earlier NOT_RUN/technical STOP
states; the linked later receipts update execution status without rewriting them.

## Decision and minimal future-only handoff

Authentication would require credible contemporaneous evidence binding the
actual producer or reuse decision, the exact effective data observed at the old
02F call and its specific completed output, independently verifiable in scope.
None of the found records meets that rule. A CSV hash match plus source code,
metadata, timestamps and later diagnostic agreement cannot recover the missing
historical runtime observation. Even a successful future replay cannot establish
which past bytes were consumed. This gap is unrecoverable from the reviewed
material; a genuinely surviving independent contemporaneous record would need
separate review, not reconstruction or backdating.

The next handoff is already defined in **S2D**, not a new design or run approval:

1. Bind the actual producer/reuse decision, pinned code/configuration/environment
   and distinct temporary/final input identities ([S2D §§3–5][s2dstages]).
2. Freeze and verify the effective pointer/water/lake object or snapshot at the
   02F boundary, including actual reads and lossless validity semantics
   ([S2D §5][s2deffective]); a present-path hash alone is insufficient.
3. Independently witness those events and bind them to closed, identified 02F
   outputs, retaining a separately verifiable receipt and immutable atomic
   completion ([S2D §6][s2dpublication]). Existing S2F instrumentation does not
   implement that trusted witness or production hook.

Any separately approved newly witnessed run gets a **new** run/attempt identity;
it cannot authenticate or replace historical LOW outputs. Real-data six-route
parity remains **NOT_RUN**, pending separate operator approval and explicit
source/version selection; S2B real-data mode is not enabled here. No outlet
acceptance, physical water connection or national accumulation follows.

## Verification and scope of this delivery

No tests or model code were executed: new tests **NOT_RUN** (documentation-only);
prior S2C.1 78 PASS / 0 FAIL / 0 skipped and S2F R4.6.1 75 PASS / 0 FAIL / 0
NOT_RUN are reused operator-reported results, not new PASS counts. Original
metadata is reported PASS with overall STOP/exit2, not hydrological success.
Only documentation scope, cited Git objects/line ranges and `git diff --check`
are checked for this delivery. No CSC access, original file/pixel read, full
raster hash, R/config sourcing, hydrological rerun, D8/accumulation generation,
data modification, change to previous branches or merge is part of this audit.

[issue66]: https://github.com/annasuuronen/MaaltaMerelle/issues/66
[config]: https://github.com/annasuuronen/MaaltaMerelle/blob/4bbf22bb39181c8a4c27ebc3e2769766043115b8/R/00_pipeline_config.R#L47-L95
[paths]: https://github.com/annasuuronen/MaaltaMerelle/blob/4bbf22bb39181c8a4c27ebc3e2769766043115b8/R/00_pipeline_config.R#L142-L228
[manifest]: https://github.com/annasuuronen/MaaltaMerelle/blob/4bbf22bb39181c8a4c27ebc3e2769766043115b8/R/01_prepare_hydrology_inputs.R#L453-L599
[producer]: https://github.com/annasuuronen/MaaltaMerelle/blob/4bbf22bb39181c8a4c27ebc3e2769766043115b8/R/02_build_baseline_hydrology.R#L710-L762
[opens]: https://github.com/annasuuronen/MaaltaMerelle/blob/4bbf22bb39181c8a4c27ebc3e2769766043115b8/R/02_build_baseline_hydrology.R#L769-L779
[callback]: https://github.com/annasuuronen/MaaltaMerelle/blob/4bbf22bb39181c8a4c27ebc3e2769766043115b8/R/02_build_baseline_hydrology.R#L799-L820
[caller]: https://github.com/annasuuronen/MaaltaMerelle/blob/4bbf22bb39181c8a4c27ebc3e2769766043115b8/R/02_build_baseline_hydrology.R#L12617-L12630
[consumer]: https://github.com/annasuuronen/MaaltaMerelle/blob/4bbf22bb39181c8a4c27ebc3e2769766043115b8/R/02F_water_connected_route_diagnostics.R#L130-L151
[outputs]: https://github.com/annasuuronen/MaaltaMerelle/blob/4bbf22bb39181c8a4c27ebc3e2769766043115b8/R/02_build_baseline_hydrology.R#L12632-L12651
[hashquote]: https://github.com/annasuuronen/MaaltaMerelle/blob/332da2852b994e2441c22d66f4d438e0e787c7a0/diagnostics/water_connected_graph_design/EXISTING_SYKE_AUXILIARY_VALIDATION.md#L60-L72
[identities]: https://github.com/annasuuronen/MaaltaMerelle/blob/332da2852b994e2441c22d66f4d438e0e787c7a0/diagnostics/water_connected_graph_design/s2c_original_source_preflight.py#L27-L57
[oldissue]: https://github.com/annasuuronen/MaaltaMerelle/issues/10
[oldreceipt]: https://github.com/annasuuronen/MaaltaMerelle/pull/12#issuecomment-6211025631
[archive]: https://github.com/annasuuronen/MaaltaMerelle/blob/332da2852b994e2441c22d66f4d438e0e787c7a0/docs/csc/2026-10-14/EVIDENCE.md#L3-L28
[archivedigests]: https://github.com/annasuuronen/MaaltaMerelle/blob/332da2852b994e2441c22d66f4d438e0e787c7a0/docs/csc/2026-10-14/EVIDENCE.md#L84-L90
[receiptprototype]: https://github.com/annasuuronen/MaaltaMerelle/blob/332da2852b994e2441c22d66f4d438e0e787c7a0/docs/csc/phase2c/README.md#L11-L42
[fixtures]: https://github.com/annasuuronen/MaaltaMerelle/blob/332da2852b994e2441c22d66f4d438e0e787c7a0/automation/csc/tests/fixtures/README.md#L1-L16
[metadatareceipt]: https://github.com/annasuuronen/MaaltaMerelle/pull/65#issuecomment-6359218689
[testreceipt]: https://github.com/annasuuronen/MaaltaMerelle/issues/64#issuecomment-6359128603
[s2flimits]: https://github.com/annasuuronen/MaaltaMerelle/blob/477c5b13d5714d618c9c9de88f5f80290b53d994/diagnostics/water_connected_graph_design/S2F_CONSUMER_OBSERVATION_QA.md#L142-L178
[rreceipt]: https://github.com/annasuuronen/MaaltaMerelle/issues/62#issuecomment-6358150098
[offlineci]: https://github.com/annasuuronen/MaaltaMerelle/blob/332da2852b994e2441c22d66f4d438e0e787c7a0/.github/workflows/low-02d02f-evidence-inventory.yml#L24-L39
[cirun]: https://github.com/annasuuronen/MaaltaMerelle/actions/runs/39743899249
[lowci]: https://github.com/annasuuronen/MaaltaMerelle/blob/332da2852b994e2441c22d66f4d438e0e787c7a0/.github/workflows/test-low-transfer.yml#L28-L49
[lowupload]: https://github.com/annasuuronen/MaaltaMerelle/blob/332da2852b994e2441c22d66f4d438e0e787c7a0/.github/workflows/test-low-transfer.yml#L141-L155
[s2dhistorical]: https://github.com/annasuuronen/MaaltaMerelle/blob/eb09f39238dc8852d768ffc7a45cd3365e80d7a2/diagnostics/water_connected_graph_design/S2D_FORWARD_PROVENANCE_CONTRACT.md#L69-L100
[s2dstages]: https://github.com/annasuuronen/MaaltaMerelle/blob/eb09f39238dc8852d768ffc7a45cd3365e80d7a2/diagnostics/water_connected_graph_design/S2D_FORWARD_PROVENANCE_CONTRACT.md#L114-L216
[s2deffective]: https://github.com/annasuuronen/MaaltaMerelle/blob/eb09f39238dc8852d768ffc7a45cd3365e80d7a2/diagnostics/water_connected_graph_design/S2D_FORWARD_PROVENANCE_CONTRACT.md#L218-L254
[s2dpublication]: https://github.com/annasuuronen/MaaltaMerelle/blob/eb09f39238dc8852d768ffc7a45cd3365e80d7a2/diagnostics/water_connected_graph_design/S2D_FORWARD_PROVENANCE_CONTRACT.md#L256-L294
