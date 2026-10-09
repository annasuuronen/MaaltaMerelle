# Human-modification validation gradient (baseline)

Use measured national inventories, with source date and provenance, to select:
A: at least one natural 10 km core whose tested lake/outlet hydrological
context has zero known dams/locks/gates/other major hydraulic structures and
zero influenced waterbodies. Unknown influence is not natural evidence.
B: E200000_N6900000, one known dam (verify inventory); flag affected
waterbodies and exclude them from natural-rule derivation.
C: if available, a comparable tile with several structure-influenced lakes.
D: TEST_SULKU_11, a heavily modified robustness/stress test.

Required inventory per candidate: tile ID; core/halo geometry; DEM/water
coverage; number of lakes and other waterbodies; counts of dams, locks, gates,
other structures within core and hydrological influence context; number of
influenced/unknown-influence waterbodies; lake fraction, relief, river density,
ecoregion, source date and completeness. Screen for >=99% input coverage and
complete structure metadata. Rank natural and moderate candidates by robustly
standardized distance to B in relief, lake fraction and river density; preserve
diversity by choosing additional candidates from other ecoregions if possible.
Never use structures to override routing; use them only to stratify QA.
No actual A/C identity or structure count can be asserted from this repository:
it contains TEST_SULKU_11 fixtures but not the national candidate inventory.

Each tile must preserve all observed spill groups and candidate outlet edges;
never assume one outlet per lake or invent a split. Natural unaffected cases
alone define general lake spill/escape rules; B/C test transferability and D
tests resilience. Keep NATIONAL locked until the gradient, multi-tile handoff,
global mass propagation, per-cell accumulation reconstruction and CSC pass.
The 4 ha stream network is deferred to the forest-harvesting erosion scenario.
