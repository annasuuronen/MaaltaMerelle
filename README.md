# MaaltaMerelle hydrology pipeline

The scripts run with R on Windows or Linux. Install `terra`, `sf` and
`whitebox`; future Whitebox operations also need the separate WhiteboxTools
executable. In the prepared Codex Cloud shell, first run
`source /workspace/hydro-env/activate.sh`.

## Paths and modes

The repository root is inferred from the script's location when using
`Rscript` or `source()`, independently of the working directory. Set
`HYDRO_PROJECT_ROOT` to override it (a relative override is relative to the
calling working directory). Other relative path overrides are resolved against
that repository root. Absolute paths, including Windows drive and UNC paths,
are supported on their native operating system. Windows drive paths are not
Linux mounts.

`HYDRO_MODE` defaults to `LOCAL_TEST`. Configuration overrides:

| Environment variable | Default |
| --- | --- |
| `HYDRO_PIPELINE_ROOT` | Repository root in LOCAL_TEST; CSC pipeline directory in CSC_TEST |
| `HYDRO_SOURCE_TEST_ROOT` | `data/hydro_test/TEST_SULKU_11` in LOCAL_TEST |
| `HYDRO_STRUCTURES_ROOT` | `data/hydrology_structures` in LOCAL_TEST |
| `HYDRO_RUN_ROOT` | `<pipeline root>/runs/TEST_SULKU_11` |
| `HYDRO_CSC_ROOT` | `/scratch/project_2004707/pienvedet` (CSC_TEST only) |

CSC_TEST retains its existing layout: `<CSC root>/hydrology_pipeline_v2`,
`<CSC root>/hydro_test/TEST_SULKU_11`, and `<CSC root>/hydrology_structures`.
LOCAL_TEST expects the structures GeoPackage under `processed/`; CSC_TEST
expects it directly under the structures root. Each root can be overridden.
`NATIONAL` remains unconditionally locked: validation of LOCAL_TEST and CSC_TEST
and a separate reviewed change are required before enabling it. Setting the
mode does not certify validation.

## LOCAL_TEST

Supply these real input files (they are not included in the repository):

```text
data/hydro_test/TEST_SULKU_11/
  dem_12km_rumpukorjattu.tif
  RANTA10_TEST_SULKU_11.gpkg
  ranta10_lake_id.tif
  ranta10_river_area_mask.tif
  ranta10_river_line_mask.tif
  ranta10_water_class.tif
  ranta10_water_mask.tif
data/hydrology_structures/processed/
  HYDRO_STRUCTURES_LOCAL_TEST_SULKU_11_12km.gpkg
```

Run from the repository root:

```sh
Rscript R/01_prepare_hydrology_inputs.R
Rscript R/02_build_baseline_hydrology.R
```

Or use `source("R/01_prepare_hydrology_inputs.R")` from an R session at the
repository root. Absolute script paths work from other directories.
For existing external data directories, set overrides before sourcing/running
(the following R example works on both platforms; use your actual paths):

```r
Sys.setenv(HYDRO_MODE = "LOCAL_TEST",
           HYDRO_SOURCE_TEST_ROOT = "../hydro_test/TEST_SULKU_11",
           HYDRO_STRUCTURES_ROOT = "../hydrology_structures")
source("R/01_prepare_hydrology_inputs.R")
```

`00` configures paths, creates run directories and enforces safety.
`01` validates inputs and prepares the canonical lake elevation raster,
input manifest and QA report in `runs/TEST_SULKU_11/01_inputs`.
`02` is an incomplete baseline development script: the checked-in version
loads inputs, checks matching geometry and ends at the OUTPUTS heading.
It does not yet perform the calculations described in its header.
No final outlet selection, final D8 routing or flow accumulation is implemented.

EPSG:3067, 2 m cells, the 4 ha threshold, Whitebox pointer scheme, test extent
and all TEST_SULKU_11 regression expectations are unchanged. `OVERWRITE` remains
FALSE. Keep large inputs and generated run outputs out of version control.

## Checks without external data

From the repository root, run `Rscript tests/portability.R`. These base-R checks
exercise script parsing, path overrides, mode handling, output directories,
configuration invariants and the NATIONAL lock using a temporary project.
They do not validate hydrological outputs. Input geometry, feature counts,
lake elevations, raster IDs, canonical raster preparation and baseline input
checks require the real test data. Native Windows execution must also be
verified on a Windows machine.
