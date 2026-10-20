# Synthetic D8 scale validation v1

Research branch: `codex/low-synthetic-scale-validation-v1`.
Base: `effab29aa4d44ecc897efc0c91c96f3bfc1b4db6` on
`codex/low-boundary-receivers-v1`. No real raster values are used by the
new scale framework. This is software and resource validation, not evidence
about LOW drainage, real ditches, outlets, or hydrological correctness.

## Scope and independent evidence

`generator.R` constructs an explicit row-major successor graph first and
encodes its adjacent steps as Whitebox D8 pointers. `oracle.R` calculates
expected edges, indegrees, confluences, ordered source paths, cycle closure,
censoring, confirmed source-to-exit groups and conservation directly from that
successor graph. It never decodes D8 or calls a production routing function.
The implementation under test consumes the encoded pointers through the
existing LOW / first-contact / land-route cores. Eight independently specified
centre-cell neighbour cases check the direction convention.

Four fixtures are generated at each size (100, 1,000, 10,000):

- `fan`: upstream branches enter common eastward chains; many consecutive
  confluences and multiple independent exits. A D8 node has at most one
  successor; there is no invented downstream flow splitting.
- `long`: a serpentine path through the whole graph, with an eventual exit.
- `mixed`: zeros, missing/invalid pointers, NoData targets, cycles, invalid
  water classes and known water classes 1/2/3.
- `random`: all eight directions, convergences, cycles and unusable cells;
  reproducible seed 20261020, without changing the caller's RNG state.

The grid is synthetic, 10 columns wide, 2 m EPSG:3067, with explicit global
row/column offsets. Its elongated geometry is one stress pattern, not a
representative survey of all possible network shapes.

The production builder, inventory and selector retain their original 121-cell limits.
The scale adapter makes **test-process copies** of these three functions and
changes only numeric limit literals (expected replacement counts 2, 1, 1).
The adapter leaves the original functions intact and does not change the routing/decoder algorithms.
`test_harness.R` checks identical bodies and results at limit 121, unchanged
original functions, rejection of an oversized production grid, deterministic
fixtures and deliberate oracle mismatches. The adapter is a testing aid,
not a supported large-raster processing interface.

The global scale series observes **at most four transitions per source** to
bound output size. It does not claim complete downstream tracing on large
graphs. A separate 100-cell fan case uses cap 16 and checks complete exit
accounting. Two sparse probes on each serpentine graph use the unchanged
256-transition core limit. Censored paths remain `STEP_LIMIT`, never verified
exits. Shared source memberships and local indegrees are not flow accumulation.

## Resource supervision and reproduction

On Linux, with Base R available:

```sh
python3 diagnostics/land_network_topology/synthetic_scale/run_validation.py --rscript Rscript --phase optimized --sizes 100 1000 10000 --regressions --consider-100000
```

The supervisor uses only the Python standard library. Each child has a
1,536 MiB virtual-address-space hard limit. Aggregate child-process RSS is
sampled every 50 ms and stopped at 1,792 MiB, leaving room below the 2 GiB
package ceiling for the small supervisor. `wait4` records the child's peak
RSS separately. R object sizes are output sizes, **not peak RAM**.

The shared persistent 1,200-second budget covers all phases; an absolute
deadline also charges pauses between them. Individual cases have a 180-second
watchdog (60 seconds for regression scripts and the complete small fan) to leave time for independent cases. A resource stop is a failure,
not a pass. Existing results are retained and repeat log names get an attempt
suffix. To reproduce a fresh campaign, use a clean checkout and a separate
copy of this directory without the committed `results.json`, `results.csv`
and `*.log` observations; preserve those historical observations separately.

100,000 cells can only be reached through a conservative gate after all four
10,000-cell cases pass. The gate projects 15 times each measured time/RSS and
requires enough remaining package time and memory headroom. A rejected gate
is reported as `NOT_RUN`, never passed or benchmarked by extrapolation.

`test_supervisor.py` checks successful and failed child exits, deadlines,
timeout termination, an injected RSS tripwire (without allocating gigabytes),
the actual child address-space limit, missing measurements, a timeout even
when the child exits 0, and preservation of previous logs.
The supervisor tests run automatically in every campaign. Its negative child results are expected assertions, not failures of that
unit-test suite.

## Observations

Measurements and outcomes are recorded in `results.csv`, `results.json` and
the referenced small local logs. Final numerical results are appended below.

The first nine `baseline` cases failed in the **new test adapter**: assigning
`NULL` through `[[<-` deleted an AST call argument. Using list-preserving AST
replacement fixed this. Those logs are kept; they are not D8 failures.
A subsequent new harness immutability assertion compared serialized whole
functions; R JIT compilation changes that representation during execution.
It was corrected to compare serialized function bodies, as the scale workers
do. This was a test assertion defect, not a change to routing functions.

Supervisor regression tests also reproduced two false-pass cases in the new
framework: a child with no measurement output, and a timed-out child that
handles SIGTERM with exit 0. The final supervisor explicitly rejects both;
`supervisor_before_fix.log` preserves the two initial failed assertions.

The corrected `baseline_fixed` cases passed for all four 100- and 1,000-cell
fixtures plus the complete 100-cell fan. No hydrological data was changed.

## Safety and limits

Changes are restricted to this new synthetic test directory and a small
in-memory performance repair in `../analyse_land_network_topology.R`.
The repair indexes source-to-confluence membership once from already-stored
paths instead of scanning every source separately for each confluence.
First visits, source order, all QA and the original 121-cell guard are kept.
`test_inventory_compatibility.R` reads the pinned Git source object and
compares whole typed inventories, including row order, on five fixtures
(four 100-cell types and a 1,000-cell dense fan, all with cap 16).
No existing raster reader, 121-cell real LOW window bound, 14-receiver/56-value
bound, workflow, production file under `R/`, raster, mask, pointer or outlet is changed.
Original regressions include tiny synthetic GeoTIFF tests; no CSC paths are
read, no Whitebox process is started and no Slurm job is submitted.

The 16 workflow files at the pinned source were inspected. Push-triggered
hydrological workflows and the retry workflow are restricted to
`baseline-no-structures`; CSC preflight PRs also target that branch. This
research branch and its intended PR base match neither restriction. No
workflow is added or changed and no Actions dispatch is sent. A later default
branch workflow change would require a fresh trigger review.

`hydrological_validation=NOT_ASSESSED`
`channel_interpretation=NOT_ASSESSED`
`MODERATE=REVIEW_REQUIRED`
`NATIONAL=LOCKED`

## Measured optimized results (2026-10-20)

Local R 4.5.0; single-thread BLAS settings. Times include a fresh R process,
construction, inventory, independent oracle and sparse probes where applicable.
The reported RSS is the larger of child peak RSS and sampled group peak RSS.

| Cells | Fixture | Result | Build s | Inventory s | Oracle s | Total s | Peak RSS MiB |
| ---: | --- | --- | ---: | ---: | ---: | ---: | ---: |
| 100 | fan | PASS | 0.643 | 0.651 | 0.173 | 1.730 | 64.578 |
| 100 | long | PASS | 0.692 | 0.324 | 0.119 | 1.476 | 64.566 |
| 100 | mixed | PASS | 0.597 | 0.512 | 0.150 | 1.629 | 64.523 |
| 100 | random | PASS | 0.581 | 0.533 | 0.186 | 1.627 | 64.586 |
| 1,000 | fan | PASS | 4.077 | 3.931 | 0.571 | 9.060 | 116.941 |
| 1,000 | long | PASS | 3.664 | 0.565 | 0.180 | 4.789 | 114.094 |
| 1,000 | mixed | PASS | 3.078 | 0.952 | 0.156 | 4.521 | 93.066 |
| 1,000 | random | PASS | 3.449 | 1.868 | 0.382 | 6.058 | 105.328 |
| 10,000 | fan | PASS | 28.922 | 44.232 | 6.420 | 80.078 | 398.738 |
| 10,000 | long | PASS | 26.361 | 4.556 | 0.473 | 32.005 | 288.121 |
| 10,000 | mixed | PASS | 29.014 | 7.598 | 0.653 | 37.840 | 250.547 |
| 10,000 | random | PASS | 26.764 | 18.919 | 4.153 | 50.492 | 314.164 |

All 12 fixed-cap cases and the separate complete 100-cell fan passed, with
65,002 independent assertions including the sparse long-path probes.
100,000 cells: **NOT_RUN**. The 15x projection from the dense 10,000-cell
case alone is about 5,981 MiB and 1,201 s; the gate cannot demonstrate safe
headroom. These are projections, not 100,000-cell measurements.

The previous inventory version (`final` phase, before optimization) exceeded
its 180 s case watchdog on the dense 10,000-cell fan (TIME_STOP; about
280 MiB RSS at interruption). Other original 10,000-cell cases passed:
long 33.781 s, mixed 37.454 s, random 108.683 s. Random inventory time fell
from 80.838 s to 18.919 s after membership indexing. The dense fan now
completes in 80.078 s (44.232 s inventory), at a higher but bounded RSS.
This is a targeted stress comparison, not a general complexity guarantee.
Global UID lookups, stored per-source paths and output table construction
still consume resources; exhaustive 32/256-step all-source scaling is not
measured here. No production large-area readiness is claimed.

## Final regression and campaign accounting

| Script | Result | Observed summary |
| --- | --- | --- |
| `test_supervisor` | PASS | Ran 9 tests in 0.802s; OK |
| `test_harness` | PASS | PASS: 49 synthetic harness contracts; original 121-cell limits retained |
| `test_inventory_compatibility` | PASS | PASS: 5 complete inventory outputs identical to pinned base |
| `test_land_network_topology` | PASS | TESTS=46 PASS=46 FAIL=0; PASS: bounded synthetic topology only; no accumulation or hydrological approval |
| `test_land_network_topology_inventory` | PASS | TESTS=25 PASS=25 FAIL=0; PASS: synthetic topology inventory only; no CSC or hydrological approval |
| `test_one_low_network_window` | PASS | TESTS=25 PASS=25 FAIL=0 NOT_RUN=0; PASS: synthetic read-only window contracts; no CSC data or hydrological approval |
| `test_boundary_receivers` | PASS | TESTS=21 PASS=21 FAIL=0 NOT_RUN=0; PASS: contract and synthetic observations only; no CSC reads or hydrological approval |
| `test_land_d8_route` | PASS | TESTS=23 PASS=23 FAIL=0; PASS: synthetic D8 continuity only; no real LOW validation or verified ditch network |
| `test_first_water_contact` | PASS | TESTS=26 PASS=26 FAIL=0; PASS: first-water synthetic prototype only; no CSC evidence or hydrological approval |
| `test_lake_1847_focus` | PASS | PASS: LOW 1847 local window counts, elevations, mask and bounded D8 tracing |
| `water_connected_route_diagnostics` | PASS | PASS: 02F classifies downstream D8 route terminals without changing pointers |

Final campaign: 24 worker runs PASS; no final worker failures; one optional 100,000-cell series NOT_RUN.
Cumulative measured worker runtime across all attempts: 775.500 s.
Absolute campaign interval, including development pauses: 1071.363 s, below 1,200 s.
The separate pre-fix supervisor regression reproduced 2 failing assertions
out of 9; its <1 s runtime is covered by the absolute campaign interval.
Historical failures remain in the report/logs: nine AST adapter failures,
one dense-fan watchdog stop, one JIT-sensitive harness assertion and the two
supervisor assertions. All corresponding final tests passed. Original
regression scripts and real-data safety gates were not edited.

The final transcript-format check additionally passed all 10 supervisor unit
tests (the original nine plus a raw-digest / normalized-log / CSV-LF check).
Review transcripts have trailing whitespace removed; original and normalized
SHA256 values are recorded per log. Original failure text is also retained in
JSON. No numerical observation or test outcome is changed by this formatting.
