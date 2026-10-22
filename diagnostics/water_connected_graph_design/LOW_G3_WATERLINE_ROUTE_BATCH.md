# LOW G3: original RANTA10 river-line identities, 02C water-neighbor footprint and 02F summaries

This adds an isolated read-only scientific diagnostic stacked on the already completed G2 observational draft PR #41. No DEM, D8, STORAGE, water masks, outlet points or source vector geometry are changed. No outlet or channel approval.

## Starting G2 facts

- Lake1894 RANTA10 level=0.44 m, lake1892 level=0.37 m, original vector polygon gap=38.12 m; this is not an accepted drainage connection.
- Component274 terminal is 2.25 m from lake1892; component276 2.11 m and component277 1.92 m from lake1894; nearest river LINE feature identities were not yet checked.
- Comp235 has four class-1/lake3181 neighbors and one class-3/river-line-only neighbor; comp236 has one class-1 lake neighbor.
- SYKE catchment outlet 7025519 lies within RANTA10 lake3181 geometry, not necessarily at a shoreline outlet.
- Six 02F route summaries start from origin lake1894 and end at component274 land cell23211319; the summaries contain no per-cell path chain.

## Five grouped G3 checks

1. LINE_CONTINUITY. Read original 30 RANTA10 river_lines features with fid and objectid. Report the twelve lines with the smallest total distance to the two lake shore polygons and both endpoint coordinates. Assess same-feature near-both-lakes and undirected line-to-line geometry chain reachability at exploratory tolerance 0,1,2,5,10m. A line/chain is only a geometry observation, NOT hydrological flow.
2. NEAREST_LINES. Report the three nearest original river_lines fid/objectid features to each of the seven land terminal centers, with distances.
3. 02C_WATER_NEIGHBOR_FOOTPRINTS. Read all 18 known component water-neighbor pairs from the existing 02C CSV. Compare actual 2m water cell center AND exactly sized 2m square footprint with its original RANTA10 lake polygon or the nearest river-line-only geometry, including possible overlap with the other type. Raster class 1=LAKE, 2=RIVER_AREA, 3=RIVER_LINE_ONLY is defined in R/02_build_baseline_hydrology.R. Pixel square overlap may differ from original terra rasterization and water-class precedence. Current 18 cases have class1/class3, not class2.
4. SYKE_SHORELINE_DISTANCE. Compute the distance of SYKE point7025519 (coordinates rounded to 0.1m) to the boundary of RANTA10 lake3181, rather than point-to-polygon distance (0 when inside); also compare four component centers with the same boundary.
5. 02F_EXISTING_SIX_ROUTES. Read original 02F_water_connected_route_evidence.csv only. Validate the observed 101 unique records and six origin1894 / terminal cell23211319 / D8_ZERO_INTERIOR records. Display their unique route IDs, starting cells, steps, statuses, and start-cell proximity to lake1894, lake1892 and nearest river-line. This is not a per-cell D8 re-trace: intermediate chain information remains NOT_ASSESSED.

Every step has PASS (the computation completed) or STOP, with a PARTIAL batch outcome if any step stops. Native GEOS C via existing GDAL and immutable read-only SQLite; no Spatialite required. Only the fixed 24 lakes, 5 river areas and 30 river lines in EPSG3067, plus two small existing CSVs, are read. Strict input schemas and expected record counts prevent acceptance of a changed dataset without review.

## Planned operator test

Pin the branch to one exact SHA in a new temporary checkout, not the original PR #41 checkout. Run unittest discover for test_low_g3_batch.py, then one execution of low_g3_batch.py with --gpkg and --baseline pointing at the previously verified existing CSC LOW files. New synthetic methods exercise full five-stage completion with a miniature GPKG, GEOS line endpoints and boundary distance, altered CSV STOP conditions, and line continuity tolerance. At authoring time, actual Roihu G3 test remains NOT_RUN.

## Guardrails

RANTA10 height attributes are not validated hydraulic sill elevations. A line that touches two lakes or a graph path connecting lines within 10m is **not** a D8 route or a validated channel. Six 02F summaries may merge; they must not be treated as six independent pathways. A point inside a water polygon is not a shoreline outlet. The RANTA10 lake polygon can be clipped at the LOW boundary.

Science locks: NATIONAL=LOCKED; MODERATE=REVIEW_REQUIRED; hydrological_validation=NOT_ASSESSED; channel_interpretation=NOT_ASSESSED. No flow accumulation, no accepted outlets and no raster modifications.

## Roihu G3 actual evidence, 2026-10-22

The user ran the existing-source G3 grouped batch. **5/5 G3 stages PASS, 0 STOP**; this is a computational read-only evidence status and does NOT establish a functioning routed lake outlet. Source signature still 24 RANTA10 lakes, 5 river areas, 30 river lines in EPSG:3067.

### 1894 / 1892 original RANTA10 line geometry

- Closest original RANTA10 river line: fid 29, objectid 129081.0, GEOS distance to lake1894 0.00m and to lake1892 22.78m. Endpoints: (205632.7,6903219.0) and (205615.1,6903264.7). The mapped line reaches/touches lake1894, but remains >22m from lake1892.
- Reference vector lake-to-lake polygon gap: 38.12m (G2). Next closest lines are >877m from lake1894.
- Single river-line near both lakes: NONE at exploratory threshold 0/1/2/5/10m; undirected feature-chain geometry link: NONE at those same thresholds. This only describes the 30 available mapped RANTA10 river lines and exploratory thresholds; it does NOT exclude unmapped channels or establish a valid D8 crossing.
- All three comp274,276,277 have the same nearest original line fid29 / objectid129081, with distances 21.94m, 5.46m, 11.52m respectively.

### Lake3181 local classification and SYKE point

- Comp235 and comp236 have the same nearest original river line fid8 / objectid57590, distances 3.11m and 3.41m. Comp108/109 nearest fid1 / objectid57622 at 614.02m / 616.60m.
- All **18** adjacent 02C water-cell footprints (2m squares) intersect their expected RANTA10 water type: 17 class1 LAKE; 1 class3 RIVER_LINE_ONLY. Of class1, exactly 6 cell centers intersect the expected lake polygon; 11 do not, although their cell squares do. The one class3 center is 0.96m from the source vector line and its 2m square intersects it. None of these 18 tested squares intersected an other-type water feature in the restricted G3 comparison. This is consistent with boundary-pixel rasterization and DOES NOT prove terra raster precedence or reveal a hydrological outlet.
- Water neighbor cell 15395415 is shared by components235 and236, so they do not represent independent lake-neighbor contacts.
- SYKE catchment outlet point 7025519 (source XY rounded 0.1m) intersects RANTA10 lake3181 polygon; its computed shortest distance to vector polygon boundary is **0.04m**: shoreline-coincident at reported coordinate precision, NOT confirmed lake-specific outlet.

### Six preexisting 02F summaries: lake1894 to component274

All six are distinct route summary entries of origin lake1894, terminal cell23211319, status D8_ZERO_INTERIOR, with terminal_lake_id NA, not actual REACHES_OTHER_LAKE statuses.

| route_id | start_receiver_cell | route_steps | distance start to lake1894 m | distance start to lake1892 m |
|---|---|---|---|---|
| 11 | 23337318 | 21 | 3.01 | 35.33 |
| 14 | 23343318 | 22 | 1.52 | 37.15 |
| 15 | 23343319 | 22 | 2.86 | 36.39 |
| 16 | 23343320 | 23 | 4.19 | 35.74 |
| 18 | 23349320 | 23 | 2.70 | 37.65 |
| 20 | 23355321 | 24 | 2.55 | 39.06 |

These are six unique start/route records, NOT six independent channels. The stored 02F CSV does not contain each intermediate path cell; do not infer uninterrupted flow through the whole gap or a receiving lake from terminal-cell vicinity.

### Scientific status after real G3

- Geometric evidence shows a mapped river-line from lake1894 toward the vicinity of lake1892 but no mapped feature/feature chain reaching both shorelines within 10m of each. A possible lake1894->lake1892 downstream relationship remains open and unapproved.
- Comp235 MIXED arises from **four lake3181 raster neighbors and one distinct river-line-only neighbor**, not a demonstrated vector/raster error. Do not recode or treat it as functioning outlet.
- SYKE point7025519 may align with lake3181 shore and catchment hierarchy, but is not proven to be a true lake discharge point.
- Next optional G4 is a **bounded read-only audit of existing D8-pointer cells for these six route summaries** (ideally small source window or sparse sample in a compute allocation), comparing all traversed cells to original 02F starts, steps and D8_ZERO terminal. No DEM, D8, STORAGE, lake masks, point edits or flow accumulation.
- NATIONAL=LOCKED, MODERATE=REVIEW_REQUIRED, hydrological_validation=NOT_ASSESSED, channel_interpretation=NOT_ASSESSED. All PRs remain draft.

### New constrained D8 geometry deduction from original 02F summaries (no new raster read)

With the validated 6000-column LOW grid and original route start/end cell IDs, all six routes end exactly 21–24 raster **rows north** of their starts and only 0–2 columns east/west. Critically, the existing 02F route_steps values match the number of rows advanced north for every one of these routes:

| 02F route | northward row difference | eastward column difference | reported pointer steps |
|---|---:|---:|---:|
| 11 | 21 | +1 | 21 |
| 14 | 22 | +1 | 22 |
| 15 | 22 | 0 | 22 |
| 16 | 22 | -1 | 23 |
| 18 | 23 | -1 | 23 |
| 20 | 24 | -2 | 24 |

**Correction to the previous statement:** route16 moves 22 rows north but uses 23 D8 steps; one move could be sideways without moving north. For the other five routes whose northward row count equals the reported step count, every D8 step must be one of N/NW/NE according to the documented Whitebox direction convention; there can still be east-west zigzags. For route16, the path must include exactly one non-northward-row step if no opposite-row moves; it could also include a southward step if permitted by step constraint, which would require at least one compensating northward step exceeding the total available and thus is impossible when 22/23 (max possible row displacement 23); therefore exactly one step with zero row displacement. Confirm directly from pointer samples rather than claiming an actual continuous stream.

This is a combinatorial consequence of the **already recorded** 02F starts, terminals and 02F route-step semantics. It does not prove hydraulic connection, monotone elevation, culvert continuity or waterbody reception. Planned small-window G4 D8 read is still NOT_RUN.
