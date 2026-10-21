# 02G.2 independent synthetic tile messages and receipts

Parent branch: `codex/low-02g-accumulation-tile-prototype-v1`, PR #25.
Exact parent: `08a7b17f856aa266cd989a3c9c2bb9734e623900`.
Research branch: `codex/low-02g-independent-tile-receipts-v1`.

This bounded Base R experiment replaces centrally inferred receipts **within
this new experiment only**. The original 02G prototype, reports, PR #25,
production files and workflows are unchanged. No CSC, Slurm, Whitebox, real
raster reads or dataset downloads are used. No transport service is installed.
The constructor accepts at most 121 synthetic grid positions on a 2 m
EPSG:3067 grid. Each owned land source contributes 4 m², exactly once.

## Protocol and independence

`messages.R` exposes functional actors: calls return a new state and leave the
original state untouched. Each actor is constructed independently from its
own rectangular core and one-cell halo, plus a common metadata contract.
The contract contains global grid identity/offsets, unique core ownership,
declared synthetic input provenance, a protocol/run version and a global
per-source step budget. It contains no stitched observations or accumulation.

1. `g2r_seed()` creates one token for each owned land cell. Halos create none.
   A second seed call is rejected. A token contains its global source ID,
   chronological cell path and D8 codes of completed transitions.
2. `g2r_advance()` observes and advances only inside this actor's core. It uses
   the unchanged reviewed `l1847_trace()` direction decoder. A crossing emits
   an immutable outbox message and stops this actor's processing of that token.
   The source's budget never resets at a tile seam.
3. `g2r_receive()` accepts only the exact message field contract. It verifies
   run/provenance/budget, global identities, ownership, path geometry and every
   path edge covered by its own core/halo observations. In particular, the
   incoming sender pointer is independently checked from the receiver's halo.
   Foreign history outside that halo remains declared sender evidence.
4. The receiver independently observes its owned target, stores an inbox entry
   and produces `OBSERVED_RECEIPT`. It then advances using its own observations.
   It never reads the sender's state, accumulation or numeric contributor count.
   Messages carry source identities, not an additive accumulation scalar.
5. `g2r_confirm()` records an acknowledgement only for an actual sender outbox
   message. Its target observation must match the sender's own halo. It does
   not add any new source contribution.
6. `g2r_collect()` reconciles existing actor ledgers. Every received message
   must match the sender's independently stored outbox, and every confirmed
   receipt must exist in the receiver's independently stored inbox. Merely
   having an available receiving tile never creates a receipt.

The logical message ID binds run, global source, global edge and global step
number. The full contract and payload are also checked, including on replays.
An identical replay returns the original receipt with no additional processing;
a conflicting payload or inconsistent source history is rejected before the
caller receives any changed state. Unknown fields (including arbitrary command
or accumulation fields) are rejected. Receipts are likewise idempotent.
Final membership sets are sorted for deterministic semantic results; inbox
arrival order itself remains an audit fact and is not rewritten.

Independence is tested in a fresh R process given **only one receiver state
and one message**. Its state/receipt match the direct receiver calculation.
The test worker is local synthetic test code, not a new CSC launcher.

These are trusted, local, synthetic actors. Message IDs are not cryptographic
authentication or hashes. The protocol does not authenticate a hostile sender,
independently re-observe foreign terrain outside a halo, implement a network
broker, durable transactions, concurrent writers or an exactly-once transport.
It demonstrates idempotent processing under explicit in-memory/RDS checkpoints.

## Source balance and unresolved evidence

Local membership at land cell v is the union of source IDs whose own observed
token path actually reached v. It includes v's own unit. A common downstream
edge or a repeated message never creates a copy of an upstream source.
For fully observed acyclic paths this represents the familiar local relation
`A(v) = 1 + sum(A(parent))`; censored paths supply observed contributions only.

The final source ledger partitions each available owned source once:

```
owned source units = first-water source units + unresolved source units
approved physical exports = 0
```

Missing neighbours remain `MISSING_NEIGHBOUR_TILE`, and undelivered messages
to available actors remain `PENDING_DELIVERY`. Lost acknowledgements are
reported separately as unconfirmed transport entries, even if the receiver
already observed a later endpoint. Retrying the stored message returns its
original receipt. A missing neighbour can later join with its own seeds;
existing owners are not reseeded. Missing tiles' land classifications and
source-unit counts are not guessed from halos.

`STEP_LIMIT`, `CYCLE`, `NO_DATA`, missing/invalid pointers, invalid water
classes and domain exits remain explicit unresolved endpoints. A cycle's
observed memberships remain auditable, while its recurrence-based local A
and area are NA. NoData validity is distinct from a land cell's NA water class.
An incomplete required halo is an invalid actor input, not a successful read.

External import remains `UNKNOWN`, and total catchment counts are always NA.
No positive external-import or whole-catchment contract is implemented here.
Water contributes no land source. First contacts preserve observed water class
and valid lake IDs; no unique river/line recipient IDs are invented. A water
cell's outgoing pointer has no effect on first contact. A receipt or a first
contact is neither a lake outlet decision nor hydrological acceptance.

4 ha = 40,000 m² = 10,000 cells remains metadata only. No smaller route or
contact is filtered, and neither accumulation nor a burned connection proves
that a real ditch or small waterbody exists.

## Independent reference and observed tests

`tests/oracle.R` follows fixture **explicit successor IDs** and builds source
sets/terminal partitions and crossing tuples. It does not call this protocol,
the accumulation implementation, any route/D8 decoder or tile ownership helper.
Expected ownership is separately computed from fixture rectangle cuts. The
actors' results are compared directly with this independent whole-fixture
reference, not with a centrally stitched invocation of the same implementation.

The principal example has 27 positions and 11 land sources in three cores
(4/4/3 owned source units). All 11 reach the same synthetic water contact:
44 m² of **observed local** source area. Crossings carry 4 and then 8 source
identities. Those 12 transit memberships represent 8 distinct travelling
sources, not 12 new source units. At budget 2, the first sender has 4 observed
contributors but only 2 tokens actually cross; no other trace lends them steps.

The final targeted suite on 21 October 2026 (R 4.5.0) passed:

- **12 cases / 2,293 assertions.** Two/three cores, budgets 2/32 and FIFO,
  reverse and seeded shuffled order: 12 oracle comparisons with replays.
- Fresh-process independent reception; conflicting fields, stale context,
  wrong directions/owners, inconsistent observations and fabricated receipts.
- Duplicate message/receipt idempotence, missing neighbour, lost delivery,
  lost acknowledgement, checkpoint resume and later neighbour arrival.
- Cross-tile cycles, zero/NA/invalid pointers, NoData, invalid water class,
  domain exits, first contacts in classes 1/2/3, empty inputs and invalid halos.
- Independently exported sender and receiver audit tables agree by identity.

Final full-suite wall time: **1.9807 s**. Peak direct-child RSS: **65.250 MiB**;
sampled combined process-group RSS including the receiver worker:
**130.898 MiB**. These are measurements of this small suite, not scalability
estimates or CSC performance. No 1,000-cell or larger test was run in 02G.2.
The earlier broad campaigns were not repeated.

Two initial suite failures are retained: arrival-order-dependent ordering of
membership vectors, then NULL-versus-empty source inventory handling. Sorting
the final membership representation and preserving typed empty products fixed
them; no source counts, expected topology or acceptance criteria were relaxed.
Three subsequent suite attempts passed, including the final expanded suite.
There was no actual timeout or memory stop.

`results.json` / `results.csv` retain all attempts, source SHA256 snapshots,
exit states, timings, RSS and normalized-log digests. Raw pre-normalization
digests are recorded too; only normalized log bytes are archived.
`example_sent.csv` comes from outboxes; `example_received.csv` comes from
independently stored inbox receipts; `example_source_ledger.csv` is reconciled.
All are synthetic, not previously observed CSC data.

Run with Base R and Python's standard library:

```sh
MM_RSCRIPT=Rscript python3 -B diagnostics/02g_independent_tile_receipts/tests/run_tests.py
```

The runner reuses the unchanged resource supervisor: 120 s per suite,
1,536 MiB address space per child, 1,792 MiB sampled group RSS and a persisted
1,200 s campaign deadline. Zero cases/assertions or a missing RESULT fails.
For a later campaign, retain committed evidence and use a disposable checkout
where only this directory's generated results/logs/example CSVs are removed.
The Base R protocol itself does not read or write files.

## Before any later CSC experiment

Separate review and authorization are still required. First establish a bounded
real-cell observation/provenance contract (exact commit/input identities, common
grid and mask semantics, unique source/core ownership, explicit missing data
and global step budget). Keep the existing LOW 121-cell window and
14-receiver/56-value reading limits unchanged. No new real read is proposed
or implemented by this delivery.

A real multi-worker system additionally needs authenticated serialized messages,
validated payload sizes/versioning, transactional checkpoint/outbox/inbox
storage, crash/restart and concurrency semantics, explicit receipt-delivery
failures, resource measurements and a separately reviewed external-import
contract. Foreign history requires appropriate evidence; a local receipt does
not verify it. Independent real observation and scientific review remain
necessary before interpreting paths as ditches or accepting hydrology.

`hydrological_validation=NOT_ASSESSED`
`channel_interpretation=NOT_ASSESSED`
`MODERATE=REVIEW_REQUIRED`
`NATIONAL=LOCKED`
