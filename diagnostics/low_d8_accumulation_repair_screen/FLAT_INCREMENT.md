# LOW: Whitebox-tasannelisäyksen offline-sormenjälkitarkistus

**Tila:** Uusi ohjelmistokoe, **ei** tuotantorasterin luku, hydrologinen hyväksyntä eikä lopullisen korjaustarpeen laskenta.

## Mitä on jo havaittu?

Käyttäjän 22.10.2026 Roihu-raportti LOW D8 -pisteseulonnasta:
- Keskuspisteitä 256: LAND 236, WATER 7, SOURCE_NODATA 13.
- LAND-pisteiden D8-askelista 117 selvästi laskevia, **119 hyvin lievästi laskevia** ja **0 nousevia/täysin tasakorkeita**.
- Näiden 119 reunaparin erot `z_target - z_source` olivat noin **-9e-7 ... -3e-7 m**.
- Aiemman ajon CSV: `/scratch/project_2004707/pienvedet/mm_low_d8_screen.VR0UZ3WM/{raw.csv,centers.csv}`. Tiedostot eivät ole GitHubissa, eikä niitä ole luettu uudelleen tätä koodia valmisteltaessa.
- Käyttäjän raportoimat SHA256-summat ovat ohjelmassa lukittuina. Ohjelma torjuu eri tiedostot, järjestyksen muutokset, puuttuvat rivit ja eri aggregaatit.

## Miksi 3e-7 m kannattaa testata?

Kanonisen putken `R/02_build_baseline_hydrology.R` kutsu:
1. `whitebox::wbt_fill_depressions(dem=f_land_raw, fix_flats=TRUE)` tuottaa `land_dem_filled_FLT8S.tif`;
2. `terra::cover(land_fill, lake_z)` tuottaa `routing_surface_land_water_FLT8S.tif`;
3. `whitebox::wbt_d8_pointer(dem=f_land_water, esri_pntr=FALSE)` tuottaa välivaiheen pointerin;
4. erillinen WATER_STORAGE-pinta tehdään `fix_flats=FALSE`.

WhiteboxToolsin julkisen `FillDepressions`-lähdekoodin automaattinen `small_num` perustuu syötteen `maximum`-arvon numeroiden määrään ja pikselin lävistäjään. Jos **lähtö-DEM:n suurin arvo on positiivinen kaksinumeroinen** ja solukoko 2 m, laskettu ehdokas on `3e-7 m` (`ceil(sqrt(2^2+2^2))=3`; `3 × 10^(2-9)`). Automaattinen lisäys voidaan toistaa tasanteen eri peräkkäisillä solureunoilla.

Viitteet:
- https://whiteboxr.gishub.org/reference/wbt_fill_depressions.html
- https://github.com/jblindsay/whitebox-tools/blob/master/whitebox-tools-app/src/tools/hydro_analysis/fill_depressions.rs

**Rajoitus:** Tämä on *upstream*-lähdekoodin mahdollinen sormenjälki, **ei näyttö siitä**, että Roihun käytössä olleessa Whitebox-binäärissä on sama algoritmi tai että lähtö-DEM:n `maximum` on kaksinumeroinen. **0,3 mikrometrin erot eivät yksilöi askelta:** jos positiivisen lähtö-DEM:n maksimin kokonaisosa on yksinumeroinen, vastaava lähdekoodin askel olisi `3e-8 m` ja `3e-7 m` voi syntyä kymmenestä peräkkäisestä lisäyksestä. Jos maksimi on kolminumeroinen, vaihtoehto on `3e-6 m`. Uusi ohjelma raportoi vertailun kaikille kolmelle oletukselle; yksittäinen osuma ei todista käytettyä parametria. Aikaisemman LAND_FILL-ajon versio, `flat_increment`-arvo, DEM-provenienssi ja mahdollinen jälkikäsittely on selvitettävä erikseen. Älä muuta `fix_flats`-asetusta tämän tutkimuksen perusteella.

## `audit_flat_increment.py` – ei uusia rasterilukuja

Ohjelma lukee **vain kaksi edellisessä CSC-kokeessa luotua CSV-tiedostoa** ja tarkistaa SHA256-summat, 256 pistettä, kaikki 2 304 näytesolua, Whitebox-D8-askeleet sekä alkuperäiset 236/117/119/7/13 -luvut. Sen jälkeen se luokittelee jokaisen 119 pienoiskaltevuuden sen mukaan, vastaako korkeuseron itseisarvo lukua `k × 3e-7 m` kokonaisluvulla `k>=1` ensisijaisesti `1e-9 m` toleranssilla sekä erikseen ennalta määritetyillä `1e-10`, `1e-9` ja `5e-8 m` herkkyysrajoilla. Tulosteessa on `k`-histogrammi ja yhteensopimattomien määrät. **Yhteensopivuus ei todista syy-yhteyttä.**

Alkuperäisessä valmistelussa raportoitiin **9/9 synteettistä Python-testiä PASS**; myöhemmin lisättiin kaksi uutta hylkäystestiä, tiukempi toleranssi ja vaihtoehtoisten askelten vertailu. **Päivitetty 11 testin versio on NOT_RUN**, eikä todellista CSC-dataa ole käsitelty tässä vaiheessa. Varsinainen CSV-sormenjälkianalyysi on **NOT_RUN**, koska tiedostot sijaitsevat Roihulla.

Kun ajankohtaista, analyysin voi tehdä **erillisen puhtaan tämän haaran checkoutin** jälkeen, eikä rastereita tarvitse avata:

```bash
python3 -B diagnostics/low_d8_accumulation_repair_screen/audit_flat_increment.py --selftest
python3 -B diagnostics/low_d8_accumulation_repair_screen/audit_flat_increment.py --work-dir /scratch/project_2004707/pienvedet/mm_low_d8_screen.VR0UZ3WM
```

Ei uusia rastersoluja, ei uutta D8:aa, Slurmia eikä aiempien testikampanjoiden uusintaa. Tiedostot luetaan paikallisina CSV:inä vain käyttäjän erikseen käynnistämällä komennolla.

**Tieteelliset lukot:** `hydrological_validation=NOT_ASSESSED`, `channel_interpretation=NOT_ASSESSED`, `MODERATE=REVIEW_REQUIRED`, `NATIONAL=LOCKED`. Lopullinen WATER_CONNECTED-D8 ja varsinainen flow accumulation: `NOT_COMPUTED`, niiden korjaustarve: `NOT_ESTIMABLE`.
