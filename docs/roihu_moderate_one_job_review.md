# Roihu: one-job, read-only MODERATE scientific review

**Status:** implementation committed on `codex/moderate-02d4-diagnosis`;
**not yet executed on CSC Roihu**. This is **not** a production or national
workflow acceptance. No full-area Whitebox filling, new D8 routing, pointer
edits, modified study data, or national job submission.

## Why this replaces manual commands

The prior interactive checks were already run and documented in
[`moderate_02d4_followup_20261016.md`](moderate_02d4_followup_20261016.md).
Do **not** repeat them merely to gather the same numbers again.

One submitted Slurm job invokes two read-only analyses:

1. `scripts/audit_moderate_spill_d8_readonly.R`: lake mismatch totals,
   shortest nominated shore receiver traces in existing D8 (cap 100),
   component precondition, and terminal classification.
2. `scripts/audit_moderate_lake_geometry_readonly.R`: new independent
   lake-ID cell coverage, domain-edge contacts, NA/NoData adjacent shoreline,
   variable lake source elevations, source WATER_STORAGE elevations.

These checks cannot by themselves prove Whitebox's mechanism or identify a
natural outlet. The analyses are **observational**, not repairs.

## Preconditions

The job will refuse to execute unless the configured checkout is on a **clean**
`codex/moderate-02d4-diagnosis` branch, contains the two scripts, and the
original MODERATE files exist. It does not pull or update the checkout.

The default `HYDRO_CODE_ROOT` is
`/projappl/project_2004707/MaaltaMerelle`; this directory was previously
observed on a separate production commit and therefore **must not be assumed
to contain this diagnostic branch**. Use a separate clean code checkout at a
user-approved path (or ask an operator to set it up); do not replace or force
reset production.

The job uses the already observed CSC environment `r-env/461` and
`/projappl/project_2004707/project_rpackages_461`, with single-thread
BLAS/Whitebox environment settings. Exact package/module availability must
be confirmed in its output, not assumed here.

Once a clean diagnostic-branch checkout exists, a single scheduled command is:

```bash
HYDRO_CODE_ROOT=/path/to/clean/MaaltaMerelle sbatch --export=ALL,HYDRO_CODE_ROOT=/path/to/clean/MaaltaMerelle /path/to/clean/MaaltaMerelle/scripts/roihu_moderate_validation.sbatch
```

Run **only with an authorized Roihu session**. This example does not
start anything until a person submits it. The direct stdout of `sbatch`
gives the Slurm job ID. No automatic repeated submissions are configured.

The job creates a new (never overwritten)
`/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/moderate_scientific_review/job_<SlurmID>/`
directory with:

- `provenance.txt` – UTC timestamp, source commit, tree state, R / terra,
  full input paths and SHA256s;
- `spill_d8.log` – existing candidate routing interpretation;
- `lake_geometry.log` – targeted independent NoData and shoreline counts;
- `steps.txt` – individual exit statuses;
- `summary.txt` – concise scientific review summary.

Log files are written only to this new review directory; original inputs and
pipeline rasters remain untouched. A failed diagnostic ends the batch with
a nonzero exit. A zero exit means only the observations completed, **not
that the hydrology passed scientifically**.

## Scientific decision gates

- **MODERATE:** keep `REVIEW_REQUIRED` until no-data and geometry observations
  have been assessed alongside Whitebox behavior and 02D.5 logic.
- **LOW:** diagnostic `RESOLVED` is not sufficient for accepting an outlet.
- **NATIONAL:** `LOCKED`, and this script does not contain a national run.

A subsequent, separately reviewed proposal may address physical outlet
representation and/or classification semantics. Do not make a generated
depression component, force uphill receiver paths, or weaken acceptance
checks simply to let 02D.5 run.

This review script is a **necessary next empirical discriminator**, not the
final nationally validated implementation.
