# S2I-B/2b — standalone synthetic native-value v2 codec QA

**IMPLEMENTED_STANDALONE / SYNTHETIC_ONLY / NOT_AUTHENTICATED.**
Parent: reviewed [S2I-B/2a design, draft PR #75][design] at
`c7d9cb41a5ac3e76fddb5c54ad51ec990afd1834`. Reviewed/tested2026-10-23.
This increment implements the value codec, not the S2F adapter, native routing,
source selector or trusted observer. No existing file is modified.

All API records/results retain:

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

## 1. Grammar audit before implementation

No ambiguity preventing lossless standalone interoperability was found. The
following interpretations follow the pinned design without changing it:

| Audited point | Decision / nonblocking consequence |
| --- | --- |
| Magic/header/frame/trailer layout | `MM-S2CV`+NUL and `MM-END2`+NUL are each8 bytes; version/scope/profile bytes are2/1/1. Total length includes all framing. Batch body is exactly `7+n*(request_width+1+response_width)`. Trailer is14 bytes. |
| Slots versus triplets | Three matching request vectors per triplet make slot totals divisible by3. Under the512 cap the largest valid total is510;513 is over budget. Advertised511/512 with a510-slot body fail the count check. No limit is enlarged to make512 reachable. |
|206-byte header /9140-byte bound | Safe conservative upper bounds. In particular the R-version regex is tighter than its32-byte length ceiling. No padding is permitted to fill unused capacity. |
| NA_REAL versus NAN | Both require IEEE NaN-category bits; the R-observed tag is retained separately. A standalone decoder cannot authenticate R predicate semantics. A structurally valid tag flip must fail exact reference matching. No hard-coded NA payload normalization. |
| Declared dtype versus native storage | The three dtype declarations are always encoded, UNKNOWN by default. They do not control request/response widths or classify255 as missing. |
| S2F/full-observation rules in design §§2/6/8 | Deliberately deferred by this task. Standalone parsing never returns LOCAL_OBSERVATION_MATCH. No S2F report, callback, native function or detached loader is accepted/loaded here. |

## 2. Exactly five new files

| File | Purpose |
| --- | --- |
| `s2i_b2b_native_value_v2.R` | Independent pure Base-R encoder, native-vector/raw-vector constructors and bounded validation |
| `s2i_b2b_native_value_v2.py` | Independently written pure Python encoder/decoder and synthetic reference-byte comparison |
| `test_s2i_b2b_native_value_v2.R` |58 new named tests and seven bounded synthetic wire fixtures |
| `test_s2i_b2b_native_value_v2.py` |125 new unittest cases, independent byte expectations and separate-stage R comparison |
| `S2I_B2B_NATIVE_VALUE_V2_QA.md` | This audit, interface, results and limitations |

The frozen v1 codec/writer, S2F, native02F, prior reports/designs/evidence, R
pipeline, workflows and existing tests are unchanged. No new dependency package,
installation step, network capability, raster or persistent fixture is required.

## 3. Interfaces and exact representation

Python input records are frozen dataclasses:
`Header`, `Request`, `Values`, `Batch`, `Transcript`. Requests/responses retain
explicit INTEGER/DOUBLE types and immutable raw bytes; responses also retain
ordered validity tags. Input tuples/bytes are required; mutable lists/bytearrays,
bool-as-integer metadata, subclasses and unsupported fields cannot silently
become valid wire data.

- `encode(Transcript)` returns immutable `Encoded(data,synthetic_payload_sha256)`
  with `disposition=STRUCTURALLY_WELL_FORMED`, authentication NOT_AUTHENTICATED.
- `decode(bytes)` is v2-only and returns immutable `Decoded(transcript)` with
  that same structural disposition. It rejects noncanonical framing and checks
  exact re-encoding after independent parsing; it never imports v1 or falls back.
- `compare_synthetic_reference(bytes,reference_bytes)` parses both bounded
  inputs and requires complete byte equality. A match returns only
  SYNTHETIC_REFERENCE_BYTES_MATCH / RECORDED_UNVERIFIED, with
  `LOCAL_OBSERVATION_MATCH=NOT_ASSESSED`. A missing/mismatching reference STOPs.
- Codec failures raise `Stop` with a bounded reason and fixed safety properties.
  Invalid dataclass constructor signatures raise TypeError before any encoding;
  neither path produces a successful record or executes supplied content.

Base-R constructors are `s2cv_header`, `s2cv_request`, `s2cv_request_raw`,
`s2cv_values`, `s2cv_values_raw`, and `s2cv_batch`.
`s2cv_encode(header,batches)` returns a value list containing raw `data`, the
structural disposition, NOT_AUTHENTICATED and fixed safety fields. All structured
input schemas and safety fields are rechecked; typed errors are `s2cv2_stop`
with `S2CV2_STOP:<reason>`. Ordinary R value/copy semantics are not a hostile-code
sandbox or independent witness.

Native constructors preserve INTEGER/DOUBLE vector types, deriving observed
validity and little-endian `writeBin` bytes without converting the supplied
responses. They first check the int32/binary64 runtime profile; an unsupported
profile STOPs rather than converting values. Raw constructors preserve explicit tags/bits, including arbitrary
NaN sign/payloads. Integer minimum bytes `00000080` are NA_INTEGER; double
NA_REAL/NAN retain all eight original bytes. Signed zero, subnormal values,
infinities and exact integer16777217 survive. Every role accepts either native
storage type, while a role's type stays constant within one transcript.

Requests preserve storage type, raw order and duplicates. Integer IDs are
checked exactly; double IDs are matched to exact binary64 encodings for1…81,
never rounded into a grid. Generated validation-table integers are not coercions
of observed inputs. Scalar values are validated through integer bit fields;
Python does not decode responses into Python floats for equality.
Native-type and validity labels are length-bounded before lookup, so malformed
structured API strings cannot make validation scan arbitrarily long labels.

The Python synthetic content SHA256 identifies supplied bytes only. Raw tags,
declared grid/CRS/runtime/dtypes, UUID labels and a matching caller-supplied
reference cannot authenticate source data or an actual consumer invocation.
No native outputs or original producer lineage are encoded by this value format.

## 4. New tests actually executed

Local environment: R4.5.0 (`x86_64-pc-linux-gnu`), Python3.12.14. No CSC access.
Both final processes exited0. Each process had a **256 MiB RLIMIT_AS** address-space
cap and a30s external deadline, TERM then KILL after2s; BLAS/OMP threads fixed to1.
No enforcement fallback or budget increase was needed.

| Final distinct new cases | PASS | FAIL | NOT_RUN |
| --- | ---: | ---: | ---: |
| Base-R codec tests |58 |0 |0 |
| Python unittest cases, including five R-equivalence methods |125 |0 |0 |
| **Total named cases** | **183** | **0** | **0** |

No case was skipped. Counts are named test executions in the final versions,
not sums of development reruns, scalar assertions or per-fixture subtests.
The initial Python119-case set passed; four additional511/512 framing,
permutation and deduplication checks passed in the expanded123-case set. Adding the
native-runtime guard and its two new R cases exposed one Python static-test
false positive: the substring `file(` occurred inside `native_profile()`.
That intermediate run was **122 PASS,1 FAIL,0 NOT_RUN**. The test now matches
function-call tokens, with positive checks that actual file/source/system calls
are still rejected; the codec's I/O prohibition was not relaxed. All123 passed
after that test correction. A final length-before-lookup guard added two Python
and one R negative case; the final125/58-case suites passed. No failure was
hidden or waived.

The seven R-emitted fixtures match both the Python encoder and a separate
field-by-field test oracle. The minimal fixture also matches a hand-laid-out
**176-byte literal** independent of either codec. Fixtures cover all six
role/response-storage combinations, both request storage types, duplicate IDs,
raw NA/NaN/±0/±Inf and extreme finite bits, declared-dtype/native-type separation,
maximum metadata/grid fields and24 batches/510 slots. No native02F is invoked.
Fixture wire runtime text `0.0.1` / `synthetic-fixture` is deliberately declared
synthetic metadata; actual test runtimes are the versions reported above.
Some position-sensitive transport fixtures deliberately assign different values
to duplicate requested IDs. They are not claimed to be fixed-source callback
observations; source/response consistency belongs to the later S2F report checks.
The standalone codec preserves the supplied positions rather than inventing or
deduplicating a source history.

Adversarial cases include every byte-prefix truncation of the literal, altered
lengths/counts/end markers, v1/unknown magic/version/scope/profile, UUID/ASCII/grid
errors, wrong/reordered roles, unknown native types/tags, inconsistent widths,
fractional/NA/NaN/Inf/outside requests, substituted/permuted triplet data, per-role
storage changes,33-value/27-batch/513-slot overflows and oversized transport.
Native R input bytes are checked before and after helper encoding. An isolated
test copy of the runtime check with an unsupported numeric profile confirms its
STOP path without modifying the actual runtime or global machine metadata.

Valid-looking changed scalar bits, NA_REAL↔NAN tags, consistent cell substitution,
and whole-triplet removal with repaired framing **may remain structurally valid**.
The tests require their rejection against the original synthetic reference.
No digest is treated as authenticity, and no parser is claimed able to detect
all self-consistent forgeries without a reference.

Final observed process wall time: R0.6660s; Python0.1655s (including startup).
Largest child RSS across the final stages:64.91 MiB, Linux RUSAGE_CHILDREN; not
an individual module memory profile or national scalability estimate. R stdout
was23571 bytes, below the64 KiB test transport bound.

Not executed in this task:

| Separate scope | Current execution status |
| --- | --- |
| Accepted v1 seven-test, S2F75-test, B/2 five-probe campaigns | NOT_RUN; accepted historical results unchanged, not repeated |
| New v2 under Roihu R4.6.1 / Python-geo3.14.5 | NOT_RUN; prior v1 compatibility does not verify v2 |
| S2F integration, native02F callback/output parity, detached source loader | NOT_RUN / NOT_IMPLEMENTED here |
| Original LOW data, raster pixels, runtime input lineage, hydrology or CSC jobs | NOT_RUN; unauthorized by this standalone implementation |

## 5. Reproduction and separate stages

Only the new R test file is run, then only the new Python test file. Python
never invokes R, which also avoids nested CSC container wrappers. The local
R path below is the actual available test binary; replace it with a reviewed
runtime only when executing this new test scope in another environment.

```sh
(
set -eu
umask 077
MM_V2_OUT=$(mktemp /tmp/mm-s2cv-output.XXXXXXXX)
trap 'rm -f -- "$MM_V2_OUT"' EXIT
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 \
  timeout --signal=TERM --kill-after=2s 30s prlimit --as=268435456 -- \
  /tmp/mm-base-r/bin/Rscript --vanilla \
  diagnostics/water_connected_graph_design/test_s2i_b2b_native_value_v2.R > "$MM_V2_OUT"
tail -n 1 "$MM_V2_OUT"
MM_S2CV_R_OUTPUT="$MM_V2_OUT" PYTHONDONTWRITEBYTECODE=1 \
  OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 \
  timeout --signal=TERM --kill-after=2s 30s prlimit --as=268435456 -- \
  python3 -B -m unittest discover -s diagnostics/water_connected_graph_design \
  -p test_s2i_b2b_native_value_v2.py -v
)
```

`set -e` stops before Python if R fails. The explicit R-output file is bounded
at65536 bytes, must contain seven unique fixture cases,58 unique R PASS lines
and exactly one complete zero-failure summary. In a future approved Roihu test,
load R for the first stage, unload it and load python-geo for the second; no
Python-to-R subprocess exists. The transport remains self-reported test evidence,
not authenticated custody. If no R-output file is supplied, Python explicitly
marks the five cross-language methods skipped/NOT_RUN; it never invents PASS.

## 6. Readiness and remaining limits

**Ready as a standalone, locally tested dependency for a subsequent separately
reviewed S2F integration stage.** The v1 representation blocker is addressed by
the new v2 format, without changing v1. This is not a claim that native callback
interoperability is already implemented or that Roihu v2 compatibility passed.

Next-stage prerequisites remain the reviewed detached S2F code selector, a pure
adapter from complete sealed reports, all-new targeted request/value/reference
and native-output parity tests, and the chosen runtime's actual verification.
No S2F entry point, source loader, real-data mode, producer recorder, witness,
trusted signature, approval mechanism, routing integration or automatic dispatch
was added. The historical02F STOP and all scientific locks remain in force.

[design]: https://github.com/annasuuronen/MaaltaMerelle/blob/c7d9cb41a5ac3e76fddb5c54ad51ec990afd1834/diagnostics/water_connected_graph_design/S2I_B2A_NATIVE_R_CALLBACK_PROTOCOL_V2_DESIGN.md
