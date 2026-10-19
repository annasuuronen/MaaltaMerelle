# MaaltaMerelle: MODERATE 49 sisäjärven rajattu Slurm-eräajo (19.10.2026)

Tämä on **uusi**, RStudioa tarvitsematon tutkimusajon käynnistin.
Edellisiä GitHub-tiedostoja, CSC:n tutkimusrastereita tai valmiita tuloksia
ei muuteta. Tämä ohje ja sen synteettinen testiketju **eivät ole todellisen
Roihu-eräajon suorituskuitti**.

## Rajaus ja resurssit

- Käynnistys **Roihu-CPU → Tools → Login node shell** -kuoresta, ei RStudiosta.
- Projektitili `project_2004707`, Slurmin `small`-osio, yksi solmu,
  yksi CPU-ydin, **32 GiB**, enintään **30 minuuttia**.
- Yksi yksityinen `/scratch/project_2004707/pienvedet/mm_mod_probe.XXXXXXXX/`
  -hakemisto per yritys. Siihen sijoittuvat `code/`, `reports/` ja
  `logs/`. **Ei uusia tutkimusraportteja /users/asuurone-kotihakemistoon**.
  Vanhoja ZIP-, TAR-, loki- ja testitiedostoja ei poisteta.
- Alkuperäisen 02A:n, tuotantoreitityksen tai koko 36 miljoonan solun
  Whitebox FillDepressions -täytön uudelleenajo on kielletty.

## Peräkkäiset turvallisuusportit

1. Vaaditaan todella käynnissä olevan Slurm-erätyön numeerinen työnumero,
   oikea laskentaprojekti, `small`-osio, laskentasolmu ja muuttumaton,
   yksityinen **täsmälleen 40-merkkiseen SHA:han pinattu** Git-checkout.
   Puuttuvat/ristiriitaiset tiedot pysäyttävät ajon.
2. Aiempi `scripts/roihu_probe_rstudio.sh --memory-preflight-only` suoritetaan
   **erätyön omassa host-ympäristössä**, ei RStudiossa. Sen Python-tarkistin
   vaatii live-Slurm-vahvistuksen ja riittävän muisti-headroomin.
   Tämä ei avaa R:ää eikä hydrologisia aineistoja. Jos tämä portti ei
   pääty `MEMORY_PREFLIGHT_COMPLETE`-tilaan, ajon seuraavia vaiheita ei tehdä.
3. Ladataan `module load r-env/461` ja tehdään pieni Rscript/terra-saatavuuskoe.
4. Vasta tämän jälkeen käynnistetään olemassa oleva **rajattu read-only**
   `scripts/roihu_probe_bundle.py` -koetin: 49 sisäjärveä, korkeintaan
   250 000 solua/ikkuna ja 4 000 000 yhteensä, 2 000 käyntiä/järvi,
   kahden pääsyötteen SHA256-varmennus, R-lapsiprosessin 2 GiB RLIMIT_AS,
   CPU 120 s/R-vaihe, työbudjetti 900 s ja ulkoinen aikakatkaisu 1080 s.
   R/terra/Apptainer-aliprosessin toimivuutta näillä rajoilla **ei ole vielä
   vahvistettu aidossa Roihu-eräajossa**: epäonnistuessaan pysähdymme,
   emme höllennä rajoja arvaamalla.

Erilliset raportit syntyvät `reports/fill_probe_*/review_bundle.tar.gz`
-polkuun. Muistin tarkistus ja mahdollinen 49 järven koe ovat **kaksi
eri raporttipakettia**. `COMPLETE` tarkoittaa teknisesti kirjattuja
rajattuja havaintoja, **ei** luonnollisen outletin, Whiteboxin alkuperäisen
toiminnan tai hydrologisen jatkuvuuden hyväksyntää.
`PARTIAL/BLOCKED` ei ole PASS.

## Lähetys Login node shellistä

Käytä käyttäjälle erikseen ilmoitettua, GitHubissa tarkistettua SHA:ta;
`MM_PIN` on tässä tarkoituksella paikkamerkki. Älä vaihda sitä
automaattisesti liikkuvaan branch-HEADiin.

```bash
bash -c '
set -euo pipefail
umask 077
MM_PIN=KORVAA_TARKALLA_40_MERKIN_SHA_TUNNUKSELLA
[[ "$MM_PIN" =~ ^[0-9a-f]{40}$ ]] || { echo "Virheellinen commit" >&2; exit 2; }
MM_RUN=$(mktemp -d /scratch/project_2004707/pienvedet/mm_mod_probe.XXXXXXXX)
git clone --quiet --single-branch --branch codex/moderate-02d4-diagnosis \
  https://github.com/annasuuronen/MaaltaMerelle.git "$MM_RUN/code"
git -C "$MM_RUN/code" checkout --quiet --detach "$MM_PIN"
mkdir -m 700 "$MM_RUN/reports" "$MM_RUN/logs"
JOB=$(sbatch --parsable \
  --output="$MM_RUN/logs/slurm-%j.out" \
  --error="$MM_RUN/logs/slurm-%j.err" \
  --export=ALL,MM_EXPECTED_COMMIT="$MM_PIN",MM_CODE_DIR="$MM_RUN/code",MM_REPORT_PARENT="$MM_RUN/reports" \
  "$MM_RUN/code/scripts/roihu_moderate_bounded_batch.sbatch")
printf "JOB_ID=%s\nRUN_DIR=%s\n" "$JOB" "$MM_RUN"
'
```

Tarkista työn tila ilman uutta varausta:

```bash
squeue -u "$USER" -o "%.18i %.9T %.30j %.10M %.4D %R"
```

Lue tuloste `RUN_DIR/logs/slurm-JOBID.out` (ja mahdollinen `.err`).
Tulosta omasta ajosta saadut `JOB_ID`, `RUN_DIR`, `BATCH_STATUS`,
`TECHNICAL_STATUS` sekä viimeinen `REPORT`-polku.
Älä siirrä raakarastereita tai luvanvaraisten aineistojen arvoja GitHubiin.
Pysähtynyttä työtä ei toisteta ilman lokien arviointia.

## Lähteet

- [CSC: Roihun eräajot](https://docs.csc.fi/computing/running/creating-job-scripts-roihu/)
- [CSC: Roihun Slurm-osiot](https://docs.csc.fi/computing/running/batch-job-partitions/)
- [CSC: r-env-eräajo](https://docs.csc.fi/apps/r-env/)
- [MODERATE draft PR #7](https://github.com/annasuuronen/MaaltaMerelle/pull/7)
- `tests/test_roihu_moderate_batch_contract.py`: vain offline-syntaksin,
  resurssirajojen ja porttijärjestyksen tarkistus; ei aitoa Slurm-ajoa.

**MODERATE=REVIEW_REQUIRED; NATIONAL=LOCKED; continuation_authorized=false.**
