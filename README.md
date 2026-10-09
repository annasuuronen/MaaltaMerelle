# MaaltaMerelle hydrology pipeline — baseline without structures

This branch is the baseline-only production path for lake, river, outlet and
flow-routing development. Human-made hydraulic structures such as dams, locks,
gates, hydropower channels, pumps, canals and tunnels are intentionally out of
scope for this version and can be added later as a separate extension.

The scripts run with R on Windows or Linux. Install `terra`, `sf` and
`whitebox`; Whitebox operations also need the WhiteboxTools executable.

## Scope

The active sequence is:

1. prepare DEM and RANTA10 inputs;
2. resolve lake spill, outlet and escape evidence;
3. build the WATER_CONNECTED baseline surface;
4. build final baseline D8;
5. calculate baseline flow accumulation and the 4 ha stream network;
6. build tile handoffs / hydrologic graph;
7. run QA and golden regression;
8. produce the baseline output contract;
9. proceed to CSC and national baseline runs after validation.

No dam, lock or other structure input is required or tested in this branch.
There is no structure-based routing override in this version.

## Paths and modes

The repository root is inferred from the script location when using `Rscript`
or `source()`. Set `HYDRO_PROJECT_ROOT` to override it. Other relative path
overrides are resolved against that repository root.

`HYDRO_MODE` defaults to `LOCAL_TEST`.

| Environment variable | Default |
| --- | --- |
| `HYDRO_PIPELINE_ROOT` | Repository root in LOCAL_TEST; CSC pipeline directory in CSC_TEST |
| `HYDRO_SOURCE_TEST_ROOT` | `data/TEST_SULKU_11` in LOCAL_TEST |
| `HYDRO_RUN_ROOT` | `<pipeline root>/runs/TEST_SULKU_11` |
| `HYDRO_CSC_ROOT` | `/scratch/project_2004707/pienvedet` in CSC_TEST |

`NATIONAL` remains locked until the baseline LOCAL_TEST and CSC_TEST have
passed and enabling the national mode is reviewed separately.

## LOCAL_TEST inputs

Supply these real inputs:

```text
data/TEST_SULKU_11/
  dem_12km_rumpukorjattu.tif
  RANTA10_TEST_SULKU_11.gpkg
  ranta10_lake_id.tif
  ranta10_river_area_mask.tif
  ranta10_river_line_mask.tif
  ranta10_water_class.tif
  ranta10_water_mask.tif
```

No `HYDRO_STRUCTURES_*.gpkg` file is part of the baseline input contract.

Run from the repository root:

```sh
Rscript R/01_prepare_hydrology_inputs.R
Rscript R/02_build_baseline_hydrology.R
```

For an external input directory:

```r
Sys.setenv(
  HYDRO_MODE = "LOCAL_TEST",
  HYDRO_SOURCE_TEST_ROOT = "../hydro_test/TEST_SULKU_11"
)
source("R/01_prepare_hydrology_inputs.R")
```

## Safety and QA

EPSG:3067, 2 m cells, the 4 ha threshold, Whitebox pointer scheme and current
TEST_SULKU_11 baseline regression expectations are preserved. Large inputs and
generated run outputs stay out of version control.

Run portability checks with:

```sh
Rscript tests/portability.R
```

The GitHub Actions workflow tests only the baseline lake/outlet/routing path in
this branch. Structures are deliberately deferred to a later version.
