# Maasolun ensimmäinen vesistökontakti: rajattu menetelmäprototyyppi

Tämä on synteettisesti testattava tutkimusmenetelmä, ei tuotantoreititys.
Ei rasterilukuja, CSC-ajoja, Whiteboxia, outlet-valintaa, kertymää tai
tiilien yhdistämistä. **MODERATE=REVIEW_REQUIRED; NATIONAL=LOCKED.**

## Lähtö ja vertailuhaara

- Uusi haara: `codex/land-first-water-prototype`.
- Lähtö: PR #12:n `codex/low-d8-scope-options`, commit
  `cd9612aa1cb4dd39bc6b33d825302202b28ef09e`.
- Mahdollisen draft PR:n kohde on **`codex/low-d8-scope-options`**, jolloin
  diff sisältää tämän prototyypin eikä PR #12:n keskeneräistä LOW-tutkimusta
  ehdoteta tämän muutoksen mukana baselineen. Nykyisiä PR:iä ei yhdistetä.
- Tieteellinen rajaus: [suunnitelma PR #15:n commitissa a8789f4](https://github.com/annasuuronen/MaaltaMerelle/blob/a8789f4c2be3e2071e9ac511c9858cc956e95a84/docs/maaltamerelle_maa_vesi_soluverkko_tutkimussuunnitelma.md).

`first_water_contact.R` käyttää sellaisenaan tiedoston
`diagnostics/low_d8_scope/lake_1847_focus_core.R` funktiota `l1847_trace()`.
Vanha ydin, LOW:n 1847-regressiot ja tuotannon 02F säilyvät muuttumattomina.
Kutsu tekee yhden jäljityksen. Sen `read_cell`-kuori kirjaa kontaktia
edeltävän maasolun; toista itsenäistä jäljitystä ei tehdä.

## Syöte ja tulossopimus

Lataa ensin vanha ydin ja sitten sovitin. Funktio on:

```r
first_water_contact(start, grid, read_cell, max_steps = 128L, provenance)
```

`start` on paikallisen ruudukon 1-pohjainen rivijärjestyksen maasolunumero.
`read_cell(cell)` palauttaa yhden solun listana: numeeriset `pointer`,
`water_class`, `lake_id` ja loogisen `valid`. Viimeinen tarkoittaa erikseen
aineiston/domainin kelvollisuutta. Kelvollisen maasolun vesiluokka on `NA`;
vesiluokat ovat 1 = järvi, 2 = jokialue ja 3 = uomaviiva. `valid=FALSE`
pysäyttää ennen solusta jatkamista tilaan `NO_DATA`. Puuttuva pointeri ei
yksin osoita NoDataa. Virheellinen havaintorakenne hylätään virheenä.
Vesiluokalla on oltava kelvollinen arvo ja lähtösolun on oltava maata.

`grid` sisältää `grid_id`, `nrow`, `ncol`, `row_offset`, `col_offset`,
`xmin`, `ymax`, `resolution_m=2` ja `crs="EPSG:3067"`. Origo `xmin,ymax`
on **yhteisen globaalin ruudukon** vasen yläkulma, ei jokaisen ikkunan
oma origo. Offsetit ovat ikkunaa edeltävien rivien/sarakkeiden määrät.
Rivit kasvavat etelään, sarakkeet itään. UID on
`grid_id:global_row:global_col`, ja koordinaatit ovat solukeskipisteitä.
Samalla globaalilla ruudukolla eri ikkunoiden sama solu saa saman UID:n.
Tämä tunnistesopimus ei vielä toteuta kansallista rekisteriä tai tiilisiirtoa.

`provenance` vaatii merkkijonot `run_id`, `code_revision`, `pointer_source`,
`water_source`, `lake_id_source`, `validity_source`, `lake_id_namespace`.
Ne ovat kutsujan ilmoituksia: `provenance_verification="DECLARED_ONLY"`.
Prototyyppi ei varmista tiedostotiivisteitä tai historiallista syntyprovenienssia.

Tulos on lista. `source`, `first_successor`, `terminal`, `last_land` ja
`first_water` sisältävät paikallisen solun, UID:n, globaalin rivin/sarakkeen,
keskipistekoordinaatit ja CRS:n. Kontaktikohtaiset `last_land` ja `first_water`
ovat `NULL`, ellei vettä saavuteta. `first_successor` on ensimmäinen
jäljityksessä luettu seuraajasolu; se on `NULL`, jos seuraajaa ei havaita
paikallisen ruudukon sisällä. Ulkoraja jää `DOMAIN_EXIT_UNRESOLVED`-tilaan.

`water_reached`, `recipient_identified` ja
`hydrological_validation="NOT_ASSESSED"` ovat eri asioita. Kelvollinen
järvitunnus sidotaan ilmoitettuun nimiavaruuteen. Puuttuva/virheellinen
järvitunnus säilyttää saavutetun kontaktin mutta ei tunnistettua vastaanottajaa;
raaka-arvo näkyy `observed_lake_id`-kentässä. Pelkkä jokialue-/uomaviivaluokka
ei saa keksittyä kohde-ID:tä. Epävarmuuden syyt säilyvät erikseen.

## Päättyminen ja laskurit

Ytimen tilat säilytetään `raw_trace_status`-kentässä. Sovitin nimeää
`REACHES_WATER_CLASS` → `FIRST_WATER_CONTACT`, `MAX_STEPS` → `STEP_LIMIT`
ja `DOMAIN_EXIT` → `DOMAIN_EXIT_UNRESOLVED`. Muut ytimen tilat ovat
`D8_ZERO`, `POINTER_NA`, `INVALID_POINTER` ja `CYCLE`. Sovittimen oma
kelvollisuus-/luokkatarkistus voi päättää `NO_DATA`- tai
`INVALID_WATER_CLASS`-tilaan; silloin ydin ei palauttanut omaa statusta
ja `raw_trace_status=NA`.

`n_transitions` laskee toteutuneet ruudukon sisäiset D8-siirtymät, myös
syklin sulkevan siirtymän. Ulkorajan yli yritettyä askelta ei lasketa
toteutuneeksi. `n_cell_reads` laskee callback-kutsut; sykliin palaavaa
solua ei lueta uudelleen. NoData-soluun päätyminen kirjaa siihen tehdyn
siirtymän ja havainnon, mutta ei reititä solusta eteenpäin.

Raja on 1–256 siirtymää vanhan ytimen mukaisesti. Vesi tarkistetaan myös
täsmälleen viimeisen sallitun siirtymän jälkeen. Samoin todellinen
nollapääte tai sykli voi ratketa rajalla ilman `STEP_LIMIT`-luokkaa.
02F:n nykyinen `max_steps`-sopimus tarkistaa solun ennen jokaista
siirtymää eikä tarkista viimeisen siirtymän kohdetta samalla tavalla.
Myös sen syklin askellaskenta eroaa. **02F:n merkityksiä ei muuteta.**

## Rajatut paikalliset tarkistukset

Aja repositorion juuresta Base R:llä, ilman terraa tai Whiteboxia:

```bash
Rscript --vanilla diagnostics/land_first_water/test_first_water_contact.R
Rscript --vanilla diagnostics/low_d8_scope/test_lake_1847_focus.R
Rscript --vanilla tests/water_connected_route_diagnostics.R
```

Uusi testi käyttää pieniä käsin määriteltyjä 2 m ruudukoita ja laskee
suoritetut tapaukset. Tyhjä tai epäonnistuva testijoukko ei ole PASS.
Testit eivät todista todellisen LOW:n vastaanottajia, DEM:n oikeellisuutta,
koko alueen kattavuutta tai menetelmän skaalautuvuutta.

Paikallinen tarkistus 19.10.2026 (Base R 4.5.0): uusi testijoukko
`TESTS=26 PASS=26 FAIL=0`; vanhat 1847- ja 02F-regressiot kumpikin PASS.
Tämä ei ole CSC- tai todellisen aineiston testitulos.

Seuraava erikseen hyväksyttävä oikean aineiston koe: valitaan muutama
LOW:n **olemassa olevan** `02B_land_to_first_water_entries.csv`-raportin
maasolualoitus ja tarkistetaan niiden yhden askeleen kontaktit raportin
`source_cell`, `receiver_cell`, `water_class` ja `lake_objectid`-tietoja
vasten. Järvi-, jokialue- ja uomaviivatapauksia käytetään vain, jos niitä
on todellisessa raportissa. Aineistosidonta varmennetaan ensin. Mahdollinen
rajattu rasteriluku edellyttää erillistä hyväksyntää; koetta ei ajeta nyt.
