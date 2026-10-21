# Long D8 paths, confluences and censoring

Research branch: `codex/low-long-path-censoring-validation-v1`.
Pinned parent: `01485c080cab48fadece38f30dc8526f6b575b40`, PR #23,
`codex/low-synthetic-scale-validation-v1`.
Exact pre-optimization comparison: `effab29aa4d44ecc897efc0c91c96f3bfc1b4db6`.

Only this new synthetic test directory changes. The routing core, inventory,
real-data drivers, historical scale reports and workflow files are unchanged.
No software defect in the methods under test was demonstrated by this campaign.
No CSC connection, Slurm submission, Whitebox execution or real raster sampling
was made. Existing regression scripts use tiny generated raster fixtures only.

## What is being distinguished

- A canonical land edge records one observed first in-grid move per land
  source. It is not proof of a ditch or a field-verified watercourse.
- A confluence has at least two observed incoming land edges in this window.
  Inflow from outside the window remains `UNKNOWN`.
- A shared downstream segment describes an already-stored confluence trace.
  A source membership can claim only its own observed common prefix with that
  segment. `FULL_CONFLUENCE_SEGMENT_OBSERVED` means the full **observed** segment,
  which can itself be censored; it does not prove complete downstream routing.
- A direct exit is an outward D8 pointer at a window boundary, observed in
  that cell's own trace. No outside receiver is read.
- A source reaches an exit only if its original trace reports
  `DOMAIN_EXIT_UNRESOLVED`. Its transition count excludes the outward step;
  the last path cell is the in-window exit source. Further routing is unknown.
- `STEP_LIMIT` reports a work limit. Even when the terminal cell is a known
  direct exit source, the original capped trace is not upgraded to an exit.
- Synthetic water classes 1/2/3 exercise the RANTA10 contact contract. Lake
  identity is preserved only for class 1; river/line recipient IDs stay unknown.
  These are generated labels, not real RANTA10 observations.

Local indegrees, source memberships and grouped exit-route counts are not
flow accumulation. A canonical edge can be referenced by several overlapping
confluence segments; their lengths must not be summed as disjoint geometry.
Within a segment, closing a cycle cannot count an edge twice. A cycle-closing
cell revisit is explicitly represented without an extra observation read.

## Reused methods and independent checks

`common.R` sources the unchanged LOW, first-contact, land-route and inventory
functions, plus the previous campaign's generator, oracle and synthetic limit
adapter. The adapter changes only allocation-limit literals in test-process
function copies; all original 121-cell limits and the 14-receiver/56-value
real-data read budget remain intact. It is not a large-area routing engine.

The oracle works from explicit synthetic successors, cell kinds and terminal
annotations, not by decoding production pointers or copying reported answers.
The additional checks independently verify every transition, ordered reads,
terminal states, censor counts, unique shared geometry, source-specific shared
lengths and exit memberships. Negative controls deliberately fabricate a
censored source's exit membership and a longer shared suffix; the oracle must
reject both. They never modify the actual inventory.

For every A case and the three B inventories, whole typed inventory objects
are compared with `identical()` against the exact `effab29` implementation,
including row order, IDs, membership order, lengths and status fields. A
mismatch stops the campaign with `STOP_BASELINE_MISMATCH`; the reference is
never adapted to agree with the new implementation.

## Phase A: all-source budgets 4, 16 and 32

Eight workers run 100/1,000 cells x fan/long/mixed/random, each at all three
budgets: 24 graph/inventory/oracle/reference comparisons. This does not repeat
the previous full 10,000-cell campaign. The fixture is serialized before/after
and all original function bodies are checked unchanged.

Between budgets, earlier paths, transitions and raw observations must be an
unchanged prefix of the longer observation. The old result itself stays
unchanged. In the **new** result, the `pointer_followed` annotation can change
at the former budget terminal when the extra move is now actually observed;
pointer values never change. Resolved terminals stay resolved, membership
extent can grow, and already-confirmed exit identities remain stable.

Per-cap CSVs report construction, indexed inventory, pinned old inventory and
oracle/check time separately, plus statuses, transitions and output sizes.
The worker wall time includes all three budgets, both inventory versions,
oracles, startup and checks. Worker RSS is not a per-cap measurement. Single
measurements are validation observations, not a controlled benchmark.

## Phase B: fixed sparse starts and long common suffixes

The 1,000-cell long fixture is a 100x10 serpentine graph. Let `order[q]` mean
its q-th path cell; IDs are row-major with declared global offsets. Starts are
fixed by these definitions before each case, without a search for favourable
results:

- `order[1]`, cap 256: 256-move censored land chain.
- `order[745]`, cap 256: exit after 255 moves, just before the limit.
- `order[744]`, cap 256: reaches the same exit-source cell at move 256 and
  remains `STEP_LIMIT` under the unchanged core contract.
- `order[1]` with a zero at `order[256]`: zero after 255 moves.
- `order[1]` with the fixed adjacent edge `order[40] -> order[39]`:
  a cycle before the cap, including the closing edge and no repeated read.
- Source cell 1 in a derived serial fixture: fixed S shortcuts at column 2
  of rows 1, 11 and 21 make at least three confluences visible on this sparse
  256-move trace. Only synthetic fixture pointers are changed to construct it.
- Source cell 1 with water at `order[128]`: class 1, 2 and 3 contacts after
  127 moves. Class 1 additionally varies the water cell's unused outgoing
  pointer among zero, invalid and NA; first contact must stay unchanged.
- `order[113]`, cap 32, and `order[129]`, cap 256: the secondary trace has
  more transitions and reaches beyond the original capped observation. It
  cannot resolve or mutate that original source. The original 256-move
  source and the direct-exit source `order[1000]` are also kept separate.

There are 15 sparse cases, never all-source 256-step tracing. The exact
source/terminal IDs and counts are in `B_sparse_results_15_cases.csv`.
A separate 100-cell serial fixture uses S shortcuts at rows 1 and 5, column 2.
Full inventories at budgets 32/64/128 check long shared suffixes and exact
old/new equality. At cap 32, source cell 3 reaches confluence cell 12 after
16 moves and can claim only 16 further shared edges, even though that
confluence's own trace observes 32. At cap 128, all sources actually exit and
the conditional N-E accounting check becomes applicable; it is not promoted
from the known graph alone when source traces remain censored.

## Phase C and resource supervision

The only optional large case was preselected as `long`, 10,000 cells, cap 16.
The gate and its inputs are recorded in `results.json`. It uses a conservative
15x projection from the *entire* 1,000-cell long worker (all three budgets,
both inventory implementations), so it deliberately overbounds a single-cap
case. It does not estimate exact 10,000-cell resource demand. Safe headroom
was not established; outcome: **NOT_RUN_RESOURCE_GATE**. No replacement
smaller-budget case, second large case or 100,000-cell case was run.

`run_campaign.py` reuses `synthetic_scale/run_validation.py` and changes only
its report/log locations. Each child retains a 1,536 MiB address-space cap,
a process-group RSS stop at 1,792 MiB, <=180 s per worker and the persisted
1,200 s absolute campaign deadline. Both elapsed worker time and development
pauses after the first worker count towards that deadline. The RSS threshold
leaves space for the small observer below the 2 GiB package ceiling.
`wait4` child peak RSS and sampled group RSS are reported separately; object
sizes are not peak memory. A resource stop or absent measurements cannot pass.

The original ten supervisor unit tests explicitly check intended child failures:
nonzero exit, two TIME_STOP cases (including exit 0 after SIGTERM), an injected
MEMORY_STOP without allocating gigabytes, MISSING_RESULT and expired-budget
NOT_RUN. Those are successful negative tests, not genuine campaign failures.
Raw and normalized log SHA256 values are preserved. Any gzip transcript is
lossless storage of normalized output; its stored-byte digest is separate.

## Reproduction and regressions

Base R and Python standard library suffice for the new cases. Existing raster
regressions additionally need terra/Rcpp; this campaign used R 4.5.0,
terra 1.8.29 and Rcpp 1.0.14. The pinned Git source object `effab29...` must
exist locally for exact compatibility comparisons.

```sh
python3 -B diagnostics/land_network_topology/long_path_validation/run_campaign.py --rscript Rscript --section all
```

The committed `results.json` is an observed campaign with a fixed historical
deadline, not a fresh budget. For a new reproduction, use a disposable checkout
at this commit and remove only this directory's generated reports/logs/CSVs
from that disposable copy before the command. Retain the archived checkout's
evidence. `--section B` reruns only the small B suite under the same persisted
deadline; it does not reset the campaign budget. Repeated logs get attempt
suffixes. Earlier scale-validation evidence is never overwritten.

All required old suites are run: topology 46, inventory 25, LOW window 25,
receivers 21, land routes 23, first contact 26, LOW core and production 02F.
The prior synthetic harness, prior compatibility suite and resource supervisor
are run as well. Their actual outcomes and logs are listed below.

## Next bounded scientific check

After CSC maintenance and separate authorization, use the already-prepared
14 boundary receiver test: exactly the fixed 14 unique cells in four existing
rasters, at most 56 returned values. Join all 16 original exit edges to these
receivers, retain original IDs and classify observed LAND/WATER/NoData/pointer
states. Do not read the old window again or follow a receiver's route farther.
A LAND observation does not verify a ditch; WATER does not approve an outlet.
This campaign gives no authorization to start that test.

`hydrological_validation=NOT_ASSESSED`
`channel_interpretation=NOT_ASSESSED`
`MODERATE=REVIEW_REQUIRED`
`NATIONAL=LOCKED`

## Measured campaign (20 October 2026)

| Cells | Fixture | Caps | Worker wall s | Child/group peak RSS MiB |
| ---: | --- | --- | ---: | ---: |
| 100 | fan | 4,16,32 | 5.1850 | 83.902 |
| 100 | long | 4,16,32 | 3.1657 | 70.590 |
| 100 | mixed | 4,16,32 | 2.9991 | 67.602 |
| 100 | random | 4,16,32 | 3.7685 | 67.785 |
| 1,000 | fan | 4,16,32 | 45.0965 | 187.340 |
| 1,000 | long | 4,16,32 | 14.0205 | 185.938 |
| 1,000 | mixed | 4,16,32 | 12.8973 | 137.449 |
| 1,000 | random | 4,16,32 | 21.2196 | 145.621 |

| Cells | Fixture | Cap | STEP_LIMIT | Reached exits | Direct exits |
| ---: | --- | ---: | ---: | ---: | ---: |
| 100 | fan | 4 | 65 | 35 | 5 |
| 100 | fan | 16 | 0 | 100 | 5 |
| 100 | fan | 32 | 0 | 100 | 5 |
| 100 | long | 4 | 96 | 4 | 1 |
| 100 | long | 16 | 84 | 16 | 1 |
| 100 | long | 32 | 68 | 32 | 1 |
| 100 | mixed | 4 | 19 | 35 | 10 |
| 100 | mixed | 16 | 0 | 46 | 10 |
| 100 | mixed | 32 | 0 | 46 | 10 |
| 100 | random | 4 | 24 | 21 | 11 |
| 100 | random | 16 | 0 | 25 | 11 |
| 100 | random | 32 | 0 | 25 | 11 |
| 1,000 | fan | 4 | 650 | 350 | 50 |
| 1,000 | fan | 16 | 0 | 1000 | 50 |
| 1,000 | fan | 32 | 0 | 1000 | 50 |
| 1,000 | long | 4 | 996 | 4 | 1 |
| 1,000 | long | 16 | 984 | 16 | 1 |
| 1,000 | long | 32 | 968 | 32 | 1 |
| 1,000 | mixed | 4 | 187 | 330 | 100 |
| 1,000 | mixed | 16 | 0 | 419 | 100 |
| 1,000 | mixed | 32 | 0 | 419 | 100 |
| 1,000 | random | 4 | 228 | 176 | 78 |
| 1,000 | random | 16 | 0 | 191 | 78 |
| 1,000 | random | 32 | 0 | 191 | 78 |

All 24 A inventories and three distinct B serial inventories were exactly
identical to the pinned old implementation (27 distinct fixture/budget pairs,
including nine cap-32 pairs). There were no baseline mismatches.

Final B: 15 sparse cases plus three serial inventories PASS, 2,029 assertions, 4.6351 s, 68.938 MiB RSS.

| Sparse case | Start cell | Cap | Status | Moves | Reads | Terminal cell |
| --- | ---: | ---: | --- | ---: | ---: | ---: |
| long_chain_censored_at_256 | 1 | 256 | STEP_LIMIT | 256 | 257 | 254 |
| exit_one_move_before_cap | 745 | 256 | DOMAIN_EXIT_UNRESOLVED | 255 | 256 | 991 |
| at_exit_source_exactly_at_cap | 744 | 256 | STEP_LIMIT | 256 | 257 | 991 |
| zero_one_move_before_cap | 1 | 256 | D8_ZERO | 255 | 256 | 255 |
| cycle_before_cap | 1 | 256 | CYCLE | 40 | 40 | 32 |
| multiple_serial_confluences | 1 | 256 | STEP_LIMIT | 256 | 257 | 305 |
| first_water_class_1 | 1 | 256 | FIRST_WATER_CONTACT | 127 | 128 | 128 |
| water_outgoing_pointer_0 | 1 | 256 | FIRST_WATER_CONTACT | 127 | 128 | 128 |
| water_outgoing_pointer_3 | 1 | 256 | FIRST_WATER_CONTACT | 127 | 128 | 128 |
| water_outgoing_pointer_NA | 1 | 256 | FIRST_WATER_CONTACT | 127 | 128 | 128 |
| first_water_class_2 | 1 | 256 | FIRST_WATER_CONTACT | 127 | 128 | 128 |
| first_water_class_3 | 1 | 256 | FIRST_WATER_CONTACT | 127 | 128 | 128 |
| shorter_source_budget_32 | 118 | 32 | STEP_LIMIT | 32 | 33 | 145 |
| other_source_observes_beyond_primary_cap | 129 | 256 | STEP_LIMIT | 256 | 257 | 385 |
| other_source_direct_exit | 991 | 256 | DOMAIN_EXIT_UNRESOLVED | 0 | 1 | 991 |

B was repeated only as the test package was finalized: the initial 14-case
version, a frozen-source confirmation, the explicit 32-vs-256 counted-length
control (15 cases), and quiet return-value logging. All attempts passed and
remain recorded; older verbose B transcripts are losslessly gzip archived.
A was not repeated, nor was the prior large scale campaign.

| Original/guard suite | Result | Observed summary |
| --- | --- | --- |
| `test_land_network_topology` | PASS | TESTS=46 PASS=46 FAIL=0; PASS: bounded synthetic topology only; no accumulation or hydrological approval |
| `test_land_network_topology_inventory` | PASS | TESTS=25 PASS=25 FAIL=0; PASS: synthetic topology inventory only; no CSC or hydrological approval |
| `test_one_low_network_window` | PASS | TESTS=25 PASS=25 FAIL=0 NOT_RUN=0; PASS: synthetic read-only window contracts; no CSC data or hydrological approval |
| `test_boundary_receivers` | PASS | TESTS=21 PASS=21 FAIL=0 NOT_RUN=0; PASS: contract and synthetic observations only; no CSC reads or hydrological approval |
| `test_land_d8_route` | PASS | TESTS=23 PASS=23 FAIL=0; PASS: synthetic D8 continuity only; no real LOW validation or verified ditch network |
| `test_first_water_contact` | PASS | TESTS=26 PASS=26 FAIL=0; PASS: first-water synthetic prototype only; no CSC evidence or hydrological approval |
| `test_lake_1847_focus` | PASS | PASS: LOW 1847 local window counts, elevations, mask and bounded D8 tracing |
| `water_connected_route_diagnostics` | PASS | PASS: 02F classifies downstream D8 route terminals without changing pointers |
| `test_harness` | PASS | PASS: 49 synthetic harness contracts; original 121-cell limits retained |
| `test_inventory_compatibility` | PASS | PASS: 5 complete inventory outputs identical to pinned base |
| `test_supervisor` | PASS | Ran 10 tests in 0.849s; OK |

Cumulative measured worker execution, all attempts: **178.655 s**.
Absolute interval from first worker through final B completion: **427.163 s**, below 1,200 s.
Maximum measured child/group RSS across the package: **384.215 MiB** (synthetic LOW-window regression).

Phase C: **NOT_RUN_RESOURCE_GATE**. Conservative batched-worker projections
were 2789.070 MiB and 210.308 s, above the
1,024 MiB headroom gate and 180 s case watchdog. These are upper projections,
not observed 10,000-cell requirements. No such raster or synthetic graph was read.

Actual campaign FAIL, TIME_STOP and MEMORY_STOP counts: **0**. One optional
case was NOT_RUN_RESOURCE_GATE. The intentional negative supervisor child
conditions listed above were caught as expected; their ten unit tests passed.
No scientific status was promoted. These finite synthetic examples do not
prove correctness for every graph, large-area scaling or real LOW drainage.
