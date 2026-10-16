# LOW — RANTA10-rasteroinnin `touches=TRUE` -säännön tarkistus

GitHubin alkuperäisessä, CSC:n validointia vastaavassa commitissa
`4bbf22bb39181c8a4c27ebc3e2769766043115b8` on
`R/00A_prepare_validation_fixture.R`: `terra::rasterize(vect(lakes), template,
field = objectid_field, background = NA, touches = TRUE)`.
`R/01_prepare_hydrology_inputs.R` **ei rasteroi uudelleen** vaan käyttää
RANTA10-rastereita kanonisina syötteinä (erityisesti järven korkeusrastersubst).

Alkuperäisen LOW-rasterin valmistelutapaa ei oletettu pelkän koodin perusteella:
Roihun `00A_validation_fixture_QA.csv`-kuitti raportoi oikeasti
**`SOURCE_00A_RECEIPT_RASTERIZATION_TOUCHES: TRUE`**. Kuitti ja erillinen
olemassa olevan järvirasterin vertailu vahvistavat tämän tutkituissa järvissä.

## Rajattu, vain lukeva kokeilu

Vain järvet 1847 ja 1898. Kummankin RANTA10-vektoripolygonista tehdään
olemassa olevan LOW-rasterin ruudukolle kaksi **vain muistissa**
tapahtuvaa rasterointia: `touches=TRUE` ja `touches=FALSE`.
Niitä verrataan sekä alkuperäisen järvirasterin **kaikkiin paikallisen
ikkunan kyseisen järven soluihin** että todellisiin D8-järvi→maa-
osoitinreunoihin. Aiempien 198/197/88 ja 189/55/26-laskureiden
täsmääminen vaaditaan fail-closed. Tämä ei ole koko RANTA10-tason
kaikkien järvien uudelleenrasterointi eikä byte-by-byte-validointi.

MML 2025 `jarvi` -tasolta haetaan geometrioita samasta pienestä alueesta.
Valitun lähipolygonin identiteettiä arvioidaan **todellisen
pinta-alaleikkauksen** avulla: leikkauspinta-ala sekä leikkauksen
osuus kummastakin polygonista ja IoU. Lähin polygoni ei silti
välttämättä vastaa semanttisesti samaa järveä ilman muuta näyttöä.

## Todellinen CSC Roihu -ajo — PASS, 16.10.2026

`PASS: touch-vs-center replay, original mask comparison, fail-closed cases`
ja
`PASS: LOW 1847/1898 RANTA10 touches-vs-centers replay and MML geometry QA`;
`========== LOW TOUCH RULE REVIEW DONE ==========`.

| Mittari | Järvi 1847 | Järvi 1898 |
| --- | ---: | ---: |
| Paikallisen tarkastusikkunan rasterisoluja | 65670 | 8235 |
| Alkuperäisen järvi-ID-rasterin soluja | 24344 | 2059 |
| `touches=TRUE` -replay-pikseleitä | **24344** | **2059** |
| `touches=FALSE` (keskipiste) -pikseleitä | 23619 | 1926 |
| Alkuperäisen rasterin soluja, joita järvipolygoni ei kosketa | **0** | **0** |
| Polygonin koskettamia soluja, jotka eivät kuulu alkuperäiseen rasteriin | **0** | **0** |
| Rasterin soluja, joiden keskipiste ei ole polygonissa | 725 | 133 |
| D8-järvi→maa-lähtöreunoja | 198 | 189 |
| Lähtösolukeskuksia RANTA10-vektorissa | 92 | 91 |
| Lähtösolujen ruutuja, jotka koskettavat RANTA10-vektoria | **198** | **189** |
| Maavastaanottajien ruutuja, jotka koskettavat RANTA10-vektoria | **0** | **0** |
| Erillisiä välittömiä D8=0-vastaanottajia | 88 | 26 |
| D8=0-vastaanottajien ruutuja, jotka koskettavat RANTA10-vektoria | **0** | **0** |
| Tutkitun MML-lähipolygonin ja RANTA10:n leikkauspinta-ala, m² | 87583.41 | 4372.146 |
| Leikkauksen osuus RANTA10-polygonista | **92.754 %** | 56.811 % |
| Leikkauksen osuus MML-polygonista | **91.288 %** | 97.784 % |
| Polygonien IoU | **0.852107** | **0.560888** |

**Tulkinta:** näiden kahden järven paikallisessa vertailussa alkuperäinen
RANTA10-järvirasteri on täysin yhteensopiva
`rasterize(...,touches=TRUE)`-säännön kanssa. Lähdesolujen suuri
keskipiste-ulkopuolisuus on tämän rasterointisäännön odotettu vaikutus,
ei yksin havainto väärästä rasteroinnista.

**Ristiriita jää MML-rajaukseen:** aikaisempi erillinen 2025 MML-
polygoniin perustuva QA osoitti, että järvellä 1847
**88/88** nollavastaanottajasolun keskipistettä kuuluu MML-`jarvi`-
polygoniin, mutta yhdenkään vastaanottajan ruutu ei kosketa
RANTA10-järvipolygonia. Kontrollijärvellä 1898
MML-`jarvi`-polygoniin kuuluu **0/26** erillistä
nollavastaanottajaa. Tämä on geometrisesti paikallistettu
aineistorajaero, ei todiste kumpaankaan aineistoon sisältyvästä
virheestä tai oikeasta hydrologisesta purkupaikasta.

MML:n vuoden 2025 ja RANTA10:n lähde-/päivitysajankohtien,
rannan peittoerojen ja riippumattoman purkureitin tarkastelu on
jäljellä ennen malliratkaisua.

## Toistaminen lukitussa CSC LOW -ympäristössä

```bash
D=diagnostics/low_d8_scope
B=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000/02_baseline
module load r-env/461
Rscript --vanilla "$D/test_low_touch_replay.R" &&
  Rscript --vanilla "$D/run_low_touch_replay.R" "$B"
```

Riippuvuus: tämän saman PR:n `lake_to_land_d8_core.R`.
Rastijärjestelmän lukeminen: enintään 500 000 solua per
paikallinen ikkuna, kolme rasteria, ei Slurmia eikä rasterien
kirjoittamista.

**NATIONAL LOCKED; MODERATE REVIEW_REQUIRED;
SCIENTIFIC_STATUS: REVIEW_REQUIRED.**
Ei DEM-, D8-, WATER_STORAGE-, syöterasteri- eikä outlet-muutoksia.
