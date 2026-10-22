# S2 – LOW:n kuuden D8-reitin rajattu ketjuauditointi (toteutussuunnitelma v1)

**TILA: DESIGN_ONLY / CSC_NOT_RUN / hydrological_validation=NOT_ASSESSED.**

Tämä suunnitelma täydentää S1-evidenssiluokitinta (draft PR #45) ja G2/G3-geometriatarkistuksia. S2:n tarkoitus on lukea **olemassa olevasta** D8-rasterista vain kuuden aiemman 02F-reitin väliaskelten tarvitsemat solut. Ei muuta DEM:iä, STORAGEa, D8:aa, RANTA10-vesimaskeja, SYKE-purkupisteitä eikä mallin virtauskertymää. Ei muodosta eikä hyväksy uutta järven purkupistettä.

## 1. Täsmälleen rajattu tieteellinen kysymys

Tarkistetaan järven 1894 kuusi alkuperäistä 02F-yhteenvetoriviä, jotka kaikki päättyvät LAND_WATER-D8:n sisäiseen nollapointersoluun 23211319 / 02C-komponenttiin 274 järven 1892 lähellä. Riippumattomasti kontrolloidaan:
- Jokainen D8-väliaskel, osoitinkoodi, solutunnus, rivin/sarakkeen muutos, 02F:n laskema askelmäärä ja päättymisstatus.
- Mitkä reitit käyttävät samoja soluja ja missä niiden reitit ensimmäisen kerran yhtyvät. Kuusi lähtöä ei tarkoita kuutta erillistä uomaa.
- Solukeskusten / kapean ketjun suhde alkuperäiseen RANTA10-jokiviivaan fid29 / objectid129081 (G3:n lähin viiva). Viiva osuu järveen1894 mutta jää 22,78m järvestä1892. Geometrian läheisyys ei ole todistettu hydraulinen kanava.
- D8=nolla-solun naapurivesi- ja identiteettitieto sekä yhteys 02C:n kirjattuihin kolmeen lake1892-vesinaapuriin. Ei jatketa väkisin vesinaapuriin, eikä muuteta pointeria.
- Mahdolliset ristiriidat lähdeaineiston, 02F:n summarisoiman reitin ja G2/G3:n geometrian välillä raportoidaan STOP/REVIEW_REQUIRED, **ei korjaustoimintona**.

## 2. Lukitut alkuperäiset 02F-havainnot

| route_id | start_receiver_cell | terminal_cell | steps | terminal status |
|---|---:|---:|---:|---|
| 11 | 23337318 | 23211319 | 21 | D8_ZERO_INTERIOR |
| 14 | 23343318 | 23211319 | 22 | D8_ZERO_INTERIOR |
| 15 | 23343319 | 23211319 | 22 | D8_ZERO_INTERIOR |
| 16 | 23343320 | 23211319 | 23 | D8_ZERO_INTERIOR |
| 18 | 23349320 | 23211319 | 23 | D8_ZERO_INTERIOR |
| 20 | 23355321 | 23211319 | 24 | D8_ZERO_INTERIOR |

Kaikkien lähtöjärvi on 1894; päätesolun rasterin lake-ID on **NA** (ei järven 1892 vesitermi). 02F:n kuudessa raportissa ei ole väliaskelten listaa. Koko 02F-aineistossa on 101 yksilöllistä reittiyhteenvetoa; tästä ei saa päätellä 101 riippumatonta vesistöyhteyttä.

## 3. Miksi pieni 73 × 52 rasteri-ikkuna riittää?

LOW:n oma 01_input_QA.csv on varmistanut ruudukon 6000 × 6000, pikselikoko 2m, EPSG3067, x=199000..211000, y=6899000..6911000. Käytämme 1-pohjaista solutunnusta ja 0-pohjaista GDAL-riviä/saraketta:

- GDAL-row = (cell_id - 1) // 6000
- GDAL-col = (cell_id - 1) % 6000
- xcenter = 199000 + 2*col + 1
- ycenter = 6911000 - 2*row - 1

Kuuden alun ja yhden päätesolun tiukin yhdistetty solualue on row=3868..3892 ja col=3317..3320. Maksimi 02F-askeleita = 24. Yksittäisen D8-askeleen muutos kumpaankin pikselikoordinaattiin on enintään 1. Näin varma yläraja kaikille mahdollisille enintään 24 askeleen ketjuille saadaan laajentamalla kumpaankin suuntaan 24 pikseliä:

- 0-based window: row=3844..3916, col=3293..3344 (sis. päätepisteet).
- GDAL srcwin: xoff=3293, yoff=3844, xsize=52, ysize=73.
- Vastaava fyysinen rajaus: E 205586..205690, N 6903166..6903312.
- Soluja ikkunassa 3796; kolmessa rasterissa yhteensä 11388 soluarvoa. Tämä ei ole 6000×6000-pikselisen koko aineiston analyysi.

**Huomio:** tämä on *yläraja* alkuperäisten enintään 24-askeleisten reittien jokaiselle välisolulle, jos tiedoston 02F-askelmäärät pitävät paikkansa. Jos askelmäärä tai rasterin kohdistus ei täsmää, pysähdy eikä kasvateta aluetta automaattisesti. Käyttäjän erillinen hyväksyntä vaaditaan suuremmalle ikkunalle tai uusille reitityksille.

## 4. Alkuperäiset tiedostot, provenienssi ja lukutila

Oikean LOW-alueen olemassa olevat syötteet:
- Todennettu manifesti: /scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000/01_inputs/01_input_QA.csv ja 01_input_manifest.csv.
- 02F-yhteenveto: saman alueen 02_baseline/02F_water_connected_route_evidence.csv. Aiemmassa auditissa SHA256 oli 402fdbf16cb41eaa6a3ad2180cc4d3af8534e32cff299d73eacec8dc5c187db5. Varmista nykyinen hash ja riviskeema ennen data-analyysiä. Älä ota uuden version tuloksia vanhan näyttönä.
- 02C-neighborevidenssi: 02_baseline/02C_zero_pointer_water_neighbors.csv ja 02C_zero_pointer_cells.csv, viimeksi mainitun aiempi SHA256 e72d231c2a3d1fed7cc26009921e8945747015772184f00b798be4aa2eb433bd. Vesinaapuritaulukon SHA ei ole ennakkoon varmistettu; raportoi laskettu hash.
- 02B:n käyttämä nykyinen alkuperäinen D8: 02_baseline/d8_pointer_land_water_FLT8S.tif (Whitebox esri_pntr=FALSE; EI 02G eikä suunniteltu final WATER_CONNECTED).
- RANTA10:n luokkarasteri: SOURCE_TEST_ROOT/ranta10_water_class.tif; järvitunnisterasteri SOURCE_TEST_ROOT/ranta10_lake_id.tif. SOURCE_TEST_ROOT **selvitetään alkuperäisestä ajomanifestista**, ei arvata DEM-polusta. Jos nämä tiedostot eivät ole samoja nykyisen 02F-ajon kanssa, STOP.
- LOW RANTA10-vektori aiemmin varmennetussa polussa /scratch/project_2004707/pienvedet/csc_validation_4bbf22b/inputs/E200000_N6900000/RANTA10_E200000_N6900000.gpkg; vain jokiviiva fid29:n mahdollinen rajattu geometriavertailu.

Ennen rasterin **yhtään arvolukua** varmista metadata lukutilassa: 6000×6000, EPSG3067, resoluutio 2m, rasterin origo ja extent täsmälleen LOW:n QA:n kanssa, band count ja nodata, tiedoston koko, lähteen alkuperä, syöte-CSV-rivien ja tunnisteiden eheys. Manifestin hash-string ei yksin todista autenttisuutta: laske ja vertaile tiedostojen todelliset tiivisteet, jos käytettävissä ja kustannukset soveltuvat (3 suuren rasterin koko tiedoston hash on I/O-raskas; älä tee login-solmulla oletusarvoisesti). Ellei rasterin identiteettiä voida osoittaa luotettavasti, STOP/NOT_ASSESSED.

## 5. S2:n toteutusrajapinta

Erota kaksi puhdasta komponenttia:

**S2A (GitHub, ei CSC-dataa):** Puhdas, synteettisesti testattu D8-ketjujäljitin saa pienen äärellisen 73×52 taulukon, alkuperäiset route-ID:t, lähtö- ja päätesolut, rasterin tarkat geometriatiedot ja eksplisiittisen NA/NoData-luokituksen. Palauttaa muuttumattomat ketjut / askelkohtaiset solut, Whitebox-koodit, jakautumis- ja yhtymishavainnot, toteutuneen 02F-status-/askelmäärävertailun ja fail-closed-virheet. **Ei** GDAL-/CSC-sisääntuloa, tiedostokirjoitusta, graafipatcheja eikä purkuvalintaa.

**S2B (sallitaan vasta erillisessä rajatussa CSC-suorituksessa):** Lukutilainen sovitin hakee vain kolme ennakkoon rajattua 52×73 rasteri-ikkunaa alkuperäisistä D8-, water_class- ja lake-ID-TIFFeistä. Etusijalla GDALin ikkunaoperaatio ja putki muistiin/stdoutiin; ei uutta pysyvää rasteria tai keskeneräisten lähdetiedostojen muokkauksia. Ensin testataan sovitin täysin synteettisillä pienillä rastereilla (vain paikalliset väliaikaiset testifixturet). Todellinen ajo tarkoituksenmukaisessa CSC-laskenta-allokaatiossa; älä aja raskasta I/O:ta login-solmulla. Korkeusrasteria ei avata S2:ssa.

Tarkista GDAL-stdout-streamingin toimivuus erikseen synteettisellä fixturellä. Jos valitun ajurin stdout-ikkunapoiminta ei toimi, STOP ja raportoi se; **älä** siirry automaattisesti koko rasterin lataamiseen tai suureen tmp-GeoTIFFiin. Yhdenkään subprocess-komennon argumentti ei saa hyväksyä rajoittamatonta lukua tai syötepolun kirjoitusta.

## 6. Whitebox-D8-koodit (sama kuin nykyinen 02F-lähdekoodi)

Koodit ja rivi-/sarakesiirtymät:
- 1 NE (-1,+1)
- 2 E (0,+1)
- 4 SE (+1,+1)
- 8 S (+1,0)
- 16 SW (+1,-1)
- 32 W (0,-1)
- 64 NW (-1,-1)
- 128 N (-1,0)

Ensimmäisenä jokaisella solulla tarkistetaan alkuperäisen water_class-rasterin vesiluokka; jos solu on vettä, 02F:n logiikka päättyy nykyiseen vesitermi-statukseen. Muuten: NA → D8_POINTER_NA, 0 → D8_ZERO_INTERIOR tai D8_ZERO_AT_RASTER_EDGE, kielletty koodi → D8_POINTER_INVALID, validi koodi → seuraava solu, mahdollinen D8_DOMAIN_EXIT ja mahdollinen sykli. Alkuperäiseen 02F:ään kuuluu myös STEP_LIMIT ja LAKE_ID_MISSING. Ei yhtään uutta reittikoodia eikä muuteta 02F:n precedenssiä. Raportoi tarkasti, minä soluna koodi luettiin ja minä soluna askel lopulta laskettiin.

Kaikille kuudelle vertaa: lähtösolu, alkuperäinen route_id, jäljitettyjä D8-siirtymiä, alkuperäinen 02F-route_steps, päätesolu, terminal_water_class, terminal_lake_objectid ja route_status. Jos yksikin eroaa, **S2_RESULT=REVIEW_REQUIRED/FAIL_CLOSED**, ei korjata alkuperäistä CSV:tä.

## 7. Mittarit ja raportointi

Yhden kohteen kerralla tuottava analyysi:
- Exact read window bounds ja 3 rasterin metadata/provenienssitaulukko.
- Kuusi reittiä yksilöivä tulos. Kaikista välisoluista myös alkuperäinen integer cell_id, row/col, x/y, pointer value, water class ja lake ID; rajaa yhteenvetotulosteen koko ja tarjoa tarkka tiiviste koko rakenteesta tarvittaessa.
- Per-route uudet D8-ketjusolut; jaetut solut, ensimmäiset yhteiset solut, yksilölliset osaketjut, no-cycle QA; älä ilmoita kuutta riippumatonta jokea.
- Vertailu RANTA10-jokiviivaan fid29: lähin koko ketjun etäisyys/etäisyyssarja, geometrinen yhtenäisyys (EI "kanava varmennettu").
- Nollapointersolun paikalliset luokkarasterinaapurit ja 02C:n water neighbor -CSV:n vastaavuus. Maastosoluun päättyminen ei ole yhteys järveen1892.
- Selkeät testiasteet INPUT_QA, TRACE_PARITY, WATER_NEIGHBOR_PARITY, GEO_REFERENCE, SOURCE_PROVENANCE, AGGREGATION, RESOURCE_BOUND; jokainen PASS/STOP/NOT_RUN. Hydrologinen hyväksyntä aina NOT_ASSESSED.

## 8. Synteettinen testimatriisi ennen CSC:tä

Vähintään 40 merkityksellistä synteettistä assertionia:
- Oikea Whitebox 8-suuntakoodisto ja eri rivi/sarake + raja.
- Kuusi 02F-tyyppistä yksilöllistä alkua ja yksi päättymissolu, jokaisen ketjun rakenne, omat ja yhteiset solut.
- D8_ZERO termi, jo syntynyt water class ennen nollaa, puuttuva lake ID, RETURNS_TO_ORIGIN_LAKE, REACHES_OTHER_LAKE, RIVER_AREA/LINE.
- NoData vs. 0, NAN, laiton pointer, syklinen osoitin, ruuturajan ylitys, STEP_LIMIT.
- Yksi alkuperäinen 02F-askeleiden virhe, ristiriitainen route-ID, muuttunut lähde-CSV, ristiriita 02C-rantanaapuriin → STOP.
- Virheellinen CRS/origo/pikselikoko, ikkunan ulkopuolelle joutuva askel, laskettavan ikkunan automaattisen suurenemisen esto → STOP.
- Water-class ennen pointeria, nollapointerin luokitus, 1-pohjaiset solut vs GDALin 0-pohjaiset indeksit.
- Koko S2 ei tuota outletia tai VALIDATED-tilaa eikä kirjoita rastereita; stdout/raporttikäyttäytyminen testataan ilman todellisia aineistoja.

## 9. Valtakunnallinen hyöty, mutta ei valmista kansallista ratkaisua

Tämän kuuden reitin G4/S2-tarkistuksen arvokkain yleistettävä osa on **päällekkäisten D8-ketjujen todellinen yhteenliittyminen ja terminaalien alkuperän jäljitettävyys**. Se antaa myöhemmin syötteen S1-luokittimelle useista muista tutkimusruuduista, mutta S2:n tulosta ei saa normalisoida automaattiseksi purkuvalinnaksi. Menetelmän toimivuus eri alueilta, riippumattomat referenssit, hydrologinen korkeusvarmuus ja suorituskyky kansallisessa mittakaavassa pysyvät S3:n tehtävinä.

## 10. Ehdotettu seuraava Codex-vaihe

1. Toteuta S2A puhtaana Python-kirjastona + riittävät synteettiset regressiot, ei CSC:tä.
2. Toteuta erillinen S2B-read-only-adapterin sopimus ja synteettiset GIS-testit. Älä vielä käynnistä todellisen LOW-rasterin lukua ilman eksplisiittisesti hyväksyttyä, kirjattua resurssirajaa.
3. Dokumentoi tulokset ja julkaise uusi **draft**, pinottu PR tämän suunnittelun päälle; ei mergeä.

**Tieteelliset lukot:** NATIONAL=LOCKED; MODERATE=REVIEW_REQUIRED; hydrological_validation=NOT_ASSESSED; channel_interpretation=NOT_ASSESSED.
