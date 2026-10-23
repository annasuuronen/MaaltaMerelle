# S2C.1 — isolated GDAL PROJ database lookup correction

**Scope:** diagnostics-only forward fix on original S2C draft PR #52 (`7324f2c22b3151fffe7b172617bde4d0ef6ee821`), issue #64. No modification to hydrology, data or outputs. Source changes and synthetic test additions are **not yet executed on Roihu or independently re-run** in this PR review.

## Evidence from Roihu 2026-10-23

The operator executed the unchanged S2C metadata-only CLI with Python-geo 3.14.5 and GDAL 3.12.2: original five small CSV files, manifest, QA, 02C/02F identities and GDAL version passed. Old 02F CSV SHA256 matched the recorded version. Raster metadata failed due to `GDALINFO_EXIT_OR_WARNING`. Original S2C's `InfoOnly.command` runs `gdalinfo` with a deliberately stripped child environment that excludes `PROJ_DATA` / `PROJ_LIB`.

Operator reproduced the pointer's first GDAL call using that stripped environment:
- exit 0, 3159 stdout bytes, warnings that PROJ could not open its search path and GeoTIFF CRS EPSG:3067 differed from the EPSG registry.
- Same metadata-only `gdalinfo` call with an existing `proj.db` directory explicitly set through `PROJ_DATA`: exit 0, 9183 stdout bytes and **no stderr**. Thus at least the two previously observed warnings were environmentally induced in this comparison.

**No conclusion yet about all three raster metadata contracts**: the full original S2C still has `metadata_status=STOP`; the source-chain STOP is independent of metadata correctness.

## Narrow change

The standard-library function `find_proj_data(executable)` checks at most four already known directories, in order:
1. `PROJ_DATA` if it is an absolute directory containing `proj.db`;
2. legacy `PROJ_LIB` with the same check;
3. active `sys.prefix/share/proj`;
4. resolved GDAL executable's installation prefix `share/proj`.

The first candidate with a present regular `proj.db` is resolved and passed as the **only** additional `PROJ_DATA` field to the isolated `gdalinfo` subprocess. No arbitrary environment variables are copied. When no database is found, the existing strict child environment and stderr-to-STOP condition are unchanged; absence of a database never becomes a pass.

No `GTIFF_SRS_SOURCE` override, no warning suppression, no extra `gdalinfo` flags, no GDAL stats/checksums, no raster pixel access, no network (`PROJ_NETWORK=OFF`), no GDAL PAM writes. The absolute original three raster paths and native 01/02C/02F CSV checks are unchanged.

Five new named standard-library tests are added to the **existing** S2C test suite: explicit valid PROJ_DATA, PROJ_LIB fallback, missing DB fail-safe, subprocess environment allowlist, and warnings still STOP even with selected PROJ_DATA. Earlier S2C and other regression tests should be re-executed in a suitable environment; their past PASS results are not new S2C.1 evidence.

## Operator validation is future-only

Use a separately prepared, pinned checkout/archive of this **new** S2C.1 commit and Python-geo, never overwrite or mutate original S2C's pinned files. Confirm GDAL3.12.2, Python>=3.10 and single `proj.db` availability. First test pure Python regressions, then separately approved and bounded original LOW metadata-only CLI. The latter must always exit **2** by design. Record stage-level `metadata_status` independently of process exit.

Passing `RASTER_METADATA`, if obtained, verifies only the current metadata contract; it does not show the producer or exact `ptr_land_water` state consumed by historical 02F. `RUNTIME_INPUT_LINEAGE=NOT_ASSESSED`, `SOURCE_AUTHENTICATION=NOT_ASSESSED`, `TRUE_02F_CONTINUITY=NOT_RUN`, `raster_pixel_reads=0`.

**Science locks:** `NATIONAL=LOCKED`; `MODERATE=REVIEW_REQUIRED`; `hydrological_validation=NOT_ASSESSED`; `channel_interpretation=NOT_ASSESSED`; `routing_authorized=false`; `outlet_selection=UNASSIGNED`. Draft only, do not merge.
