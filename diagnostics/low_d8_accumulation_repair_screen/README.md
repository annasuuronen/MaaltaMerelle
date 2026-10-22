# LOW D8: alustava vikaseulonta ja flow accumulation -valmius

**Kokeen luonne:** vain LOW:n olemassa olevan välivaiheen LAND_WATER-D8:n mekaanisten poikkeamien seulonta. Ei lopullisen hydrologisen korjaustarpeen arvio, eikä uusi D8- tai accumulation-laskenta.

Kanonisen putken `R/02_build_baseline_hydrology.R` mukaan lopullinen WATER_CONNECTED-D8 ja flow accumulation **eivät vielä ole toteutettuja**. Niiden korjattavien solujen määrää ei voi nyt mitata. Nykyinen LAND_WATER-D8 ei ole lopullinen malli.

**Rajaus:** kiinteä siemen `20261022`, 16 × 16 osaruutua, kussakin yksi satunnainen keskus: **256 keskusnäytettä**; niistä kukin enintään 3 × 3 -naapurusto. Enintään **2 304 solua kerroksesta**, **3 rasteria**, **6 912 palautettua arvoa**. Ei kokorasteriskannausta.

Kerrokset: `d8_pointer_land_water_FLT8S.tif`, `routing_surface_land_water_FLT8S.tif`, `ranta10_water_class.tif`. Ensin tarkastetaan 6000 × 6000, EPSG:3067, 2 m ja täsmällinen rasterirajaus. Seulotaan puuttuva/virheellinen D8-koodi, D8_ZERO, puuttuva kohdekorkeus, epäselvä vesiluokka tai nykyisellä LAND_WATER-pinnalla yli `1e-6 m` nouseva D8-reuna. Erikseen raportoidaan vesikontaktiehdokkaat, tasanteet, maastossa laskevat reunat ja ruudukkorajalle päätyvät reunat.

**Seulontalippu ei ole korjattava virhe.** Esimerkiksi tasanne, nollapointeri tai RANTA10-vesiluokan lähellä kulkeva virtaus tarvitsee lisäselvityksiä; järvipurkuja ja ojia ei voida hyväksyä tällä kokeella. Lippujen osuuden likimääräinen Wilson-95%-väli ei ole hydrologisten virheiden korjausprosentti. Mitään ei yleistetä kansalliseksi arvioksi.

Yhden komennon `one_shot_low_screen.sh` vaatii puhtaan Git-kloonin ja täyden SHA:n muuttujassa `MM_EXPECTED_COMMIT`, kirjoittaa tulosteet vain erilliseen scratch-hakemistoon `mm_low_d8_screen.*`, ei muuta CSC-raste­rei­ta. Ei Slurmia, Whiteboxia, aiempien hyväksyttyjen testikampanjoiden uusintaa, uusia D8- tai kertymärastereita.

**Paikalliset ohjelmistokokeet:** 6 synteettistä Python-ryhmää PASS; Roihun R 4.6.1 / terra 1.9.34 ja oikeiden rasterien luku toistaiseksi NOT_RUN. Ennen laajempaa CSC-ajoa erillinen hyväksyntäportti.

`hydrological_validation=NOT_ASSESSED` · `channel_interpretation=NOT_ASSESSED` · `MODERATE=REVIEW_REQUIRED` · `NATIONAL=LOCKED`.
