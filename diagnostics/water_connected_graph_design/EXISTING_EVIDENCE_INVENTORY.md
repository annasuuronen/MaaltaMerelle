# LOW 02D–02F: existing CSV evidence inventory

Status: **DRAFT / read-only / evidence accounting only**. This extends [PR #38](https://github.com/annasuuronen/MaaltaMerelle/pull/38) without altering production or scientific locks. **No raster reads, D8 reruns, Slurm jobs, outlet selections or accumulation.**

## Input files (all existing, no recomputation)

Point `--input-dir` at the existing Roihu LOW baseline output:
`/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000/02_baseline`.

Five required files, each max **15 MB**, max **200,000 CSV data rows**, no symlinks:
- `02D8_final_spill_evidence.csv` — entire per-spill-group 02D.8 set, including `outlet_selection=UNASSIGNED`;
- `02D_lowest_spill_shore_edges.csv` — **all** minimum-spill shore edge records, not only included candidates;
- `02E_water_connected_candidate_evidence.csv` — same groups + candidacy, including REVIEW_REQUIRED and NO_EXTERNAL_EVIDENCE;
- `02E_water_connected_candidate_spill_edges.csv` — exactly the eligible group edges;
- `02F_water_connected_candidate_route_edges.csv` — exactly the eligible edges enriched by 02F's **first-water/terminal** diagnostic.

If a file is missing, oversized, truncated or inconsistent, **STOP**; this does not trigger any baseline recomputation. The Python program validates exact group identities, spill levels, 8-neighbour geometry, original and derived group statuses, exact candidate-edge coverage and one-to-one 02E-to-02F edge linkage, deduplicated 02F receiver+origin traces and water-terminal class consistency.

A source-label is mandatory but **operator-supplied and not independently verified**. Input SHA256 checksums and rows are included in the JSON output for future reproducibility. Neither the historical scientific source commit nor the correct RANTA10 raster provenance can be derived from these five CSVs alone.

## Outputs

A new, private `INVENTORY_WORK` scratch directory contains:
- `synthetic_tests.log`, status PASS/STOP for local Python unit tests;
- `result/spill_group_inventory.csv`: one row per original group, including unresolved groups and counts of low shore edges, diagonals, eligible edges, first-water contacts, and other termination statuses;
- `result/lake_inventory.csv`: number of groups, candidate groups, review groups and first-water-only groups **per lake**;
- `result/summary.json`: totals, source input hashes and all scientific locks.

**Interpretations strictly limited:**
- `FIRST_WATER_CONTACT_ONLY` means 02F's first water contact; **not** verified outlet, not water-to-sea route.
- `n_diagonal_shore_edges` detects diagonal **grid** adjacency only; **not** proof of an isolated vector *corner-only* contact.
- `n_lakes_with_multiple_included_candidate_groups` means alternatives still need review; **not** simultaneously active outlets and **not** default 50/50 split.
- `n_lowest_spill_edges` is an edge count, **not** a unique outlet count.
- `NO_EXTERNAL_EVIDENCE` and `REVIEW_REQUIRED` remain unresolved, and are **not equivalent** to lakes proven to have no outlet.
- A complete `02F` join establishes only what the previous run reported; **not** D8 physical correctness.
- `verified_outlet_count=NOT_ASSESSED` and `flow_accumulation=NOT_COMPUTED`. This is **not** an estimate of hydrological corrections.

## Test and running gates

Tests only, no user data:
```bash
python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_existing_evidence_inventory.py -v
```

Pinned Roihu shell runner:
`diagnostics/water_connected_graph_design/run_existing_evidence_offline.sh`.
Run in a **separate clean clone** of the implementation draft branch with `MM_EXPECTED_COMMIT` set to its reviewed exact SHA; pass the absolute existing baseline folder as the only argument. The script uses `timeout 20s` synthetic tests and `timeout 90s` the inventory program, writes only to a new private scratch directory. No module/terra/R/Whitebox required. **Do not run until independently reviewed** against actual generated CSV headers and login-node policy.

The 33 synthetic methods and the new CI workflow are **software tests only**, never substitute for validating historical 02D/02E/02F values. At authoring, **actual CSC CSV inventory NOT_RUN**; CI status must be confirmed separately.

Prior audits of LOW D8 microscopic increments remain distinct (PR #35/#37); their numeric match to Whitebox flat increments is not outlet evidence.

`hydrological_validation=NOT_ASSESSED` · `channel_interpretation=NOT_ASSESSED` · `MODERATE=REVIEW_REQUIRED` · `NATIONAL=LOCKED`.
