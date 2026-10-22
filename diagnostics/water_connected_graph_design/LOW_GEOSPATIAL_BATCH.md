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

This is designed to avoid multiple single-question Roihu command rounds. No source object modification, new rasterization, Slurm jobs, DEM/D8/accumulation recalculation, accepted outlets or write outputs. GDAL runs with ogrinfo -ro; Python opens GeoPackage metadata with sqlite3 mode=ro, reads only two bounded CSVs, and prints to terminal. Six local SQLite-dialect GDAL queries use a per-command 18 s timeout; outer execution should be bounded by timeout 120s. Seven independent data stages preserve completed results even if some are STOP, with a final BATCH_STATUS=PARTIAL, nonzero exit. Source files must not be symlinks; source GeoPackage must have 24 lake, 5 river-area and 30 river-line features and EPSG:3067 (STOP on mismatch). The program purposely does not read any original raster.

**Scientific interpretation limits**: A short RANTA10 distance or SYKE point proximity alone cannot establish flow direction or a functioning outlet. Note the 2m rasterization of RANTA10 mask geometry may differ at pixel boundaries; ST_Intersects is a vector geometry check, not a raster-class assertion. A shared 02C receiver used by both lake 1894 and 1892 must be source-direction aware; an interior-review/MIXED receiver must stay unresolved. The 02C neighboring water class and water-level threshold values are algorithmic evidence only, not observed discharge.

**Testing**: python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_low_geospatial_batch.py -v. 13 standalone synthetic methods PASS in local authoring environment, with fake SQLite headers, CSV neighbor mixtures, mocked GIS results, stop/fail cases and deterministic 7-cell centroids. The **real CSC batch is NOT_RUN** until operator executes exact pinned code.

Locks: NATIONAL=LOCKED, MODERATE=REVIEW_REQUIRED, hydrological_validation=NOT_ASSESSED, channel_interpretation=NOT_ASSESSED. No merge, source changes or acceptance of production routing.

Reference documentation: EXISTING_SYKE_AUXILIARY_VALIDATION.md and stacked draft PR #40. This batch is a new isolated diagnostic draft stacked on #40.
