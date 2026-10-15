All files in this directory are **synthetic test fixtures**. They are not CSC
logs, scientific evidence, an approval record or an instruction to submit work.
The job ID, scheduler completion, D8 PASS and 52-lake diagnostic in
`synthetic_report.json` exercise independent fields of the contract. They do not
verify a real CSC job or the hydrological correctness of D8 routing.

`synthetic-qa.csv` is a deliberately small byte-level checksum fixture (48 bytes).
Its SHA256 is
`d1465212fb7b623ba6ac9216f33bc68ef401e93f84c40d40e7a3ec57bbf34811`.
The manifest and report bind that checksum to `reports/synthetic-qa.csv` beneath
the named `CSC_HYDRO_4BBF22B` root. Tests copy these bytes into a temporary local
bundle; they never read the real `/scratch` tree or connect to CSC.

The report's stored semantic fingerprint binds the synthetic manifest. Tests
also calculate it at runtime when mutating manifests. Even a contract-valid
fixture always returns `authorization=NOT_GRANTED` and retains scientific review.
