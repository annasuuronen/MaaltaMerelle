# 02G observed accumulation and tile ownership research prototype

Parent: `f626ba465d8c044acb0ad981da18667fbfa98df6`.
Research plan read from PR #15, `053df7c32d22391ccc1fb14d10d82e969bdb6bd3`,
particularly sections C/D (accumulation and tile boundaries), B/F (small-water
candidates and independent evidence). That branch was read, not merged.

This is a bounded Base R experiment, not production 02G, a distributed solver,
a whole-LOW engine or hydrological acceptance. All new cells, lake IDs and
reports are generated synthetic examples. No CSC connection, Slurm submission,
Whitebox calculation, dataset download or real raster read was performed.
Only this directory changes. Original 121-cell and 14-receiver/56-value driver
guards, R/ production files, prior reports and all workflows remain unchanged.

## Mathematical and observation contract

One owned land cell contributes one source unit = 4 m² on the 2 m EPSG:3067
grid. In a fully observed acyclic local graph:

```
S(v) = {v} union all S(u), for land predecessors u
A(v) = |S(v)| = 1 + sum A(u)
local area(v) = 4 A(v) m²
```

With at most one successor, the predecessor source sets in an acyclic graph
are disjoint. The implementation retains unique source IDs rather than
repeatedly summing route counts. The independent test oracle follows explicit
fixture successors and constructs source sets without production pointers,
routes, the D8 decoder or accumulation output.

`g02_from_network()` consumes already-stored network traces and never extends
a censored source. `g02_observe()` can make a new explicitly requested synthetic
observation using the unchanged `trace_land_d8_route()` core. Per-source budget
is global across all tiles, not reset at a seam. Canonical observed directions
are checked with the reviewed core on virtual one-step values; this is geometric
QA of existing edges, not new raster sampling or a new D8 decoder.

For incomplete traces, `local_upstream_cells` is the count of confirmed observed
local contributions, **not an exact whole catchment**. `source_sets` provides
the corresponding local catchment membership. A source that merely reaches a
sender at STEP_LIMIT cannot be propagated by somebody else's longer trace.
Coverage is `PARTIAL_OBSERVATION` for cycles, step limits or missing core tiles.
Other unresolved endpoints remain `LOCAL_GRAPH_ONLY_UNRESOLVED_TERMINALS`.
The local recurrence is checked only for fully observed acyclic local graphs;
a passing recurrence alone never approves a downstream connection.

Cycles have no finite solution of the stated recurrence: cycle cells get NA
for local A and area. Their observed reachable source IDs/counts remain
available for audit, without being called valid cyclic flow accumulation.
Zero/NA/invalid pointers, NoData, STEP_LIMIT and boundary exits remain explicit
unresolved terminal types. Source balance is exactly:

```
owned land sources = sources at first water + unresolved sources
approved physical exports = 0
```

Water contributes no new land unit. First-water counts preserve source IDs,
water class and valid lake ID. River/line recipient IDs are not invented.
Water-cell outgoing D8 does not affect first contact. Incoming land accumulation
is unrelated to selecting a lake outlet or routing through a lake.

External import defaults to `UNKNOWN`; total catchment values stay NA.
`KNOWN_ZERO_SYNTHETIC` is an explicit closed-test-domain declaration only,
requires complete cell coverage and still conveys no hydrological acceptance.
Positive external scalar imports are not implemented. Internal tile imports
are explicit source IDs, not additive copies of upstream numeric counts.

The metadata preserves 4 ha = 40,000 m² = 10,000 cells as a future presentation
threshold. No source, contact or small route is filtered by that threshold.
Area is not discharge: no rainfall, time-dependent flow, flux or capacity model
is implemented.

## Core/halo and transfer experiment

Tiles have non-overlapping rectangular cores on one global grid and exactly
one in-grid halo ring. Shared halo observations must agree. Each available
source belongs to exactly one core; halo cells add no source contribution.
Duplicate cores, missing/excess halo samples and conflicting grids/observations
are rejected.

The prototype centrally stitches validated core observations, then observes
fresh bounded source paths. This validates ownership and accounting, not
asynchronous distributed accumulation or out-of-core scaling. Transfer IDs
identify canonical global cell-to-cell edges. Each edge/source pair appears
once even when multiple paths share that edge. Records include sending and
receiving tiles, checked D8 code, known local count at the sender, actually
transferred source IDs/count, external-import uncertainty and transfer status.
Receipts acknowledge a validated available receiver core; they are derived
bookkeeping, not independently executed remote messages.

Four exact comparisons cover two/three neighbouring tiles at budgets 2/32,
including independent explicit transfer/source tuples, and match the same
monolithic graph's counts, areas, memberships and endpoints. Source ownership
and results are invariant to tile/observation order.

The 27-cell example has 11 land sources, owned 4/4/3 across three cores. All
11 reach the same synthetic first water. Crossings carry 4 and 8 source IDs:
these sum to 12 transit memberships, not 12 new sources. Internal sent/received
memberships cancel exactly. At cap 2, a sender can have 4 observed contributors
but transfer only 2 whose own traces actually cross the seam.

With the middle tile absent, only seven land seeds are owned/observed: three
reach water and four terminate `MISSING_NEIGHBOUR_TILE`. Nine missing core
positions are recorded; their land class/source count is not guessed. Halo
knowledge does not authorize continuing through their unavailable owner.
No import or accumulation is fabricated to restore agreement.

## Results, limitations and reproduction

Tests use 15-cell fixtures for joins, three serial tributaries, first contacts,
zero/NA/invalid pointers, NoData, cycles, STEP_LIMIT, exits and empty products.
Two/three-tile cases use 27 positions. A 1,000-cell fan is the only performance
case. The initial small suite failed because an empty water table combined
zero-length columns with scalar metadata. Length-aware typed empty products
and zero-source handling corrected that bug. The failed log is retained.
Coverage labels were also made explicit for unresolved terminal types.

The optional 10,000-cell case was NOT_RUN_RESOURCE_GATE: this prototype is
intentionally capped at 1,000 positions and a conservative 15x RSS projection
from the calibration is above safe headroom. This is not a measurement of
10,000-cell memory demand. No larger campaign or 100,000-cell test was run.

The existing Python supervisor enforces 1,536 MiB per child address space,
1,792 MiB sampled process-group RSS, <=180 s per test and a shared 1,200 s
persisted deadline. This task's actual deadline starts at its initial review,
including coding pauses. Original supervisor negative tests deliberately
exercise TIME_STOP, MEMORY_STOP and nonzero/missing-output failures; those
expected child conditions are not successful hydrological tests.

Run in a disposable checkout with Base R and Python standard library:

```sh
MM_RSCRIPT=Rscript python3 -B diagnostics/02g_accumulation_tile/tests/run_tests.py all
```

Original selected regressions additionally require terra/Rcpp. The local tests
used R 4.5.0 and the existing synthetic terra environment. Committed results
have a historical deadline: retain that evidence and remove only generated
reports/logs/example CSVs in the disposable copy before a fresh campaign.
A targeted `small`, `tiles` or `performance` argument reuses the same budget.
The prototype itself reads no files or rasters and requires synthetic provenance.

`results.json`/`results.csv` retain every attempt, source snapshots, wall time,
child/group RSS and raw/normalized log digests. The example CSVs are synthetic
node, water, source-ledger and tile-transfer products, not CSC observations.

Production prerequisites remain: scalable source representation/streaming,
independent distributed import/receipt computation, error/restart semantics,
real input identity verification, positive external-import contracts, uncertainty
localization, and separately approved real-data validation. The bounded source
sets and per-source traces are not a scalable national solution.

## Later ditch/small-water research

Accumulation, continuity and confluences can later support computational channel
candidates, including paths below 4 ha. D8 routes, candidate ditches/channels and
independently confirmed features are separate evidence classes. Output placeholders
provide independent feature ID, dataset version, provider and evidence grade;
none are populated or inferred from synthetic counts here. Future MML or other
approved observations must be versioned and independent of the DEM-burning source.
Do not classify every large accumulation or burned link as a real small waterbody.

The next actual LOW read remains the separately prepared 14 receiver cells /
56 values after maintenance and separate authorization. It is not started here.

`hydrological_validation=NOT_ASSESSED`
`channel_interpretation=NOT_ASSESSED`
`MODERATE=REVIEW_REQUIRED`
`NATIONAL=LOCKED`

## Observed test report (21 October 2026)

| Suite | Outcome | Wall s | Peak child/group RSS MiB |
| --- | --- | ---: | ---: |
| small | PASS | 1.2689 | 65.945 |
| tiles | PASS | 1.4249 | 65.066 |
| performance | PASS | 4.4623 | 144.812 |
| test_land_network_topology | PASS | 2.0481 | 64.898 |
| test_land_network_topology_inventory | PASS | 1.3701 | 64.492 |
| test_one_low_network_window | PASS | 8.9417 | 384.102 |
| test_boundary_receivers | PASS | 7.1080 | 329.621 |
| test_land_d8_route | PASS | 0.5598 | 64.734 |
| test_first_water_contact | PASS | 0.3574 | 64.770 |
| test_lake_1847_focus | PASS | 0.2552 | 64.746 |
| water_connected_route_diagnostics | PASS | 0.3073 | 63.672 |
| test_supervisor | PASS | 0.9669 | 19.652 |

Final small suite: 15 cases / 320 assertions. Tile suite: four exact monolithic
comparisons plus missing-neighbour and malformed-input tests / 230 assertions.
1,000-cell fan: independent source sets and local recurrence / 3,007 assertions.
Original suites: topology 46, inventory 25, LOW window 25, boundary receivers
21, land routes 23, first contact 26, LOW core and 02F all PASS. Supervisor:
10 unit tests PASS. No earlier large validation campaign was repeated.

Latest performance: compute 3.786 s, independent
oracle 0.430 s, output 3.163 MiB.

History: one actual FAIL (empty water-table row-length bug), corrected;
all subsequent small/tiles/performance runs PASS. No actual TIME_STOP or
MEMORY_STOP; optional 10,000 cells NOT_RUN_RESOURCE_GATE. Expected negative
child statuses inside the supervisor suite were caught correctly.

Cumulative observed worker time across all attempts: 49.584 s.
Initial task review through final report validation: 1097.835 s, below 1,200 s.
