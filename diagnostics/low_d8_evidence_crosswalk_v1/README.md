# LOW D8 evidence crosswalk — stream C, 2026-10-24

Documentation-only delta for [issue81][coord] and [issue36's parallel task][task].
Base: `d9397df73cd0fdbe1ccddf1cfeaac161a7ee1b6c` (draft PR37).
No new model, route reconstruction, raster read, input download, or test campaign.
The companion `evidence_ledger.json` records the same bounded evidence units for
coordination; it is not an input to hydrology or an execution manifest.

```text
NATIONAL=LOCKED
MODERATE=REVIEW_REQUIRED
hydrological_validation=NOT_ASSESSED
channel_interpretation=NOT_ASSESSED
routing_authorized=false
outlet_selection=UNASSIGNED
HISTORIC_02F_EFFECTIVE_D8=NOT_ASSESSED
```

## Why this is a distinct delta

PR37's pinned README/FLAT_INCREMENT still records the archived CSV comparison
as NOT_RUN. [The later issue36 record][quantum] reports that the operator already
completed it. That accepted result must be retained without repeating the CSV
experiment, changing PR37, or promoting current file checksums to historical
source authentication. Chronological issue comments also use different units:
centers, eligible centers, candidate edges, unique starts, zero cells,
components, and source lakes. This crosswalk reconciles those units and the
precision limits in one review artifact. It proposes **no duplicate synthetic
fixture** for cases already exercised in PR11/12/37 or later graph work.

The records below were read from existing GitHub issue text. The underlying
Roihu CSVs, rasters, console logs and source-run receipts were **not** accessed
or independently recalculated here. `OPERATOR_REPORTED` does not mean an
independent witness or authenticated producer lineage.

## Denominators, observations, and permitted conclusions

| Evidence unit / scope | Recorded numerator / denominator | What it establishes; what remains unresolved |
| --- | --- | --- |
| PR35 stratified pilot centers | 256 centers =236 eligible LAND +7 WATER +13 source NoData | [Reported sample composition][screen], not 256 independent lake-outlet trials; no population correction rate. |
| Mechanical flags in that pilot | 0/236 eligible LAND centers | No predefined mechanical flag in this selected one-step sample. The reported descriptive Wilson interval 0–1.6017% is not a national, spatially independent or hydrological confidence bound. |
| Near-flat sample subset |119/236 LAND steps; remaining117 steeper downhill | All119 recorded steps strictly downhill, not equal/uphill. A routing-surface micro-gradient is not an observed physical terrain slope or a fault. |
| Accepted archived-CSV fingerprint |119/119 fit3e-7m:104 at1×,11 at2×,4 at3×; also119/119 fit3e-8m;0/119 fit3e-6m | [Accepted operator result][quantum]; supports nonunique numerical compatibility, not the historical increment, binary version or causal mechanism. Do not rerun PR37. |
| 02F candidate-edge rows |229 edges:93 ZERO +51 origin-return +75 river-area +10 river-line | [Edge-weighted status accounting][edgecounts]. The85 first-water contacts are diagnostic stops, not approved outlets or routes to sea. |
| Unique 02F receiver/origin starts |101 starts:41 ZERO +21 origin-return +34 river-area +5 river-line | [Issue10 source table][case] distinguishes unique starts from229 edge labels.41 starts are not41 unique erroneous cells. |
| Unique ZERO termini within those starts |41 starts→7 cells /7 components | [Reported 02C join][join]:6 provisional SAFE components and1 INTERIOR_REVIEW. Lake-specific distinct totals1+3+4=8 overlap globally at7. |
| Cross-origin reuse |Component274 /cell23211319:8 starts from1892 self-target;6 starts from1894 target1892 | Source→target relation is directional. A component cannot acquire one fixed “correct origin”; neither relation authorizes a connection. |
| ZERO-start provisional target relation |33/41 self-target SAFE;6/41 other-lake SAFE;2/41 INTERIOR_REVIEW | The6 other-lake starts are candidates only. Component235 /cell15389414 has MIXED lake/river-line contact and target NA; never impute a lake. |
| Origin-return endpoints |21 starts from lake1940→11 distinct terminal water cells | First water is the origin lake; not proof that lake1940 lacks a natural outlet. |
| Selected 7-cell shoreline inspection |7/7 have incoming lake D8;10 incoming lake pointers total;17 adjacent lake cells RAW/FILL masked | [Reported local mechanism][mask]. One flat-neighbor case 23373314 is distinct from six other minima. Exact Whitebox NoData-boundary causation UNKNOWN. |
| Existing 02C shoreline-zero domain |643 zero LAND cells /340 components, not all LOW cells | [Reported sparse check][shore]:535/643 cells receive ≥1 lake D8 pointer;1273 lake→zero edges across22 source lakes. This is a measured local discontinuity under the reported masks/pointers, not535 approved corrections. |
| SAFE subset in that domain |640 cells:534 receive lake D8;632 below their own minimum water-neighbor Z and8 same level | [Cell-height record][heights] and [incoming-pointer record][shore] measure different predicates. Below water does not imply an incoming pointer; SAFE means lake-only/one-ID/non-edge classification, not continuity PASS. |
| Lake1847 local shoreline |198 lake→LAND edges:197 immediate zero,1 reaches zero after one LAND step;88 distinct immediate-zero receivers | [Existing targeted record][lake1847], not an additional121-source accumulation or a required outlet-repair count. All88 centers lie in reported MML2025 lake\RANTA10 difference area; source geometry disagreement is not proof of which boundary is physically correct. |

None of these denominators is a national sample or the set of all hydrologically
relevant LOW cells. Do not sum overlapping41/535/643/88 cell/start sets. Do not
call39/41 provisional SAFE starts a95% hydrological success rate. The41/101
unique-start proportion and93/229 edge-weighted proportion answer different
questions and cannot be exchanged. `SAFE_LAKE_CONNECTOR` can coexist with
`D8_ZERO_INTERIOR` without an implementation contradiction: the former tests
water-neighborhood identity, the latter the observed existing route terminal.

## Failure taxonomy and limits of precision

1. **Mechanical sample checks:** source-count/order/geometry checks and pointer
   codes have explicit computational contracts. The pilot recorded0/236 flags.
   Separately, lake→LAND-zero links are observed local route discontinuities in
   the targeted shoreline domain. Neither record identifies a justified DEM/D8
   edit. A self-consistent terminal classification is not an externally
   validated continuous route.
2. **Lake-mask boundary uncertainty:** the7-cell record supports unchanged
   RAW→FILL land minima adjacent to masked lake cells and lake pointers entering
   zero cells. The exact installed Whitebox boundary mechanism is UNKNOWN.
   [The accepted local touches replay][touches] found no mismatch to
   `touches=TRUE` in two lake windows; do not repeat it or recast expected
   rasterization as a proven error. Independent physical shore/outlet evidence
   and semantic identity of reference geometries remain separate requirements.
3. **Flat continuation and surface identity:** [lake1847's accepted3×3
   observation][surfaces] explains why STORAGE's NW lower edge may differ from
   LAND_WATER's steepest south D8. It does not prove a faulty D8 or a functioning
   downstream escape. The source/receiver values agree on both surfaces at two
   cells while neighboring S/E/SE values differ. Never generalize that two-cell
   equality to whole-window or whole-raster equality.
4. **Numerical precision:** console values such as 12.14700 or 0.3949003 are
   rounded text, not raw IEEE754 source bits or enough information to prove a
   slope tie. The reported S/E slope difference around 3e-7 has limited printed
   precision. Pinned production source names `land_dem_raw_FLT8S.tif` but its
   write call uses `datatype="FLT4S"`; a filename does not identify on-disk
   precision. Actual old file dtype, producer binary, source maximum and raw
   effective02F pointer provenance remain unverified here. No raster header or
   pixel was read to fill those gaps.
5. **Missing final network:** pinned production source explicitly defers
   WATER_CONNECTED surface/outlet construction and ends with diagnostic 02F
   tables. Existing LAND_WATER D8 is not final WATER_CONNECTED D8. Final
   hydrologically approved routing and area-wide flow accumulation are not
   established by these records; correction amounts remain NOT_ESTIMABLE.

Candidate alternatives—mask reconciliation, flat handling, separate lake graph
representation, and a changed routing surface—remain REVIEW_REQUIRED. No
alternative is selected. A lower STORAGE neighbor, a D8 origin return, a first
river-class contact, or a nearby SYKE outlet point cannot itself authorize an
outlet or authenticate past routing. Existing SYKE outlet/catchment references
are project auxiliary inputs, not newly discovered independent ground truth.

## Evidence source boundary and next STOP

The recorded current LOW grid is 6000×6000, 2 m, EPSG:3067,
xmin 199000 / xmax 211000 / ymin 6899000 / ymax 6911000, from [operator input-QA
output][grid]. These are reported metadata, not a new read or inferred extent
from tile ID. A raw display coordinate or checksum never proves the exact
historical producer-to-consumer chain. The historical 02F STOP remains.

Before any new real-data work, the smallest unresolved **evidence acquisition**
question is the historical Whitebox/runtime/output metadata for the already
accepted near-flat observation and authenticated original source binding. That
cannot be answered by another synthetic quantization fixture. The lake-specific
physical recipient/orientation question needs separately scoped independent
reference review. Neither belongs in the synthetic Roihu minitest batch.

**Stream C introduces no executable test.** New software tests PASS=0, FAIL=0,
SKIPPED=0, NOT_RUN=0 (none proposed); documentation/ledger consistency and
allowlist checks are static checks, not hydrological tests. Existing accepted
screen, quantization, shoreline, local3×3 and large regression campaigns were
not repeated. No new CSC minitest is requested. Scientific/data-verification
checks above remain NOT_RUN/UNKNOWN and excluded from the batch pending their
own evidence/authorization gates. This is the natural STOP of this delta.

[coord]: https://github.com/annasuuronen/MaaltaMerelle/issues/81
[task]: https://github.com/annasuuronen/MaaltaMerelle/issues/36#issuecomment-6385292074
[screen]: https://github.com/annasuuronen/MaaltaMerelle/issues/36#issuecomment-6333999489
[quantum]: https://github.com/annasuuronen/MaaltaMerelle/issues/36#issuecomment-6334875647
[edgecounts]: https://github.com/annasuuronen/MaaltaMerelle/issues/36#issuecomment-6336363601
[case]: https://github.com/annasuuronen/MaaltaMerelle/issues/10
[join]: https://github.com/annasuuronen/MaaltaMerelle/issues/36#issuecomment-6336637109
[mask]: https://github.com/annasuuronen/MaaltaMerelle/issues/10#issuecomment-6210057401
[shore]: https://github.com/annasuuronen/MaaltaMerelle/issues/10#issuecomment-6211466156
[heights]: https://github.com/annasuuronen/MaaltaMerelle/issues/10#issuecomment-6211363048
[lake1847]: https://github.com/annasuuronen/MaaltaMerelle/issues/10#issuecomment-6213436047
[touches]: https://github.com/annasuuronen/MaaltaMerelle/issues/10#issuecomment-6214324270
[surfaces]: https://github.com/annasuuronen/MaaltaMerelle/issues/10#issuecomment-6215342302
[grid]: https://github.com/annasuuronen/MaaltaMerelle/issues/36#issuecomment-6338242521
