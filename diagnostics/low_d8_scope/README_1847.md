# LOW 1847 — kohdennettu read-only D8-rantadiagnostiikka

Tämä hakemiston `lake_1847_focus_core.R`, `test_lake_1847_focus.R` ja
`run_lake_1847_focus.R` on siirretty **sellaisinaan** Roihussa onnistuneesta
testipaketista 16.10.2026. Kolmen R-tiedoston Git-blob-tunnisteet vastaavat
alkuperäistä testipakettia; koodia ei muokattu GitHub-viennissä.

## Mitä testataan?

Vain RANTA10:n `objectid=1847`. Polygonin ympärille muodostetaan 20 metrin
lisämarginaalilla ikkuna. Ohjelma lukee vain seitsemän jo olemassa olevan
rasterin paikalliset ikkunat (enintään 500 000 solua/rasteri), ja tarkistaa
järvisolujen sijainnin ikkunan sisäpuolella sekä aiemman koko LOW:n ajon
`198 / 197 / 88` -laskurit. Ensimmäisessä vaiheessa verrataan
`LAND_RAW`- ja `LAND_FILL`-pintoja, myöhemmin `LAND_WATER`- ja
`WATER_STORAGE`-pintoja. Ainoa muu kuin D8=0-vastaanottaja jäljitetään
korkeintaan 128 askelta. **Mitään aineistoa ei kirjoiteta tai muuteta.**

## Todellisen CSC Roihu -ajon tulokset — PASS 16.10.2026

- Synteettinen R-regressio: **PASS: LOW 1847 local window counts, elevations, mask and bounded D8 tracing**.
- Todellinen ikkuna **388 × 155 = 60 140 solua**; RANTA10-järvisoluja **24 344**.
- Järvi→maa-D8-osoittimia **198**, joista **197** suoraan D8=0-maasoluun;
  erillisiä nollavastaanottajia **88** ja yksi muu maavastaanottaja.
- Kaikki **88/88** D8=0-vastaanottajaa ovat muuttumattomia
  `LAND_RAW → LAND_FILL`-vertailussa.
  **WATER_STORAGE nostaa kaikki 88/88** suhteessa `LAND_WATER`-pintaan.
- Järven `LAND_WATER`-korkeus on vastaanottajaa suurempi
  **198/198 reunassa**: ero **0.00099945068–0.001999855 m**,
  mediaani **0.001999855 m**.
- Ainoa ei-nollavastaanottaja: järvisolu **13138288**
  (`LAND_WATER=11.900 m`) → maasolu **13144289**
  (`LAND_WATER=11.899 m, D8=2`) → maasolu **13144290**
  (`D8=0`, järvitunnus `NA`), `TRACE_STEPS=1`.
- Aiemman 36M-solun lohkoajon lukuihin täsmäävä
  **PASS: LAKE 1847 RECONCILES WITH FULL LOW 198/197/88 SNAPSHOT**.

**Johtopäätös:** tämän järven kaikki 198 maalle osoittavaa D8-reunaa
päättyvät D8=0-soluun joko välittömästi (197) tai yhden maalla
tapahtuvan D8-askeleen jälkeen (1). Nämä ovat paikallisia katkoksia,
eivät tieteellisesti vahvistettuja purkupisteitä tai epäonnistuneita
valuma-alueita. Pelkkä 1–2 mm:n erotus ja maskatun rantavyöhykkeen
muuttumattomuus eivät vielä todista Whiteboxin NoData-käsittelyn
yksittäistä juurisyytä.

## Ajo vastaavassa alkuperäisessä CSC LOW -ympäristössä

```bash
D=diagnostics/low_d8_scope
B=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000/02_baseline
module load r-env/461
Rscript --vanilla "$D/test_lake_1847_focus.R" &&
  Rscript --vanilla "$D/run_lake_1847_focus.R" "$B"
```

Aiemman tutkimuksen RANTA10-rajauksen lukitus sekä oikea commit säilytettävä.
`lake_to_land_d8_core.R` on tämän PR:n jo olemassa oleva riippuvuus.

NATIONAL `LOCKED`; MODERATE `REVIEW_REQUIRED`; 1847
`SCIENTIFIC_STATUS=REVIEW_REQUIRED`. Ei tuotannon `R/`-muutoksia,
DEM-/D8-/STORAGE-/outlet-muutoksia eikä automaattista korjausta.
