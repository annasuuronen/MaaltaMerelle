# LOW RANTA10 / 02C batched geometry audit (draft)

Read-only diagnostic, **not** validation of any selected lake outlet, D8 correction or downstream-to-sea connection.

Source: existing LOW 01_input_QA.csv, 02C_zero_pointer_cells.csv, 02C_shore_component_classification.csv, 02C_zero_pointer_water_neighbors.csv and the same existing LOW RANTA10_E200000_N6900000.gpkg used in the baseline. Exact 2m raster bounds were independently reported by the user: [199000,211000] x [6899000,6911000], 6000x6000. **The raster itself is not opened.**

The command-line Python program does seven stages in one run (each individually PASS or STOP):
1. Existing 02C component status, target-lake identity, elevation threshold difference, and near-water class/ID evidence for all seven known terminal components.
2. RANTA10 lakes geometry validity, korkeus_m and polygon area for 1892, 1894 and 3181.
3. Exact polygon-to-polygon distance, touches and intersection for lakes 1894 and 1892.
4. All 7 zero-pointer terminal cell center distances and intersections with each of those 3 RANTA10 lake polygons (21 pairs).
5. Distance from each cell center to the nearest RANTA10 river-area polygon.
6. Distance from each cell center to the nearest RANTA10 river-line geometry.
7. Spatial relation of already observed SYKE catchment-outlet point 7025519 (user-reported coordinates rounded to 0.1m) to three RANTA10 lakes.

This is designed to avoid multiple single-question Roihu command rounds. No source object modification, new rasterization, Slurm jobs, DEM/D8/accumulation recalculation, accepted outlets or write outputs. Python opens the GeoPackage in immutable SQLite read-only mode to read bounded original geometry blobs; native GEOS C API (libgeos_c from the loaded GDAL environment) computes metric and topological operations. No SpatiaLite functions or Python GIS packages are required. The existing ogrinfo executable and GDAL runtime are preflight-checked, but spatial SQL is not used. Outer execution should be bounded by timeout 120s. Seven independent data stages preserve completed results even if some are STOP, with a final BATCH_STATUS=PARTIAL, nonzero exit. Source files must not be symlinks; source GeoPackage must have 24 lake, 5 river-area and 30 river-line features and EPSG:3067 (STOP on mismatch). The program purposely does not read any original raster.

**Scientific interpretation limits**: A short RANTA10 distance or SYKE point proximity alone cannot establish flow direction or a functioning outlet. Note the 2m rasterization of RANTA10 mask geometry may differ at pixel boundaries; ST_Intersects is a vector geometry check, not a raster-class assertion. A shared 02C receiver used by both lake 1894 and 1892 must be source-direction aware; an interior-review/MIXED receiver must stay unresolved. The 02C neighboring water class and water-level threshold values are algorithmic evidence only, not observed discharge.

**Testing**: python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_low_geospatial_batch.py -v. The first 13 standalone synthetic methods were exercised locally on the original version; 17 updated methods now include GEOS C ABI metric/topology, a real synthetic in-memory-built GeoPackage spatial read, and fail-closed checks (full updated suite is awaiting CSC execution), with fake SQLite headers, CSV neighbor mixtures, mocked GIS results, stop/fail cases and deterministic 7-cell centroids. **Roihu v1 status (2026-10-22): 02C component/water-neighbor stage PASS; six spatial stages STOP because its SQLite dialect does not expose ST_IsValid, ST_Distance or MakePoint. No evidence of a hydrological mismatch in those STOPs.** The revised native GEOS backend is locally tested with a synthetic immutable GeoPackage (all six geometry functions completed with correct feature counts) but **revised real CSC batch is NOT_RUN** until operator executes updated pinned code. The previous operator checkout is pinned to old SHA and must be deliberately advanced to new SHA; do not reuse the old branch tip silently.

Locks: NATIONAL=LOCKED, MODERATE=REVIEW_REQUIRED, hydrological_validation=NOT_ASSESSED, channel_interpretation=NOT_ASSESSED. No merge, source changes or acceptance of production routing.

Reference documentation: EXISTING_SYKE_AUXILIARY_VALIDATION.md and stacked draft PR #40. This batch is a new isolated diagnostic draft stacked on #40.

## Real operator evidence from the first CSC run (before GEOS remediation)

The CSV-only first stage **PASS** is trustworthy and must not be repeated as a model recomputation. Reported 02C values:

| Component | 02C class | Target lake | Water neighbors | terminal_minus_water_m |
|---|---|---|---|---|
| 108 | SAFE_LAKE_CONNECTOR | 3181 | 1 lake cell / lake3181 | -0.0380 |
| 109 | SAFE_LAKE_CONNECTOR | 3181 | 2 lake cells / lake3181 | -0.0170 |
| 235 | INTERIOR_REVIEW / MIXED | NA | **4 lake cells / 3181 + 1 class-3 river-line-only cell / no lake ID** | -0.0380 |
| 236 | SAFE_LAKE_CONNECTOR | 3181 | 1 lake cell / 3181 | -0.0710 |
| 274 | SAFE_LAKE_CONNECTOR | 1892 | 3 lake cells / 1892 | -0.0330 |
| 276 | SAFE_LAKE_CONNECTOR | 1894 | 3 lake cells / 1894 | -0.0930 |
| 277 | SAFE_LAKE_CONNECTOR | 1894 | 3 lake cells / 1894 | -0.0451 |

Water class semantics explicitly defined by existing R/02_build_baseline_hydrology.R: 1 LAKE, 2 RIVER_AREA, 3 RIVER_LINE_ONLY. For component235, the four lake neighbors plus river-line-only neighbor **explain the MIXED signature**. They do not determine outlet status or receiver precedence. Distinct receiver ends of lake1894→lake1892 use component274, which is classified for lake1892 and cannot be treated as an already accepted flow direction. All six prior GPKG geometry-query errors were missing SQLite spatial functions, **not** data FAILs.


## 2026-10-22 CSC operator run, pinned GEOS version b95060143a5bee558fd3a958c03f2f6a5f4caf3f

**Real run: 17 Python unittest methods OK; RANTA10 metadata 24 lakes, 5 river areas, 30 river lines, EPSG:3067; seven scientific evidence stages PASS, none STOP.** Passed means that the read-only checks completed; it does **not** mean hydrological validation passed. Console has a duplicated START/END wrapper because the operator command and the Python script both print delimiters; no data ambiguity.

RANTA10 lake geometries:
- Lake 1892: vector height 0.37 m, area 758.0 m², GEOS valid=1.
- Lake 1894: vector height 0.44 m, area 3207.8 m², GEOS valid=1.
- Lake 3181: vector height 0.92 m, **area of geometry in the LOW input GeoPackage** 3,366,620.6 m², valid=1; cannot assume this equals full source lake area if the GeoPackage clips tile boundaries.
- Lakes 1894 and 1892: exact polygon separation **38.12 m**; ST_Touches=0, ST_Intersects=0. 1894 vector height exceeds 1892 by 0.07 m, consistent with but **not proof of** hypothetical 1894→1892 drainage. No continuous channel or land-D8 traversing the 38m gap has been proven.

All seven zero-pointer terminal **land-cell centers** lie outside the three target RANTA10 lake polygons (all point intersects=0); key vector distances (meters):

| 02C component | terminal cell | nearest own/target lake and distance | nearest RANTA10 river-area | nearest river-line |
|---|---|---|---|---|
| 108 | 10007129 | 3181: 3.98 | 11.99 | 614.02 |
| 109 | 10031127 | 3181: 2.75 | 20.21 | 616.60 |
| 235 | 15389414 | 3181: 1.52 | 1185.85 | 3.11 |
| 236 | 15401414 | 3181: 3.42 | 1186.45 | 3.41 |
| 274 | 23211319 | 1892: 2.25; 1894: 44.20 | 3223.04 | 21.94 |
| 276 | 23355315 | 1894: 2.11; 1892: 43.39 | 3198.27 | 5.46 |
| 277 | 23373314 | 1894: 1.92; 1892: 49.63 | 3194.28 | 11.52 |

Previous in-window SYKE point 7025519 coordinates rounded to (209277.1,6907673.6) are **inside the RANTA10 lake3181 polygon (intersects=1, distance=0)**. This is a catchment-outlet record located inside the water polygon, NOT validation of a shoreline discharge location. Distances from that point to other two lakes are 5681.09m (1892) / 5755.43m (1894).

**02C component235 nuance:** existing CSV shows four adjacent lake3181 water cells and one class-3 river-line-only water cell; component236 has only one lake neighbor. Their terminal centers are 4m apart and their distances to the same type of vector features are similar. This is real mixed raster water-neighbor evidence; the vector/raster correspondence and whether a hydrological route exists remain untested. No approval of component235.

**Next grouped read-only G3 tests (not yet run):** (a) select local river-line feature identities nearest components235/236 and274/276/277 and measure their nearest approaches to both lake boundaries and feature endpoints; inspect whether any one polyline actually bridges lakes1894 and1892; (b) join original 02C water-neighbor cell-center coordinates to original RANTA10 lake/river-line geometry and classify 1/2/3 per neighbor (vector-vs-raster differences, boundary sensitivity, class precedence) without rewriting masks; (c) use existing 02E/02F 1894→1892 **six** unique? Original 02F count is six origin-1894 routes ending at component274, count routes as distinct traces, not necessarily independently distinct corridors, and compare their enumerated cell chains if already stored; otherwise NOT_ASSESSED; (d) distinguish inherited national catchment point IDs from lake-specific outlets. No new DEM, D8 or accumulation.

**Science state:** computational PASS for this GPKG evidence bundle only; hydrological_validation=NOT_ASSESSED, channel_interpretation=NOT_ASSESSED, MODERATE=REVIEW_REQUIRED, NATIONAL=LOCKED. No commits touching model, hydro inputs, masks or outlets.
