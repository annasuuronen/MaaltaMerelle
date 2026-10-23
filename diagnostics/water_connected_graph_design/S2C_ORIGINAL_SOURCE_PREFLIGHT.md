# S2C — original LOW source lineage and metadata preflight

Issue #51; parent S2B PR #50 at
`b461b4cd85ce8c4e5f94de320830c136c450265a`. This adds only the standalone
preflight, its tests and this report. No existing modules, R scripts, tests,
workflows or data are changed. S2B's synthetic-only restriction remains intact.

**Implementation/test scope: synthetic only.** Codex has not connected to CSC,
opened an original CSC file, read a raster pixel, run R or executed the operator
command below. The only actual GIS operation tested here is `gdalinfo` against
temporary synthetic GeoTIFFs. No S2A replay, new accumulation or routing change
is part of this preflight.

`NATIONAL=LOCKED`, `MODERATE=REVIEW_REQUIRED`,
`hydrological_validation=NOT_ASSESSED`,
`channel_interpretation=NOT_ASSESSED`, `routing_authorized=false`,
`outlet_selection=UNASSIGNED` are immutable report fields.

## Producer-to-consumer findings from canonical R source

The following four R files were read at the pinned parent. Their contents are
also unchanged from historical Git commit
`4bbf22bb39181c8a4c27ebc3e2769766043115b8`. A directory containing `4bbf22b` is
**not** evidence that its output files were produced by that commit.

| Source | Code-proven relationship | Not established by that source |
|---|---|---|
| `R/00_pipeline_config.R` | `SOURCE_TEST_ROOT` comes from `HYDRO_SOURCE_TEST_ROOT` or its mode-specific default; `RUN_ROOT` has a separate override; `DIR_02=RUN_ROOT/02_baseline`; pointer convention is Whitebox | Actual historical environment overrides or the producer of files currently at those locations |
| `R/01_prepare_hydrology_inputs.R` | Writes `01_input_manifest.csv` and `01_input_QA.csv`; manifest records exact source `lake_id_raster` and `water_class_raster` paths | No producer Git SHA, D8 output path/hash, completed 02F runtime identity or authenticated input ledger |
| `R/02_build_baseline_hydrology.R` | 02B builds D8 from `routing_surface_land_water_FLT8S.tif`, `esri_pntr=FALSE`, then writes `DIR_02/d8_pointer_land_water_FLT8S.tif` as FLT8S; reads the two RANTA10 rasters directly from `SOURCE_TEST_ROOT` | Its existence guard can reuse a pre-existing pointer when `OVERWRITE=FALSE`; current file presence/mtime cannot establish that it was the pointer used by a completed 02F run |
| `R/02F_water_connected_route_diagnostics.R` and its caller | 02F receives the same in-memory `ptr_land_water`, `water_class`, `lake_id` objects and writes `02F_water_connected_route_evidence.csv` with eight native columns | The resulting CSV contains route summaries, not the input filenames, input hashes or intermediate cells |

01's lake-elevation file is a separate derived input. No elevation TIFF, DEM,
STORAGE or vector file is opened here. Config is **not executed**: doing so would
create run directories and could select different environment defaults.

The current R config constructs its DEM path under `SOURCE_TEST_ROOT`, but this
preflight does **not** infer the source root from a DEM path or assume that the
historical run followed that default. It resolves only the two actual manifest
entries and checks their shared parent and code-defined basenames. Different
DEM and RANTA10 directories are deliberately supported and tested.

## Exact later operator scope and discovery policy

The production CLI has no root, tile, output path, arbitrary file or GDAL-flag
override. It is restricted to this run:

```text
/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000
```

Only these five small native CSVs are read and hashed completely:

| Relative file | Purpose |
|---|---|
| `01_inputs/01_input_manifest.csv` | Actual source-path claims and native pipeline configuration |
| `01_inputs/01_input_QA.csv` | Grid dimensions, resolution and extent |
| `02_baseline/02F_water_connected_route_evidence.csv` | Complete source version and six selected original summaries |
| `02_baseline/02C_zero_pointer_water_neighbors.csv` | Component274's three neighbor records |
| `02_baseline/02C_zero_pointer_cells.csv` | Terminal23211319's component, coordinates and interior-edge flag |

The three metadata candidates are:

1. The **code-derived candidate** `RUN_ROOT/02_baseline/d8_pointer_land_water_FLT8S.tif`.
2. The exact `water_class_raster` path from the actual manifest.
3. The exact `lake_id_raster` path from the actual manifest.

The pointer name is derived from reviewed producer/consumer code, not invented
from draft designs. It is explicitly reported as a candidate, **not** an
independently established original 02F runtime input. If missing, STOP; no other
filename, temporary pointer, 02G/final raster, archive or other tile is searched.

Manifest raster paths must remain under
`/scratch/project_2004707/pienvedet`, share a parent, have the reviewed RANTA10
basenames, and contain no explicit different E/N tile component. The declared
LOW identity and exact metadata geometry must then agree. Unlabeled source
folders can be inspected through explicit manifest bindings; no DEM-relative
fallback, wildcard, directory enumeration or recursive scan exists.

All opened files must be nonempty regular files, without symlinks in any ancestor
or hardlink aliases. Small reads use read-only/no-follow descriptors, verify
identity before/after reading and are limited to **2 MiB per file**, 20000 CSV
rows and bounded fields/headers. The five original files are not copied.
Raster files are **never opened by Python or hashed**; only stat metadata and
`gdalinfo` headers are used. Device/inode, byte size and modification/change
times are retained and checked around inspection; they are version observations,
not content authentication. Kernel access-time updates are not claimed to be
prevented by ordinary read-only access.

A programmatic `Request(project=..., kind="SYNTHETIC")` exists only for explicit
private temporary fixtures named `mm-s2c-synthetic-*`. The production CLI cannot
select it or enable S2B real-data mode.

## Native schema and identity checks

Only the reviewed native schema is supported. UTF-8 BOM handling is explicit;
renamed columns, different column order, extra/duplicate fields, extra manifest
keys or undocumented schema versions STOP with observed fieldnames/key names.
No aliases are guessed and no CSV is repaired or rewritten. Observed headers
and file hashes are retained in the report, subject to the output size guard.
An oversized header yields a resource STOP rather than an unbounded header dump.

- Manifest: `key,value`, exactly the 14 keys emitted by 01. LOW test identity,
  pipeline version, allowed non-NATIONAL mode, `pointer_scheme=whitebox` and 2 m
  cell size must agree. A new `producer_commit` key is preserved as a reported
  claim but STOPs the unsupported schema; it cannot authenticate a run by itself.
- Input QA: `item,value`, the 14 reviewed items. The grid must be 6000×6000,
  resolution2 m, E199000–211000 / N6899000–6911000.
- 02F: `route_id,start_receiver_cell,origin_lake_objectid,terminal_cell,terminal_water_class,terminal_lake_objectid,route_steps,route_status`.
  Duplicate IDs are rejected across the complete file. IDs11/14/15/16/18/20 must
  preserve starts23337318/23343318/23343319/23343320/23349320/23355321,
  steps21/22/22/23/23/24, origin1894, terminal23211319,
  `D8_ZERO_INTERIOR`, and missing terminal water class/lake ID.
- 02C neighbors: `component_id,source_cell,water_cell,water_class,lake_objectid,water_z_m`.
  Component274 must supply exactly three distinct adjacent water cells from
  source23211319, class1/lake1892, with finite reported elevations. Their actual
  IDs are obtained from the CSV; no neighbor positions are hardcoded.
- 02C zero cells: `cell,component_id,x,y,z_m,raster_edge`.
  Terminal23211319 must be component274, center(205637,6903263), interior
  (`raster_edge=FALSE`) and have a finite reported elevation. This compares
  existing report observations only; it does not sample an elevation raster.

The complete small-file hashes are always printed for files successfully read.
The actual 02F SHA is compared with historical
`402fdbf16cb41eaa6a3ad2180cc4d3af8534e32cff299d73eacec8dc5c187db5` as a
**reported match/difference**, not a presumed current version. An optional
`--expect-02f-sha256 HASH` adds a strict operator-specified pin: a changed file
STOPs before GDAL. A matching operator/historical digest still never authenticates
origin. No full-file TIFF hashing is attempted on a login node.

## Metadata-only GDAL contract

Only GDAL **3.12.2** `gdalinfo` may execute. The entire allowed command surface is:

```text
gdalinfo --version
gdalinfo -json -nomd -noct -norat -nogcp -if GTiff EXACT_ALLOWLISTED_TIFF
```

There are at most four calls: one version and three distinct candidate headers.
`-stats`, `-approx_stats`, `-mm`, `-hist`, `-checksum`, `-srcwin`, alternative
paths/tools and all value-extraction commands are rejected before spawning.
There is no subprocess shell, network API, R execution, Slurm client or raster
array library. The future `3293 3844 52 73` window is a report reference only;
it is never sent to GDAL in S2C.

Each source must be single-band GTiff, 6000×6000, affine
`[199000,2,0,6911000,0,-2]`, with exact corners, center and normal x/y mapping.
Both the WKT EPSG3067 identifier and structured PROJJSON are checked: projected
CRS3067, method9807, origin latitude0/longitude27, scale0.9996, false easting500000,
false northing0, metre east/north axes and GRS80 ellipsoid. The known EPSG4258
ETRS89 and EPSG10690 EUREF-FIN base identities are explicitly supported; the
pinned GDAL image uses the latter. A 3067 label with altered projection parameters
is rejected. Missing structured CRS evidence STOPs rather than being inferred.

The pointer must be Float64, as actually written by 02B. Water-class/lake-ID bands
must have a supported real numeric dtype. Scale/offset changes, additional masks,
overviews, complex types or missing/ambiguous NoData STOP. Typed finite NoData
must fit an integer band's range; NaN requires a floating band. Pointer NoData=0,
water-class NoData1/2/3 and positive lake-ID NoData are rejected. No conclusions
about actual pixel validity, integer lake-ID values, mask membership or D8 codes
follow from metadata alone; those value checks remain NOT_RUN.

`subprocess.run` receives fixed argument tuples with `shell=False`, no stdin,
10-second call timeouts and a 40-second metadata command budget. Concurrent
pipe readers cap stdout at 1 MiB and stderr at 32 KiB **while collecting**.
Warnings, nonzero exit, output overflow or timeout STOP without retry/fallback.
The CLI additionally installs a 60-second POSIX alarm for the whole preflight
and restores the previous handler. Uninterruptible filesystem/kernel stalls
remain an operating-system limitation, not a timing guarantee established here.

The child environment disables PAM writes, sibling discovery, dynamic GDAL
plugins and PROJ networking; cache32 MiB and one GDAL thread. The script writes
only its final stdout report. It never writes an output file, source sidecar,
source data copy or cache in the run tree.

## Report, unresolved lineage and operator behavior

`preflight()` returns frozen metadata records. `framed()` produces one compact
JSON record between exactly one pair of delimiter lines:

```text
=== TULOKSET ALKAVAT ===
{...}
=== TULOKSET LOPPUVAT ===
```

Untrusted marker text is escaped in JSON, without changing decoded field values.
The JSON size cap is64 KiB; amplified input reports collapse to an explicit
locked `COMPACT_REPORT_SIZE_LIMIT_DETAILS_OMITTED` STOP instead of partial output.

Stages: `PATH_SCOPE`, `SMALL_FILE_VERSIONS`, `MANIFEST_SCHEMA`, `INPUT_QA`,
`CSV_IDENTITIES`, `GDAL_VERSION`, `RASTER_METADATA`, `RUNTIME_INPUT_LINEAGE`, each
PASS/STOP/NOT_RUN. Exact source paths, file versions, actual small-file hashes,
selected CSV identities, raster dimensions/bands/dtype/NoData/CRS/affine and
center coordinates are reported. No source pixel values or full CSV copy is emitted.

Even complete metadata yields:

```text
metadata_status=PASS
overall_status=STOP
RUNTIME_INPUT_LINEAGE=NOT_ASSESSED
RUNTIME_PRODUCER_COMMIT=UNKNOWN
SOURCE_AUTHENTICATION=NOT_ASSESSED
stop_reason=RUNTIME_PRODUCER_LINK_UNVERIFIED_NO_PIXEL_PERMISSION
raster_pixel_reads=0
S2A_REPLAY=NOT_RUN
TRUE_02F_CONTINUITY=NOT_RUN
```

This is intentional. The native manifests contain no independently verifiable
runtime producer link. The implementation does not invent a new source ledger,
trust a directory name as a Git SHA, or upgrade source-supplied claims to verified
lineage. If a real schema contains additional provenance, it is reported and
STOPs for explicit review rather than being silently adapted. Schema, identity or
metadata failures instead set `metadata_status=STOP`; later stages stay NOT_RUN.

The CLI exits **2**, including after complete metadata, to prevent a caller from
using zero exit status as an automatic S2A/S2B continuation signal.

The delivery response supplies one literal SHA-pinned Roihu command. Run it only
from an **already available, reviewed S2C checkout**, after the draft has been
reviewed. It checks Git HEAD and the script diff, loads `gdal/3.12.2` and invokes
this metadata-only CLI. It performs no download, checkout, source-data copy,
Slurm submission or raster-value read. This command has **not** been executed on
Roihu by Codex. No actual Roihu checkout path or file availability is assumed.

## Actual tests

No new dependencies: Python standard library and the separately configured GDAL
CLI. Synthetic tests use native-style manifests and CSVs with invented data;
no real original reports are embedded. The two integration tests reuse only the
existing stdlib sparse-GeoTIFF fixture writer, never its raster reader.

```sh
python3 -B -W error::ResourceWarning -m unittest discover -s diagnostics/water_connected_graph_design -p test_s2c_original_source_preflight.py -v
MM_S2C_GDAL_TESTS=1 python3 -B -W error::ResourceWarning -m unittest discover -s diagnostics/water_connected_graph_design -p test_s2c_original_source_preflight.py -v
python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_decision_contract_v1.py -v
python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_s2a_pure_d8_trace.py -v
git diff --check
```

| Check | PASS | FAIL | NOT_RUN/skipped |
|---|---:|---:|---:|
| S2C, actual GDAL3.12.2 synthetic metadata integration enabled | 73 | 0 | 0 |
| S2C, host-only run | 71 | 0 | 2 |
| Existing S1 unit regressions | 101 | 0 | 0 |
| Existing S2A pure Python regressions | 89 | 0 | 1 optional R oracle |
| Original CSC metadata, pixel values and true runtime lineage | — | — | NOT_RUN |

The actual GIS environment is the existing pinned image
`ghcr.io/osgeo/gdal@sha256:885caba325a405ab08793feba1510170ef19d9758c41849f8554ac97e7221dd3`
(GDAL3.12.2/Python3.12.3), network disabled, read-only repository/root, 512 MiB
memory, two CPUs and disposable128 MiB `/tmp` tmpfs. Host Python3.12.14.
Fixture bytes/names/mtime are checked for mutation, and subprocess instrumentation
confirms only `gdalinfo` executed. These checks establish software behavior, not
successful original-data provenance or hydrological validity.

The first development run had one failing test case because a missing-route
fixture accidentally retained a contradictory duplicate-ID mutation. The core
correctly stopped on that contradiction. Separating the fixtures resolved the
test without relaxing the identity check. Later framing, alarm, CRS-semantic and
resource adversarial tests passed. No broad CSC campaign was repeated.

Remaining work requires the actual operator report: determine current native
schema/paths/metadata, explain any historical digest change, and find independent
runtime evidence binding the completed 02F run to these exact raster versions.
Only a separately reviewed decision can address that missing link or authorize
any later bounded value read. Terrain gradients, fill history, channel continuity
and natural outlet interpretation remain unresolved. S2C grants no such approval.
