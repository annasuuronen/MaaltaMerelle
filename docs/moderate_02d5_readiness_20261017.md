# MODERATE: 49 sisäjärven avoin syy ja erillinen 02D.5-valmiusdiagnostiikka

17.10.2026. Työmääräys: [issue #13](https://github.com/annasuuronen/MaaltaMerelle/issues/13).
Lähtöcommit ja uusi Roihu-näyttö: `de3d3808bd657c680134b578524ce4ddd4863a0c`.
Haara `codex/moderate-02d4-diagnosis`, draft PR #7. Toteutuscommit ja sen
Actions-run-ID:t kirjataan PR:n kuvaukseen tarkistuksen valmistuttua, jotta
pelkkä tarkistustuloksen kirjaaminen ei käynnistä samaa koodia uudelleen.

**Tekninen valmistelu ei ole hydrologinen hyväksyntä. MODERATE=REVIEW_REQUIRED;
NATIONAL=LOCKED.** Tuotannon `R/`-koodi, 02D.5-portti, outlet-valinta, D8,
rasterien tulokset ja historialliset CSC-skriptit säilyvät muuttumattomina.
Uusia Roihu-ajoja, täyttöjä tai D8-tutkimuksia ei tässä työssä käynnistetä.

## Mitä uusi näyttö ratkaisee

Ensisijainen tuloslähde on
[Roihu-raportti 16.10.](moderate_roihu_readonly_review_20261016.md).
Kahden read-only-ajon exit oli 0. Sen kirjaamissa 52 tapauksessa oli
29 290 järvisolua ja 14 192 rasterin sisäistä ulkorantaparia. Kolme ID:tä
(203439, 203443, 203444) koskettaa ulkoreunaa; **49 ei kosketa**.
Sisäisissä rantanaapureissa ei havaittu NoDataa, lähtöjärvipinnan min–max
oli toleranssin sisällä ja STORAGE-korotuksia ei havaittu.
Myös 159 D8-paluuta lähtöjärveen ja kolme nollapointeripäättymää järvellä
204104 vahvistettiin. Niitä ei lasketa täällä uudelleen eikä niistä päätellä
luonnollista ulostuloa.

Seuraavat aiemmat ehdotukset eivät enää kelpaa 49 sisäjärven yleisselitykseksi:
suora rasterireunan kosketus, välitön NoData-rantanaapuri tai merkittävästi
epätasainen järven lähtöpinta. Kaikkien 52 järven syyn johtaminen yhdestä
synteettisestä `flat_rim`-esimerkistä olisi edelleen perusteetonta.

**Uusi ehdollinen päätelmä pit-ehdokkaista:** saman syötepinnan ja
WhiteboxTools 2.4.0:n vertailusääntöjen vallitessa sisäisen, äärellisen
järvi-ID:n jokaisella 8-yhteysosalla on alin solu. Tällä solulla ei ole
alempaa saman osan naapuria. Jos kaikki ulkoiset naapurit ovat äärellisiä
ja korkeampia, solu täyttää alustavan pit-ehdokkaan ehdon. Positiivisen
rantakynnyksen pienin raportoitu arvo (~0.000991821 m) on selvästi suurempi
kuin järven tasaisuus- ja pintavertailutoleranssit (1e-7 m); samoilla arvoilla
korkeampaa äärellistä rantaa koskeva ehto on perusteltu. Erilliset maskiosat
eivät itsessään poista niiden omia paikallisia minimejä.

Siksi **kaikkien alkuperäisten pit-ehdokkaiden puuttuminen ei ole vahva selitys**
49 järvelle, jos alkuperäisen täyttöajon syöte vastasi nyt auditoitua pintaa.
Tämä ei todista, että kaikki ehdokkaat käsiteltiin tai että outlet löytyi:
tuotoksen vanha provenienssi ja Whiteboxin myöhemmän käsittelyn tila on vielä
erotettava alkuperäisestä geometrisesta ehdokkuudesta. Toleranssin sisäinen
tasaisuus ei myöskään tarkoita bitintarkkaa tasaisuutta: Whiteboxin pit-ehto
käyttää tarkkaa `<`-vertailua, joten ehdokkaiden lukumäärää ei voi päätellä
pelkästä toleranssiluokasta.

## Jäljellä olevat mekanismit

Whitebox v2.4.0:n
[pit-/outlet-lähde](https://github.com/jblindsay/whitebox-tools/blob/28ed01f506f2024cfb52db85348b887f2ded4e5d/whitebox-tools-app/src/tools/hydro_analysis/fill_depressions.rs)
etsii aluksi sisäisiä pit-ehdokkaita, käy niitä läpi korkeimmista alaspäin,
laajenee kasvavan korkeuden prioriteetilla ja tunnistaa ulostulon, kun
käsittelemättömästä naapurista löytyy nykyistä solua alempi arvo.
Täyttö edellyttää `outlet_found`-haaraa. `fix_flats=FALSE` poistaa myöhemmän
keinotekoisen gradientin, **ei painanteen täyttöä**.

| Hypoteesi | Nykyinen rajaus | Erottava lisätieto |
| --- | --- | --- |
| Pit-ehdokas puuttui kokonaan | Epätodennäköinen 49:n nykygeometrialla, jos sama syöte ja semantiikka | Täsmälliset pit-ehdokkaat jokaisessa maskiosassa; alkuperäisen syötteen identiteetti ja NoData-metatieto |
| Monotoninen nousu/tasanne ei tarjoa hakutilassa alempaa käsittelemätöntä naapuria | Avoin; paikallinen rantaminimi ei kuvaa laajempaa hakualuetta | Rajattu, komponenttikohtainen kasvatus: löytyykö alempi naapuri ennen ikkunan/työbudjetin rajaa? |
| Erilliset saman ID:n maskiosat vaikuttavat hakuun | Ei mitattu 16.10. raportissa | Osien lukumäärät, koot ja erikseen raportoidut hakutulokset; osia ei yhdistetä keinotekoisesti |
| Kauempi NoData tai domainin raja katkaisee kasvatusympäristön | Ei suljettu pois välittömän rannan NA-testillä | Saavuttaako rajattu kasvatus kauempana olevan ei-äärellisen naapurin tai ikkunarajan? NoDataa ei tulkita purkureitiksi |
| Koko DEM:n pit-järjestys, aiemmat täytöt tai `flats`-tila eroaa eristetystä hausta | Avoin | Jos eristetty haku löytää tavallisen kynnyksen, vertaa ennen mahdollista uutta laskentaa alkuperäisiä komento-/versio-/checkpoint-tietoja. Paikallista mallia ei väitetä koko Whitebox-ajoksi |
| Alkuperäinen STORAGE oli välimuistissa/väärä syöte, versio tai keskeytynyt tuotos | Avoin | Olemassa olevat alkuperäisen 02A:n lokit, todellinen komento/exit, binääri ja syöte-/tulosmanifestit |

V2 kopioi alkuperäiset 02A-pinnat. Alkuperäisen ja V2-kopion hash-yhtäläisyys
ei ole toinen täyttöajo. LAND_WATER- ja STORAGE-tiedostojen eri hashit eivät
yksin todista rasteriarvojen eroa (GeoTIFF-metatieto/pakkaus voi erota).
Riippumaton aiempi fill-uusintayritys päättyi timeoutiin 124 eikä tuottanut
vertailupintaa: sitä ei lasketa onnistuneeksi replikoinniksi eikä toisteta nyt.

## Erillinen raporttien valmiusluokittelija

Puhdas funktio:
[`scripts/lib/classify_02d5_readiness.R`](../scripts/lib/classify_02d5_readiness.R).
Se ei lue rastereita tai muuta tuotannon porttia. Raportin väitteiden
keskinäinen johdonmukaisuus ei ole niiden aitouden riippumaton mittaus.

Pakolliset 02D.4-yhteenvedon sarakkeet ovat `lake_objectid`, `n_lake_cells`,
`n_raised_lake_cells`, `raised_fraction`, `n_depression_components`,
`depression_component_ids`, `spill_raised`, `spill_raise_m`, `storage_raised`
ja `max_storage_raise_m`. Vanhasta `depression_status`-tekstistä ei johdeta
valmiutta; luokka lasketaan mittarisarakkeista. Muita raporttisarakkeita saa
olla mukana. Komponenttiviitteiden saman ID:n sisäiset toistot hylätään;
sama komponentti voi silti aidosti koskea eri järviä, joten viitteitä ei
vaadita globaalisti yksikäsitteisiksi.

Puuttuva/NA-arvo, väärä tyyppi, kaksoisjärvi-ID, negatiivinen tai murto-osainen
solu-/komponenttimäärä, epäjohdonmukainen korotusosuus, lippu/korkeusristiriita
tai virheellinen komponenttiviite tuottaa `NEEDS_REVIEW` ja syykoodit.
Solumäärien ja viitteiden pitää täsmätä; komponentteja ei voi olla enemmän
kuin korotettuja soluja. Tyhjä taulukko ei ole läpäisy. Vakava taulukon
rakennevirhe keskeyttää virheellä. Komponenttien rasterigeometriaa CSV:stä
ei voida todentaa.

| Tekninen luokka | Tulkinta |
| --- | --- |
| `POSITIVE_THRESHOLD_NO_OBSERVED_RAISE` | Positiivinen kynnys, nolla raportoitua korotussolua ja komponenttia; ei valmiutta komponenttiportin katselmointiin |
| `OBSERVED_COMPONENT_ELIGIBLE_FOR_GATE_REVIEW` | Johdonmukaiset raportoidut korotussolut ja 1..N komponenttia positiiviselle kynnykselle; vain tekninen katselmointiehdokkuus |
| `OBSERVED_RAISE_WITHOUT_POSITIVE_THRESHOLD` | Todellinen raportoitu osittainen korotus ilman positiivista kynnystä; säilytetään erillisenä tapauksena |
| `NO_OBSERVED_COMPONENT` | Ei positiivista kynnystä eikä raportoitua korotuskomponenttia; ei tyhjän kohdejoukon hyväksyntää |
| `NEEDS_REVIEW` | Puutteellinen tai ristiriitainen näyttö; syyt koneellisesti mukana |

Rantamaksimi on vain rantaparien lähdesolujen maksimi. Siksi nolla
`max_storage_raise_m` ja positiiviset sisäsolujen korotukset eivät ole
automaattisesti ristiriita. Ne merkitään tulkinnalla
`RAISE_NOT_DETECTED_BY_SHORE_MAX`. Useat havaitut komponentit säilytetään
erillisinä; niitä ei korvata yhdellä keksityllä komponentilla.

CLI lukee enintään 5 MiB:n CSV:n ja kirjoittaa valitun raportin **stdoutiin**:

```sh
Rscript --vanilla scripts/classify_02d5_readiness.R APPROVED_02D4_SUMMARY.csv lakes
Rscript --vanilla scripts/classify_02d5_readiness.R APPROVED_02D4_SUMMARY.csv summary
```

Järvikohtaisessa raportissa on ID, tekninen luokka, raportoidut määrät,
`evidence_consistent`, `gate_component_evidence_present`, `interpretation` ja
`review_reasons`. Koosteessa on järvien, kohteiden, puutteellisten rivien ja
katselmointiehdokkaiden lukumäärät sekä `component_evidence_complete`.
Kaikilla riveillä ja koosteessa `continuation_authorized=FALSE`,
`scientific_status=REVIEW_REQUIRED` ja `national_status=LOCKED`.
Exit 0 tarkoittaa raportin tuottamista, ei tuotantolupaa.

Nykyisten 52:n **synteettinen vastine** tuottaa 52
`POSITIVE_THRESHOLD_NO_OBSERVED_RAISE`-riviä, 106 muuta ilman komponenttia ja
`component_evidence_complete=FALSE`. Varsinaista CSC-CSV:tä ei ole ajettu
tämän uuden luokittelijan läpi tässä työtilassa; sitä ei korvata keksityillä
havainnoilla. Testi myös evaluoi nykyisen tuotannon 109-vaiheen portin
sellaisenaan synteettisellä 52-rivisellä syötteellä: se epäonnistuu edelleen.
Fixture-version ”49 järveä, tasan yksi komponentti” -ehtoa ei käytetä
todellisen tuotantoportin korvikkeena.

## Valmisteltu uusi, rajattu read-only-hypoteesikoetin

[`scripts/probe_fill_hypotheses_readonly.R`](../scripts/probe_fill_hypotheses_readonly.R)
ja sen erillinen matrix-funktio lukevat **vain ennalta rajatun ikkunan**.
Ne eivät suorita Whiteboxia, täytä pintaa, muodosta STORAGE-korotuskomponentteja,
muuta D8:aa tai kirjoita rastereita. Maskin yhteysosat ovat havaintoja
lake-ID-maskista, eivät keksittyjä depressiokomponentteja.

Raportti erottaa saman ID:n 8-yhteysosat, laskee täsmälliset alku-pit-ehdokkaat
ja tekee yhden eristetyn kasvatuskokeen kunkin osan alimmasta ehdokkaasta.
Se ilmoittaa alemman käsittelemättömän naapurin paikallisen todistajan
(rivi/sarake ja korkeudet), myös mahdollisen saman ID:n erillisen vastaanottajaosan,
kauemman ei-äärellisen kontaktin, ikkunarajan ja työbudjetin katkaisun.
Todistaja ei edellytä naapurin olevan järven lähtötasoa alempana: Whiteboxin
ehto on alempi kuin **nykyinen kasvatussolu**. Tämä ero on oleellinen
tasanne-/kynnystutkimuksessa.

Rajaukset: enintään 250 000 ikkunasolua, 158 kohde-ID:tä, 100 osaa/ID,
1 000 raporttiriviä, 2 000 käsiteltyä hakusolua/osakoe ja erikseen annettu
1..20 000 solun kokonaisbudjetti (oletus kirjastossa 10 000).
Puuttuva/rajautunut ID, lähdesolujen epäkelvot arvot, ikkunareuna tai katkennut
haku ilmoitetaan eksplisiittisesti. Koko ID:n solumäärän täsmääminen on
välttämätön kattavuustarkistus, ei syöteikkunan aitouden todistus.
Rajaan päättyvä haku on `CENSORED_*`, ei näyttö globaalin ulostulon puutteesta.
NoData-kontakti ei ole hyväksytty veden purkureitti.

Paikallinen malli ei toista koko Whiteboxin korkeimmasta pitistä alkavaa
järjestystä, aiempien täyttöjen `flats`-tilaa tai koko domainin reunakäsittelyä.
Se normalisoi ei-äärelliset arvot pois hausta, joten alkuperäisen GeoTIFFin
NoData-koodauksen vastaavuus pitää varmistaa erikseen. Tasakorkeuksien
käsittelyjärjestys voi myös erota. Siksi jokaisella rivillä
`actual_whitebox_behaviour_verified=FALSE` ja `natural_outlet_verified=FALSE`.

**Seuraavan välttämättömän Roihu-testin täsmällinen tarkoitus** on erottaa:
(1) löytyykö 49 sisäjärven todellisista maskiosista alku-pit-ehdokkaita;
(2) löytääkö samaan syötteeseen rajattu eristetty haku alemman naapurin
ennen mittausrajoja vai jääkö se tasanteelle, kauemman NoDatan tai
ikkunarajan katkaisemaksi; (3) mitkä järvet vaativat laajempaa kontekstia.
Se ei toista 159/3 D8-jakaumaa tai valmista STORAGE-korotuksia.

Ennen ajoa tarkistetaan **olemassa olevat** 02A-/Whitebox-lokit ja manifestit:
syöte, tuotos, binäärin versio/tiiviste, todellinen komento, exit, valmistumisaika
ja tiedostovälimuistin ohitus. Nykyinen auditoitu pinta ja alkuperäisen ajon
syöte eivät saa vaihtua huomaamatta. Tarkistetut ikkunat ja kohde-ID:t on
nimettävä etukäteen; niitä ei ratkaista rajattomalla hakemistohakemisella.
Mitään uutta koko 36 miljoonan solun FillDepressions-ajoa ei tarvita tähän.

Myöhemmin erikseen hyväksyttävä CLI-muoto (ei suoritettu Roihussa):

```text
Rscript --vanilla scripts/probe_fill_hypotheses_readonly.R LAND_WATER.tif LAKE_ID.tif APPROVED_TARGET_SUMMARY.csv 10000 ROW1:ROW2 COL1:COL2
```

Rivi-/sarakevälit ovat täsmällisiä numeroita ilman globia ja enintään
250 000 solua. Ilman kahta viimeistä argumenttia molempien syötteiden on jo
oltava tämän rajan sisällä. Ikkunaa luetaan laiskasti muistissa, ei tallenneta.
Tulostettavat siemen-/todistajakoordinaatit muunnetaan alkuperäisen rasterin
rivi-/sarakejärjestelmään ja ikkunan sijainti raportoidaan.
Kohdeyhteenvedon on oltava hyväksytyn katselmointipaketin pienraportti.
Tässä valmistelussa ei anneta uusia CSC-luku-, siirto- tai laskentavaltuuksia.

Jos eristetty haku löytää tavallisen ulostulotodistajan, seuraava kysymys
on alkuperäisen täyttöajon provenienssi ja koko ajon hakutila, ei portin
ohitus. Jos haku rajautuu, tulos kertoo tarvittavan lisäkontekstin, ei syytä.
Jos täydellinen äärellinen osa tutkitaan ilman todistajaa, se tukee kyseisen
paikallisen hakumekanismin hypoteesia; silloinkin alkuperäinen Whitebox-ajo
ja hydrologinen ratkaisu odottavat riippumatonta todentamista.

## Testit ja CI-ketju

Paikallisesti rinnakkain: `tests/readiness_02d5.R` (**64** synteettistä
tarkistusta) ja `tests/fill_hypothesis_probe.R` (**22** tarkistusta).
Jälkimmäinen testaa myös kauemman NoDatan, osamaskit, täsmällisen pit-ehdon,
budjetin, rajautumisen sekä stdout-only-CLI:n ja alkuperäisten
ruutukoordinaattien säilymisen. Kaikki aineistot ovat tilapäisiä synteettisiä
matriiseja/rasternäytteitä; syötteiden muuttumattomuus tarkistetaan.

Nykyinen default-haaran `moderate_autostart.yml` ajaa neljä riippumatonta
suitea onnistuneen tämän PR:n `CSC preflight`-ajon jälkeen. Sitä tai
preflightia ei muuteta. Uudet base-R-testit lisätään nykyiseen
`spill_storage`-entrypointiin ja uudet ikkunatestit nykyiseen `geometry`-entrypointiin.
`d8` ja `whitebox_integration` säilyvät erillisinä eikä niissä toisteta näitä
uusia testejä. Uutta päällekkäistä workflowta/dispatchia ei luoda. Lähdetiedoston
puuttuminen tai assertion-virhe päättää oman suiten virheeseen; olemassa oleva
kooste hylkää epäonnistuneen, ohitetun tai perutun jobin.

Paikallinen R on 4.2.2, terra 1.7.29; terra ilmoittaa olevansa rakennettu
R 4.2.3:lla. GitHubin ajon R/terra ja Whitebox-binäärin todelliset versiot
ja tiivisteet tarkistetaan ajolokista; Roihun 16.10. ympäristö oli eri
(R 4.6.1, terra 1.9.34). Luokittelija ei tarvitse terraa tai Whiteboxia;
ikkuna-CLI tarvitsee terraa, ei Whitebox-binääriä. Alkuperäisen CSC-täyttöajon
provenienssia ei korvata CI:n versiotiedoilla.
