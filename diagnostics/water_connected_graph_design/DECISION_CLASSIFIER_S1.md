# S1.0 evidence classifier: implementation and synthetic verification

[Issue #44](https://github.com/annasuuronen/MaaltaMerelle/issues/44), stacked on
[draft PR #43](https://github.com/annasuuronen/MaaltaMerelle/pull/43).
Starting branch: `codex/national-routing-decision-contract-design-v1`, exact
verified HEAD `ed7f1b5825f17195eda16a75ec316da183748081`.
Implementation branch: `codex/national-s1-pure-evidence-classifier-v1`.

Binding documents read: `NATIONAL_ROUTING_DECISION_CONTRACT_V1.md`,
`S1_CLASSIFIER_IMPLEMENTATION_CONTRACT.md`, and
`EXISTING_SYKE_AUXILIARY_VALIDATION.md`. Those documents and all earlier code,
tests, results and branches are unchanged. Only the three issue-allowlisted
files are added: this document, `decision_contract_v1.py`, and
`test_decision_contract_v1.py` in this directory.

## Scope and trust boundary

This is an in-memory Python standard-library classifier, not an outlet solver.
It reads no application files, rasters, vectors, manifests or Git repositories;
it performs no network calls, accumulation, geometry operations or routing.
It neither authenticates a manifest's contents nor verifies an actual source
commit. Digest syntax, supplied metadata agreement, identities and source-role
consistency are checked. `CURRENT`/`VERIFIED` and reported physical evidence are
caller-supplied normalized claims, not new findings by this library. A producer
fabricating all consistent inputs cannot be detected by a pure function.

All returned decisions/grouped results retain:

```text
routing_authorized=false
outlet_selection=UNASSIGNED
NATIONAL=LOCKED
MODERATE=REVIEW_REQUIRED
hydrological_validation=NOT_ASSESSED
channel_interpretation=NOT_ASSESSED
```

A decision's `route_chain_assessment` and `independent_validation_state` are
also always `NOT_ASSESSED`. `VALIDATED`, `APPROVED`, selected outlets,
authorization flags, unknown fields/statuses and caller-supplied reason codes
are not input fields that can grant privileges: they raise `SchemaStop`.
Even an externally reported complete chain cannot establish continuity in S1.
There is no production import, adapter, CLI, file writer or activation hook.

## API and immutability

```python
observation = validate_observation(normalized_mapping)  # or SchemaStop
result = classify(observation)                          # immutable Decision
routes = group_routes([normalized_mapping, observation])
plain = to_plain_mapping(result)                        # detached JSON values
```

`Observation`, nested `Grid`, `Provenance`, `Source`, `Evidence`, claims and
negative reports are frozen dataclasses containing only immutable values.
`Decision`, route/terminal groups and `GroupedRoutes` are immutable as well.
Validation detaches caller-owned lists/dictionaries, canonically sorts sources,
water-class multisets, claims, reasons and witnesses, and revalidates directly
constructed observations before classifying/grouping. No mutable global
selection state, time, random identifiers or input mutation is used.

`to_plain_mapping` produces a fresh JSON-compatible dictionary/list tree;
changing it cannot change the original result. Use
`json.dumps(plain, sort_keys=True, allow_nan=False)` for canonical JSON text.
The serializer rejects unknown record types, nonfinite floats and attempts to
export altered authorization/validation fields. This is not a sandbox against
arbitrary hostile Python code in the same interpreter.

`SchemaStop(ValueError)` carries `reason_code` and `path`, and formats as
`SCHEMA_STOP:<code>:<path>`. Failure returns no partial decision or grouping.

## Normalized input schema

Required top-level fields:

| Field | Contract |
| --- | --- |
| `schema_version` | Exactly `s1.0` |
| `observation_id`, `region_id` | Nonempty canonical strings, not `UNKNOWN` |
| `grid` | `grid_id,epsg,nrow,ncol,resolution_m,xmin,xmax,ymin,ymax` |
| `provenance` | Fields described below |

Grid dimensions are positive exact integers, EPSG is the integer `3067`,
resolution is exactly 2 m, all bbox coordinates are finite and the width/height
must equal `2*ncol` / `2*nrow`. The independently *supplied* manifest-grid
metadata must match the observation-grid metadata, including its origin and
identifier. There is no assumption of 6000 columns or bbox inference from a
tile name. A coherent but falsely supplied pair of grids cannot be detected
without the future source audit. Software representability guards limit cell
products/IDs to `2**53-1` and absolute bbox coordinates below `2**52`; these are
numeric-safety constraints, not hydrological thresholds.

Optional top-level fields are normalized explicitly, without NULL-to-zero or
floating-point ID rounding:

| Fields | Meaning / defaults |
| --- | --- |
| `origin_lake_id,component_id,receiver_id` | Positive exact integer or `None` |
| `source_cell,start_receiver_cell,terminal_cell` | Exact cell ID within supplied grid, or `None` |
| `receiver_type` | `UNKNOWN` (default), `LAKE`, `RIVER_AREA`, `RIVER_LINE` |
| `route_id` | Canonical string or `None`; scoped by region/grid |
| `route_status` | Existing 02F status, or default `NOT_ASSESSED` |
| `route_geometry` | `NOT_ASSESSED` (default), `SUMMARY_ONLY`, `FULL_CHAIN_REPORTED` |
| `steps` | Exact nonnegative integer or `None`; no steps are generated |
| `evidence` | Whitelisted normalized fields below; default empty |

A route record requires `route_id,origin_lake_id,source_cell,start_receiver_cell,steps`.
A directed hypothesis requires the origin and both start-edge cell IDs even
when no 02F route exists yet. Missing receiver information remains unknown and
requires review; river feature IDs are never invented. Component ID is required
when `component_status=OBSERVED` and forbidden when `ABSENT`. Unknown component
status is distinct from an observed absence.

The accepted existing route statuses are `D8_ZERO_INTERIOR`,
`D8_ZERO_AT_RASTER_EDGE`, `D8_POINTER_NA`, `D8_POINTER_INVALID`, `D8_DOMAIN_EXIT`,
`D8_CYCLE`, `RETURNS_TO_ORIGIN_LAKE`, `STEP_LIMIT`, `LAKE_ID_MISSING`,
`REACHES_OTHER_LAKE`, `REACHES_RIVER_AREA`, and `REACHES_RIVER_LINE`.
They are retained literally; there is no invented `REACHES_SEA` status.

### Provenance and source roles

`provenance` requires `manifest_sha256` (64 lowercase hexadecimal characters),
`producer_commit` (40 lowercase hexadecimal characters), non-UNKNOWN
`evidence_version`/`algorithm_version`, `manifest_state` (`CURRENT`, `UNKNOWN`,
`STALE`), the full `grid`, and a nonempty `sources` sequence. `STALE` stops;
explicit unknown source history/currency is retained as an evidence gap.

Every unique source requires all eight fields:

```text
source_path_or_id, source_version, source_role, kind,
used_in_build_or_candidate_review, reference_role,
shared_lineage, verification_state
```

`source_role` is exactly `INPUT`, `AUXILIARY` or `INDEPENDENT_REFERENCE`.
`kind` is `DEM`, `D8`, `RANTA10`, `SYKE_OUTLETS`, `SYKE_CATCHMENTS` or `OTHER`.
The use-history/lineage fields are booleans or explicit `UNKNOWN`;
`verification_state` is `VERIFIED` or `UNKNOWN`. `source_version=UNKNOWN`
is allowed and remains unknown. Source IDs must be real supplied identifiers,
not `UNKNOWN`. These extend the SYKE document's six-field provenance contract
with an explicit source role and source kind.

INPUT remains INPUT with `reference_role=INPUT`. An unknown-use auxiliary
source retains `REFERENCE_USE_UNKNOWN`. An `INDEPENDENT_REFERENCE` declaration
requires `HELD_OUT_COMPARISON`, explicit unused/unshared history, a known source
version and verified metadata. These are eligibility checks on supplied claims,
not independent verification. A role-conflicting source is rejected, not silently
promoted/downgraded. `COMPARISON_REPORTED` requires such an eligible source;
even then hydrological validation remains unassessed. SYKE shore/catchment
agreement is auxiliary evidence regardless of that declaration.

### Evidence fields

All are optional; omitted scientific booleans/numbers stay `None`:

- `water_classes`: a sorted immutable multiset of classes 1/2/3, preserving
  multiplicities; `None` is distinct from an explicitly observed empty list.
- `classification_02c`: the original `SAFE_LAKE_CONNECTOR`, `INTERIOR_REVIEW`,
  `LAKE_ONLY`, `RIVER_AREA_ONLY`, `RIVER_LINE_ONLY`, `MIXED`, or `NOT_ASSESSED`.
- `component_status`: `OBSERVED`, `ABSENT`, or default `NOT_ASSESSED`.
- `footprint_intersects,center_intersects,mapped_line_present,syke_point_match,
  same_catchment,directed_hypothesis,proposes_functioning_outflow,claims_continuous`:
  strict boolean or `None`.
- `tile_crossing`: `NOT_ASSESSED`, `NOT_PRESENT`, `UNVERIFIED`, `REPORTED_VERIFIED`.
- `height_difference_m,height_uncertainty_m,separation_m`: finite numeric values
  or `None`; uncertainty/distance must be nonnegative. Explicit zero is retained.
- `independence_state`: `NOT_ASSESSED` or `COMPARISON_REPORTED`.
- `receiver_claims`: records with `receiver_type,receiver_id,source_path_or_id`;
  every source reference must bind to the provenance. Conflicting claims remain
  present and require review.
- `impossibility`: optional explicit negative report with
  `source_path_or_id,evidence_id,criterion,statement`; criterion must be exactly
  `EXPLICIT_PHYSICAL_CONTRADICTION`. It is not generated from a missing line.

Water-class/footprint evidence requires a RANTA10 source, route evidence a D8
source, and SYKE flags the corresponding SYKE source kind. Up to 64 sources,
64 neighbor observations/claims, 4096 grouping records and 512 characters per
text identifier/statement are accepted. These are software input-size guards.

## Decision rules and reasons

Validation always precedes decision rules. Every matching reason and gap is
collected; no final matching `if` can discard earlier safety evidence.

| Outcome | Rule |
| --- | --- |
| `SCHEMA_STOP` exception | Invalid identities, schema/types, nonfinite values, stale/conflicting manifest, invalid role/independence claims, unauthorized state or contradictory route identity |
| `REVIEW_REQUIRED` | Mixed classes; retained 02C review; an outflow proposal; candidate at zero terminal; unsupported continuity; cycle/return; unresolved pointer/step limit; tile join; conflicting receivers/positive and negative reports; unquantified height difference on a directed hypothesis |
| `REJECTED` | Only an explicitly documented negative report bound to eligible held-out `OTHER` evidence, with no overriding review conflict; never missing map data or a SYKE/RANTA10 match alone |
| `CANDIDATE` | Identified directed hypothesis not blocked by a review condition; still no routing authority |
| `OBSERVED` | Original class/component, route summary, geometry or auxiliary observation without a qualifying directed hypothesis |
| `NOT_ASSESSED` | Structurally valid input without the scientific observations needed for the preceding outcomes |

The specific negative-report rule is not an inference from missing evidence.
A positive hypothesis and negative report, in one record or grouped records,
produce review rather than approval/rejection by last-match order. REJECTED
records only the supplied explicit negative evidence; it is not an independent
finding about a real lake. S1 performs no physics proof.

`case_type` is separate: a `LAKE_TO_LAKE_HYPOTHESIS` may require review.
`SAFE_LAKE_CONNECTOR` is retained as a 02C classification, never an outlet.
`INTERIOR_REVIEW` does not invent a MIXED class. `LOW_GRADIENT_UNCERTAIN`
means uncertainty is missing for a reported height difference of **any** size;
there is no LOW-derived gradient threshold. Even explicit zero uncertainty
cannot establish a physical direction or satisfy a future approval gate.

The twelve required reason codes are implemented, including group-derived
`MULTIPLE_STARTS_ONE_TERMINAL`. Each decision's `reason_evidence` links codes
to normalized field paths; group terminal witnesses retain case keys and route
IDs. Additional explicit reasons identify 02C review, unresolved routes/history,
unsupported continuity, receiver/negative-report contradictions and review-only
outflow proposals. Unknown incoming codes are schema errors.

## Route grouping and counts

Route/case key: `(region_id,grid_id,manifest_sha256,origin_lake_id,start_receiver_cell)`.
Terminal key replaces the last field with `terminal_cell`. Raw observations
without a directed/route identity use `(region_id,grid_id,observation_id)`.

A 02F trace ID is scoped by region/grid and must identify the same
`origin_lake_id,start_receiver_cell,terminal_cell,route_status,steps,route_geometry`.
Several original shore `source_cell` edges or evidence interpretations may cite
one trace. Their source cells and observation IDs remain present; they do not
create a second trace. Reusing an observation ID for different data, reusing a
trace ID for a different trace, combining incompatible traces for one start,
or mixing source versions within a region/grid causes STOP.

Exact replays retain `input_record_count`/group `record_count`, but do not
increase `unique_route_count`. Different reported IDs for the same start remain
in one case, with all original IDs preserved. Different starts of one origin
sharing one known terminal produce the shared-terminal reason. Missing terminals
are listed separately, never merged into a fictitious common issue. Different
origins/tiles remain distinct; cross-tile duplicate ownership is not resolved.
No route is extended using another source's summary or trace union.

`independent_route_count=None` and `flow_accumulation=NOT_COMPUTED` always.
Counts are inventories of reports/keys, not independent channels, accumulation,
validated error frequencies or national sample denominators.

## Three executed synthetic examples

These are projections of actual fixture outputs, not real LOW observations.
The full objects also contain all immutable source records and scientific locks.

Original LAKE_ONLY observation:

```json
{"case_type":"SOURCE_OBSERVATION","decision_state":"OBSERVED","reason_codes":["INDEPENDENCE_UNVERIFIED"],"routing_authorized":false}
```

Lake-to-lake hypothesis with a zero terminal, absent mapped line, 38.12 m
separation and an unquantified 0.07 m height difference:

```json
{"case_type":"LAKE_TO_LAKE_HYPOTHESIS","decision_state":"REVIEW_REQUIRED","reason_codes":["INDEPENDENCE_UNVERIFIED","LAND_D8_ZERO_TERMINAL","LOW_GRADIENT_UNCERTAIN","MAPPED_LINE_GAP","ROUTE_GEOMETRY_SUMMARY_ONLY"],"routing_authorized":false}
```

Six distinct synthetic starts to one terminal:

```json
{"input_record_count":6,"unique_route_count":6,"cases":6,"terminal_groups":1,"route_ids":["route-1","route-2","route-3","route-4","route-5","route-6"],"reason_codes":["MULTIPLE_STARTS_ONE_TERMINAL"],"independent_route_count":null,"flow_accumulation":"NOT_COMPUTED","routing_authorized":false}
```

## Executed verification

Local Python 3.12.14, Base R 4.5.0; no new packages installed. Required command:

```sh
python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_decision_contract_v1.py -v
```

Final output:

```text
Ran 101 tests in 0.146s
OK
```

| Executed synthetic suite | PASS | FAIL | NOT_RUN |
| --- | ---: | ---: | ---: |
| New S1 schema/provenance cases | 32 | 0 | 0 |
| New S1 classification cases | 39 | 0 | 0 |
| New S1 grouping cases | 18 | 0 | 0 |
| New S1 immutability/determinism/I/O isolation cases | 12 | 0 | 0 |
| Existing `EvidenceInventoryTests` | 37 | 0 | 0 |
| Existing `CandidatePreflightTests` only | 12 | 0 | 0 |
| Existing `LowGeoBatchTest` | 17 | 0 | 0 |
| Existing `G3Tests` | 11 | 0 | 0 |
| Existing `tests/water_connected_candidates.R` | 1 script | 0 | 0 |
| Existing `tests/water_connected_route_diagnostics.R` | 1 script | 0 | 0 |

Thus **178 Python test cases and two Base-R regression scripts pass**. The
existing geometry tests used tiny generated SQLite/WKB fixtures and the
already available native GEOS library. No real GPKG, raster or CSC input was
opened. The old graph-oracle accumulation tests were deliberately not run;
only its candidate-preflight class was selected. Broad historical campaigns,
real raster/vector audits, CSC/Slurm, new accumulation and S2–S4 are NOT_RUN.

During development three targeted review tests initially failed: two assertion
failures (invented MIXED evidence and an overly strong SYKE negative report)
and three invalid-status subtest errors in one case (the real 02F pointer/edge
status names). These were corrected in the new classifier only. All three
cases pass in the final suite; no old test or scientific limit was changed.
Additional tests cover parallel shore edges sharing one trace, missing start
identities, simultaneous safety reasons, source-role forgeries, duplicate
outputs, disallowed validation states and invariance under input permutations.
An isolated audit-hook test rejects write/network/process side effects during
import and all application-file access during validation/classification/grouping.

Only the three permitted files contain changes; existing files must compare
identically with the pinned starting commit. Raw local test logs stay under
`/tmp/mm-s1-*`; they are not added as a fourth repository artifact. This document
records executed results rather than claiming unexecuted CSC tests as PASS.
The following source/log fingerprints bind the final local verification:

| Verified artifact | SHA256 |
| --- | --- |
| `decision_contract_v1.py` | `4c3e920d6d960b2e3207d799aece1d4daf9b145b5bf4748fb3d345effbc9cf73` |
| `test_decision_contract_v1.py` | `dca50049ceea1b0c27baade4df4c42017b9395d04f11b982767266f14d8bc87b` |
| `mm-s1-new-tests-final.log` | `a4bf7ce74d123d74c280c1583449f4925d0eb1dc31f4e28717e91c6794a81782` |

## Scientific limits and publication gate

S1 does not establish full D8 chains, height-datum compatibility, measurement
uncertainty, independent field truth, physical channel/outlet existence,
shared-lineage independence, tile ownership/joins, global acyclicity,
connectivity to the sea or national accuracy. It does not turn six starts,
41 summaries, a mapped-line gap, a nearby SYKE point or a 7 cm difference into
an independent sample or a rule for Finland. River feature IDs and unknown
components remain unresolved rather than being invented. Source-reported
negative evidence is not authenticated by its syntax. S2 requires separately
approved sparse source checks; S3 requires geographically stratified independent
validation; S4 needs a separate scientific/production decision.

The intended new PR is **DRAFT**, base
`codex/national-routing-decision-contract-design-v1`, linked to issue #44 and
PR #43; no merge or production activation is permitted. GitHub API access from
this environment currently returns `Post https://api.github.com/graphql:
Forbidden` (observed with `gh pr view 43`); `api.github.com` is outside the
configured allowed hosts. Git transport/read-only public pages are available.
Draft-PR creation must be reported BLOCKED unless it is actually confirmed;
a pushed branch or compare URL is not described as an opened PR. Resolving
that network/API authorization is separate from the scientific safeguards.

```text
NATIONAL=LOCKED
MODERATE=REVIEW_REQUIRED
hydrological_validation=NOT_ASSESSED
channel_interpretation=NOT_ASSESSED
```
