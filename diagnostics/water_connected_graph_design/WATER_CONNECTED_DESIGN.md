# WATER_CONNECTED – vesistögraafin toteutussuunnitelma

**Tämä on katselmointiehdotus, ei hyväksytty hydrologinen toteutus.** Lähtökohtana kanonisen `annasuuronen/MaaltaMerelle`-repon `baseline-no-structures` commit `7050b582edab3195669529f366b4f5a2915488c6`. Suunnitelmassa ei lueta CSC-rastereita eikä muuteta mitään nykyisistä baseline-, DEM-, D8-, STORAGE-, vesi- tai purkupistetiedostoista.

## 1. Nykyinen aineistosopimus ja rajat

- `R/00A_prepare_validation_fixture.R` rasteroi **testifixturen** RANTA10-järvet `objectid`-kentällä, jokialueet ja jokiviivat 2 m DEM-ruudukkoon (`touches=TRUE`). Vesiluokan etusija on järvi 1, jokialue 2, jokiviiva 3. Tämä ei yksin todista, että jokainen CSC:n historiallinen rasteri on muodostettu täsmälleen samalla tavalla.
- `R/01_prepare_hydrology_inputs.R` pitää olemassa olevan `ranta10_lake_id.tif`-rasterin kanonisena ja muuntaa `objectid -> korkeus_m` samalla pikselijoukolla. Uudelleenrasterointi voisi muuttaa rantareunasoluja.
- `R/02_build_baseline_hydrology.R`: järvien solut poistetaan maa-DEM:n fill-vaiheesta, mutta jokialueet ja jokiviivat jäävät maapintaan. Maa-DEM:n `FillDepressions(fix_flats=TRUE)` luo `land_fill`; `cover(land_fill,lake_z)` luo `land_water`, josta nykyinen välivaiheen D8. Erillinen WATER_STORAGE käyttää `fix_flats=FALSE`.
- `02D` tarkastelee kahdeksan naapurin järvi->ei-samaan-järveen suuntautuvia rantareunoja ja `pmax`-periaatteen kynnystasoja sekä alimpia spill-ryhmiä. Positiivinen kynnys ei ole sama kuin rasteriin toteutunut korotus.
- `02D.8` säilyttää jokaisen spill-ryhmän `outlet_selection=UNASSIGNED`. `02E` pitää rinnakkaiset, riittävän ulkoisen evidenssin ehdokkaat. `02F` jäljittää niiden vastaanottajat nykyisellä D8:lla **ensimmäiseen RANTA10-vesisoluun** tai eksplisiittiseen STOP-tilaan. `REACHES_RIVER_LINE`, `REACHES_RIVER_AREA` tai `REACHES_OTHER_LAKE` ei vielä varmista jatkuvaa reittiä mereen.

## 2. Ehdokasverkko on eri asia kuin reititysverkko

**Evidenssiverkossa** säilyvät kaikki 02D–02F:n rantareunat, myös tarkistettavat ja puutteelliset. Yksilöivä avain on `(lake_objectid, spill_group_id, source_cell, receiver_cell)`. Säilytä alkuperäinen taulunimi, commit/provenienssi, RANTA10-luokat, kynnyskorkeudet, 02F-tila ja tiedon aukot. Ehdokkaasta ei tule aktiivista graafin kaarta vain, koska sen luokka on `EXTERNAL_EVIDENCE`.

**Laskettava verkko** tarvitsee erillisesti tarkistetut aktiiviset kaaret. `READY_FOR_SEPARATE_APPROVAL` tarkoittaa vain, että ehdokas ei kaadu automaattisiin ennakkotarkistuksiin. Se ei ole hyväksyntä eikä muuta alkuperäisen `outlet_selection`-kentän arvoa. Useampi rinnakkainen ehdokas pysyy vaihtoehtona, ellei itsenäinen hydrologinen näyttö ratkaise, ovatko ne vaihtoehtoja vai samanaikaisia purkautumisia.

**Solmut:** `LAND:<cell>`, `LAKE:<objectid>`, erikseen yksilöitävä `RIVER_REACH:<id>`, `COAST:<verified-id>`, `TILE_BOUNDARY:<id>`. Nykyinen jokialueen vesiluokka 2 tai jokiviivan luokka 3 **ei anna jokijaksotunnusta**. Ennen jokisolmujen hyväksyntää tarvitaan jokiverkon segmentointi ja rasteri–vektori-yhteys. Ruudukon ulkopuolelle päättyminen ei automaattisesti ole yhteys mereen.

## 3. RANTA10:n rajaus ja rantareunojen QA

Pidä alkuperäinen vektorigeometria ja nykyiset rasterit ennallaan. Tulevassa vain-luku-QA:ssa vertaile:

1. sivunaapuruus (4) vai vain kulmakosketus (8); kulmakosketus aiheuttaa **REVIEW_REQUIRED**-lipun, mutta ei automaattista hylkäystä, koska kapea todellinen yhteys on mahdollinen;
2. vektori-/rasterikontakti, `touches=TRUE`-vaikutus ja solurajojen määritys sekä lähdeaineiston geometrinen tarkkuus;
3. saman järvi-ID:n komponentit, saaret, muut vesistöt, päällekkäisten rasteriluokkien etusija ja jokilinjan liittyminen järvirantaan;
4. todelliset kapeikot, ojat, sillat, rummut, puuttuvat tai ristiriitaiset reittitiedot.

Rantaviivan muokkaaminen vastaamaan odotettua D8:aa ei ole hyväksyttävä korjausperiaate. Jos RANTA10 ja DEM ovat ristiriidassa, tee erillinen havainto sekä perusteltu ratkaisu myöhemmässä vaiheessa.

## 4. Purkupisteen tieteellinen portti

Ehdokkaan käyttöönotto vaatii **kaikki** seuraavat erikseen todennetut asiat: lähdeversiot; ranta- ja vastaanottajageometria; STORAGE-spill-tason merkitys vs. mahdollinen toteutunut rasterin korotus; jatkoreitti ensimmäisen vesikontaktin jälkeen; syklin, lähtöjärveen palaamisen ja erottamattoman rasterirajan poissulku; luotettava kohdevesistön/jokijakson identiteetti sekä epäselvien rinnakkaisten vaihtoehtojen käsittely. Tuntematon status pysyy tuntemattomana.

Oman suunnitteluvaiheen ehdokaspreflight palauttaa **vain** `REVIEW_REQUIRED` syineen tai `READY_FOR_SEPARATE_APPROVAL`. Se ei koskaan kirjoita oikeisiin hydrologisiin tiedostoihin tai tee purkupisteen valintaa.

## 5. Kertymäsopimus

- Jokainen 2 m rasterisolu saa **yhden alueomistajan**: maa, järvi, jokijakso tai muu erikseen hyväksytty solmuluokka. Yksi solun pinta-ala on 4 m². Omistajuuden täydellisyys suhteessa todelliseen maskiin on erillinen QA, ei tämän synteettisen testin tulos.
- Maan D8-solmulla on yksi lähtökaari. Järven rinnakkaiset **vaihtoehtoiset** spill-ryhmät eivät ole moninkertainen virtaus.
- Jos järvellä on tutkitusti **useita yhtäaikaisia ulosmenoja**, haarautumisen painot täytyy määrätä erikseen ja summan olla 1. D8 tai ehdokkaiden lukumäärä ei kerro jakoa. Jos painoja ei tunneta, ei lasketa yhtä oletettua lopullista kertymää.
- DAG:n topologinen eteneminen: `acc(v) = area_owned(v) + sum[frac(u,v) * acc(u)]`. Tämä on reititettyä pinta-alaa, **ei vesimäärää tai virtaamaa**. Sama ylärinnealue ei saa tulla lasketuksi kahdesti, vaikka reitit yhtyvät uudelleen.
- Erillinen tile-rajojen ulkopuolinen yläpuolinen kertymä pidetään tilassa `UNKNOWN`; paikallinen koe merkitään `LOCAL_ONLY`, ei koko vesistöalueen laskennaksi. 
- Testaa jokaisen hyväksytyn yhteyden geometriakelpoisuus, syklittömyys, solujen yksikäsitteisyys ja pinta-alan säilyminen. Koko LOW:n tulosta ei voi julistaa hydrologisesti hyväksytyksi vain näillä mekaanisilla testeillä.

## 6. Numeerinen provenienssi

Nykyinen koodi kirjoittaa `land_dem_raw_FLT8S.tif`-nimisen tiedoston **`datatype="FLT4S"`**, samoin `ranta10_lake_elevation_m.tif` kirjoitetaan `FLT4S`-tyyppisenä; myöhempi `land_water` kirjoitetaan `FLT8S`. Vain tiedoston nimi ei kerro alkuperäistä numerotarkkuutta. WHITEBOX-binäärin ja välituotteiden versiot / metatiedot pitää tarkistaa, ennen kuin 0,3–0,9 µm korkeuseroja käytetään maanpinnan fysikaalisina tulkintoina. Mikrokaltevuuksista saadut käyttäjän 22.10.2026 tulokset (119 = 104+11+4 kappaletta) ovat **laskennallisen pintakäsittelyn mahdollinen sormenjälki**, eivät 119 virhettä. Edes molempiin 3e-7 ja 3e-8 m askeliin sopiminen ei yksilöi historiallista ohjelmistoa.

## 7. Etenemisportit

| Portti | Toimi | Hyväksymis-/STOP-ehto |
|---|---|---|
| G0 synteettinen sopimus | Pieni Python-orakkeli ja 26 testitapausta, ei CSC-yhteyttä | Ohjelmiston toimintaperiaatteet vain; ei hydrologista PASS-tulosta |
| G1 olemassa oleva 02D–02F-evidenssi | Skeemojen ja valmiiden CSV-yhteenvetojen read-only inventaario | Jos tiedostoa ei ole, `NOT_RUN`, ei uusintalaskentaa |
| G2 rantaraja-/purkugeometrian QA | Ennalta rajatut 4/8-naapuruus-, vektori- ja jokijaksotutkimukset | Käyttäjän erillinen hyväksyntä mahdollisille uusille CSC-luennolle |
| G3 reititysverkko | Ehdokasjoukko → erikseen hyväksyttävät yhteydet | Avoin reitti => ei täyttä WATER_CONNECTED-laskentaa |
| G4 ensimmäinen LOW D8 -ehdokas | Vain erikseen hyväksytyllä kokeella CSC:n laskentasolmulla | Uusi output-hakemisto; vanhat rasterit ennallaan, täysi QA |
| G5 accumulation | Kytkettyä, validoitua DAG:ia ja rajavirtoja hyödyntävä vertailu | Massatase, riippumaton orakkeli, tuntemattomat ylävirrat eksplisiittisesti |

**EI** mergetystä versiosta väitettyä hyväksyntää, **EI** tuotanto-D8:n/DEM:n/STORAGEn/vesimaskien/outletien muutosta, **EI** tähän suunnitelmaan liittyviä uusia Roihu-ajoja. PR #22/#32/#34/#35/#37 pysyvät draft-tilassa.

`hydrological_validation=NOT_ASSESSED` · `channel_interpretation=NOT_ASSESSED` · `MODERATE=REVIEW_REQUIRED` · `NATIONAL=LOCKED`