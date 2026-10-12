# MaaltaMerelle hydrology pipeline — baseline without structures

This branch is the baseline-only production path for lake, river, outlet and
flow-routing development. Human-made hydraulic structures such as dams, locks,
gates, hydropower channels, pumps, canals and tunnels are intentionally out of
scope for this version and can be added later as a separate extension.

The scripts run with R on Windows or Linux. Install `terra`, `sf` and
`whitebox`; Whitebox operations also need the WhiteboxTools executable.

## Scope

The planned sequence is:

1. prepare DEM and RANTA10 inputs;
2. resolve lake spill, outlet and escape evidence;
3. preserve WATER_CONNECTED spill candidates and QA without selecting outlets;
4. build final baseline D8;
5. calculate baseline flow accumulation and the 4 ha stream network;
6. build tile handoffs / hydrologic graph;
7. run QA and golden regression;
8. produce the baseline output contract;
9. proceed to CSC and national baseline runs after validation.

The current implementation reaches 02D.8 spill/escape evidence and 02E
candidate QA. 02E includes every spill group with external evidence and no
review flag as a parallel candidate, preserves all of its lowest-spill shore
edges, and leaves `outlet_selection` as `UNASSIGNED`. It writes source- and
receiver-cell masks for those edges and verifies that they match the
evidence (no masks are emitted when there are no eligible edges). These masks
stop at the lake shore spill edge: they do not prove a downstream route,
modify DEM elevations, alter D8 pointers, or constitute a routing surface.
Any `REVIEW_REQUIRED` group is excluded from the masks; a final
WATER_CONNECTED routing surface remains unimplemented until downstream paths
are validated and review cases are resolved.

WhiteboxTools `FillDepressions` runs with one worker to avoid its intermittent
parallel output-handle panic. If it fails to create a non-empty output, the
pipeline retries once and then stops with an explicit error.

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
Rscript tests/water_connected_candidates.R
Rscript tests/whitebox_fill_retry.R
```

The LOW transfer workflow also locks the 02D.7K component 396 case: its
`LAKE:1892` gate and `RIVER_LINE` flat-trace evidence are kept distinct, while
the separately traced lower escape remains one `EXTERNAL_CANDIDATE`.

The GitHub Actions workflows validate spill/escape evidence and the
outlet-independent 02E candidate contract. They do not yet test final routing.
Structures are deliberately deferred to a later version.
