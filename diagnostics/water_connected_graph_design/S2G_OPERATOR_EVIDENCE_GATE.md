# S2G – kahden erillisen Roihu-evidenssitarkistuksen hyväksyntäportti

**Tila:** OPERATOR_PREPARED / NOT_RUN / READ_ONLY. Tämä on dokumentaatio, ei ajo eikä lupa tuotanto-D8:n käsittelyyn. Pohjana S2F draft PR #61 / commit 477c5b13d5714d618c9c9de88f5f80290b53d994. Ruutujen ja lähteiden tieteelliset lukot säilyvät: NATIONAL=LOCKED, MODERATE=REVIEW_REQUIRED, hydrological_validation=NOT_ASSESSED, channel_interpretation=NOT_ASSESSED, routing_authorized=false.

## 1. Yhden tavoitteen kaksi erillistä tarkistusta

| Portti | Koodiversio | Sallittu operaatio | Odotettu tulos | Mitä tulos ei todista |
|---|---|---|---|---|
| A – R-yhteensopivuus | S2F 477c5b13d5714d618c9c9de88f5f80290b53d994 | Olemassa oleva 75 tapauksen Base-R-synteettinen havainnointitesti alkuperäisellä 02F-funktiolla | R 4.6.1:llä 75 PASS ja 0 FAIL, vain jos testi todella läpäisee | Ei oikeaa rasterinlukua, D8-version autentikointia tai validointia |
| B – LOW-metatiedot | S2C 7324f2c22b3151fffe7b172617bde4d0ef6ee821 | Olemassa olevan S2C-scriptin viisi pientä CSV:tä ja gdalinfo-metadata kolmesta nimetyistä alkuperäisistä TIFF-tiedostoista | **Exit 2 / STOP myös täydellä metadatalla**, historiallinen runtime-lähdeketju NOT_ASSESSED | Ei alkuperäisen 02F:n tosiasiallisesti käyttämää D8:aa eikä yhtään D8-soluarvoa |

Molemmat ohjelmat on jo toteutettu, eikä niitä muokata tässä. Portit ovat riippumattomia; portin A suorittaminen ei automaattisesti käynnistä porttia B eikä minkään muun vaiheen ajoa. S2C:n tekninen metadatastatus PASS on täysin eri asia kuin hydrologinen hyväksyntä; exit 2 ei yksin todista metadatan täydellisyyttä.

## 2. Suoritusympäristö ja erilliset checkoutit

Käytä **kahta eri, etukäteen olemassa olevaa, paikallisesti katselmoitua ja puhdasta Git-checkoutia**. Alla olevat viitteelliset polut `$HOME/MaaltaMerelle_S2F_PINNED` ja `$HOME/MaaltaMerelle_S2C_PINNED` ovat oletusarvoja komenteille, eivät väite olemassa olevista hakemistoista. Jos hakemistoa ei ole, pysähdy: älä anna komennon kloonata, hakea, päivittää, vaihtaa haaraa tai luoda uutta checkoutia. Käyttäjä hyväksyy checkoutin valmistelun erikseen tarvittaessa. Työhakemistojen tulee olla toisistaan ja CSC:n lähdekansioista erilliset.

`git rev-parse HEAD` on **täsmällinen lukitus**. `GIT_OPTIONAL_LOCKS=0 git status --porcelain --untracked-files=all` varmistaa, että checkout on puhdas. Molemmat käskyt käyttävät vain lähtötilan tarkistusta ja jo olemassa olevia skriptejä. Kummassakaan ei käytetä `R/00_pipeline_config.R`-tiedoston `source()`-kutsua, koko hydrologisen putken ajuria tai aktiivista `02_build_baseline_hydrology.R`-koodia.

### Gate A: vain synteettiset R 4.6.1 -testit

Suoritetaan erikseen vain käyttäjän hyväksynnän jälkeen. Skripti lataa `R/02F_water_connected_route_diagnostics.R`-tiedoston ja S2F:n syntettisen havainnoijan, mutta ei CSC:n alkuperäisiä TIFF/CSV-arvoja.

```bash
( set -euo pipefail; C="$HOME/MaaltaMerelle_S2F_PINNED"; PIN=477c5b13d5714d618c9c9de88f5f80290b53d994; trap 'echo "=== TULOKSET LOPPUVAT ==="' EXIT; echo "=== TULOKSET ALKAVAT ==="; test -d "$C/.git" || { echo "STOP: S2F_CHECKOUT_MISSING"; exit 1; }; test "$(git -C "$C" rev-parse --verify HEAD)" = "$PIN" || { echo "STOP: S2F_HEAD_MISMATCH"; exit 1; }; test -z "$(GIT_OPTIONAL_LOCKS=0 git -C "$C" status --porcelain --untracked-files=all)" || { echo "STOP: S2F_WORKTREE_CHANGED"; exit 1; }; module load r-env/461; cd "$C"; timeout --signal=TERM --kill-after=2s 10s Rscript --vanilla -e 'stopifnot(identical(as.character(getRversion()),"4.6.1"))'; echo "S2F_PIN=$PIN"; timeout --signal=TERM --kill-after=2s 45s Rscript --vanilla diagnostics/water_connected_graph_design/test_s2f_synthetic_02f_observer.R )
```

Tuloksen arviointi: tarkista `SUMMARY PASS=75 FAIL=0 NOT_RUN=0 NAMED_TESTS=75 R=4.6.1` sekä exit=0; jos lopputulos eroaa, merkitse GATE_A=STOP. Pelkkä viimeinen yhteenvetolause ilman ehjää outputia tai oikeaa commitia ei riitä. `Rscript`- ja `timeout`-poikkeamat ovat STOP eivätkä synteettisen algoritmin tieteellisiä FAIL-tuloksia.

### Gate A (vaihtoehto): poimi vain kolme lukittua testitiedostoa paikallisesta Git-objektista

Tämä vaihtoehto poistaa tarvetta erilliselle S2F-checkoutille. Käynnistä komento **minkä tahansa ennestään olemassa olevan paikallisen MaaltaMerelle-Git-checkoutin sisältä**, jos sillä on täsmällinen S2F-commit paikallisessa objektitietokannassa. Nykyisen checkoutin HEAD/työpuu voi olla eri: `git archive` poimii **vain** commitin 477c5b1... kolme nimettyä tiedostoa; se ei checkouttaa, hae verkosta, muuta nykyisiä Git-refejä tai lue CSC-aineistoja. Jos objektia ei löydy, STOP eikä automaattista `git fetch`-toimintoa. Vain erikseen luotu `mm-s2g-a-*`-tilapäishakemisto poistetaan. Git-arkistointimekanismi on tarkistettu pienellä paikallisella testirepositoriolla ja Rscript-korvikkeella; varsinaista R 4.6.1 -tapausta ei ole suoritettu.

```bash
( set -euo pipefail; umask 077; PIN=477c5b13d5714d618c9c9de88f5f80290b53d994; REPO="$(git rev-parse --show-toplevel)" || exit 1; git -C "$REPO" cat-file -e "${PIN}^{commit}" 2>/dev/null || { echo "STOP: S2F_COMMIT_OBJECT_NOT_LOCAL"; exit 1; }; module load r-env/461; command -v timeout >/dev/null; timeout 10s Rscript --vanilla -e 'stopifnot(identical(as.character(getRversion()),"4.6.1"))'; T="$(mktemp -d "${TMPDIR:-/tmp}/mm-s2g-a-XXXXXXXX")"; trap 'if test -n "${T:-}" && test -d "$T"; then rm -rf -- "$T"; fi' EXIT; git -C "$REPO" archive --format=tar "$PIN" -- R/02F_water_connected_route_diagnostics.R diagnostics/water_connected_graph_design/s2f_synthetic_02f_observer.R diagnostics/water_connected_graph_design/test_s2f_synthetic_02f_observer.R | tar -xf - -C "$T"; cd "$T"; echo "=== TULOKSET ALKAVAT ==="; set +e; OUT="$(timeout --signal=TERM --kill-after=2s 45s Rscript --vanilla diagnostics/water_connected_graph_design/test_s2f_synthetic_02f_observer.R 2>&1)"; RC=$?; set -e; printf '%s\n' "$OUT"; echo "S2F_EXIT=$RC S2F_SOURCE_COMMIT=$PIN"; echo "=== TULOKSET LOPPUVAT ==="; test "$RC" -eq 0; grep -Fqx "SUMMARY PASS=75 FAIL=0 NOT_RUN=0 NAMED_TESTS=75 R=4.6.1" <<< "$OUT" )
```

Jos tulosteessa ei ole täsmälleen 75 PASSia, R 4.6.1 ja poistumiskoodi 0, Gate A on STOP. Komentoa ei saa suorittaa suoraan satunnaisesti nimetystä Git-tietokannasta: tarkista repositorion kanoninen alkuperä ennen käyttäjän hyväksymää ajoa. Kuten muu S2G, tämä on vain *operaattorille valmisteltu, vielä NOT_RUN* synteettinen testi, ei myöhempien ajovaiheiden automaattinen hyväksyntä.
### Gate B: vain alkuperäisen LOW:n metadata ja pieni CSV

Tämä **on erillinen checkout ja erillinen käyttäjän päätös**. S2C:n CLI tulostaa jo itse yhden `=== TULOKSET ALKAVAT ===` / `=== TULOKSET LOPPUVAT ===` -parin; älä lisää komennossa toista merkintäparia. S2C sisältää rajatut JSON-gdalinfo-kutsut ilman rasterin arvolukua; se lukee vain ennalta määrätyt viisi pientä CSV-tiedostoa `01_inputs`- ja `02_baseline`-hakemistoista.

```bash
( set -euo pipefail; C="$HOME/MaaltaMerelle_S2C_PINNED"; PIN=7324f2c22b3151fffe7b172617bde4d0ef6ee821; test -d "$C/.git" || { echo "STOP: S2C_CHECKOUT_MISSING"; exit 1; }; test "$(git -C "$C" rev-parse --verify HEAD)" = "$PIN" || { echo "STOP: S2C_HEAD_MISMATCH"; exit 1; }; test -z "$(GIT_OPTIONAL_LOCKS=0 git -C "$C" status --porcelain --untracked-files=all)" || { echo "STOP: S2C_WORKTREE_CHANGED"; exit 1; }; module load gdal/3.12.2; cd "$C"; echo "S2C_PIN=$PIN"; set +e; PYTHONDONTWRITEBYTECODE=1 timeout --signal=TERM --kill-after=2s 90s python3 -B diagnostics/water_connected_graph_design/s2c_original_source_preflight.py; RC=$?; set -e; echo "S2C_PROCESS_EXIT=$RC"; if test "$RC" -eq 2; then echo "S2C_EXPECTED_STOP_EXIT=CONFIRMED"; else echo "STOP: UNEXPECTED_S2C_EXIT"; exit 1; fi )
```

**Exit=2 tarkoittaa tarkoituksellista ei-hyväksyntää** riippumatta siitä, saatiinko tarkistettua kaikki metadata. Tutki erikseen JSON:n `metadata_status`, vaihekohtaiset PASS/STOP/NOT_RUN-arvot ja `stop_reason`. Vain silloin, kun rasteri- ja CSV-metadata täsmäävät, voidaan raportoida `metadata_status=PASS`; sekään ei muuta `RUNTIME_INPUT_LINEAGE=NOT_ASSESSED` eikä `SOURCE_AUTHENTICATION=NOT_ASSESSED`. Jos skripti palauttaa muuta kuin 2, se ei ole odotettu tulos. Tästä ei saa jatkaa automaattisesti S2B:n alkuperäistä dataa lukevaksi toteutukseksi.

### Gate B: Roihun Python-versio ja korjaus

Roihun operaattorin ensimmäinen B-suoritus 2026-10-23 palautti `S2C_EXIT=1`,
`S2C_UNEXPECTED_EXIT=STOP`, koska ohjelman tietoluokan `Raster` tyyppimerkintä
`nodata: int | float | str` aiheutti `TypeError: unsupported operand type(s) for |: 'type' and 'type'`.
Tämä on Python 3.9 -yhteensopivuusvirhe **ohjelmaa tuotaessa**, ei metadata-analyysin tulos
eikä suunniteltu `STOP/2`. CSC dokumentoi järjestelmän Python 3.9:n Roihussa.
S2C-skriptin lähdekoodia ei pidä muuttaa vain kiertääkseen tämän; valitse olemassa
oleva `python-geo`-moduuli, josta CSC:n 2026-dokumentaation mukaan löytyvät Python 3.14.5
ja `gdalinfo` 3.12.2. Tarkista versiot paikallisesta todellisesta ympäristöstä ennen
metadatan lukemista. Moduulilataukset tehdään vain subshellissa.

```bash
( set -euo pipefail; module purge; module load python-geo; echo '=== TULOKSET ALKAVAT ==='; python3 --version; gdalinfo --version; python3 -c 'import sys; assert sys.version_info >= (3,10)'; echo '=== TULOKSET LOPPUVAT ===' )
```

Jos Python ei ole >= 3.10 tai GDAL ei ole 3.12.2, merkitse GATE_B=STOP eikä jatka.
Mahdollinen uusintasuoritus voidaan tehdä alkuperäiseen commit-versioon poimitulla
S2C:n yhdellä skriptillä, `GIT_NO_LAZY_FETCH=1` ja ilman lähdetietojen kirjoittamista.
Tarkista ennen kutsua komennon `gdalinfo --version` todellinen merkkijono ja säilytä
erikseen `metadata_status` ja ohjelman exit=2. Alkuperäisen historiallisen 02F:n
lähdeketju pysyy NOT_ASSESSED, vaikka kaikki nykyiset metatiedot täsmäisivät.
## 3. Ei-automaattinen päätöstaulukko

| Gate A | Gate B | Sallittu seuraava päätelmä |
|---|---|---|
| NOT_RUN | NOT_RUN | Ei uusia ympäristö-/LOW-havaintoja |
| PASS | NOT_RUN | Alkuperäisen 02F:n synteettisen havainnoinnin R 4.6.1 -yhteensopivuus; historiallinen source-linkki tuntematon |
| PASS | metadata PASS, overall STOP/2 | LOW-tiedostojen nykyinen metadata on yhteensopivaa tässä rajatussa tarkistuksessa, mutta alkuperäinen 02F-tuottajalinkki todistamatta; ei D8-arvolupaa |
| PASS | metadata STOP/2 | R-yhteensopivuustesti läpäisty mutta nykyiset tiedosto- tai skeemaehdot eivät täyty; dokumentoi lähdekohtainen STOP |
| STOP | mikä tahansa | Älä nosta R-observeria valmiiksi Roihuun tai väitä jatkoajon pariteettia |
| mikä tahansa | muu exit | Odottamaton metatietotyökalun suoritus / preflight-keskeytys, STOP; ei piilokorjausta |

Historian keskeinen puute: 01_input_manifest.csv ei yksilöi luotettavasti nimenomaista 02F:n käyttämää `ptr_land_water`-objektia tai versionvaihtoa. `OVERWRITE=FALSE`, WBT:n väliaikaisesta rasterista pysyvään muunnos ja mahdollinen `terra`-olion laiska tiedostoluku estävät takautuvan hyväksynnän pelkän nykyisen tiedoston SHA:n perusteella.

## 4. Evidenssiraja ja tavoiteltu myöhempi toistettavuus

Mahdollinen tuleva hallittu **uusi** koeajo tarvitsee erikseen hyväksytyn run-/attempt-ID:n, tarkat syötteiden versiot/immutabilityn, suoritetun R/Whitebox-koodin tunnisteet, tarkoituksenmukaisen riippumattoman kuluttajarajapinnan havainnoinnin, output-manifestin sekä riippumattoman todennuksen. Nykyiset S2D/S2E/S2F eivät toteuta tätä kokonaisuutta.

Historiallista LOW:n 02F-d8-ketjua ei voida kutsua varmennetuksi sillä perusteella, että uuden ajon koodi tai metadata näyttää samalta. Ei vanhan ajon tulosten kirjoittamista uudelleen, ei toistuvia 36 miljoonan solun käsittelyjä eikä uutta kertymä- tai kansallista ajoa ilman erillistä tieteellistä päätöstä.

**Tämän dokumentin toteuma:** komennot on valmisteltu olemassa olevan lähdekoodin perusteella, **niitä ei ole suoritettu**. GATE_A=NOT_RUN, GATE_B=NOT_RUN, TRUE_02F_CONTINUITY=NOT_ASSESSED, SOURCE_AUTHENTICATION=NOT_ASSESSED. Tämä PR on dokumentaatio-only ja pysyy draftina.
