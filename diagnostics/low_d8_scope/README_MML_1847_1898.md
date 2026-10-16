# LOW — RANTA10–MML 2025 -rantavyöhykkeen riippumaton vertailu

Kohdejärvi **1847**, kontrollijärvi **1898**. Vain lukeva D8-diagnostiikka
(LOW-ruutu E200000_N6900000), jonka molemmat R-regressiotestit ja varsinainen
rasteri/vektorivertailu **suoritettiin onnistuneesti CSC Roihussa 16.10.2026**.

## Aineistot ja menetelmä

- RANTA10: `lakes`-vektoripolygonit, `ranta10_lake_id.tif`,
  `ranta10_water_class.tif`; käytössä oleva 02-baseline LAND_WATER-D8 ja
  korkeusmallipinnat.
- MML: `MTK-vakavesi_25-04-03.gpkg`, taso **`jarvi`** (2025).
  Vektoripolygonit haetaan RANTA10-järvialueiden rajoitetuista
  40 m -lähiympäristöistä. Kummaltakin järveltä löytyi yksi lähipolygoni.
- Paikalliset rasteri-ikkunat: 1847: **65 670 solua**,
  1898: **8 235 solua**. Yhteismäärät varmistetaan aiempaan,
  riippumattomaan koko LOW:n inventointiin.
- `sf::st_covered_by` luokittelee kutakin todellista D8-osoitinreunaa
  edustavien **lähde- ja vastaanottajasolukeskusten** sijainnin polygonissa.
  Etäisyys lähimpään MML-`jarvi`-rajaan raportoidaan 88 ja 26
  **erilliselle** välittömälle nollavastaanottajalle, ei jokaiselle
  osoitinreunalle itsenäisenä havaintona.

## CSC Roihu: vahvistetut tulokset (16.10.2026)

Molemmat testit:
- `PASS: MML/RANTA10 shoreline center classification, shared receivers, elevations, fail closed`
- `PASS: sf shoreline water/land coverage and nearest-boundary distances`

Todellinen aineisto:
- `PASS: RANTA10/MML TARGETED 1847 AND 1898 EDGE COUNTS RECONCILED`
- `========== SHORELINE VECTOR COMPARISON DONE ==========`

| Mittari | 1847 | 1898 |
| --- | ---: | ---: |
| RANTA10-järvirasterisoluja paikallisessa ikkunassa | 24344 | 2059 |
| Järvi→maa-D8-reunoja | 198 | 189 |
| Välittömät D8=0-reunat | 197 | 55 |
| Erilliset välittömät D8=0-vastaanottajat | 88 | 26 |
| Lähdesolukeskuksia RANTA10-vektorijärvessä | 92 | 91 |
| Lähdesolukeskuksia MML-järvialueella | 191 | 32 |
| RANTA10:n mukaan maalla olevia vastaanottajakeskuksia RANTA10-vektorijärvessä | 0 | 0 |
| RANTA10:n mukaan maalla olevia vastaanottajakeskuksia MML-järvialueella | **198** | **9** |
| Välittömiä zero-reunoja, joiden vastaanottaja MML-järvialueella | **197** | **0** |
| **Erillisiä välittömiä zero-vastaanottajia MML-järvialueella** | **88/88** | **0/26** |
| Nollavastaanottajien mediaanietäisyys MML-rantaan | 4.64851036 m | 9.24794606 m |
| Nollavastaanottajien MML-rantaetäisyys ≤2 m / ≤5 m | 21 / 47 | 3 / 7 |
| Nollavastaanottajien LAND_RAW→LAND_FILL muuttumaton | 88 | 26 |
| Nollavastaanottajien WATER_STORAGE-korkeus noussut | 88 | 26 |
| Järvi LAND_WATER-korkeammalla kuin välitön maavastaanottaja | 198/198 | 189/189 |
| Järvi–maa-korkeuseron mediaani | n. 2 mm | n. 28 mm |
| Järvi–maa-korkeuseron vaihteluväli | n. 1–2 mm | n. 1–93 mm |

## Tulkinta ja seuraava tekninen tarkastus

Järven 1847 kaikki 88 erillistä LAND_WATER-D8=0-vastaanottajaa ovat
**RANTA10-rasterin mukaan maalla mutta MML:n vuoden 2025 järvipolygonin
sisällä**. Kontrollijärvellä 1898 vastaavia nollavastaanottajia on 0/26.
Havainto tukee aineistojen **vesialuemaskien ja geometristen rajojen
yhteensopivuuden** merkitystä, mutta ei todista, että MML:n rantaviiva
olisi hydrologisesti oikea tai että MML-polygonin automaattinen käyttö
korjaisi D8-reitityksen.

Tärkeä jatkotarkistus: vaikka lähderasterissa järviksi luokitellut
D8-lähtösolut ovat kaikki oikein järven ID:n mukaisia, niiden **keskuksista**
vain 92/198 (1847) ja 91/189 (1898) osuu vastaavan **RANTA10-vektori**-
järven polygonin sisään. Rasteroinnin kattavuussääntö (keskipiste /
kaikki-kosketukset / osittainen peitto), lähdeaineiston ajallinen
erilaisuus ja MML-geometrioiden paikallinen vastinpari on tarkistettava
ennen kausaalipäätelmiä. `MML_POLYGONS_NEARBY=1` ei yksin todista
MML- ja RANTA10-kohteiden semanttista identtisyyttä.

## Toistaminen lukitussa CSC LOW -ympäristössä

```bash
D=diagnostics/low_d8_scope
B=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000/02_baseline
module load r-env/461
Rscript --vanilla "$D/test_compare_mml_shore.R" &&
  Rscript --vanilla "$D/run_compare_mml_shore.R" "$B"
```

Sama alkuperäinen lähdeaineisto ja commit vaaditaan. `run_compare_mml_shore.R`
sallii MML-GPKG-polun toisena argumenttina. Ranta10- ja MML-`jarvi`-
vesiluokkia ei vaihdeta automaattisesti. `lake_to_land_d8_core.R` on
jo tämän PR:n riippuvuus. Diagnoosit eivät kirjoita tiedostoja.

**NATIONAL LOCKED, MODERATE REVIEW_REQUIRED, SCIENTIFIC_STATUS REVIEW_REQUIRED.**
Ei mallin tuotanto-D8:n, DEM:n, WATER_STORAGE-pinnan tai outletien muutoksia.
