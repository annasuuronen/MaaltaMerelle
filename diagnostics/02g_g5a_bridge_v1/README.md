# Stream B — 02G.3 / G5A accumulation-contract crosswalk

Issue #78 under coordination issue #81. Base: G5A draft #55,
`e1c94b876d5b5ed6a0a485445d011c384cdc9e5c`. Read-only comparison: 02G.3 draft
#32, `fb5c673b5fb08652e846191074095627b364d7db`. Their merge base is
`7050b582edab3195669529f366b4f5a2915488c6`; the pins have47/60 unique commits.
They are not assumed to contain one another. No merge/cherry-pick or copied
accumulation implementation is included.

```text
NATIONAL=LOCKED
MODERATE=REVIEW_REQUIRED
hydrological_validation=NOT_ASSESSED
channel_interpretation=NOT_ASSESSED
routing_authorized=false
outlet_selection=UNASSIGNED
HISTORIC_02F_EFFECTIVE_D8=NOT_ASSESSED
```

## Decision: common-prefix contract only; full handoff STOP

**A general numeric 02G.3→G5A handoff is not ready.** The two accepted contracts
do not measure the same source population. 02G.3 assigns one source unit to
each owned LAND cell and zero to WATER. G5A starts with4m² per owned physical
cell, including owned LAKE cells. Consequently the quantities cannot be equated
simply by multiplying every 02G count by4. Equality of a LAND-only prefix is a
useful software check, not parity of whole water-connected graphs.

The second mismatch is terminal semantics. 02G.3 stops at known first WATER,
whose source contribution is zero, and rejects missing successor/STEP_LIMIT.
G5A requires LAKE to own physical cells and permits hypothetical lake outlet
arcs/fractions; an area-free BOUNDARY is not a lake. G5A also rejects a cross-tile
transfer into an area-free boundary because no physical receiving cell can be
verified. Relabelling a lake as an empty river/boundary, adding water as LAND,
inventing an outlet or treating a censored path as completed would hide the
mismatch. None is done here.

| Contract dimension | 02G.3 at pinned #32 | G5A at pinned #55 | Bridge rule / remaining dependency |
| --- | --- | --- | --- |
| Source area | LAND count×4m²; WATER contributes0 | All owned physical pixels×4m², including LAKE | Compare only explicitly common LAND population; water/source-weight mapping needs review |
| Local completeness | Whole declared ≤27-position census,≤11 LAND; independent core/halo/source tables | Bounded explicit graph/masks,≤2 tiles,20 nodes,64 cells | Neither contract authenticates the other input or historical data |
| Numeric arithmetic | Exact small R double-integers | Exact Python Fraction and independent weighted-path verifier | Unit conversion4 is exact on common integer domain; fractions are outside 02G single-successor domain |
| Global total | Always UNKNOWN external import; total fieldsNA | UNKNOWN if outside imports/unresolved terminals; explicit closed synthetic fixture can PASS | Even closed G5A PASS must not promote an 02G local count to global total |
| Ownership / halo | Every grid position has one owner; halos observe, never source | Unique cell/node owner; remote halos never contribute | Shared physical cells counted once; no halo-to-source promotion |
| Shared lake cells | WATER zero-source terminal cells | Multiple cells may belong to one LAKE owner node; remote references possible | Real distributed lake ownership/aggregation is not solved by either bridge |
| Confluence / seam | One successor, DAG; source sets not materialized | Explicit seam record once per cross-tile arc; no reinjected area | Common LAND seam can be compared; actual independent R/Python result handoff is NOT_RUN |
| Duplicate transfers | No message/receipt transport implemented | Duplicate IDs/pairs or injected flux STOP | Do not claim receipt idempotence or independent receiving process from this wrapper |
| Cycles | Full declared graph checked before counts | Combined graph distinguishes local/cross-tile cycles | Local acyclicity does not certify global acyclicity; accepted tests already cover this |
| Terminal boundary | Unknown successor/uncensused boundary is not complete | TILE_BOUNDARY/unlabelled boundary gives UNKNOWN, never inferred coast | Boundary≠coast; common-prefix fixture closes no physical outlet |
| Optional lake split | Not supported; exactly one successor per LAND, none from WATER | Explicit Fraction splits only with split_mode, hypothetical outlets | STOP rather than rounding/normalizing to an integer local count |
| 4ha / routing truth | Threshold metadata, not channel proof | Pixel-derived area, not discharge or approved outlet | No stream/channel/coastal inference or national threshold from tiny LOW observations |

## Three new files and targeted missing tests

`bridge_scope.py` is a tiny **comparison guard**, not an accumulator or R loader.
`compare_declared_reference(Fixture, Reference)` calls the unchanged G5A
`reconcile` once and checks it against **hand-declared synthetic** LAND-only
counts. It delegates existing graph/halo/transfer/cycle validation; no second
propagation algorithm is copied. A successful crosswalk is
`LOCAL_COMPATIBLE_EXTERNAL_UNKNOWN`, never VALIDATED, global completeness or
observed 02G interoperability. Total fields remainNone and
`actual_02g_invocation=NOT_RUN`. STOP returns no numeric fields.

The new fixture has three LAND sources, two seam transfers converging on the
third source and an unresolved boundary reference. Independently specified
source memberships are a={1}, b={2}, c=end={1,2,3}, hence areas4,4,12,12m².
This is an abstract common-prefix fixture, not a complete 02G cell census or
real D8 geometry. The boundary reference is not claimed to be known first water.

`test_bridge_scope.py` runs only18 new named checks: common source/area parity;
local≠global even for G5A closed PASS; outside UNKNOWN lower bound; rejection of
zero/total claims, LAKE physical-area substitution, split semantics, count-unit
collisions, altered counts, wrong origin/scope, duplicate/extra sources,
invalid/missing references and over-budget sources; order invariance and locked
scientific output. Expected memberships are declared independently, not read
from G5A output. The tests do not import previous test modules or 02G code.

Executed locally 2026-10-24, Python3.12.14:

| New suite | PASS | FAIL | SKIPPED / NOT_RUN |
| --- | ---: | ---: | ---: |
| `test_bridge_scope.py` | 18 | 0 | 0 |

One test execution, exit0; wall0.0846s, child maximum RSS13.875MiB. Hard outer
TERM15s/KILL2s timeout,256MiB address-space limit; standard library only.
These are tiny-fixture measurements, not regional/national scaling estimates.
The former G5A97, graph-oracle campaign and 02G.3 739 checks were not repeated.
Actual R02G/PythonG5A interoperability and Roihu execution are **NOT_RUN**.

From the repository root, only the new checks:

```sh
PYTHONDONTWRITEBYTECODE=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 \
  timeout --signal=TERM --kill-after=2s 15s prlimit --as=268435456 -- \
  python3 -B -m unittest discover -s diagnostics/02g_g5a_bridge_v1 \
  -p test_bridge_scope.py -v
```

No new B-specific Roihu minitest is required now: these stdlib comparison
checks already ran in Codex and have no R/Terra/GDAL dependency. Repeating them
on CSC would not resolve the source-weight or endpoint design decision. Keep
the unimplemented integration outside the coordinated minitest manifest.

## Exact dependency / integration STOP plan

Only read the divergent R source with `git show pin:path`; do not source it now.
Any future dual-language handoff needs a separately reviewed detached loader,
without merging drafts, automatic fetch or old test runners. These exact bytes
were inspected; hashes identify code only, not authenticated datasets:

| Commit / source | Bytes | SHA256 |
| --- | ---: | --- |
| G5A pin, `diagnostics/water_connected_graph_design/graph_oracle.py` | 7008 | `924a6ca5af1c78af516e06d1ab87cb2183a302ec48f9a9d96d9e6427de56b659` |
| G5A pin, `diagnostics/water_connected_graph_design/tile_accumulation_contract_v1.py` | 17840 | `beeb47c747ca68b5588131e7bb908a47d87941ad7b1c59eaaba7295f120b9753` |
| 02G.3 pin, `diagnostics/02g_complete_local_dag_core/count_core.R` | 14744 | `3d430c8193e82602fefd2d7df603f5c5a28fab6cb1bd429ae90fcdd4fdfe96a4` |
| 02G.3 pin, `diagnostics/02g_complete_local_dag_core/README.md` | 13919 | `770483003a73e31e55ea18bbcdce8ca98dbb2c2994f234b1f99c9f2b76ec8080` |

Before implementing that loader/adapter, explicitly choose and review the target
quantity: LAND-only local contribution versus all-owned-cell contribution.
Define water-cell ownership/source weight, known first-water endpoints versus
G5A routing nodes, and any preserved split fractions without silently adapting
accepted cores. Do not subtract arbitrary lake areas from a mixed accumulation
number; upstream contributions and split histories differ. The future fixture
must independently declare whole local census, shared identities and expected
source subsets; an event/route union cannot substitute for that census.

If approved, the loader must require both exact commit objects locally,
disable Git lazy fetch/replacements and text conversion, verify every code blob
above before sourcing/importing captured bytes, bound all sizes, and use separate
Base-R then Python stages. Missing/changed code or ambiguous population/endpoint
mapping STOPs. No automatic fetch, source of a mutable draft checkout, container
nesting, real raster reader or production integration is permitted. Code hashes
and synthetic equality are not provenance/witness claims.

Three additions only under this prefix. Existing code, workflows, tests,
reports and all other branches remain unchanged. No CSC/SSH/Slurm, real raster
access, accumulation raster, natural outlet decision, hydrological approval or
merge is performed.
