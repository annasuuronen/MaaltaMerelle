# MODERATE 02D.4–02D.5: Roihussa suoritettu koottu D8- ja geometriadiagnostiikka (2026-10-16)

**Todellinen CSC:n aineisto, read-only.** Tämä on ensimmäisen yhteen kootun Roihu-diagnostiikka-ajon tulosten **raportointi** (ei tuotantolaskennan korjaus eikä uusi FillDepressions-ajo). Tulokset luettiin käyttäjän ChatGPT-keskusteluun 16.10.2026 lähettämästä Roihun raporttiarkistosta. Alkuperäisiä rastereita ei ole ladattu GitHubiin.

**Lopputila: molemmat read-only-diagnostiikat suoritettiin teknisesti onnistuneesti. MODERATE=REVIEW_REQUIRED; NATIONAL=LOCKED.** Hydrologista hyväksyntää tai luonnollista purkureittiä ei ole osoitettu.

## Ajon provenienssi

- UTC-start: `2026-10-16T17:12:49Z`.
- Ajotunnus: `rstudio_2354869_20261016T171249`; RStudio interactive compute node, koska `sbatch` ei ollut käytettävissä tässä Roihu-istunnossa.
- Commit **`a2c5c509dfa534b7b2313cd3894930c45dfd3184`**, kehityshaara `codex/moderate-02d4-diagnosis`.
- Ajettiin `scripts/audit_moderate_spill_d8_readonly.R` ja `scripts/audit_moderate_lake_geometry_readonly.R` jo olemassa olevia MODERATE-tiedostoja lukien.
- Ympäristö: R 4.6.1, `terra` 1.9.34. `r-env/461`-moduulia ei löytynyt interaktiivisessa ympäristössä: käytettiin alkuperäisen sbatch-skriptin **tilapäistä kopiota, josta poistettiin vain** `module load r-env/461` -rivi. GitHubin skriptiä tai tuotantoaineistoja ei muutettu tämän ajon vuoksi.
- MODERATE-lähtöraporttien juurihakemisto: `/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/moderate_resume_20261014_v2/run/02_baseline`.
- Tuloshakemisto: `/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/moderate_scientific_review/job_rstudio_2354869_20261016T171249`.
- `steps.txt`: `spill_d8 exit=0`, `lake_geometry exit=0`.
- `summary.txt`: `ALL_DIAGNOSTICS_ATTEMPTED=true`, `DIAGNOSTIC_TECHNICAL_PASS=true`, `REAL_DATA_HYDROLOGICAL_APPROVAL=false`.
- Syöterasterien SHA256-tiivisteet raportoituina `provenance.txt`-tiedostossa:
  - `routing_surface_land_water_FLT8S.tif`: `940d8198b3f383cceb0fdc2e9a9e341015cc99d7e31d7acc09e0b77764e19571`
  - `routing_surface_water_storage_FLT8S.tif`: `3077150d0f6a2439278a2c234295780158932edbd1aad6bb99ff1cad759f88e4`
  - `d8_pointer_land_water_FLT8S.tif`: `3114978a114029d8e67c448bea00b2f5742d7e76d93fc4e657e1304d142b2b56`
  - `ranta10_lake_id.tif`: `a3b647067ebb35647639190c8cebd6c69864bbb1022a6db5a6047fe8bdea2db5`
- Käyttäjän toimittama raporttiarkisto nimellä `MaaltaMerelle_MODERATE_review.tar.gz` oli tiedostosisällöltään **pakkaamaton POSIX tar**, ei gzip-virta; kaikki viisi raporttitiedostoa saatiin siitä silti luettua. Ladatun arkiston SHA256: `f526195f660a7fe095b4814d69aa7a881ea222925ec1e8fb35f4ca639d8dddf9`. Tähän GitHub-tiedostoon on kirjattu johdetut tulokset; alkuperäistä arkistoa ei julkaista repositorioon.

## Vahvistetut tulokset

### 1. D8-/spill-diagnoosi: aiempien havaintojen riippumaton koottu toisto

| Mittari | Roihun tulos |
| --- | ---: |
| Järviä MODERATE-raportissa | 158 |
| Positiivinen rantakynnys (`SPILL_RAISED`) | 52 |
| `SPILL_RAISED_NO_COMPONENT`-luokassa | 52 |
| Näiden järvien alimpia spill-rantareunoja | 162 |
| Korotettuja järvisoluja näillä järvillä | 0 |
| Näistä järvistä korotuskomponentin sisältäviä | 0 |
| Suurin raportoitu toteutunut STORAGE-korotus | 0 m |
| Positiivinen rantakynnys, vaihteluväli | 0.0009918212890625–1.19699096679688 m |
| D8:n paluu lähtöjärveen | 159 |
| D8:n päättyminen nollapointeriin | 3 |
| `PRODUCTION_02D5_GATE_PASS` | **FALSE** |

Kaikki kolme nollapointeriin päättyvää rantareittitapausta ovat järvestä **204104** ja päättyvät soluun **12373731** (4 askelta). Tämä terminaali ei ole `02C_zero_pointer_cells.csv`-taulukossa, mutta 02C-taulukko on vain rajattujen ehdokassolujen luettelo, ei kaikkien nollapointerien inventaario. Tämä tulos vastaa aiemmin raportoitua 159/3-jakaumaa; se **ei** todista luonnollista lasku-uomaa.

### 2. UUSI: 52 järven todellinen rasterigeometria

`lake_geometry.log` tarkasti kaikki 52 ongelmaluokan ID:t, yhteensä **29 290 järvisolua**, rasterikoko **6 000 × 6 000**, sekä **14 192** rasterin sisäistä järven ulkoista 8-naapurirantaparia.

| Geometriatarkistus | Tulos |
| --- | ---: |
| Kohdejärviä | 52 |
| Rasterin ulkoreunaa koskettavia | **3** |
| Rasterin ulkoreunaa koskemattomia | **49** |
| Järviä, joilla in-domain ulkorantanaapuri on NoData LAND_WATER -pinnalla | **0** |
| Vastaava NoData STORAGE-pinnalla | **0** |
| Järviä, joilla lähtöpinnan järvitason min–max ylittää 1e-7 m | **0** |
| Järviä, joilla järvisolun STORAGE eroaa LAND_WATERista yli 1e-7 m | **0** |
| Puuttuvia lähdejärvisolujen äärellisiä arvoja | **0** |

Kolme ulkoreunaa koskettavaa järveä:

| `lake_objectid` | Järvisoluja | Järvisoluja rasterin reunalla | Ulkoisia rantapareja |
| ---: | ---: | ---: | ---: |
| **203439** | 105 | 19 | 97 |
| **203443** | 94 | 15 | 75 |
| **203444** | 697 | 26 | 240 |

**49 muuta järveä** eivät kosketa rasterin ulkoreunaa. Erityisesti aiemmassa poikkeavassa D8-reitissä esiintyvä järvi **204104** on tämän tarkistuksen mukaan sisäinen (270 järvisolua; 0 ulkoreunasolua). Järvisolujen alkuperäiset korkeudet olivat kaikilla 52 ID:llä tasaiset käytetyllä toleranssilla.

**Tarkka rajaus:** `terra::adjacent`-raportti kattaa rasterin sisäiset naapurisolut; rasterin ulkopuolella olevalle naapurille ei muodostu paria. Näin `HAS_NODATA_OUTSIDE_SHORE 0` ei tarkoita, että kolme ulkoreunajärveä olisi ympäröity joka suunnasta äärellisillä soluilla. Raportti **ei** tutki rannasta kauempana olevia NoData-alueita, kaikkien järvien 8-yhteyskomponentteja, laajemman pinnan minimax-ulostuloreittejä eikä Whiteboxin sisäisen pit-/outlet-haun käyttäytymistä.

## Mitä tulokset erottavat – ja mitä eivät

1. **Välitön rasterin reuna** voi vaikuttaa enintään 3/52 järveen suoran reunakosketuksen kautta. Se ei selitä yksin muita 49 järveä.
2. **Välitön in-domain NoData-rantanaapuri** ei selitä minkään 52 järven havaittua nollakorotusta. Kaukana olevia NoData-reittejä ei kuitenkaan ole tutkittu.
3. **Epätasainen lähdejärvipinta** ei selitä 52 järven ilmiötä tämän toleranssitestin perusteella.
4. **Lähdejärvisolujen todellinen korotus** on 0/52 kuten aiemmin raportoitiin; uudessa ajossa ei verrattu kaikkia 36 miljoonaa solua uudelleen. Rasterien hashit vastaavat aiempaan Roihu V2 -lähtötilaan: tämä on provenienssivahvistus, **ei uusi Whitebox-täyttö**.
5. Koko 52-järven Whitebox-käyttäytymisen selitys on yhä **avoin**. Synteettinen `flat_rim`-Whitebox-tapaus osoittaa mahdollisen algoritmisen erikoistapauksen mutta ei todista sen toteutuneen näillä järvillä. Myöskään alkuperäisen STORAGE-tuotoksen tosiasiallisesta Whitebox-suorituksesta (binary, syöte, exit, välimuisti) ei ole riippumatonta uusintanäyttöä.
6. Positiivinen `spill_raise_m` on rantakynnys, ei näyttö havaitusta `STORAGE - LAND_WATER`-korotuksesta. 02D.5:n nykyinen komponenttiehto ei täyty, eikä sitä saa ohittaa testin läpäisemiseksi.

## Priorisoitu seuraava tutkimus (Codex ja myöhempi Roihu)

**Ensin GitHub/Codex, ilman uutta Roihu-laskentaa:**

- Toteuta [issue #13](https://github.com/annasuuronen/MaaltaMerelle/issues/13): fail-closed 02D.5:n tekninen valmiusluokittelu ilman muutoksia tuotantokoodiin tai komponenttien valmistamista.
- Kehitä tarvittaessa uusi read-only kohdennettu hypoteesien erotin, joka tarkistaa 52 järven maskikomponentit, alempaan ulostuloon johtavan äärellisen pinnan jatkuvuuden ja Whiteboxin oletusten kannalta relevantit todelliset tasanne-/aluerajaolosuhteet. Testaa pienillä synteettisillä rastereilla ensin. **Älä väitä hydrologista purkureittiä ilman itsenäistä todistetta.**

**Ennen mitään uutta raskasta Roihu-ajoa:** tarkista olemassa olevista 02A-/Whitebox-lokeista ja metadata-/checkpoint-tiedoista todellinen `FillDepressions`-komento, binääri/versio, syötteen ja tuotoksen identiteetti, prosessin tila ja välimuistin käyttö. Tämän vuoden epäonnistunut riippumaton täytön uusintayritys ei tuottanut validia vertailupintaa. Älä aloita 36 miljoonan solun täyttöä pelkästään diagnoosin toistamiseksi.

**Tieteellinen portti säilyy:** `MODERATE=REVIEW_REQUIRED`; `NATIONAL=LOCKED`.

## Todisteaineisto / raportin rajat

Alkuperäinen käyttäjän lataama arkisto sisälsi `provenance.txt`, `steps.txt`, `spill_d8.log`, `lake_geometry.log` ja `summary.txt`. Tämä tutkimusmuistio nojaa niiden luettuun sisältöön, ei laskennallisesti uudelleen muodostettuun rasteriin. Per-lake-riviloki sisältää myös lähtöpinnan ja rantanaapurien korkeudet; sitä ei kopioida tässä julkiseen repositorioon. Jatkoa varten alkuperäinen arkisto kannattaa säilyttää käyttäjän valvotussa tutkimusarkistossa.
