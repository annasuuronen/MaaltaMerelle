# CSC LOW + MODERATE hydrology QA: executed diagnostics and reproducible follow-up

**Dated 2026-10-16.** This is a record of diagnostics executed on Roihu and
reported in the project conversation. It **does not claim** the author ran the
Roihu jobs directly or independently downloaded the original GeoTIFFs/CSVs.
No production routing change, no data overwrite, no new fill job, no scientific
acceptance. **NATIONAL=LOCKED; MODERATE=REVIEW_REQUIRED; PR remains draft.**

For the underlying explanation of why a positive shoreline threshold does not
imply an observed STORAGE raise, see
[moderate_02d4_diagnosis.md](moderate_02d4_diagnosis.md).
For the synthetic Whitebox examples, see the already existing
`tests/spill_storage_semantics.R`. Do not rerun the synthetic tests simply to
repeat the same evidence.

## Completed checks and reported results

### LOW, existing 02D.6 / 02F investigations

- Eleven ordinary raised-depression components assessed; 15
  `LOWER_ESCAPE` edges from 11 component/source pairs. 02D.6
  `RESOLVED` is **diagnostic**, not a verified natural outlet.
- Original LAND_WATER D8 chose the nominated lower escape in 7 of 11
  component/source cases; four differed: components **241, 270, 289, 402**.
- Components **241** (lake 1847) and **402**: the examined original D8 routes
  returned to their source lake.
- Component **270**: D8=0 at a land-cell local minimum near lake 1849.
- Component **289**: at least 32 D8 transitions; `STEP_LIMIT` does not prove
  outlet absence.
- A distinct large domain-edge case (component 1, lake 1940/1941) included
  11,997 nonfinite domain exits and should not be generalized to an ordinary
  interior depression.

### MODERATE, 6000×6000 at 2 m, 158 lakes

- Original LAND_WATER vs WATER_STORAGE audit: reported **0 raised, 0 lowered
  cells**, matching NA masks; D8 raster equality verified independently at
  36 million cells (0 different values / invalid directions). Numerical
  tolerance and actual NA-mask coverage must be kept distinct.
- **52** lakes with `spill_raised=TRUE`, **0** with
  `storage_raised=TRUE`, **52** `raise_mismatch=TRUE`.
  All 52 have **zero raised lake cells**, **zero raised depression components**,
  and status `SPILL_RAISED_NO_COMPONENT`; 106 other lakes are
  `NO_RAISED_COMPONENT`.
- Positive shoreline threshold ranges from **0.0009918213 m to
  1.1969909668 m**. Every one of the 52 has precisely one low spill group;
  the groups contain a total of **162** lowest shore edges. All 106
  non-spill-raised lakes have at least one low edge (62,403 edges total).
- Lake 203439: W(source)=153.8000031 m, receiver
  153.8130035 m, D8(source)=0, D8(receiver)=64 returning to source.
  Storage matches the original surface at those cells.
- Lake 203443: W(source)=177.7400055 m, lowest receiver
  178.9369965 m, three source edges; receivers follow D8 back into
  the source lake, and sampled STORAGE elevations match LAND_WATER.
- Following the **existing** D8 from the 162 nominated lowest-spill receiver
  cells (at most 100 steps per route) yielded **159
  RETURN_TO_SOURCE_LAKE** and **3 TERMINAL_0**. All 3 exceptions concern
  lake **204104**, converging on terminal cell **12373731** with LAND and
  STORAGE elevation 134.375 m, D8=0. The nearest traced upstream elevations
  were 134.3919983, 134.3880005, 134.3860016 m.
- Terminal 12373731 is absent from `02C_zero_pointer_cells.csv` (6688
  entries). **This is not evidence that it is missing from the D8 raster**:
  02C uses `zero_cells <- candidate_cells[is.finite(p_all) & p_all==0]`,
  where candidates come from a restricted adjacent-land selection.
  Its table is not an inventory of every D8 zero pointer.
- The original MODERATE 02A `02A_storage_regression_QA.csv` contains
  `NA` benchmark comparison entries and `CHECK DIFFERENCES`. Do not
  call that a regression PASS.
- Original MODERATE Slurm array task 1 (job 2264133) reached 02B
  `building land-water D8 pointer` and was canceled by the time limit.
  The MODERATE V2 resume copied the original 02A land/water and STORAGE
  files; their SHA256 checksums matched across original and V2 paths:
  LAND_WATER `940d8198b3f383cceb0fdc2e9a9e341015cc99d7e31d7acc09e0b77764e19571`;
  WATER_STORAGE `3077150d0f6a2439278a2c234295780158932edbd1aad6bb99ff1cad759f88e4`.
  Matching these copies verifies provenance to the original output, **not**
  an independent second Whitebox fill.
- The isolated fresh Whitebox `moderate_fill_recheck_20261014`
  timed out (exit 124) and left **no fresh output**. Do not count it as a
  successful fill comparison and do not blindly repeat it.
- V2 `resume.log` ended with:
  `Error: all(spill_lakes$n_depression_components >= 1) is not TRUE`;
  `Execution halted`. The **actual production checkout** reported
  `4bbf22bb39181c8a4c27ebc3e2769766043115b8`.
  At 02D.5 the gate is false: **52 spill-raised lakes, 0 with >=1 component**.
  Downstream 02D.5–02D.8 and 02E/02F were not produced in this V2 run.
- **Important source distinction:** actual run code at
  `/projappl/project_2004707/MaaltaMerelle/R/02_build_baseline_hydrology.R`
  differed from the separate CSC fixture at
  `/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/fixtures/R/02_build_baseline_hydrology.R`.
  At least one inspected fixture version required **49** spill lakes,
  each with **exactly 1** component; the real logged run required
  `all(... >= 1)`. Do not attribute fixture predicates to the real run.

All figures in this section come from the user's reported diagnostic stdout,
rather than a newly created on-disk Roihu report.

## One-command batch diagnostic (no repeated copy/paste)

The repository now contains
[`scripts/audit_moderate_spill_d8_readonly.R`](../scripts/audit_moderate_spill_d8_readonly.R).
It reproduces the 52-lake classification, 162-edge D8 endpoint audit,
02C terminal-table membership, and 02D.5 prerequisite check in **one
read-only invocation**. It extracts cells on demand instead of running a
new whole-area FillDepressions. It prints findings; it does not write files,
submit Slurm jobs, modify production code, or change the scientific gate.

On Roihu, with `terra` available in the R environment:

```bash
Rscript --vanilla scripts/audit_moderate_spill_d8_readonly.R /scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/moderate_resume_20261014_v2/run/02_baseline /scratch/project_2004707/pienvedet/csc_validation_4bbf22b/inputs/E0510000_N7620000/ranta10_lake_id.tif
```

**The newly consolidated script has been committed, not yet executed
on Roihu in this interaction.** Previously observed results are kept separate
from future script output.

## Remaining genuinely new work (do not repeat completed checks)

1. Establish the underlying reason for unraised STORAGE on the **52
   individual lakes**: geometry/NoData connectivity, algorithm-specific
   pit or outlet detection, or input/version provenance. This requires a
   targeted, distinguishable test; the known D8 return paths alone cannot
   settle the physical or algorithmic reason.
2. Determine the scientific treatment of lakes lacking an observed
   depression component **without manufacturing components**, directing
   runoff through uphill shore edges, or weakening 02D.5's evidence gate.
   Any code change is a separate reviewed proposal.
3. Only then assess whether an independently validated MODERATE rerun
   is warranted and whether downstream stages can be accepted. The
   NATIONAL lock remains in place until scientific review.

Avoid further exploratory command-by-command repetition. Prefer Codex
working with the GitHub branch for code and test changes; for **Roihu-only
scratch data** Codex must have an appropriately authorized execution
environment or receive a small approved diagnostic export. GitHub alone
does not grant direct access to CSC scratch files.
