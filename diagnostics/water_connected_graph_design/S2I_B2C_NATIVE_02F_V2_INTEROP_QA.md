# S2I-B/2c — synthetic native 02F callback observations to v2

Implemented and tested locally on 2026-10-24. This is a read-only export of a
complete **synthetic** S2F observation, not a producer recorder or routing change.
The branch starts directly at `8d94ec33ce3aeeb20626b6665ae81594934087ce`.
No previously accepted module, fixture, report or test evidence is changed.

```text
NATIONAL=LOCKED
MODERATE=REVIEW_REQUIRED
hydrological_validation=NOT_ASSESSED
channel_interpretation=NOT_ASSESSED
routing_authorized=false
outlet_selection=UNASSIGNED
HISTORIC_02F_EFFECTIVE_D8=NOT_ASSESSED
SOURCE_AUTHENTICATION=NOT_ASSESSED
INDEPENDENT_WITNESS=NOT_IMPLEMENTED
```

## Audited boundaries and detached dependencies

Read the S2I-B/2 integration STOP, reviewed B/2a design, frozen S2F observer,
unchanged native consumer and accepted B/2b v2 implementation. The earlier v1
representation blocker is addressed by the separately reviewed v2 format, not
by modifying v1 or projecting native NA to Byte255. S2F remains a divergent
draft dependency; it is neither merged, cherry-picked nor vendored here.

The new selector reads exactly these existing local Git blobs:

| Role | Commit / path | Required SHA256 |
| --- | --- | --- |
| Native consumer | `477c5b13d5714d618c9c9de88f5f80290b53d994`, `R/02F_water_connected_route_diagnostics.R` | `36df1b8181cb9c604f82c3c11970ec2d553bbb59385d4a693ae5f72159447ccf` |
| Observer | Same S2F pin, `diagnostics/water_connected_graph_design/s2f_synthetic_02f_observer.R` | `81e8fa53a6117facb6cd70e3c03a2c3cd79eef77b75cda074011095ad88ab9dc` |
| R v2 codec | Base `8d94ec33ce3aeeb20626b6665ae81594934087ce`, `diagnostics/water_connected_graph_design/s2i_b2b_native_value_v2.R` | `869a253ca626899d54070e0e7665da88c9fd881e1a4f7ba3fb95da4781b6e95a` |

It requires a canonical-origin working checkout, verifies commit objects and
blob sizes/hashes, and also compares the native consumer with the base's native
blob. Working-tree copies of these dependencies are not sourced. Missing or
mismatched objects STOP; there is no automatic network fetching. Git lazy fetch,
replace objects, optional locks, transports, hooks, fsmonitor and external
configuration overrides are disabled. A new missing-promisor-object test checks
that Git does not launch a fetch. The host preparation stage invokes only
read-only Git commands; it never invokes R or a CSC container wrapper.

Only verified hex literals and fixed instructions enter a new private loader.
Its destination must be fresh, in an existing private user-owned directory,
without symlink parents. Code is captured once and sourced into locked isolated
environments: native/S2F with the standard stats namespace, v2 with base R.
No config, pipeline, previous test runner or Terra hook is loaded.

This protects local code identity against accidental substitution. It does not
sandbox malicious same-user R code, attest the host/interpreter/Git executable,
authenticate datasets, or supply historical producer lineage.

## Interface and export rules

Five new files only, all under `diagnostics/water_connected_graph_design/`:

| File | Purpose |
| --- | --- |
| `s2i_b2c_pinned_sources.py` | Bounded offline dependency preparation, Python 3.9+ syntax / standard library |
| `s2i_b2c_s2f_to_v2.R` | Pure Base-R report-to-wire adapter; no I/O or routing calls |
| `test_s2i_b2c_s2f_to_v2.R` | New native/S2F observation, parity, export and STOP checks |
| `test_s2i_b2c_interop.py` | Independent expected observations, decoding/bytes and loader tests |
| `S2I_B2C_NATIVE_02F_V2_INTEROP_QA.md` | This receipt, execution scope and remaining limits |

`s2c_export(report, dependencies, run_id, attempt_id, grid_id="tiny",
x_origin=0L, y_origin=0L)` accepts the locked dependency environment generated
by the selector and the original locked S2F report. After cheap size/count
guards, it **calls the original `s2f_check_transcript(report)` before constructing
any v2 output**. STOP/incomplete/zero-observation reports cannot export. It
also checks runtime context, scientific locks, counters and observed responses
against the report's recorded source snapshot.

For each original call, it copies S2F's captured request/response type, validity
and raw little-endian bytes into the frozen v2 raw constructors. It does not
reinterpret role as storage type, coerce values, sort/deduplicate cells, replace
NA, infer a missing callback, read a source, or run native 02F again. Frozen v2
validation enforces matching complete WATER_CLASS → LAKE_ID → POINTER triplets.
The output is a locked environment containing raw `data`, counters, all locks,
`disposition=CHECKED_SYNTHETIC_REPORT_EXPORT` and
`authentication=NOT_AUTHENTICATED`.

The original checker is a local self-seal comparison. A fully consistent report
manufactured by a malicious process is not independently authenticated. Extra
snapshot checks catch inconsistent resealing, not a producer who substitutes
all references together. Python reference equality likewise establishes only
equality with separately declared synthetic observations. It cannot assert
`LOCAL_OBSERVATION_MATCH`, verified provenance or a real consumer witness.
Declared raster dtype stays UNKNOWN; native callback type is the observed type.

## Newly relevant tests actually executed

Only these two new test files ran. No old test runner was imported or sourced.
The new R stage invokes the frozen native function twice per positive fixture:
once with a separate recording delegate and once through the original public
S2F observer. The private S2F callback is unchanged. For every fixture,
`routes`, `edge_routes`, `group_summary` and `qa` are compared exactly, including
serialized values. The adapter leaves the report/results and native function
body unchanged.

| Tiny fixture | Actual observation exercised |
| --- | --- |
| 3×3 land-to-river-line chain | Native double NA on land; duplicate requests `(5,5)` then `(6,6)`; two origins |
| 5×5 convergence | `(6,7)` then `(12,12)` then `(17,17)`; duplicate downstream requests; integer WATER_CLASS / double LAKE_ID |
| 3×3 lake contact | Integer POINTER and integer lake ID16777217, beyond exact Float32 integer range |
| 3×3 special values | Actual pointer callback returns NA_real, a nondefault NaN payload, ±Inf, +0, −0, invalid/fractional pointers; native output is preserved |
| 5×5 work limit | Only the actual first triplet exported; native STEP_LIMIT and terminal14 remain censored |

The independent Python reference declares cells, role/type/tag/raw values and
batch lists separately from R wire output. It compares every byte and every
decoded record, then roundtrips each stream. Runtime strings are taken as
unverified execution context, not independently authenticated information.
All six role/native-storage combinations occur in actual observations.

STOP tests include reordered callbacks, wrong roles, altered cells, changed
values/raw bytes, truncated observations/vectors/transport, a missing complete
triplet versus the reference, altered native results, missing seal, mismatched
counters, excessive steps, changed runtime, inconsistent source snapshots,
wrong dependency pins and unlocked reports. Public reference-callback failure
and source substitution yield incomplete/STOP reports, which cannot export.
Loader tests cover each altered blob, missing scope/objects, wrong origin,
native divergence, private-output rules, output overflow, timeout and no-fetch
behavior. These test adversarial data, not replacement of the private callback.

| Executed group | PASS | FAIL | NOT_RUN |
| --- | ---: | ---: | ---: |
| New Base-R checks, local R4.5.0 (`x86_64-pc-linux-gnu`) | 42 | 0 | 0 |
| New Python tests, Python3.12.14 / Git2.52.0, including all five R streams | 27 | 0 | 0 |
| **Final new targeted total** | **69** | **0** | **0** |

Development failure history: the first R stage had41 PASS; the independent
Python comparison had25 PASS /2 FAIL on the special-values fixture. Inspection
found the new R fixture call already supplied negative zero in both positions
intended for +0/−0, before observation or export. A separate factory probe
preserved correctly supplied bits; the exact R expression-evaluation cause was
not established. The new fixture now constructs its originally intended bits
explicitly and asserts them before S2F invocation (one added R check). Python
expected observations, the adapter, frozen components, acceptance conditions
and intended fixture values were not changed to hide the mismatch. The final
bounded R stage and all new Python checks then passed as tabulated above.

Accepted Roihu job2516979 (58 R +125 Python PASS), S2F75, B/1 seven-test and
B/2 five-probe campaigns were **not repeated**. Their accepted evidence remains
unchanged. New R4.6.1/Python-geo3.14.5 interoperability: **NOT_RUN**. There is no
CSC, original LOW, production 02F, hydrological or historical-authentication
test result in this delivery.

## Resource receipt and reproduction

Preparation: 20s total deadline; ≤32768 bytes/blob, ≤4096 stderr bytes/Git call,
≤262144 bytes/generated loader. Adapter: grid ≤9×9,3–24 complete calls,
≤32 values/call, ≤512 total scalar slots, max_steps≤8, ≤1MiB original seal,
2s cooperative export deadline. Frozen v2 keeps its ≤16KiB defensive wire cap.
No limits of accepted components were enlarged.

The final R test ran in a local read-only Docker container pinned to
`r-base@sha256:cf26bf3a050b654ae224c6d96ba8d188a2f53eb0188c6c7c0a4bb16758ec057f`.
Network was disabled. Only private test/adapter/verified code files were mounted
read-only; no repository or raster dataset was mounted. Limits:256MiB memory
including swap allowance,1 CPU,64 processes,32MiB temporary filesystem,
no capabilities, no privilege escalation, one BLAS/OMP thread. Inner TERM30s /
KILL2s timeout and outer45s watchdog. Recorded container elapsed1.0947s, exit0,
OOMKilled=false. R peak RSS was **NOT_MEASURED**, not inferred from the cap.

Python used TERM30s / KILL2s,256MiB address-space limit and one BLAS/OMP thread.
Recorded wall0.4655s, maximum child RSS19.94MiB, exit0. R stdout was5420 bytes
and stderr empty. This is a tiny interoperability/resource test, not a scaling
or national-routing benchmark. Outer process limits bound the trusted synthetic
harness; ordinary R environments/self-seals are not hostile-code isolation.

To reproduce, use an existing clean checkout of the reviewed new commit with
both pinned dependency objects already present. Missing objects STOP; the
selector never retrieves them. From the repository root, prepare a private
directory with `umask 077` and run:

```sh
python3 diagnostics/water_connected_graph_design/s2i_b2c_pinned_sources.py \
  --repo "$PWD" --output "$MM_S2C_PRIVATE/pinned.R"
```

In the separate bounded R stage:

```sh
MM_S2C_BOOTSTRAP="$MM_S2C_PRIVATE/pinned.R" \
  Rscript --vanilla diagnostics/water_connected_graph_design/test_s2i_b2c_s2f_to_v2.R \
  > "$MM_S2C_PRIVATE/r-output.txt"
```

Require R exit0 before the separate bounded Python stage:

```sh
MM_S2C_R_OUTPUT="$MM_S2C_PRIVATE/r-output.txt" PYTHONDONTWRITEBYTECODE=1 \
  python3 -B -m unittest discover -s diagnostics/water_connected_graph_design \
  -p test_s2i_b2c_interop.py -v
```

These are stage entry points; apply the timeout/memory controls above using the
chosen execution environment. On Roihu, prepare with host Python/Git first,
then run R under `r-env/461`; unload that module before running Python under
`python-geo/3.14.5`. Never invoke the R wrapper from inside Python-geo. This
delivery did not exercise CSC's module/container wrappers or their resource
controls. It does not authorize a remote execution or Slurm submission.

The Python handoff requires one complete42-PASS/zero-failure R summary,
42 unique PASS names, five distinct case streams and both pinned code markers,
with a ≤65536-byte regular input file. Missing R output marks12 interoperability
methods skipped/NOT_RUN; it cannot produce a full PASS result. A malformed,
partial or failed supplied output is an error, not a skip or successful export.

## Readiness and remaining decisions

**Ready for review and a new targeted Roihu synthetic interoperability test.**
That test is required before claiming R4.6.1/Python-geo3.14.5 compatibility of
this new adapter/loader. Run only these new files; job2516979 does not need to be
repeated. No frozen S2F/v1/v2 change was required. There is no production
integration, real-data mode, independent witness, source authentication,
historical02F proof, outlet decision or hydrological acceptance. Keep the
historical STOP and all scientific locks. No merge or CSC run is performed.
