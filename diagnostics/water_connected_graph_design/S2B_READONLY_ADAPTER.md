# S2B — bounded, read-only raster input adapter (synthetic fixtures only)

Issue #49; based on S2A PR #48 at
`a0b144f7995b0f5cd329176b4d0a6d5b0a8a671b`. Only the new adapter, its tests
and this report are added. Existing S2A, R code, workflows and data stay unchanged.

**Scope is synthetic fixtures, not a CSC execution package.** No original CSC
TIFF/CSV has been opened. This version rejects real-data mode and paths outside
its explicitly declared private disposable fixture directory. It does not
implement independent source authentication or authorize an original-data run.

Every report preserves `NATIONAL=LOCKED`, `MODERATE=REVIEW_REQUIRED`,
`hydrological_validation=NOT_ASSESSED`, `channel_interpretation=NOT_ASSESSED`,
`routing_authorized=false` and `outlet_selection=UNASSIGNED`.

## Interface and source bindings

`preflight(Request(...), Tools(...))` returns a frozen `Result` containing a
compact frozen `Report`, immutable S2A `WindowData` when extraction succeeds,
and immutable per-route traces when replay is reached. `compact_json(report)`
returns JSON text; it does not write files or print. No output path, arbitrary
GDAL options, window override, approval or command field exists in the API.
There is no automatic dispatch, retry or fallback.

A request explicitly supplies these **eight distinct existing files**:

| Field | Purpose |
|---|---|
| `qa` | Original-style `item,value` input QA CSV |
| `manifest` | Original-style `key,value` input manifest CSV |
| `provenance` | Explicit S2B synthetic producer/binding JSON described below |
| `routes` | Full supplied small 02F summary CSV, not hardcoded expected rows |
| `neighbors` | Full supplied small 02C neighbor CSV |
| `pointer`, `water_class`, `lake_id` | Three explicitly identified single-band GeoTIFFs |

The root must be a private owned directory named `mm-s2b-synthetic-*` directly
under the Python temporary directory. Paths must be absolute, within that root,
without parent traversal, symlinks in any ancestor, hardlinks or special files.
This guard prevents accidental original-data access; the label is not proof of
scientific origin and is not a sandbox against hostile same-user code.

`provenance_sha256` pins the actual small producer JSON bytes. JSON duplicate
keys and unexpected fields are rejected. Its exact top-level schema is:

```text
schema_version: "s2b.synthetic.v1"
evidence_kind: "SYNTHETIC"
producer_commit: 40 lowercase hexadecimal characters
pointer_scheme: "WHITEBOX_D8"
esri_pntr: false
files:
  qa, manifest, routes, neighbors:
    path: exact caller path
    sha256: expected SHA256 of the complete small file
rasters:
  pointer, water_class, lake_id:
    path: exact caller path
    size_bytes: expected file size
    dtype: expected GDAL numeric band type
    nodata: {kind: "FINITE", value: number} or {kind: "NAN"}
    lineage_id: explicit nonempty version/lineage label
    sha256_claim: declared SHA256, explicitly NOT verified by this adapter
```

The actual original-style schemas were checked against
`R/01_prepare_hydrology_inputs.R`, `R/00_pipeline_config.R`,
`R/02_build_baseline_hydrology.R` and S2A. QA must report 6000 columns/rows,
2 m resolution and the exact LOW extent. Manifest bindings must agree with the
explicit water-class/lake-ID paths, `test_id=E200000_N6900000`, `cell_size_m=2`
and the existing R configuration's `pointer_scheme=whitebox`. The separate
producer contract binds the LAND_WATER pointer and all small file versions.
No D8 or water-mask path is guessed from a DEM directory or historical filename.

Small files are read completely using read-only, no-follow descriptors, limited
to 2 MiB and 20000 CSV rows, and hashed in memory. CSV duplicate headers, row-width
errors, duplicate manifest/QA keys and duplicate route IDs fail closed. All six
selected 02F IDs, starts, origin, terminal, steps, classes and statuses must match
the pinned S2A records. All component274 neighbor rows must be exactly the three
adjacent class1/lake1892 rows from source23211319. Other report rows contribute
to the complete file hash; they are not invented as additional selected routes.

**The current producer JSON is a synthetic contract, not an already discovered
original 02F provenance artifact.** Original manifests/02F lineage and their
independent authentication still need a separate approved implementation.

## Bounded GDAL 3.12.2 I/O

The command-line version is checked for **both** tools before raster inspection.
The host's GDAL 3.10.3 is deliberately rejected. Only explicit GTiff sources are
opened. All three metadata checks pass before the first cell-value extraction:

- 6000 × 6000, one band, EPSG:3067 and normal x/y axis mapping;
- affine `[199000,2,0,6911000,0,-2]`, exact corners and center;
- declared numeric dtype and explicit band NoData, without scale/offset,
  overviews or additional masks;
- expected file size, inode/device and modification/change times, checked again
  around GDAL operations. These version checks detect changes; they do not
  authenticate raster content. No full-raster hash or value scan is performed.

The only extraction window is `xoff=3293,yoff=3844,xsize=52,ysize=73`:
3796 values per band, **11388 returned values** in total. There is no enlargement,
reprojection, resampling, whole-image read request or overview generation.
GTiff may physically read/decompress the source blocks intersecting this window;
11388 bounds returned band values, not physical disk bytes or block amplification.

The fixed extraction argv is:

```text
gdal_translate -q -if GTiff -of AAIGrid -co SIGNIFICANT_DIGITS=17
  -a_srs none -b 1 -srcwin 3293 3844 52 73 SOURCE /vsistdout/
```

`-a_srs none` removes only SRS metadata from the **ephemeral stdout transport**
after checking the source CRS. It does not warp coordinates, resample cells or
alter the source file. This is necessary because the AAIGrid writer otherwise
writes its projection sidecar to the same stdout stream. The strict parser
requires six headers plus exactly 73 rows of 52 tokens, the exact window's
lower-left corner/cell size and matching NoData. S2A retains the verified EPSG3067
full-grid geometry and computes global cell centers from that geometry.

Why AAIGrid instead of XYZ: an actual GDAL fixture exposed that GDAL 3.12.2's
[XYZ writer](https://github.com/OSGeo/gdal/blob/v3.12.2/frmts/xyz/xyzdataset.cpp)
uses Float32 for Float64 inputs. This can overflow a Float64 NoData sentinel or
round an illegal near-integer pointer to a valid D8 code. The
[AAIGrid writer](https://github.com/OSGeo/gdal/blob/v3.12.2/frmts/aaigrid/aaigriddataset.cpp)
reads these values as Float64. Seventeen significant digits preserve Float64
round trips. The selected format is fixed; XYZ is not an automatic fallback.
A standalone strict XYZ parser remains covered by the requested malformed-XYZ
and coordinate tests, but no raster-reader path uses that lossy driver.

All GDAL calls use `subprocess.run` with argument tuples, `shell=False`, no stdin,
a maximum 10-second process timeout, a 60-second preflight deadline and at most
eight commands (two version checks, three metadata reads, three window reads).
Two concurrent pipe readers cap stdout at 1 MiB and stderr at 32 KiB **during
collection**; they do not use unbounded `capture_output` or temporary output files.
An overflow closes its pipe and produces STOP. Nonzero exit, timeout or warning
also produces STOP; no retry, different driver, larger window or source-adjacent
file is substituted.

The GDAL child environment disables PAM writes, sibling-file discovery, plugin
loading, PROJ networking and parallel GDAL threads; the GDAL cache is 32 MiB.
All three arrays are held in memory. No adapter call writes a raster, report or
sidecar. This bounded reader is not an authentication/security sandbox for a
malicious native GDAL executable or hostile same-user filesystem races.

## NoData, precision and S2A comparison

Finite typed NoData becomes `Missing.NULL`; declared numeric NaN becomes
`Missing.NAN`. Large finite Float64 sentinels are recognized before S2A's ordinary
finite-data magnitude bound. A valid pointer **zero stays zero**. Declaring D8=0
as NoData, a water class1/2/3 as NoData, or a positive lake ID as NoData is rejected.
Undeclared NaN, infinity, invalid water classes and fractional/out-of-range lake
IDs STOP. Exact decimal checks prevent subprecision coordinate changes,
fractional codes or underflow from being silently rounded into valid integers.
Finite illegal D8 codes remain values and are classified by S2A per inspected step.

The adapter reads and hashes the actual supplied CSV bytes. Synthetic CSV bytes
cannot equal the historical LOW hash
`402fdbf16cb41eaa6a3ad2180cc4d3af8534e32cff299d73eacec8dc5c187db5`.
It therefore uses S2A's unchanged `locked_summaries`, `trace`, `aggregate` and
`neighbor_parity` helpers with the actual synthetic file hash and rows. It never
substitutes the historical hash or calls `audit_low` with a fabricated original
source claim. S2A's historical-file gate remains unchanged. A future original-data
mode must authenticate actual original bytes and enforce that historical pin;
no such mode or bypass is enabled here.

Replay compares all summary fields and preserves each original route ID. A
mismatch records the recovered status/count/terminal, STOP reason and differing
fields; it cannot rewrite 02F. Neighbor comparison uses only the already supplied
window. A zero-terminal cell is never advanced into a nearby lake. The invented
fixture chains and three invented neighbor positions are explicitly synthetic,
not recovered observations from LOW.

## Compact report interpretation

| Stage | Meaning |
|---|---|
| INPUT_QA | Request scope, distinct read-only files and producer-contract structure |
| RESOURCE_BOUND | Version/cap configuration; STOP also recorded for exceeded resource bounds |
| CSV_PROVENANCE | Complete small-file hashes match supplied bindings; native QA/manifest and selected 02F/02C rows agree |
| WINDOW_READ | All source metadata checks and three exact, valid in-memory window extractions |
| S2A_TRACE_PARITY | All six recovered summaries match the actual selected CSV rows |
| WATER_NEIGHBOR_PARITY | Supplied original-style 02C rows agree with the synthetic window |

Stages are PASS/STOP/NOT_RUN. A rejected stage yields `diagnostic_result=FAIL`;
later stages remain NOT_RUN. A fixture can yield diagnostic PASS while both
`SOURCE_AUTHENTICATION` and `SOURCE_PROVENANCE` remain **NOT_ASSESSED**. Manifest
hash strings and stat metadata alone never authenticate original raster lineage.
The report includes exact paths, source sizes/stat versions, declared raster
hash claims marked NOT_CHECKED, actual small-file hashes, returned-value count,
stdout bytes and the full supplied window's in-memory digest. It omits large
per-cell dumps; immutable traces remain available separately for inspection.

## Tests and reproducible environment

No new Python dependencies. Tests use only the standard library and GDAL CLI.
The fixture writer creates sparse, compressed GeoTIFFs with full-grid metadata
but just **two 256 × 256 data tiles per file**, each file under 64 KiB. It never
allocates a 6000 × 6000 array. All test writes stay within a disposable private
temporary directory. The integration checks verify fixture bytes, names and
modification times remain unchanged after reading.

```sh
# Pure/mocked checks; GIS integrations explicitly skip without configured 3.12.2.
python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_s2b_readonly_window_adapter.py -v
# In the explicitly configured GDAL 3.12.2 test environment:
MM_S2B_GDAL_TESTS=1 python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_s2b_readonly_window_adapter.py -v
# Relevant unchanged regressions:
MM_S2A_RSCRIPT=/path/to/Rscript python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_s2a_pure_d8_trace.py -v
python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_decision_contract_v1.py -v
git diff --check
```

The actual GDAL tests run in
`ghcr.io/osgeo/gdal@sha256:885caba325a405ab08793feba1510170ef19d9758c41849f8554ac97e7221dd3`
(GDAL 3.12.2, Python 3.12.3), with networking disabled, read-only repository and
container root, 512 MiB memory, two CPUs and a 128 MiB disposable `/tmp` tmpfs.
Host Python is 3.12.14; the S2A optional R oracle uses R 4.5.0.

| Check | Final actual result |
|---|---|
| S2B including actual GDAL synthetic GeoTIFF integration | 89 PASS, 0 FAIL, 0 skipped |
| S2B host run without the configured GDAL version | 82 PASS, 0 FAIL, 7 explicitly NOT_RUN/skipped |
| Existing S2A tests with optional R oracle | 90 PASS, 0 FAIL, 0 skipped; includes 30 Python/R agreements |
| Existing S1 tests | 101 PASS, 0 FAIL, 0 skipped |
| Original CSC rasters/reports and hydrological validation | NOT_RUN |

Coverage includes bad CRS/axis/affine/extent/dimensions/band/dtype/NoData,
source discovery/version/lineage claims, missing/changed/duplicate CSV evidence,
path escape/symlinks/hardlinks, unsafe output options, malformed XYZ and AAIGrid,
oversized stdout/stderr, timeout, driver failure, immutable locks, unchanged
source files, the six identities and authentic calls to S2A's pure helpers.
Actual integration also checks Float64 near-integer illegal D8, exact lake IDs
above Float32's integer range, NaN and extreme Float64 NoData preservation.

Development failures were retained as findings: the added extreme-NoData test
first failed on XYZ's Float32 conversion (one failure in an 81-test run). The
first AAIGrid run had three failures and two dependent errors because its SRS
footer made stdout longer than the strict raster contract. Selecting the
Float64-preserving transport and GDAL's explicit `-a_srs none` resolved these
issues without relaxing value, window, parity or scientific acceptance checks.

## Remaining scientific and operational limits

Original 01/02F lineage, original TIFF identity and band NoData, current full CSV
checksums, the actual three 02C water-neighbor cell IDs and true raster parity
remain unverified. The new producer contract is tested using invented files; an
independent original-source authentication mechanism is still missing. Real-data
mode, CSC transfer, Slurm submission and production integration are not enabled.

No terrain-gradient analysis, original fill investigation, RANTA10 line alignment,
hydraulic continuity or independent channel validation has been performed. This
reader cannot validate lake1894→1892, select an outlet, infer national thresholds
or approve routing. All scientific locks remain in force.
