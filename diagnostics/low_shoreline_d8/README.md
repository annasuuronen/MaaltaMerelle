# LOW 02F — only-read shoreline D8 terminal QA

This is a **bounded and independent** diagnostic, not an outlet selection or a hydrology rerun. It relates to [LOW 02F issue #10](https://github.com/annasuuronen/MaaltaMerelle/issues/10). It deliberately does not edit or re-source the original hydrology implementation, nor does it substitute `WATER_STORAGE` pointers for `LAND_WATER` pointers.

## Evidence classes

| Column | Strict definition |
| --- | --- |
| `LAKE_D8_TO_INTERIOR_ZERO` | An adjacent RANTA10 lake cell's **actual Whitebox D8** points into a non-water interior center cell with D8=0. |
| `MASKED_SHORE_FILL_UNCHANGED` | All adjacent RANTA10 lake cells are NoData on **both** `LAND_RAW` and `LAND_FILL`, and the center has unchanged DEM→RAW→FILL elevation within `1e-7 m`. This does **not** prove Whitebox's internal NoData processing. |
| `FLAT_CONTINUATION_REVIEW` | A non-water neighbor is at the same `LAND_WATER` height within tolerance and that neighbor's **existing** D8 points to a lower `LAND_WATER` cell in the 5×5 window. Does not establish that center→neighbor is a scientifically valid outlet. |

The output status is **`REVIEW_REQUIRED`** when at least one flag is present. No status indicates scientific acceptance or a proposed edit. Any geometry mismatch, unexpected zero terminal, stale route evidence or truncated 5×5 window stops the real-data runner. The standalone base-R detector is side-effect free. Both scripts only read data and print to stdout.

## Run on CSC Roihu (no Slurm; small 5×5 reads only)

From anywhere, after extracting the package as `low_shoreline_qa_20261016` in `$HOME`:

```bash
module load r-env/461
D="$HOME/low_shoreline_qa_20261016/diagnostics/low_shoreline_d8"
Rscript --vanilla "$D/test_synthetic.R"
Rscript --vanilla "$D/run_roihu_low.R" /scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000/02_baseline /scratch/project_2004707/pienvedet/csc_validation_4bbf22b/inputs/E200000_N6900000
```

Paste the real-data Rscript command as **one physical shell line**. A terminal paste that introduces a blank line after a `\\` may otherwise run each directory as a separate shell command.\n\nThe real-data script intentionally requires the known LOW **101 routes**, **41 D8_ZERO_INTERIOR** routes, and **7 exact terminal cells** so a later changed run is not silently mistaken for the validated observation. Its expected 10 incoming lake pointers and 1 flat-continuation case are also checked. A mismatch requests review, not data correction.

No data is uploaded to GitHub. No sources are written. A separate independent spring dataset validation (including **nonzero D8**) is tracked in [issue #9](https://github.com/annasuuronen/MaaltaMerelle/issues/9); it is **not** introduced into the model here. MODERATE remains `REVIEW_REQUIRED`; NATIONAL remains `LOCKED`.
