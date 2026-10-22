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
