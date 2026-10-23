# G5A: synthetic tile accumulation parity v1

Implementation of issue #54, stacked on draft PR #53 at
`ca0aaadb5cb99f2ced003a5b91a71821f92c5635`.
This is an in-memory mathematical QA component for at most two simulated tiles.
It neither builds a physical routing graph nor approves a real outlet.

`NATIONAL=LOCKED` · `MODERATE=REVIEW_REQUIRED` ·
`hydrological_validation=NOT_ASSESSED` ·
`channel_interpretation=NOT_ASSESSED` · `routing_authorized=false`.

## Interface and immutable records

`tile_accumulation_contract_v1.reconcile(Fixture) -> Reconciliation` uses Python
standard library types and the existing, unchanged `graph_oracle.py`.
All records are frozen dataclasses. Collection fields must be tuples; mutable
lists and wrong record types return `STOP`. Results contain only frozen records,
tuples, strings, enums, booleans and exact `Fraction` values. Inputs are not
rewritten or automatically repaired. There are no file, process, GIS or network
operations in the component.

| Record | Meaning |
| --- | --- |
| `Tile(key, mask_cells, halos=())` | Declared physical cell mask owned by this tile; halo references do not belong in this mask. |
| `OwnedNode(key, kind, owner_tile, cells=(), terminal_role=None)` | Unique graph identity and owner tile. LAND and LAKE need physical cells; RIVER_REACH may be an area-free reference. BOUNDARY cannot own cells. |
| `Halo(cell, node, owner_tile)` | Reference from a different tile to a cell with a matching real owner **inside the synthetic fixture**. Never contributes area. |
| `FlowArc(source, target, kind, fraction=Fraction(1), provenance_status="SYNTHETIC_EXPLICIT")` | Explicit hypothetical arc. LAND_D8, LAKE_OUTLET, RIVER_LINK or BOUNDARY_EXIT; original S1/02F observations are not accepted as arcs. |
| `Transfer(transfer_id, upstream_tile, downstream_tile, from_node, to_node, from_cell, to_cell, ...)` | Exactly one seam record per cross-tile arc. Endpoints must be physical cells belonging to the indicated nodes and tiles. |
| `Upstream(target, source_cells=(), area_m2=None)` | Explicit unknown outside input. Existing owned cells cannot be declared as external sources. Numeric external injections are outside this version's scope and cause STOP. |
| `Fixture(tiles, nodes, arcs, transfers=(), upstream=(), split_mode=False, resolution_m=Fraction(2))` | Fully declared tiny synthetic graph; positive integer cell IDs use the existing oracle's range 1–36,000,000. These IDs do not authenticate a real grid. |

Transfer optional fields are `provenance_status="SYNTHETIC_EXPLICIT"`,
`claimed_area_m2=None` and `injected_area_m2=Fraction(0)`. An optional claim is
checked against independent path accounting; it is never used as an input flux.
A nonzero injection is forbidden: owned upstream cells are already represented
in the global graph. Transfer IDs and node pairs must both be unique.

`SYNTHETIC_EXPLICIT` is a scope marker, **not provenance authentication**. It
asserts nothing about a real D8 pointer, geographic adjacency, historical input
version, approved lake outlet or S1 candidate. There is no real-data mode.

### Minimal two-tile example

Run with `diagnostics/water_connected_graph_design` on Python's import path:

```python
from fractions import Fraction
from tile_accumulation_contract_v1 import (
    Fixture, FlowArc, OwnedNode, Tile, Transfer, reconcile,
)

fixture = Fixture(
    tiles=(Tile("A", (1,)), Tile("B", (2,))),
    nodes=(OwnedNode("a", "LAND", "A", (1,)),
           OwnedNode("b", "LAND", "B", (2,)),
           OwnedNode("end", "BOUNDARY", "B",
                     terminal_role="SYNTHETIC_TERMINAL")),
    arcs=(FlowArc("a", "b", "LAND_D8"),
          FlowArc("b", "end", "BOUNDARY_EXIT")),
    transfers=(Transfer("ab", "A", "B", "a", "b", 1, 2),),
)
result = reconcile(fixture)
assert result.status == "PASS"                  # mathematical synthetic parity
assert result.receipts[0].area_m2 == Fraction(4)
assert result.terminal_area_m2 == Fraction(8)
assert result.routing_authorized is False
```

Tile A: 4 m² owned + 0 incoming − 4 outgoing = 0 terminal.
Tile B: 4 m² owned + 4 incoming − 0 outgoing = 8 terminal.
Adding a B reference to cell 1 or an A reference to cell 2 changes neither total.
The receipt is deterministic QA accounting, not a distributed transport service
or a demonstration of an independently running receiving process.

## Decision rules

1. Check schema, size, 2 m resolution, unique node IDs and unique physical cell
   ownership. A tile's declared mask must exactly equal its nodes' owned cells.
   Empty physical ownership cannot claim vacuous completeness. Halo identities
   must match remote owners and cannot be promoted to new area.
2. Check explicit synthetic arc semantics and exact positive `Fraction` values.
   A single outgoing arc transmits fraction 1. Multiple outgoing arcs are allowed
   only from a LAKE, with `split_mode=True`, all LAKE_OUTLET kinds and fractions
   summing exactly to 1. Alternative real spill candidates imply no such split.
3. Check global cycles before numerical accounting. DFS over the combined graph
   distinguishes `GRAPH_CYCLE` from `CROSS_TILE_CYCLE`. A locally acyclic tile does
   not certify the combined graph.
4. Require exactly one matching transfer for each cross-tile arc; reject missing,
   repeated or conflicting records, wrong physical endpoints/owners, and any
   extra flux injection. Transfers cannot end on area-free boundary references
   in another tile, since these have no physical cell to verify.
5. Retain unknown imports and unresolved terminals. `TILE_BOUNDARY` and an
   unlabelled BOUNDARY yield `TILE_BOUNDARY_UNRESOLVED` and `BOUNDARY_NOT_COAST`.
   A non-BOUNDARY terminal yields `MISSING_OUTLET`. No missing edge is invented.
6. Invoke existing `synthetic_accumulation` once, with its original algorithm.
   The sidecar checks terminal completeness itself, so
   `enforce_boundary_terminals=False` permits **local lower-bound** accounting of
   unresolved graphs. It does not relax their UNKNOWN classification.
7. Independently enumerate weighted paths from every unique owned pixel, starting
   with exactly 4 m² per pixel. No topological accumulation algorithm is copied.
   Each source's terminal path weights must sum to 1. Count traversals across
   each seam and terminal contributions separately from the oracle's results.
8. Compare every node's received area and each seam flux exactly, then require
   `sum(terminal areas) = 4 × unique owned cells`. For each tile require
   `owned + incoming − outgoing = terminal`. No floating-point tolerance is used.

### Status and result interpretation

- **PASS**: the closed, explicit **synthetic** fixture has exact area parity.
  `complete_area_m2` is the complete represented synthetic area only.
- **UNKNOWN**: explicit upstream uncertainty, unresolved tile exit or missing
  outlet. Owned and terminal numbers are **lower bounds restricted to represented
  cells**, excluding outside input. `complete_area_m2=None`; local mathematical
  equality is not global completeness. Findings retain the affected node IDs.
- **STOP**: contradictory data, unsupported evidence, schema errors or resource
  bounds. Findings contain a reason code and context; numerical result fields
  are empty/None. No graph repair is attempted. Unexpected implementation
  exceptions propagate as test/caller errors rather than becoming PASS/UNKNOWN.

`oracle_received_m2` and `path_received_m2` are separate immutable sorted
`(node, Fraction)` tuples. `receipts` and `tile_balances` are also canonical;
valid fixture row/tile/arc order does not change the result. `boundary_roles`
retains the supplied terminal labels. The sidecar reports the first failing
invariant on STOP, rather than claiming an exhaustive error inventory.

`SYNTHETIC_TERMINAL` closes an abstract fixture without a geographic claim.
An explicitly supplied `COAST` label is preserved only as a **synthetic label**;
no evidence of a real coast is checked or inferred. A raster/tile boundary is
never upgraded to COAST. Even a fixture labelled COAST cannot authorize routing.

Relevant STOP codes include `DUPLICATE_CELL_OWNERSHIP`,
`MASK_OWNERSHIP_MISMATCH`, `HALO_OWNERSHIP_MISMATCH`, `DUPLICATE_HALO`,
`MISSING_OR_DUPLICATE_TRANSFER`, `OWNERSHIP_MISMATCH`, `TRANSFER_AREA_MISMATCH`,
`INVALID_FLOW_SPLIT`, `CROSS_TILE_CYCLE`, `GRAPH_CYCLE`,
`SHARED_UPSTREAM_COUNTED_TWICE`, `UNSUPPORTED_ROUTING_EVIDENCE`,
`PARITY_MISMATCH`, `AREA_CONSERVATION_FAILURE` and `RESOURCE_LIMIT`.
The tests check these distinctions and fail-closed schema cases explicitly.

## Independent calculations and measured tests

The global oracle uses indegrees and topological propagation. The new verifier
uses a different calculation: per-cell brute-force path enumeration and products
of rational arc weights. It independently derives node contributions, seam
fluxes and per-tile balances from the same checked fixture. It does not call the
oracle for its expected values. Tests deliberately corrupt the oracle's received
area and terminal total to demonstrate that the verifier detects disagreement.

Hand-checkable fixtures:

| Fixture | Independent expectation | Observed |
| --- | --- | --- |
| Single tile a→b→end, two pixels | 4 at a, 8 at b/end | Exact parity |
| Two-tile serial | Seam 4; terminal 8 m² | Exact parity |
| Two sources across seam into b | Two distinct seam fluxes 4+4; b/end 12 m² | Exact parity |
| Lake pixels 1+2, 1/4 and 3/4 split, rejoin after three river pixels | Lake 8; branches 6 and 10; join/end 20 m² | Exact parity |
| Same split with remote halo lake references | Same 20 m²; no additional lake contribution | Exact parity |
| 1/3 and 2/3 split to separate terminals, two river pixels | 20/3 + 28/3 = 16 m² | Exact parity |
| Fractions 1/(10^40+3), 1−1/(10^40+3) | Seam fluxes 8/(10^40+3), 8−8/(10^40+3) | Exact, no rounding |
| Explicit 1/4+1/4 or unspecified multiple full outlets | STOP, INVALID_FLOW_SPLIT | STOP |
| Cross-tile return cycle with acyclic local partitions | STOP, CROSS_TILE_CYCLE | STOP |
| Unknown upstream / unresolved tile boundary | UNKNOWN, complete area absent | UNKNOWN |

The seeded test checks **24 DAG fixtures**, each with 4–12 physical LAKE nodes,
separate terminal, deterministic seed `540053`, rational splits and varying tile
ownership. Each fixture compares both calculations at every node and checks
terminal conservation and both tile balances. These are subtests of one named
test, not 24 extra named tests. No real lake interpretation is attached to them.

Final local run: Python 3.12.14, 2026-10-23. PASS counts exclude skips;
NOT_RUN counts below refer to discovered optional tests.

| Batch | PASS | FAIL/errors | NOT_RUN | Measured seconds |
| --- | ---: | ---: | ---: | ---: |
| New G5A | 97 | 0 | 0 | 0.0984 |
| Existing graph oracle | 26 | 0 | 0 | 0.0017 |
| S1 decision contract | 101 | 0 | 0 | 0.1091 |
| S2A pure D8 | 89 | 0 | 1 | 0.1400 |
| S2B adapter | 82 | 0 | 7 | 0.8277 |
| S2C metadata preflight | 71 | 0 | 2 | 0.3669 |
| **Total** | **466** | **0** | **10** | |

The one S2A skip is the optional original R 02F comparison
(`MM_S2A_RSCRIPT` unset). The seven S2B skips are actual GDAL synthetic fixture
tests; the two S2C skips are actual GDAL metadata fixture tests. Their opt-in flags
were unset; host GDAL 3.10.3 does not satisfy their pinned 3.12.2 environment.
Their mocked/synthetic contract tests passed. These skips are not PASS and do not
establish anything about real data. No dependency installations were needed.

The first 90-test G5A run passed. Review then added seven targeted cases, including
an empty-owner guard, a genuine dense-DAG path-budget stop, exact separate
terminals, and an area-free cross-tile endpoint rejection. The final 97-test run
passed. There were no observed failing test executions in this work package.

The whole six-batch process peaked at **40.95 MiB RSS** (Linux `ru_maxrss`),
including existing regression imports/fixtures. This is a process-level measured
peak, not an estimate of national memory use or a per-batch measurement.
Times include runner/logging overhead and are not scalability benchmarks.

Reproduce the required stdlib batches from the repository root:

```sh
python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_tile_accumulation_contract_v1.py -v
python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_graph_oracle.py -v
```

Other local batches used the same discovery command with
`test_decision_contract_v1.py`, `test_s2a_pure_d8_trace.py`,
`test_s2b_readonly_window_adapter.py` and `test_s2c_original_source_preflight.py`.
The runner explicitly failed on zero discovered tests or any failure/error.

## Resource and scientific limits

Hard bounds: two tiles; 20 nodes; 64 unique owned/mask cells; 64 arcs; 64 transfers;
128 halo references; 20 upstream-unknown records; 20,000 enumerated path states.
Input fraction numerator/denominator bit lengths are bounded to 256. Cells and
collections are checked before enumeration. An actual 20-node dense fixture
hits the path budget and returns STOP with no partial numerical output.

Path enumeration is exponential in the number of branches and intentionally
bounded. It is an independent **tiny-fixture verifier**, not a second scalable
production accumulation engine. No national performance claim is supported.

This version represents each lake once as a single owner node with multiple
pixels, with remote halo references. It does not solve the future distributed
aggregation of a real lake spanning multiple owner tiles. It does not prove cell
adjacency, D8 geometry, NoData validity, actual water masks or geographic coast
identity. No real source metadata, original CSVs or raster pixels were read.
An accepted synthetic split says nothing about whether a physical lake has one
outlet, several simultaneous outlets or no supported outlet.

S2C's historical 02F runtime-input lineage is still unresolved; its existing
metadata-only STOP remains intact. G5A adds no route to bypass that gate. Before
any real/national accumulation, separate work must establish authenticated
runtime input versions, real cell/halo ownership, approved physical routing and
lake aggregation, complete boundary imports/exports, global acyclicity,
independent hydrological validation and measured regional scalability. A 2 m
pixel contributes 4 m² of raster-derived area, not discharge in m³/s, exact vector
lake area, evidence of a channel or evidence that a catchment reaches the sea.

Only the three issue-allowlisted files were added. No existing module, workflow,
input, hydrological gate, archived result or production R file was modified.
No CSC/Slurm jobs, real raster reads, FillDepressions runs or real accumulation
were performed. No merge or outlet approval is part of this delivery.
