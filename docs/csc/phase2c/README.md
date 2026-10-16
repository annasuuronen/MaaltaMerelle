# MaaltaMerelle – vaihe 2C: projektin oman palvelun raporttikuittaus (offline)

**Tila: prototyyppi ja synteettiset GitHub Actions -testit, ei CSC-käyttöönotto.**

Tämä vaihe rakentaa automaation seuraavan rajapinnan ilman käyttäjän copy/pastea:
projektin *itsensä hallitsema* Roihu-kerääjä voi myöhemmin muodostaa
pienraporttien metatietokuitin; tämä Python-kirjasto tarkistaa kuitin
rakenteen, projektin isäntäpalvelun HMACin ja kertakäyttötunnisteen.
CSC-kerääjää, tunnuksia tai tiedostosiirtoa **ei ole** toteutettu.

## Toteutus

- `automation/csc/phase2c/receipts.py`: strict metadata receipt verifier,
  no network, SSH, FirecREST calls, local report reads, subprocesses or
  Slurm submission.
- `automation/csc/tests/test_phase2c.py`: fully synthetic integration
  tests, automatically discovered by the existing `CSC preflight` PR job.
- Receipt accepts only ten fixed candidates from phase 2B, operation
  `INVENTORY_LOCAL_REPORTS`, immutable host-pinned collector SHA, exact
  root ID/path, UTC observation time (maximum one hour old), 5 MiB/file
  and 25 MiB/package.
- Each entry may be `AVAILABLE`, `MISSING` or `UNREADABLE`. No
  technical `PASS`, unknown paths, wildcard, raster or data fields accepted.
- The host must inject a secret key of at least 32 bytes. HMAC-SHA256
  is calculated over a domain-separated canonical UTF-8 JSON receipt;
  the secret is never read from CI, a manifest, environment variables,
  ChatGPT, Codex, GitHub, or a command-line argument by this module.
- The host must provision an **owner-only, existing SQLite ledger in
  an owner-only directory**. `BEGIN IMMEDIATE` + unique request IDs
  reject duplicate receipts even with multiple concurrent consumers.
- The result only exposes status counts, total available bytes, and
  explicit `NOT_GRANTED` human/scientific approval statuses.
  It contains no report content or per-file output.
- Only 21 new tests plus prior tests run in GitHub Actions, using
  a **synthetic test key** and a temporary private SQLite file.

## Security boundaries

A correct HMAC authenticates the *host message*, not a CSC dataset,
human approval, authorization to export data, or scientific validity.
Receipt acceptance is only a future host-side metadata intake operation.
It is not a production ready approval system.

The SQLite ledger prototype **does not defend against** malicious local
filesystem replacement during open, privileged host compromise, backup
rollback or loss of the signing key. Key provisioning/rotation, authentic
CSC observations, trusted policy issuer, durable approval audit, secure
interprocess startup/shutdown and authenticated report publication still
require separate development and security review on the project-controlled
machine. The SQLite database must not be placed on a shared or untrusted
filesystem without a reviewed locking and integrity design.

Never store CSC access tokens in hosted Codex/ChatGPT agents. CSC's rules
allow agents on the user's own controlled workstation; robot accounts
may be requested only by the CSC project manager or vice manager.
Robot accounts use FirecREST rather than Roihu SSH.

Sources:
- https://docs.csc.fi/computing/usage-policy/
- https://docs.csc.fi/computing/firecrest/connecting/
- https://docs.csc.fi/accounts/how-to-create-new-user-account/

No CSC queries, data export or Slurm runs occur in this phase. Neither
the 52 MODERATE lakes nor NATIONAL change state:
`REVIEW_REQUIRED`, `LOCKED`. The 9/10 manual inventory remains
user-provided CSC evidence, separate from synthetic CI fixtures.

## Next engineering milestone

Implement a *project-owned* authenticated executor/collector with narrowly
defined read-only FirecREST endpoints, without remotely executable commands,
and review its security and CSC account permissions before any live call.
Only a separately authorized, redacted, non-sensitive summary may be
published to GitHub. In particular, do not put the HMAC key or any CSC
credential in GitHub Actions or third-party hosted agents.
