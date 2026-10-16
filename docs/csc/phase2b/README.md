# CSC phase 2B: synthetic-only adapter and automatic PR testing

**Status: offline simulation; NOT a CSC connection or deployment.**

GitHub PR checks already run `automation/csc/tests/run_tests.py`. The
`test_phase2b.py` tests now run automatically with the existing preflight.
They do not need CSC login, credentials, copy/paste, Slurm or new workflows.

The adapter `automation/csc/phase2b/synthetic_adapter.py` deliberately has
**no networking, filesystem, subprocess, credentials or transfer functionality**.
The only accepted provider is the exact `SyntheticMetadataProvider` type.
It simulates exactly the 10 phase 2A candidate paths, enforces the existing
independently injected SHA256 approval binding, approved operation, per-file
and total size caps, and one-shot *synthetic* approval consumption. All returned
observations are prominently labeled `SYNTHETIC_ONLY` and
`SYNTHETIC_FIXTURE_ONLY_NOT_CSC`. A synthetic PASS never means a real CSC
file was checked. The source candidate inventory stays unchanged.

The synthetic example uses **9 AVAILABLE and 1 MISSING** as test data.
A user's separately supplied Roihu-terminal metadata observation also
reported nine available paths and one missing path, but that real observation
is **not** a reproducible CI fixture, approval, or proof of report provenance.
No actual reported CSC sizes, report contents, hashes or credentials are
committed. No real report is downloaded or interpreted by this adapter.

## Why not connect GitHub Actions directly to Roihu today?

CSC's Roihu usage policy specifically forbids giving CSC credentials to
third-party AI agents or opening Roihu to them as a remote command interface.
The FirecREST API exists, but its bearer tokens confer meaningful file and job
privileges and must never be pasted into ChatGPT, Codex prompts or PR logs.

References:
- https://docs.csc.fi/computing/usage-policy/
- https://docs.csc.fi/computing/firecrest/connecting/
- https://docs.csc.fi/accounts/how-to-create-new-user-account/

A future **project-controlled**, audited execution service may connect using
the CSC-approved robot-account procedure and an authenticated, durable,
atomic approval/replay ledger. The service must not execute arbitrary
user-provided commands, expose secrets to hosted agents, or infer that a
GitHub workflow's green badge authorizes CSC access.

## Next engineering gates (not implemented)

1. Define a project-controlled trusted execution host, credential ownership,
   access constraints, allowed API endpoints, security policy and incident
   handling. Verify CSC's robot-account permission and access requirements.
2. Implement and security-review a durable authenticated approval and
   replay-prevention store. Phase 2A's in-memory `TrustStore` is only a test
   double and cannot be a production authority.
3. Confirm read-only FirecREST metadata endpoint behavior and path-symlink
   handling before enabling ten exact-path metadata checks. All service
   responses are untrusted; reject nonregular files, redirects, extra paths
   and oversized responses. Do not use broad directory traversal.
4. Add a separately approved, redacted reporting channel back to GitHub.
   No user identity details, secrets, raw private data, raster binaries or
   unvetted contents may be posted.
5. Keep report transfer and Slurm submit entirely out of scope pending
   separately defined permissions and controls.

`MODERATE` 52 lakes remain `REVIEW_REQUIRED`. `NATIONAL` is locked.
Finding or checking files does not establish scientific acceptance.
