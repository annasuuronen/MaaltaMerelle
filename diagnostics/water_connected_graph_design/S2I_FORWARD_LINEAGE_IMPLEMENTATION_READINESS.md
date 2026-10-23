# S2I — valmistelu tulevien hallittujen ajojen lähdeketjun todentamiselle

**PREPARATION_ONLY · NOT_IMPLEMENTED · NO_RUN_AUTHORIZATION.** [Issue #68](https://github.com/annasuuronen/MaaltaMerelle/issues/68). Base [S2H draft PR #67](https://github.com/annasuuronen/MaaltaMerelle/pull/67) at exact commit 3930afa6f3f475d6ca8d7e2fb5f1f4848f04c2a8. This is an *execution-independent implementation plan*, not another S2D science proposal and not authorization for even one real raster value read.

All scientific locks are immutable: **NATIONAL=LOCKED; MODERATE=REVIEW_REQUIRED; hydrological_validation=NOT_ASSESSED; channel_interpretation=NOT_ASSESSED; routing_authorized=false; outlet_selection=UNASSIGNED.** The historical LOW 02F effective D8 remains **HISTORIC_02F_EFFECTIVE_D8=NOT_ASSESSED**. Nothing here can re-identify the old consumed values by rerunning an algorithm.

## 1. Reuse exactly what has been done

| Existing layer | Pinned source / status | Reusable as | Explicit missing capability |
| --- | --- | --- | --- |
| [S2D contract #57](https://github.com/annasuuronen/MaaltaMerelle/pull/57) | eb09f39238dc8852d768ffc7a45cd3365e80d7a2; DESIGN_ONLY | Stage IDs, trust chain, immutable-input and publication requirements, 16 negative cases | No code, witness, real record schema or controlled run |
| [S2E schema #59](https://github.com/annasuuronen/MaaltaMerelle/pull/59) | 61686de88c459002a503f39cbb908a09f3743733; synthetic-only | Bounded, reject-unknown-fields, canonical integer-only JSON, claim/stop semantics | Explicitly rejects CONTROLLED_NEW_RUN; no actual bytes, real file paths, signed evidence or global ID registry |
| [S2F observer #61](https://github.com/annasuuronen/MaaltaMerelle/pull/61) | 477c5b13d5714d618c9c9de88f5f80290b53d994; Roihu R 4.6.1 75/75 PASS | Synthetic 02F callback order, typed values, unchanged native 02F route outputs | In-memory tiny handles only; no terra hook, trusted witness, source signature or durable transcript |
| [S2C.1 #65](https://github.com/annasuuronen/MaaltaMerelle/pull/65) | 332da2852b994e2441c22d66f4d438e0e787c7a0; Roihu 78/78 PASS | Exact original LOW three-raster *metadata*, native 01/02C/02F small-CSV contract | Original data pixel reads forbidden in S2C, full producer-to-consumer input lineage NOT_ASSESSED |
| [S2H #67](https://github.com/annasuuronen/MaaltaMerelle/pull/67) | 3930afa6f3f475d6ca8d7e2fb5f1f4848f04c2a8; audit-only | Bounded review of which retrospective claims are unproved | No independently verifiable historical effective 02F pointer binding |
| [Original R callback](https://github.com/annasuuronen/MaaltaMerelle/blob/4bbf22bb39181c8a4c27ebc3e2769766043115b8/R/02_build_baseline_hydrology.R#L12617-L12651) | 02F arguments and four output CSV writes | Exact future hook *location to review*, not activated | Effective input immutable snapshot, output closure seal, runtime witness |

**Branch topology matters.** S2E/S2F are on the S2D→S2E→S2F development stack. S2C.1/S2H and this document are on the S2B→S2C→S2C.1→S2H stack. A future implementer cannot import S2E/S2F paths merely by checking out this S2I branch. First compare pinned trees and explicitly plan integration/cherry-picks or a reviewed staging branch. Do not silently merge drafts, replace historical evidence or assume one branch contains all modules.

## 2. Narrow first scientific question and stage boundary

**Proposed future pilot, NOT APPROVED:** On LOW tile E200000_N6900000, given separately approved, pinned and immutable inputs, can a *new* diagnostic 02F invocation be bound to the exact **POINTER, WATER_CLASS, LAKE_ID, CANDIDATE_EDGES and callback** it actually consumes, with a separately verified evidence receipt and identified closed diagnostic CSV outputs?

This is a **new run_id + new attempt_id**. It is *not* a historic-02F replay, outlet decision, flow-routing change, D8 regeneration, fill-depressions run or accumulation. A reused D8 file may acquire a new witnessed **consumer** binding; its old **producer** remains UNKNOWN unless an independently authenticated predecessor exists. Any complete-producer-chain claim therefore STOPs. No 02A/02B/02C recomputation is a side effect of provenance collection. Preserve the original run directories and outputs without edits.

The first pilot is restricted to 02F diagnostics; its dependencies and 02E candidate rows must be separately frozen and versioned. Selection of exactly six lake-1894 historical IDs would require an approved comparison plan; source/version reconciliation is NOT_RUN and route identities must not be assigned from the old CSV to altered inputs.

A future positive verdict, if independently witnessed, is **technical producer/consumer identity inside a declared new-run scope** only. It cannot confer hydrological validation or routing authority.

## 3. Components and executable interface boundaries to implement later

| Component / owner | Input contract | Output contract and invariant | S2D gate |
| --- | --- | --- | --- |
| A. Approved run specification (independent reviewer) | New run/attempt UUID, exact Git tree/scripts and approved scope; candidate event roles; quotas; immutable input refs; module/binary versions; approved trust-root ID and expected witness identity | External immutable spec digest / authorization record, with no embedded secret; absent or mismatched approval = STOP *before any data read* | §3, §4, §7 |
| B. Immutable input registrar (not the model) | Versioned protected snapshots of input members incl. sidecars, declared source role, exact resolved path, storage version, consumer mapping and grid; producer vs reuse flag | Artifact IDs, protected mount/version identity and closed member manifest; no writable alias, mutable path, symlink/hardlink substitution, undeclared journal or inaccessible source | §4, §5 |
| C. Effective-value encoder (deterministic offline library) | Explicit grid, band/type/validity rules and typed sequence of **actual** frozen values; byte limits | Versioned logical-stream digest plus byte count distinct from file hash; retain zero, negative zero, R NA, NaN, ±Inf and exact integer lake IDs | §4, §5 |
| D. Approved 02F consumer observer (R side, new-run only) | Frozen pointer/water/lake handles, source IDs, bound native callback, candidate rows, cell IDs and max_steps | Ordered read-events including handles/role, requested cells, exact typed returned values, event sequence and result/QA references; never alters callback return, reroutes, deduplicates or invents values | §5 |
| E. Restricted event ledger / run closer (separate workspace) | Observed start + stage events, actual materialized/reused versions, executable/config IDs, closed 02F CSVs, environment measurement and source/size/hash identities | Canonical bounded manifest digest, ordered event root, COMPLETE only after all declared stages/outputs closed and witnessed; start-only/partial = INCOMPLETE/STOP | §3, §4, §6 |
| F. Independent witness (separate trust authority) | Approved spec and enrolled key known **before run**, direct contemporaneous observation of run IDs, immutable sources, effective consumer and closure | Detached signed attestation anchoring event-chain root, scope, outcome, manifest digest; custody outside producer write permissions | §3, §6 |
| G. Atomic no-replace publisher / external registry | Final canonical bytes, unique IDs, exclusive new workspace, sidecar-free closed evidence; non-authority producer payload cannot alter trust root | Append-only event/source/manifest objects; same-filesystem fsync/no-clobber publish; ID collision, crash or existing name = STOP, no overwrite/retry impersonating old run | §4, §6 |
| H. Independent verifier / gatekeeper | External approved trust store, immutable spec, detached signature, sealed inputs/outputs, full event/identity chain and budget report | Separate receipt with exact declared scope and failure code. Never infer observation from a signature on self-declared metadata. No automatic routing/national permission. | §3, §6, §7 |

**Do not consolidate the witness and model operator into the same trust role.** GitHub CI success, filename, R console log, S2E canonical SHA256, S2F local serialization seal or self-generated signature are not independent attestations. Until an external trust root and protected observer exist and pass adversarial review, status remains **RECORDED_UNVERIFIED / producer_lineage_status=NOT_ASSESSED**.

## 4. Required bindings and order of future events

1. **Approval before any source access.** Store independently registered spec + trust root, code/environment hashes and versioned resource limits. Invalid/unavailable spec → STOP; cannot mint its own approval or look up credentials through a record.
2. **Immutable source selection.** Register resolved paths, all backing datasets/members, storage snapshots and approved grid; distinguish source dataset from pre-existing unverified pointer. Do not trust the pointer's filename or make an on-the-fly hydrological replacement.
3. **Optional producer/reuse decision.** If D8 generation was actually authorized in an entirely separate stage, witness native Whitebox esri_pntr=false, actual LAND_WATER, tmp output and Float64 conversion. Otherwise record a **REUSE_POINTER with producer UNKNOWN**, never synthetic PRODUCE_D8.
4. **Effective 02F boundary.** Before 02F call, freeze/bind actual pointer, class and lake argument objects and candidate-edge full content in immutable/new-run scope. File-backed Terra can reopen sources lazily. Metadata and hashes of a mutable pathname alone cannot prove the actual values read. Instrument the exact native 02F callback semantics and preserve WATER_CLASS→LAKE_ID→POINTER invocation triplets (including duplicates and pointer reads on water cells), as established by S2F.
5. **Result and closure.** After four native 02F CSV writers complete, identify file versions and full bytes, schema/order, QA status and event linkage. No changed old output. Incomplete/partial outcomes are recorded as incomplete rather than silently re-run.
6. **Witness and verification.** Enrolled external witness observes and signs the correct scoped event chain. Publisher uses atomic **no-replace** finalization. Independent verifier checks trust root, signatures, temporal/run/attempt scope, input→consumer→output bindings, hashes, aliases, invariants and budgets; separately issues receipt or STOP.

The implementation must distinguish **producer linkage**, **effective 02F consumer binding**, **technical reproducibility**, and **hydrological acceptance**. A newly witnessed consumer of a reused D8 does not establish historical D8 production.

## 5. First *code* increment after this preparation: S2I-A (requires separate approval)

Deliver **offline synthetic-only** protocol and lossless encoding without any real file/terra/CSC access, OS run launcher or positive VERIFIED decision. Proposed separate branch, issue and independently reviewed draft PR. No code is implemented in this S2I document.

Allowed future surface (exact filenames to be frozen in that issue):
- Pure structural contract for new-run evidence records **separate from S2E's SYNTHETIC-only schema**; unknown fields/schema and deceptive CONTROLLED_NEW_RUN/verified claims STOP. Use standard library, in-memory only.
- A documented byte-level logical stream grammar: domain tag + encoding version + grid identity + band/source role + row-major indexing + typed scalar count, little-endian integer/IEEE754 payload and separate validity tag per value. Preserve R NA vs non-NA NaN (including payload), ±0, ±Inf and exact Int32 lake IDs. Specify behavior for integer NA; no Float32 downgrade, JSON float canonicalization or shell serialization shortcut.
- Pure reference encoder/decoder and deterministic SHA256 of **supplied synthetic bytes**, with bounded traversal. A synthetic digest is always labelled synthetic and cannot serve as evidence of an actual source read.
- Contract-adapter tests comparing Base R bit-level vector fixtures to a separately implemented Python decoder only if the source/environment and byte equivalence are explicitly verified. **S2F's local R serialize(v2) payload is not claimed portable canonical encoding; it is an input to analyze, not the output format by fiat.**
- Immutable status/STOP decision tests that never return verified lineage without an external separately enrolled witness and actual observed consumer binding.

Tests to pre-register: duplicate/unknown JSON keys, unknown versions, Unicode and malformed bit tags, NaN vs NA, negative zero, non-finite numbers, integer 16777217 and Int32 limits, switched raster roles, cell order/duplicate requested cells, inconsistent grid/NoData, swapped run IDs, mismatched hashes and event order, incomplete/censored transcripts, forged witness claim, missing/expired trust root, A→B→A mutation claim, resource exhaustion, and prohibited science approvals. Source files, OS/network calls, stdout secrets and hydrology operations must remain impossible at this slice. No prior S2E/S2F 130/75 tests need repetition unless a relevant module is actually integrated.

**Acceptance of S2I-A** = all named synthetic tests actually pass, negative tests STOP in intended ways, no real I/O surfaces, exact changed-file audit, and every positive record is still **RECORDED_UNVERIFIED**. This is not a pilot or proof of trusted observations.

## 6. Dependent later increments; their prerequisites

| Increment | Scope | Required before implementation | Acceptance criterion without overclaim |
| --- | --- | --- | --- |
| S2I-B | Synthetic R↔Python typed-value interoperability on S2F's unchanged native synthetic 02F invocation; verify byte equivalence and read order | Freeze S2I-A grammar; reviewed detached binary fixture handoff and R4.6.1 handling; no real Terra | Typed streams and native outputs match for tiny synthetic cases; local observation only |
| S2I-C | Immutable source + event recorder *interface* with mocked provider and negative race/substitution tests | Approved immutable snapshot/storage isolation model; private source paths and sidecars defined; quotas | Correct STOP when a source changes; no read of original LOW or autostart |
| S2I-D | External trust enrollment, witness recording and independent verifier, all against fully simulated new runs first | Independent operator and trust-root administration; protected append-only storage; cryptographic signature scheme/domain separation; key/rotation/revocation policy | Invalid signature/replay/wrong scope/missing event fail; no self-signed COMPLETE becomes VERIFIED |
| S2I-E | Explicit, off-by-default 02F-only production adapter, run closure and no-replace publication | Separately approved code changes, source snapshots, end-to-end independent trust, named CSV contracts, evidence retention, failure path and hard quotas | Read-only diagnostics in new private workspace; each consumed value and output tied to witness; no D8 regeneration |
| S2I-F | *Possible future* bounded LOW controlled pilot | Separate user and CSC approval, new run/attempt ID, stage/real-pixel authorization, enrolled witness, actual approved snapshot and resources, signed spec | Only scoped technical receipt if every check passes; reused D8 producer may remain NOT_ASSESSED; historical 02F stays STOP |

S2I-C/D/E/F are **not approved by this PR**. An OS-level immutable snapshot and independent observer are *new trust dependencies*, not behaviors of the present S2E/S2F code.

## 7. Run-authorization checklist — deliberately UNSET

| Required datum for any actual controlled LOW pilot | Current value / next owner |
| --- | --- |
| Scientific question + explicitly restricted permitted stages | Proposed 02F-only diagnostic, **NOT_APPROVED**; project reviewer must confirm |
| Effective input source and versioned immutable snapshot IDs (POINTER, WATER_CLASS, LAKE_ID, candidate rows) | **UNSET → STOP**; operator/storage custodian |
| Allowed exact original-value/cell reads and 02F execution permission | **UNSET → STOP**; user and CSC policy owner |
| Source producer or declared reuse provenance | **UNKNOWN / NOT_ASSESSED** where not witnessed; no inferred D8 commit |
| Exact canonical Git commit, reviewed R adapter and tested binary/environment versions | **UNSET → STOP** for future code; CI/reviewer |
| Trusted witness identity, enrolled public-key fingerprint, scope, key custody and revocation | **NOT_IMPLEMENTED → STOP**; independent trust operator |
| Immutable append-only storage, snapshot guarantees and external registry | **NOT_IMPLEMENTED → STOP**; storage custodian |
| CPU, memory, wall time, hashed file/byte quota, read/cell quota, temporary storage and report size | **ALL UNSET → STOP**; approved CSC allocation, no invented estimates |
| Protected output workspace, atomic no-replace semantics and retention/deletion policy | **UNSET → STOP**; storage owner |
| Explicit test plan with positive control and every S2D §7 negative control | **NOT_RUN → STOP**; independent reviewer |
| Final independent receipt, mandatory QA and scientific gate review | **NOT_RUN → STOP**; verifier and hydrology reviewers |

Avoid a blanket “run” button: future adapter defaults off and cannot infer approval from the presence of a JSON manifest. A signed producer claim without witness observation is still not evidence that it read the effective input.

## 8. Delivery and verification of this S2I preparation

Only **this new Markdown file** is introduced. No changes to 01 manifests, any original output, S2C.1 scripts, S2E/S2F code, baseline R pipeline, data, workflows or prior branches. No CSC access, real pixel read, runtime test, producer/consumer replay, signer creation, merge, or network dispatch of a job. For a documentation-only deliverable, executable tests are **NOT_RUN**; previously reported tests retain their exact historical scope.

**Next distinct coding task:** S2I-A, only after accepting this preparation and defining its own exact file allowlist, synthetic test matrix and branch integration review. Do not silently port S2E into real source mode or activate S2F on production Terra.
