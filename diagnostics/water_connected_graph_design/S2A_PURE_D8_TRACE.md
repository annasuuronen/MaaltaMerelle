# S2A — bounded in-memory LOW D8 chain audit

Issue #47 implementation, stacked on design PR #46 at
`004618871ebe57893c47371fcfbe96da0c5ecaa2`. S2A reconstructs chains from
supplied values and compares them with the six locked 02F summaries. It has no
raster reader, GDAL dependency, CSC connection, subprocess, file access, model
writer or outlet selector. The Python core uses only the standard library.

`NATIONAL=LOCKED`, `MODERATE=REVIEW_REQUIRED`,
`hydrological_validation=NOT_ASSESSED`,
`channel_interpretation=NOT_ASSESSED`, `routing_authorized=false`,
`outlet_selection=UNASSIGNED` on every trace, aggregation and audit result.

## Interface and input contract

```python
from s2a_pure_d8_trace import (
    Grid, Window, Provenance, WindowData, LOCKED_SUMMARIES, audit_low,
    canonical_json,
)

# pointer, water_class and lake_id are already supplied 73-row x 52-column
# Python lists/tuples. This example deliberately contains no data reader.
data = WindowData(
    Grid(), Window(),
    Provenance(
        data_kind="UNVERIFIED_IN_MEMORY",
        pointer_id="caller-supplied-pointer-version",
        water_class_id="caller-supplied-mask-version",
        lake_id_id="caller-supplied-lake-version",
        evidence_version="caller-supplied-version",
        producer_commit="004618871ebe57893c47371fcfbe96da0c5ecaa2",
        summary_sha256="402fdbf16cb41eaa6a3ad2180cc4d3af8534e32cff299d73eacec8dc5c187db5",
    ),
    pointer, water_class, lake_id,
)
result = audit_low(data, LOCKED_SUMMARIES)
report_text = canonical_json(result)  # returns a string; does not print/write
```

This is a structural example, **not an authenticated source declaration**.
The producer version above identifies this design; an actual evidence producer
must be identified separately by the caller. `LOCKED_SUMMARIES` stores the design's
reported identities; using it does not demonstrate that today's CSV was read.
A future approved adapter must actually read, authenticate and normalize the
original CSV rows and supply those rows, rather than substitute this constant.

All records are frozen dataclasses. `WindowData` copies arrays to nested immutable
tuples, validates all three shapes and normalizes explicit missing values.
Changing the caller's lists cannot change a replay. Metadata, values and
provenance labels contribute to an immutable SHA256 fingerprint. It identifies
**the supplied in-memory representation**, not an actual TIFF or CSV file.
`None` and numeric NaN become distinct `Missing.NULL` and `Missing.NAN` markers;
JSON output contains explicit strings rather than nonstandard numeric NaN.

No implicit `-9999`/zero NoData conversion is allowed. The caller must normalize
numeric NoData sentinels explicitly before constructing the arrays. Infinity,
booleans, strings and nonnumeric values fail input QA. Finite illegal pointer or
water-class values remain observable and produce the corresponding 02F status
if inspected. Lake IDs must be missing or positive, exact integers within R's
integer range; exact integral floats are accepted and retained in raw samples.
Fractional or overflowing lake IDs STOP instead of silently truncating them.

The one supplied `Grid` describes the common geometry of all three arrays.
S2A cannot authenticate separate raster georeferencing, bands or source files;
the later adapter must verify each source against that common metadata before
supplying values. Declared source IDs must be distinct. Provenance accepts only
`SYNTHETIC` or `UNVERIFIED_IN_MEMORY`; `source_identity_verified` is always false.
The declared historical 02F SHA is checked for version disagreement, but is
**not** treated as proof that a file was hashed or authenticated.

## Fixed geometry and locked identities

Full grid: 6000 rows × 6000 columns, EPSG:3067, 2 m pixels,
E 199000–211000 / N 6899000–6911000. Global cell IDs are 1-based;
rows and columns are 0-based. Cell centers use the full grid's origin and stride,
never the 52-column slice stride.

`prove_low_window()` validates all six complete summary records, then derives
the bounding box of their starts and common terminal, padded by the largest
reported transition count (24). It must equal:

- `xoff=3293`, `yoff=3844`, `width=52`, `height=73`;
- row0 3844–3916, col0 3293–3344, inclusive;
- E 205586–205690 / N 6903166–6903312;
- 3796 positions per array, **11388 supplied values** in total.

| Original route ID | Start receiver cell | Reported transitions | Terminal |
|---:|---:|---:|---:|
| 11 | 23337318 | 21 | 23211319 |
| 14 | 23343318 | 22 | 23211319 |
| 15 | 23343319 | 22 | 23211319 |
| 16 | 23343320 | 23 | 23211319 |
| 18 | 23349320 | 23 | 23211319 |
| 20 | 23355321 | 24 | 23211319 |

All have origin lake1894, `D8_ZERO_INTERIOR`, no terminal water class and no
terminal lake ID. Missing, extra, duplicate or changed records STOP. Input order
is irrelevant, but IDs are never renumbered to 1–6.

`audit_low()` requires this exact slice. The lower-level `trace()` mechanics
helper permits smaller windows (at most 52 × 73) at other positions of the same
LOW-shaped grid so synthetic tests can exercise actual outer-grid edges. It is
not an adapter or permission to read another real region. There is no window
expansion, arbitrary reader callback or unbounded iteration option.

## Replay and comparison rules

Water classification is inspected before deciding whether to follow a pointer,
as in the unchanged `R/02F_water_connected_route_diagnostics.R`:

1. Missing water class follows 02F's land-branch semantics. This alone does not
   prove a valid DEM/LAND_WATER surface at that position.
2. Water class1/2/3 stops at the current cell, regardless of a zero, missing,
   illegal or otherwise valid outgoing pointer. Class1 preserves a valid lake ID,
   distinguishes origin/other lake and reports `LAKE_ID_MISSING` if absent.
   Classes2/3 yield river-area/river-line terms without inventing a receiver ID.
   Other finite classes produce `INVALID_WATER_CLASS`.
3. On the land branch, missing pointer is `D8_POINTER_NA`, not zero.
   Zero is `D8_ZERO_AT_RASTER_EDGE` only at the **full 6000 × 6000 grid** edge;
   otherwise it is `D8_ZERO_INTERIOR`.
4. Whitebox codes: 1 NE, 2 E, 4 SE, 8 S, 16 SW, 32 W, 64 NW, 128 N.
   Other finite codes produce `D8_POINTER_INVALID`. Every decoded attempt records
   its source, pointer, target row/column, target ID and outcome.
5. A full-grid exit is `D8_DOMAIN_EXIT`, with the source as terminal. A cycle
   reports the repeated target as terminal. Neither attempt increments
   `route_steps` or appends the target as an accepted move.
6. An attempt outside the supplied window returns a separate safety STOP,
   `OUTSIDE_BOUNDED_WINDOW`, with no invented 02F status or target sample.
   The 25th successful move is prohibited by `TRANSITION_BUDGET_EXCEEDED`.

**02F's loop bound counts inspections.** A successful move on the last iteration
can enter an uninspected cell. That yields `STEP_LIMIT`, even if its unseen value
would terminate the route. The 24-transition route needs **25 inspections** to
observe its zero terminal. `entered_cells` includes such a censored tail, whereas
`cells` contains only actual inspections. No terminal water class or lake ID is
inferred for an uninspected tail. Bounds are 24 accepted moves and 25 inspections
per route, at most 150 inspected cell records over six routes.

`Trace.cells` retains every inspected global cell ID, row0/col0, x/y center and
raw normalized pointer/class/lake value. `Trace.steps` retains accepted and
rejected decoded attempts. Terminal/status/transition count and all other
summary fields are compared individually with the unchanged normalized original
summary. Differences and safety STOPs remain in `Comparison`, including the
original expected row. No input report is corrected or overwritten.

## Grouping and neighbor evidence

`aggregate()` groups paths by shared **global cell ID**, preserves each route,
reports first shared cells and common observed subchains, and separately retains
all terminal outcomes. A STEP_LIMIT tail is distinguished from an inspected
shared cell; a completed neighboring trace cannot extend a censored trace.
Crossing diagonal edges without a common cell are not a confluence. Cyclic pairs
are explicitly ambiguous. Duplicate route IDs, incompatible source fingerprints
and contradictory shared-cell samples STOP. No accumulation or independent
channel count is calculated.

An optional tuple of three normalized `Neighbor` rows can test 02C correspondence
using the already supplied eight adjacent positions: component274, source23211319,
water class1/lake1892. Duplicates, wrong identities or nonadjacent cells STOP;
disagreement with the supplied arrays yields diagnostic FAIL. No pointer is
extended into a neighbor. Without rows, `WATER_NEIGHBOR_PARITY=NOT_RUN`.
**The actual three neighbor cell IDs are not known to this implementation.**
Their presence in supplied rows must later be authenticated against 02C. The
three positions used in tests are invented, explicitly synthetic fixtures.

## Result interpretation and stage gates

`Stop(ValueError)` rejects invalid schemas, changed locked identities and
unsupported input claims before returning a successful audit. A valid schema
with replay/neighbor disagreement returns `diagnostic_result=FAIL` and
`S2_RESULT=REVIEW_REQUIRED/FAIL_CLOSED`, preserving traces and differences.
A consistent synthetic/in-memory replay can return `diagnostic_result=PASS`;
its overall `S2_RESULT` still remains `NOT_ASSESSED`.

| Stage | Pure S2A meaning |
|---|---|
| INPUT_QA | PASS after schema, geometry, identity and declared-version checks; otherwise exception STOP |
| TRACE_PARITY | PASS/STOP for supplied values versus the six fixed summaries |
| WATER_NEIGHBOR_PARITY | PASS/STOP for optional supplied 02C rows; otherwise NOT_RUN |
| GEO_REFERENCE | NOT_RUN; no vector geometry input or distance calculation |
| SOURCE_PROVENANCE | NOT_RUN; source authentication not implemented in the pure core |
| AGGREGATION | PASS for consistent bounded trace grouping |
| RESOURCE_BOUND | PASS within bounds; STOP when a replay hits a safety bound |

`real_raster_parity` and `source_authentication` always remain `NOT_ASSESSED`.
No public authorization argument exists. Scientific locks are non-init fields;
frozen outputs reject normal mutation/replacement of these fields. `VALIDATED`
is rejected as a summary, trace or audit decision. Python frozen records are an
integrity aid for ordinary callers, not a sandbox against hostile Python code
using reflection to forge objects.

## Verification performed locally

Python 3.12.14, R 4.5.0. Only small synthetic in-memory inputs were used.

```sh
python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_s2a_pure_d8_trace.py -v
MM_S2A_RSCRIPT=/path/to/Rscript python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_s2a_pure_d8_trace.py -v
python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_decision_contract_v1.py -v
Rscript --vanilla tests/water_connected_route_diagnostics.R
git diff --check
```

| Check | Actual outcome |
|---|---|
| S2A named synthetic tests, optional R oracle enabled | **90 PASS, 0 FAIL, 0 skipped** |
| Included Python/R 02F comparison | **30/30 route outcomes agree** across six-route, 24/25-inspection, water, missing, illegal, cycle, censor and full-grid-edge cases |
| Existing S1 synthetic regressions | **101 PASS, 0 FAIL, 0 skipped** |
| Existing R 02F synthetic regression | **PASS**, unchanged test script |
| Actual LOW raster replay and authenticated 02F/02C CSV comparison | **NOT_RUN** |
| Actual RANTA10 line fid29 geometry comparison | **NOT_RUN** |
| GDAL adapter, CSC/Slurm, accumulation, hydrological validation | **NOT_RUN** |

Without `MM_S2A_RSCRIPT`, the 89 pure Python tests run and only the optional
cross-language test is explicitly skipped/NOT_RUN. R is not a runtime dependency.
The optional test sends tiny synthetic vectors to the existing R source over
stdin; it does not allocate a full LOW vector or access rasters. Its comparison
maps rows by start/origin because 02F renumbers a subset, while S2A retains the
original six route IDs.

The first development run had one failing test method in two subcases: the
bottom/right-edge **test fixtures** excluded their intended cell. The core
correctly returned bounded-window STOP. Correcting those fixture bounds, with
an explicit containment assertion, resolved both failures. No acceptance rule
was relaxed. A local `/usr/bin/time` measurement launcher was unavailable; no
claim is made that it ran tests or measured resources. No broad historic LOW,
MODERATE or CSC campaigns were repeated.

## Remaining scientific limits and next boundary

The synthetic six-route fixture reproduces reported identities, step lengths
and terminal structure by construction. Its intermediate chain, merges and
neighbor locations are invented software test data, not observations recovered
from Roihu. Successful software parity does not establish actual LOW equality.

S2B remains **NOT IMPLEMENTED**: authenticate original manifests/CSV versions,
resolve actual source rasters, verify each raster's geometry, NoData and identity,
then separately test a strictly bounded, read-only window adapter. The known
02F hash is only a historical version anchor until actual bytes are checked.
The historical 02C cells hash in the design is not a substitute for the unknown
neighbor-CSV hash. No real raster read is authorized by this implementation.

Terrain elevations/gradients, original DEM corrections and fill provenance,
actual three water-neighbor identities, line proximity and independent hydraulic
or channel validation remain unresolved. Six starts sharing a terminal neither
prove six channels nor a lake1894→1892 connection. No national threshold, natural
outlet, hydrological approval or production integration follows from S2A.
