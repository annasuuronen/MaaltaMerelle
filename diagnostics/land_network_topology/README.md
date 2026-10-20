# Rajatun maa-alueen D8-verkon topologia

Base R -tutkimusprototyyppi käsittelee **kaikki valmiiksi syötetyn pienen
ikkunan kelvolliset maasolut**. Se ei edellytä RANTA10-kontaktia eikä lue
CSV:tä tai rastereita. Erillinen, vain lukeva R/terra-ajuri valmistelee
matriisit yhdestä ennalta määrätystä LOW-ikkunasta. Käyttäjä on raportoinut
sekä alkuperäisen kokeen että poistumisinventaarion todelliset CSC-tulokset.
Tämän haaran uusi vastaanottajasolujen tarkistus lukee vain 14 lukittua
solua; sitä ei ole ajettu todellisella CSC-aineistolla. Ei Whitebox-ajoja, uutta D8:aa,
kertymälaskentaa tai oja-/pienvesiluokitusta.

`hydrological_validation=NOT_ASSESSED`; `channel_interpretation=NOT_ASSESSED`.
**MODERATE=REVIEW_REQUIRED; NATIONAL=LOCKED.**

## Lähtö ja rajaus

- Haara: `codex/low-boundary-receivers-v1`.
- Lähtö on PR #21:n `40509d5006cbf7fb431701e7a48383dde0fdb38c`.
  Se säilyttää PR #20:n `ffcdfe93`, PR #19:n `63cfcb67` ja PR #17:n
  `753ac0d5` menetelmät.
- Draft PR:n kohde on **`codex/low-land-network-exits-confluences-v1`**. PR #18:n
  muutoksia ei yhdistetä tähän haaraan; baselinea, mainia tai aiempia
  tutkimushaaroja ei muuteta.
- Riippuvuudet ovat PR #12:n LOW-ydin, PR #16:n ensikontaktisovitin ja
  PR #17:n reittihavainnoija. Näiden tiedostojen toiminta säilyy ennallaan.

PR #18:n `08ef53bdb1886cca9d6abcd3574dd40e945f6285` ja käyttäjän
toimittamat LOW-tulokset ovat taustatietoa. Kuusi aiempaa 02B-kontaktia
valittiin vesistökontaktien joukosta. Se ei ole maa-alueen verkon edustava otos.
Vain kahdesta on tässä toimeksiannossa vahvistettu todellinen rasteritulos:

| Lähde → vastaanottaja | Kontakti | Raportoitu paikallinen verkko |
| --- | --- | --- |
| `13492315` → `13486314`, D8=64 | Järvi 1847; yksi siirtymä | `CORE_UPSTREAM_N=0`, `CORE_LAND_EDGES=44`, `CORE_TO_HALO_EDGES=2` |
| `32005997` → `31999998`, D8=1 | Uomaviiva, luokka 3; yksi siirtymä | `CORE_UPSTREAM_N=0`, `CORE_LAND_EDGES=36`, `CORE_TO_HALO_EDGES=3` |

Molemmat reitit saivat `FIRST_WATER_CONTACT`-tilan. Ympäröivien maa→maa-reunojen
olemassaolo ei yksin osoita yhteyttä näihin vesistökontakteihin. Tämä ei osoita koko alueen
maareittien puuttumista. Neljän muun valitun lähteen `33517609`, `26761820`,
`8093069` ja `24946803` tulokset ovat vahvistamatta; niitä ei päätellä näistä
kahdesta eikä korvata onnistuneemmilla kontakteilla. Raakoja CSC-tiedostoja
ei ole luettu tätä synteettistä prototyyppiä varten.

## Käyttäjän raportoima todellinen LOW-ikkuna 20.10.2026

Käyttäjä ilmoitti vain lukevan CSC-kokeen onnistuneen commitilla
`ffcdfe93262d02bb453109481afd1ff8991d80bb`. Tämä on käyttäjän toimittama
tulosnäyttö; Codex ei ole lukenut kokeen CSC-tiedostoja tai yksittäisiä
pointeriarvoja. Seuraavia lukuja ei tuoteta tämän haaran synteettisistä testeistä.

Ruudukko oli LOW `E200000_N6900000`, 6000 × 6000, EPSG:3067, 2 m,
Whitebox-D8. Ikkuna oli riveillä ja sarakkeilla 2995–3005 ja 9 × 9 ydin
riveillä ja sarakkeilla 2996–3004.

| Raportoitu havainto | Ydin | Halo | Yhteensä |
| --- | ---: | ---: | ---: |
| Kelvolliset maasolut | 81 | 40 | 121 |
| Paikalliset yhtymäsolut | 12 | 6 | 18 |

| Maa→maa-reunaluokka | Reunoja |
| --- | ---: |
| `CORE_TO_CORE` | 66 |
| `CORE_TO_HALO` | 15 |
| `HALO_TO_CORE` | 2 |
| `HALO_TO_HALO` | 22 |
| Yhteensä | 105 |

Kaikki 121 lähtöreittiä saivat `DOMAIN_EXIT_UNRESOLVED`-tilan; muita
päättymistiloja ei raportoitu. Ensimmäiset RANTA10-kontaktit olivat
`NOT_OBSERVED`. Neljä rasterilukukutsua palautti 484 arvoa; muistissa
toteutui 356 reittisiirtymää ja 477 soluhavaintokutsua.

Erotus **121 − 105 = 16** oli näiden raportoitujen lukujen perusteella
muodostettu ehdollinen päätelmä suorista poistumistapahtumista. Tuolloin
erillistä poistumisinventaariota ei ollut vielä ajettu. Päätelmä
edellyttää, että jokainen maasolun lähtö on joko sisäinen maa→maa-reuna tai
suora poistuminen ja että muiden päättymisten tai rajautumisten vaikutus on
selvitetty. 121 reittijäljitystä ei tarkoita 121 uniikkia poistumista.
Inventaario tarkistaa topologian eikä sisällä tavoitearvoa 16. Käyttäjän
myöhemmin toimittama, commitilla `40509d5` tehty todellinen inventaario
vahvisti 16 poistumista ja 14 ennustettua vastaanottajaa. Sen lukittu
taulukko ja tämän haaran seuraava tarkistus kuvataan alla.

Paikalliset yhtymät tai poistumiset eivät vahvista ojaa, rumpua, pienvettä
tai hydrologista purkupistettä. `CODE_VERSION_VERIFICATION=LOCAL_GIT_CLEAN`
koski käytettyä koodia; `HISTORICAL_SOURCE_COMMIT=UNKNOWN` ja
`HISTORICAL_PROVENANCE=INCOMPLETE` säilyvät erillisinä havaintoina.

## Lukittu 14 vastaanottajasolun tarkistus

`low_boundary_receivers_targets.csv` tallentaa käyttäjän toimittamat kaikki
16 poistumisriviä. Lähde on Roihun onnistunut `UNIQUE_WINDOW_EXIT_EDGES`-
inventaario commitilta `40509d5006cbf7fb431701e7a48383dde0fdb38c`:
16 riviä, `TRUNCATED FALSE`, `TOPOLOGY_ACCOUNTING_QA=PASS`.
Ilmoitettu alkuperäinen `ADLER32_SERIALIZE_ASCII_V2` on `0f39c62a`.
Tämä on käyttäjän raportoima täyden R-taulun tarkistussumma, jota ei lasketa
uudelleen tästä sarakeprojektiosta eikä väitetä riippumattomasti varmennetuksi.
Poistumisen `exit_id` ja lähteen rivi/sarake on johdettu toimitetusta UID:stä.
Muut taulukon arvot ovat annetut alkuperäiset arvot. Uusia kohteita ei valita.
Kaikkien vastaanottajien alkuperäinen tila oli `WINDOW_EXIT_INSIDE_FULL_GRID`
ja `receiver_raster_read=FALSE`. Tässä taulukossa ei ole vastaanottajien sisältöä.

Uniikit ennustetut vastaanottajat samalla 6000 × 6000 ruudukolla ovat:

| Rivi | Sarake | Poistumisreunoja | Raportoituja lähtöreittejä |
| ---: | ---: | ---: | ---: |
| 2995 | 2994 | 1 | 5 |
| 2995 | 3006 | 1 | 6 |
| 2996 | 2994 | 1 | 5 |
| 2996 | 3006 | 1 | 6 |
| 2997 | 2994 | 1 | 4 |
| 2997 | 3006 | 1 | 6 |
| 2998 | 2994 | 1 | 4 |
| 2998 | 3006 | 1 | 8 |
| 2999 | 2994 | 1 | 3 |
| 3000 | 2994 | 2 | 20 |
| 3005 | 2994 | 1 | 1 |
| 3006 | 3002 | 2 | 32 |
| 3006 | 3004 | 1 | 16 |
| 3006 | 3005 | 1 | 5 |

`boundary_receivers.R` sisältää Base R -menetelmät:

- `low_boundary_targets(exits, locked_exits)` vertaa kaikki 16 lähde- ja
  vastaanottajariviä lukittuun taulukkoon, tarkistaa UID:t, rajat, 16→14-
  ryhmittelyn ja raportoidun reittisumman 121. Deduplikointi tapahtuu ennen
  rasterilukua. Sama vastaanottaja luetaan kerran rasteria kohti.
- `observe_boundary_receivers(targets, samples)` luokittelee 14 havaintoa
  ja palauttaa myös kaikki 16 alkuperäistä poistuminen→vastaanottaja-liitosta.
  LAND_WATER-arvon äärellisyys määrittää kelvollisuuden. Kelvollisen pinnan
  vesiluokan NA tarkoittaa `LAND`, luokat 1–3 `WATER` ja muu luokka `UNCLEAR`.
  Epäkelvollinen pinta on `NO_DATA`. Raaka-arvot säilyvät.
- Pointerin `D8_ZERO`, `POINTER_NA`, `INVALID_POINTER` ja `VALID_D8_CODE`
  säilyvät erillisinä. Pointeria ei seurata. Kelvollinen järvitunnus
  säilytetään vain kelvollisella järvisolulla; puuttuvaa tai virheellistä
  tunnusta ei korvata. Jokialueelle tai uomaviivalle ei keksitä kohdetunnusta.
- `read_boundary_cells()` sallii vain 14 yksilöllistä kokonaislukuindeksiä
  ja neljä rasteria. Se hylkää ylimääräiset, duplikaatit, murtoluvut ja
  vääränkokoiset lukijan palautukset.

`run_low_boundary_receivers.R` käyttää samaa metadata-/otsake-esitarkistusta
kuin ikkuna-ajuri (`low_network_open_inputs()`), mutta ei kutsu ikkuna-ajuria
tai verkkotopologian jäljitystä. Manifestin `key,value`, QA:n `item,value`,
yhteinen geometria, yksi taso, 6000 × 6000, EPSG:3067 ja 2 m tarkistetaan
ennen soluarvojen lukua. Vesiluokka ja järvitunnus tulevat manifestin poluista.

Ajuri tekee neljä `terra::extract(raster, numeric_cell_ids, raw=TRUE)`-kutsua,
14 solutunnusta kussakin: yhteensä **56 palautettua rasteriarvoa**.
Numeerinen argumentti tarkoittaa globaalin rasterin solutunnuksia, ei
koordinaattipareja. Kokonaislukutarkistus estää `extract()`-rajapinnan
sisäisen pyöristyksen muuttamasta kohdetta. Tunnus on
`(global_row - 1) * 6000 + global_col`. Ei 11 × 11 ikkunan uusintalukua,
naapuruston lukua tai reittien seuraamista vastaanottajasta eteenpäin.
Raja koskee pyydettyjä ja palautettuja soluarvoja; GDAL voi käsitellä
TIFF-lohkoja sisäisesti. Alkuperäisiin aineistoihin ei kirjoiteta.

Myöhemmin erikseen hyväksyttävän käytön komentomuoto on:

```text
Rscript --vanilla diagnostics/land_network_topology/run_low_boundary_receivers.R [BASELINE_DIR]
```

CLI käyttää vain samaan puhtaaseen Git-checkoutiin kuuluvaa lukittua CSV:tä.
Kohdejoukon vaihtamiseen ei ole komentoriviargumenttia. Repositorion origin
ja koodicommit tarkistetaan; valinnainen `MM_EXPECTED_COMMIT` lukitsee SHA:n.
Kutsuttavan worker-funktion testisyötteet eivät ole vaihtoehtoinen CSC-ajolupa.

Tulosteen `OBSERVED_RECEIVERS` sisältää 14 solua ja `ORIGINAL_EXIT_TO_RECEIVER_LINKS`
kaikki 16 poistumista lähde- ja vastaanottaja-UID:ineen. `SHARED_RECEIVER_CELLS`
erottaa kaksi yhteistä solua. `d8_code` on alkuperäisen poistumisen pointeri;
vastaanottajan `pointer` on erikseen luettu arvo. Yhteinen koordinaatti
osoittaa saman ennustetun kohdesolun; sen kelvollisuus raportoidaan erikseen.
Tämä ei vielä osoita vastaanottajan jälkeistä reittiä. LAND ei vahvista ojaa,
WATER ei hyväksy purkupistettä, eikä raportoitu 20/32 lähtöreitin määrä ole
virtauskertymä. HISTORICAL-provenienssi jää edelleen keskeneräiseksi.

Tämän haaran todellista CSC-lukua ei ole suoritettu. Paikallinen tarkistus:

```bash
Rscript --vanilla diagnostics/land_network_topology/test_boundary_receivers.R
```

20.10.2026 paikallinen R 4.5.0 / terra 1.8.29: **21 PASS, 0 FAIL, NOT_RUN=0**.
Testit tarkistivat kaikki toimitetut koordinaatit ja liitokset sekä synteettiset
NoData-/luokka-/pointerihavainnot. Kolme terra-integraatioryhmää sisälsi
epäsäännölliset solutunnukset pienessä suorakulmaisessa GeoTIFFissä,
14 solun lähderasterit 6000 × 6000 VRT-otsakkeissa sekä oikean CLI-käynnistyksen
tilapäisestä Git-repositoriosta. Yhtään todellista CSC-rasteriarvoa ei luettu.

## Syöte ja käyttö

Lataa repositorion juuresta olemassa olevat riippuvuudet tässä järjestyksessä:

```r
source("diagnostics/low_d8_scope/lake_1847_focus_core.R")
source("diagnostics/land_first_water/first_water_contact.R")
source("diagnostics/land_d8_continuity/trace_land_d8_route.R")
source("diagnostics/land_network_topology/land_network_topology.R")
source("diagnostics/land_network_topology/analyse_land_network_topology.R")

network <- build_land_d8_network(
  pointer, water_class, valid, grid, provenance,
  lake_id = NULL, max_steps = 32L
)
table(network$route_summary$route_status)
window_cases <- select_land_network_cases(network) # aiempi oletus: koko ikkuna
core_cases <- select_land_network_cases(network, scope = "core")
halo_cases <- select_land_network_cases(network, scope = "halo")
inventory <- analyse_land_network_topology(network)
```

`pointer` ja `water_class` ovat samankokoisia numeerisia matriiseja;
sekä integer että double hyväksytään. `valid` on samankokoinen looginen
matriisi ilman puuttuvia arvoja. Valinnainen `lake_id` on samankokoinen
numeerinen matriisi; ilman sitä järvitunnus jää tuntemattomaksi.
Ikkunassa saa olla enintään **121 solua**, ja `max_steps` on kokonaisluku
väliltä **1–256**. Myös kokonaan vedestä tai kelvottomista soluista koostuvan
ikkunan syötesopimus tarkistetaan; nollan maasolun tulos on eksplisiittinen.

Kelvollinen maa tarkoittaa `valid=TRUE` ja `water_class=NA`. Vesiluokat
1, 2 ja 3 tarkoittavat järveä, jokialuetta ja uomaviivaa. Maa-/vesiluokitus
ja havaintojen kelvollisuus ovat eri asioita: vesiluokan NA ei yksin ole
NoDataa. Puuttuva, nolla ja virheellinen pointeri raportoidaan erikseen.

`grid` ja `provenance` noudattavat PR #16:n sopimusta. Ruudukko määrittää
`grid_id`, `nrow`, `ncol`, `row_offset`, `col_offset`, `xmin`, `ymax`,
`resolution_m=2` ja `crs="EPSG:3067"`. `xmin,ymax` on yhteisen globaalin
ruudukon vasen yläkulma, ei paikallisen ikkunan origo. Offsetit kertovat
ikkunaa edeltävien rivien ja sarakkeiden määrän. Solut ovat 1-pohjaisia
rivijärjestyksen indeksejä. UID on `grid_id:global_row:global_col`;
keskipisteet ovat `x=xmin+(col-0.5)*2`, `y=ymax-(row-0.5)*2`.
Näin päällekkäisten ikkunoiden sama solu saa saman tunnuksen.

Provenienssi vaatii kentät `run_id`, `code_revision`, `pointer_source`,
`water_source`, `lake_id_source`, `validity_source`, `lake_id_namespace`.
Ne ovat kutsujan ilmoittamia, eivät varmennettuja tiedostotunnisteita:
`provenance_verification=DECLARED_ONLY`. Tuntematonta kohdetunnusta ei keksitä
vesiluokan perusteella.

## Graafi, reitit ja päättyminen

Jokaisesta kelvollisesta maasolusta tehdään **yksi** kutsu muuttumattomaan
`trace_land_d8_route()`-havainnoijaan täydellä annetulla askelrajalla.
Havainnoija käyttää vanhaa ensikontakti- ja LOW-ydintä. Uutta itsenäistä
D8-dekooderia tai reititysmoottoria ei muodosteta.

Graafiin otetaan kustakin lähdesolusta vain tämän reitin **ensimmäinen
toteutunut siirtymä**. Siten yhteiset alavirran reunat säilyvät verkossa vain
kerran, vaikka ne esiintyvät useiden lähdesolujen kokonaisissa reiteissä.
Esimerkiksi `A → B`, kun B:n oma pointeri on nolla, on A:n
`outgoing_kind=LAND_TO_LAND`; A:n koko reitin `route_status=D8_ZERO`.
Lähtevän reunan laji ja kauempana olevan terminaalin tila eivät ole sama kenttä.

Tulos sisältää `cells`, `land_nodes`, `edges`, `land_edges`, `confluences`,
`routes`, `route_summary`, `core_land_nodes`, `halo_land_nodes`,
`land_edge_zone_counts` ja `work_budget`.
Maasolutaulukoissa ovat muun muassa
`land_indegree_in_window`, `outgoing_kind`, `route_status` ja `is_confluence`.
Yhtymässä vähintään kaksi erillistä maareunaa tulee samaan maasoluun.
Sen havaittu yhteinen alavirran jatko on `routes[[cell_uid]]`, missä
`cell_uid` on yhtymäsolun tunnus. Jatko säilyy annetun työrajan mittaisena.
NoDataan tai virheelliseen luokkaan johtava havaittu spatiaalinen siirtymä
säilytetään, mutta sitä ei lasketa kelvolliseksi maa→maa-reunaksi.

Reittitiloina säilyvät `D8_ZERO`, `POINTER_NA`, `INVALID_POINTER`, `NO_DATA`,
`CYCLE`, `DOMAIN_EXIT_UNRESOLVED`, `STEP_LIMIT` ja `FIRST_WATER_CONTACT`.
Virheellinen vesiluokka ei muutu maaksi tai onnistuneeksi kontaktiksi.
Ikkunan ulkopuolista kohdesolua ei keksitä, eikä poistuminen osoita
hydrologista katkosta. Askelrajaan pysähtyminen on rajautunut havainto.
Syklin sulkeva siirtymä kuuluu reittiin ilman solun uutta havaintolukua;
täsmälleen viimeisellä sallitulla siirtymällä saavutettu vesi tunnistetaan.
PR #16:n ja tuotannon 02F:n aiemmat laskurimerkitykset säilyvät muuttumattomina.

Paikallinen indegree ei ole todistus latvauomasta tai kokonaisesta
valuma-alueesta. Rajan ulkopuoliset tulot jäävät tuntemattomiksi:
`external_inflow=UNKNOWN`, `upstream_coverage=WINDOW_ONLY`,
`accumulation=NOT_COMPUTED`. Pintagraafi ei kuvaa itsestään salaojavirtausta,
rummun kapasiteettia tai tapahtumakohtaista virtaamaa.

## Ydin ja halo

`cells`- ja `land_nodes`-taulujen `is_core` ja `is_halo` erottavat
analyysiytimen yhden solun ulkorenkaasta. 11 × 11 ikkunan paikalliset
rivit 2–10 ja sarakkeet 2–10 ovat 9 × 9 ydin; muut 40 solua ovat halo.
Sama sääntö koskee pieniä synteettisiä suorakulmaisia ikkunoita. Jos
ikkunassa ei ole sisäsoluja, ydin on tyhjä ja ydintapaukset puuttuvat.

Kaikki ikkunan kelvolliset maasolut ja niiden lähtevät reunat säilyvät
verkossa. `edges` sisältää kentät `from_is_core`, `to_is_core` ja
`zone_transition`. `land_edge_zone_counts` raportoi vain kelvolliset
maa→maa-reunat neljässä luokassa, myös nollamäärät:
`CORE_TO_CORE`, `CORE_TO_HALO`, `HALO_TO_CORE`, `HALO_TO_HALO`.
Maa→vesi- ja kelvottomiin soluihin johtavat reunat säilyvät erikseen
`edge_kind`-kentän perusteella. Ikkunasta poistumiselle ei keksitä
vastaanottajasolua tai alueparia.

Ytimen yhtymä on **ytimessä sijaitseva maasolu**, johon tulee vähintään
kaksi kelvollista maa-D8-reunaa. Tuloreuna saa alkaa myös halosta.
Paikallista `land_indegree_in_window`-lukua ei rajata ydin→ydin-reunoihin,
eikä halo→ydin-reunaa tulkita koko yläpuolisen valuma-alueen kertymäksi.
Halossa sijaitseva yhtymä raportoidaan, mutta se ei kelpaa ydintapaukseksi.

## Esimerkkien deterministinen valinta

`select_land_network_cases(network, scope = "window")` palauttaa aina
neljä tapausriviä. Oletus `window` säilyttää aiemman koko ikkunan valinnan.
`scope="core"` rajaa ehdokkaan lähtösolun ytimeen ja `scope="halo"`
haloon; koko rajattu alavirran reitti saa silti kulkea molemmilla alueilla.
Yhtymätapauksessa ehdokas on yhtymäsolu.

| Tapaus | Ikkunassa havaittu ehto |
| --- | --- |
| `CONFLUENCE` | Maasolun paikallinen maa-indegree vähintään kaksi. |
| `LAND_CHAIN` | Reitissä vähintään kaksi maa→maa-siirtymää. |
| `ZERO_CHAIN` | Vähintään yksi maa→maa-siirtymä ja reitin pääte `D8_ZERO`. |
| `BOUNDARY_CHAIN` | Vähintään yksi maa→maa-siirtymä ja pääte `DOMAIN_EXIT_UNRESOLVED`. |

Kunkin ehdon täyttävistä valitaan pienin **numeerinen globaali rivi ja
sarake**, ei pisintä reittiä tai vesistökontaktia. Tila on `SELECTED` tai
`NOT_OBSERVED`. Sama solu voi täyttää useamman ehdon. Puuttuva tapaus
tarkoittaa, ettei sitä havaittu annetussa ikkunassa ja työrajassa; se ei
osoita kyseisen ilmiön puuttumista LOW:sta tai maastosta. Valinta ei poista
muita solmuja, reunoja, reittejä tai epäonnistumisen syitä tuloksesta.
Jos kelvollinen tapaus on vain halossa, ydintaulukossa säilyy
`NOT_OBSERVED`; erillinen halotaulukko näyttää halohavainnon. Ajuri
raportoi molemmat eikä siirrä tutkimusikkunaa puuttuvan ydintapauksen vuoksi.
Tapausrivien `scope`, `n_matches`, `n_matches_window`, `n_matches_core` ja
`n_matches_halo` säilyttävät valinnan rajauksen ja eri alueiden ehdokasmäärät.
Ennen tätä korjausta tallennetun v1-tuloksen koko ikkunan valinta on yhä
mahdollinen ilman aluekenttiä, mutta tuntemattomia ydin-/halomääriä ei
muuteta nolliksi. Ydin- tai halovalinta edellyttää aluekenttiä.

## Yhtymien, yhteisten osuuksien ja poistumisten inventaario

`analyse_land_network_topology(network, full_grid = NULL)` käsittelee vain
valmiin `network`-olion solmuja, kanonisia reunoja ja jo tallennettuja
reittihavaintoja. Se ei kutsu reittiytimiä tai solulukijaa uudelleen eikä
täydennä katkennutta reittiä graafin avulla työrajan ohi. Analyysi ei
kuluta uusia rasterilukuja tai muuta aiemman jäljityksen työbudjettia.

Yhtymän yksilöi maasolun globaali UID. Sen tietueeseen liitetään
globaali rivi ja sarake, ydin-/halo-asema, paikallinen indegree, saapuvien
kanonisten maa→maa-reunojen lähdesolut ja pointerit sekä solmun oma
lähtevä reuna tai terminaalitila. Ytimen yhtymän halosta tulevat reunat
säilyvät. Vesisolut eivät ole näitä maa-D8-yhtymiä.

Yhteisen alavirran osuuden kuvaus alkaa yhtymäsolusta ja käyttää sen
omaa valmista reittitietuetta. Solujen ja reunojen järjestys säilyy,
ja reunaviittaukset kohdistuvat yhteisen graafin yksilöllisiin
`edge_id`-tunnuksiin. Sama reuna voi olla usean yhtymäosuuden viittaus;
sitä ei lisätä uudelleen kanoniseen reunaverkkoon. Osuudelle ilmoitetaan
havaittujen reunojen määrä ja niiden geometrinen pituus: kohtisuora
2 m, diagonaalinen `sqrt(8)` m. Ulkopuolelle ennustettua askelta ei lisätä
havaittuun osuuteen tai sen pituuteen.

Lähtösolu yhdistetään yhtymään vain, jos tämän solun **alkuperäinen rajattu
reittihavainto** saavutti yhtymän. Sama lähde voi esiintyä usean alavirran
yhtymän yhteydessä mutta vain kerran samassa lähde–yhtymä-parissa.
Lähteen käytettävissä oleva yhteinen jatko voi olla yhtymäsolun omaa
reittikuvausta lyhyempi, jos lähteen askelraja tulee vastaan. Koko yhteistä
osuutta ei tällöin väitetä havaituksi kyseisen lähteen reitissä.

Suora poistumistapahtuma on maasolmu, jonka **oma**
`outgoing_kind=DOMAIN_EXIT_UNRESOLVED`. Sen tunnus perustuu viimeisen
ikkunan sisäisen maasolun UID:hen. Toisen solun koko reitin samanniminen
päättymistila ei luo uutta poistumisreunaa. Nollapointeri, puuttuva tai
virheellinen pointeri, NoData, sykli ja askelraja säilyvät erillisinä.
Poistumiseen yhdistetään vain siihen todella päättyneet tallennetut
lähtöreitit. Uniikki lähtösolujoukko sisältää myös itse poistuvan solun,
jos sen oma jäljitys päättyi tähän tapahtumaan. Tämä on ikkunassa havaittu
saavutettavuusjoukko, ei virtauskertymä tai kokonainen valuma-alue.

Suunnan ennusteessa ei kopioida `l1847_trace()`-ytimen yksityistä D8-
dekooderia. Koodin rivi-/sarakesiirtymä voidaan johtaa saman koodin jo
havaituista kanonisista sisäisistä reunoista, jos niiden suunnat ovat
johdonmukaisia. Tekstisuunta muodostetaan tästä geometrisesta askeleesta.
Jos tällaista sisäistä havaintoa ei ole, suunta ja ulkopuolinen vastaanottaja
jäävät `UNKNOWN`-tilaan ilmoitetulla syyllä; niitä ei päätellä uudesta
suuntataulukosta. Poistumistapahtuman olemassaolo perustuu silti vanhan
ytimen raportoimaan terminaaliin eikä vastaanottajaennusteen saatavuuteen.

`full_grid=list(nrow=..., ncol=...)` antaa varmennetut koko ruudun mitat
ennusteen rajatarkistukseen. Ajuri käyttää tähän tarkistettuja rasteri-
otsakkeita. Niiden avulla erotetaan ikkunasta poistuminen koko ruudun
sisällä ja myös koko ruudusta poistuminen. Ilman mittoja tai kelvollista
suuntaennustetta koko ruudun rajatulkinta jää tuntemattomaksi.
Vastaanottajan rasteriarvoa ei lueta eikä ennustettua solua lisätä
havaittujen solujen graafiin.

Topologian kirjanpito erottaa solmut, sisäiset maa→maa-reunat, muut
sisäiset reunat, suorat poistumiset ja reunattomat muut terminaalit.
Se tarkistaa myös poistumisiin päättyvien lähtöreittien yksilöllisen
ryhmittelyn. Erotusta `N_land − E_land_to_land` saa verrata suoriin
poistumisiin vasta soveltuvuusehtojen täyttyessä. Muut terminaalit tai
rajautuneet reitit raportoidaan, eikä identiteettiä pakoteta tai tulkita
hydrologiseksi hyväksynnäksi. Kaikissa tapauksissa
`accumulation=NOT_COMPUTED` ja `external_inflow=UNKNOWN` säilyvät.

## Pieni synteettinen yhtymä

Seuraavat ovat kuvitteellisen 5 × 5 ruudukon rivijärjestyksen solunumeroita.
Vesisolu 15 on luokkaa 1, kuvitteellinen järvitunnus 9001.

```text
maa 7  --D8=4--> maa 13 --D8=2--> maa 14 --D8=2--> vesi 15
maa 12 --D8=2--> maa 13
```

Maasoluun 13 tulee kaksi maareunaa. Maa→maa-reunat ovat 7→13, 12→13 ja
13→14; maa→vesi-reuna on 14→15. Yhteinen alavirran osuus 13→14→15
on reunaverkossa kerran. Tämä on topologiaesimerkki, ei todellisen järven,
ojan tai valuma-alueen havainto.

## Kevyet paikalliset regressiot

Aja repositorion juuresta Base R:llä. Komennot eivät tarvitse terraa tai
todellisia rastereita. Testitulokset ilmoitetaan vain toteutuneen ajon perusteella.

```bash
Rscript --vanilla diagnostics/land_network_topology/test_land_network_topology.R
Rscript --vanilla diagnostics/land_network_topology/test_land_network_topology_inventory.R
Rscript --vanilla diagnostics/land_d8_continuity/test_land_d8_route.R
Rscript --vanilla diagnostics/land_first_water/test_first_water_contact.R
Rscript --vanilla diagnostics/low_d8_scope/test_lake_1847_focus.R
Rscript --vanilla tests/water_connected_route_diagnostics.R
```

Ajurin testit käyttävät synteettisiä metadata- ja lukijafixtureitä sekä,
jos terra on käytettävissä, pieniä tilapäisiä GeoTIFF-tiedostoja:

```bash
Rscript --vanilla diagnostics/land_network_topology/test_one_low_network_window.R
```

Testi ei avaa CSC-polkuja. Ilman terraa integraatio-osuus merkitään
`NOT_RUN`-tilaan; sitä ei lasketa onnistuneeksi terra-tarkistukseksi.

Tässä haarassa paikallisesti 20.10.2026 suoritetut tarkistukset
(Base R 4.5.0):

| Testijoukko | Todellinen tulos |
| --- | --- |
| Verkkotopologia ja ydin-/halo-regressiot | 46 PASS, 0 FAIL |
| Uudet yhtymä- ja poistumisinventaariot | 25 PASS, 0 FAIL |
| 11 × 11 LOW-ikkuna-ajurin testit | 25 PASS, 0 FAIL, NOT_RUN=0 |
| Uusi 14 rajavastaanottajan tarkistus | 21 PASS, 0 FAIL, NOT_RUN=0 |
| PR #17:n maareitit | 23 PASS, 0 FAIL |
| PR #16:n ensikontakti | 26 PASS, 0 FAIL |
| LOW `test_lake_1847_focus.R` | PASS |
| Tuotannon 02F `water_connected_route_diagnostics.R` | PASS |

Lähtöcommitin `63cfcb67` verkkotestijoukossa oli 29 läpäissyttä tapausta.
Uusi joukko säilyttää nämä ja lisää 17 ydin-/halo-tapausta.

Lähtöcommitissa `ffcdfe93` ajurin testejä oli 23. Uusi joukko säilyttää
niiden merkityksen ja lisää lukitun LOW-ruudukon sekä rajatun tulostuksen
kirjanpidon tarkistukset. Inventaariotesteissä varmistetaan myös, ettei
analyysi kutsu jäljitysytimiä uudelleen tai täydennä lähteen askelrajaan
rajautunutta havaintoa yhtymäsolun pidemmällä reitillä.

Ajurin 25 tarkistuksesta 22 käytti synteettisiä metadata-/lukijasyötteitä.
Kolme terra-integraatioryhmää testasi 20 × 24 GeoTIFFien rajatun 11 × 11
luvun ja rivijärjestyksen, virheellisten geometrioiden hylkäyksen ennen
arvolukua sekä CLI:n commit-sidonnan erillisessä tilapäisessä Git-fixturessä.
Väärä commit-lukitus ja likainen työpuu hylättiin. CLI-testissä pienet
GeoTIFF-lähdeikkunat sijoitettiin 6000 × 6000 VRT-otsakkeiden keskelle;
36 miljoonan solun aineistoa ei muodostettu, luettu tai kirjoitettu.

Paikallinen terra oli 1.8.29, Rcpp 1.0.14 ja GDAL 3.10.3. GEOS ilmoitti
koostamisversioksi 3.13.0 ja ajonaikaiseksi versioksi 3.13.1; tästä syntyi
varoitus, mutta nämä paikalliset testit läpäisivät. Paikallinen `nlyr()`
palautti doublen. Nämä tarkistukset eivät todista CSC:n terra-version
1.9.34 tai todellisten LOW-rasterien toimivuutta.

Nämä ovat synteettisiä regressioita. Ne eivät ole CSC-ajon tai todellisen
ojaverkon hydrologisen oikeellisuuden hyväksyntä.

## PR #21:n 11 × 11 LOW-ikkuna-ajuri

`run_one_low_network_window.R` käyttää samoja Base R -verkkofunktioita.
Se ei sisällä omaa D8-dekooderia tai muuta pointereita. Ajuri on erillinen
PR #18:n kuuden 02B-kontaktin kokeesta: se ei lue 02B-kontaktitaulukkoa
eikä valitse ikkunaa kontaktin, yhtymän tai pitkän reitin perusteella.

LOW:n dokumentoitu baseline-juuri on:

```text
/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000/02_baseline
```

Pointeri `d8_pointer_land_water_FLT8S.tif` ja kelvollisuuden määrittävä
`routing_surface_land_water_FLT8S.tif` kuuluvat baselineen.
`ranta10_water_class.tif`- ja `ranta10_lake_id.tif`-rasterien polut sidotaan
input-manifestin `water_class_raster`- ja `lake_id_raster`-kenttiin;
niiden ei oleteta sijaitsevan baselinen kanssa samassa hakemistossa.

`R/01_prepare_hydrology_inputs.R` kirjoittaa manifestiin `key,value`
ja input-QA:han `item,value`. Näitä sopimuksia käsitellään erikseen.
Ajuri vaatii molemmat pienet raportit. Rasteriotsakkeista tarkistetaan
tasojen määrä, geometria, EPSG:3067 ja 2 m resoluutio ennen ikkunan arvojen
lukemista. `terra::nlyr()`-tulosta verrataan lukumäärään loogisesti;
sen double-palautusarvoa ei pakoteta `vapply(..., integer(1))`-sopimukseen.

Ikkuna-ajurin komentomuoto aiempaa koetta varten on:

```text
Rscript --vanilla diagnostics/land_network_topology/run_one_low_network_window.R [BASELINE_DIR]
```

Ilman argumenttia käytetään yllä dokumentoitua LOW-baselinea. Ajuri sitoo
käytetyn koodin saman MaaltaMerelle-repositorion puhtaaseen Git-HEADiin.
Input-manifesti ja QA oletetaan baselinen rinnakkaiseen `01_inputs`-
hakemistoon; rasteripolut luetaan manifestista. Kutsuttava funktio sallii
myös eksplisiittiset `manifest_path`- ja `qa_path`-polut sekä synteettisen
rasterilukijan, jotta lukusopimus voidaan testata paikallisesti.
CLI:n valinnainen `MM_EXPECTED_COMMIT` sitoo ajon annettuun täyteen
commit-SHA:han. Uusi CLI vaatii myös 6000 × 6000 kokonaisruudukon ennen
rasteriarvojen lukua, jotta historiallisesti valittu ikkuna ei siirry
erikokoisen rasterin keskipisteeseen. Worker-funktion valinnainen
`expected_full_grid` sallii erikokoisten synteettisten fixtureiden
testaamisen; komentorivi ei tarjoa tämän LOW-rajauksen ohitusvalintaa.
Tämän haaran laajennettua komentoa ei ole ajettu todellisilla
LOW-rastereilla tässä tehtävässä.

Manifestilta vaaditaan lisäksi `pointer_scheme=whitebox`,
`test_id=E200000_N6900000` ja `cell_size_m=2`. QA:n kahdeksaa geometria-
arvoa verrataan rasteriotsakkeisiin ennen arvolukua. Todellista CSC-
manifestia ei ole tässä luettu. Jos sen arvot poikkeavat vaaditusta,
ajuri pysähtyy ennen rasteriarvojen lukua; lähdesidonta selvitetään
ennen jatkamista. Tuntematon alkuperäinen
D8-laskentacommit säilyy `HISTORICAL_SOURCE_COMMIT=UNKNOWN`-tilassa ja
historiallinen provenienssi `HISTORICAL_PROVENANCE=INCOMPLETE`-tilassa.
CLI:n `CODE_VERSION_VERIFICATION=LOCAL_GIT_CLEAN` koskee nyt ajettavaa
koodia, ei historiallista rasterin laskentaa.

Ajuri tulostaa yhteenvedon seuraavien merkkien väliin:

```text
========== TULOKSET ALKAVAT ==========
...
========== TULOKSET LOPPUVAT ==========
```

Raportissa erotetaan käytetty koodicommit ja ilmoitettu aineistoprovenienssi,
rasterien polut ja geometriatarkistus, globaalit ikkuna- ja ydinrajat,
ytimen ja halon maasolumäärät, neljä maa→maa-reunaluokkaa, ytimen yhtymät,
neljä ydintapausta sekä halotapaukset, reittien päättymistilojen määrät ja
saavutetut ensimmäiset RANTA10-kontaktit. Kontaktit ovat olemassa olevan
D8:n laskennallisia havaintoja; ne eivät vahvista uomaa tai purkupistettä.
Sama vesisolu voi esiintyä usean maasolualoituksen reitin kontaktina.
Päättymistilojen `window`-, `core`- ja `halo`-määrät ryhmittelevät reittejä
niiden lähtösolun alueen mukaan, eivät terminaalisolun sijainnin mukaan.

Topologiainventaario lisää erilliset osiot:

- `CORE_CONFLUENCE_DETAILS` ja `HALO_CONFLUENCE_DETAILS`: yksilöidyt
  yhtymäsolut sekä niiden havaittujen tuloreunojen lähde-UID:t ja D8-koodit.
- `SHARED_DOWNSTREAM_SEGMENTS`: yhteisten osuuksien järjestetyt
  solu-/reunaviittaukset sekä havaittuihin lähtöreitteihin perustuvat jäsenyydet.
- `UNIQUE_WINDOW_EXIT_EDGES`: yksi tietue jokaista suoraan poistuvaa
  maasolua kohti, erillään siihen päättyvistä lähtöreiteistä.
- `SOURCE_ROUTES_PER_EXIT`: poistumisiin päättyneet yksilölliset
  lähtösolut; itse poistuva maasolu sisältyy joukkoon.
- `TOPOLOGY_ACCOUNTING_QA`: kirjanpidon luvut ja soveltuvuusehdot,
  mukaan lukien ehdollinen `N_land − E_land_to_land`-vertailu.

Kunkin inventaariotaulun stdout-tulostus rajataan oletuksena 121 riviin.
Tämä näyttää kaikki enintään 121 uniikkia sisäistä reunaa, poistumista ja
poistumiseen päättynyttä lähdereittiä; suuremmat yhteisosuus- ja
jäsenyystaulut voivat lyhentyä. Jokaisen taulun yhteydessä näkyvät
`TOTAL_ROWS`, `PRINTED_ROWS`, `TRUNCATED` ja **koko taulun** tarkistussumma.
Kaikki rivit säilyvät worker-tuloksen `topology_inventory`-oliossa.
Tulostusrajan voi antaa `low_network_print_result(..., inventory_row_limit=...)`
tai `low_network_print_inventory(..., row_limit=...)`-kutsulle väliltä 1–14641.
Raja ei muuta inventaariota tai sen tarkistussummaa.

`ADLER32_SERIALIZE_ASCII_V2` on Base R:n ASCII-version-2-serialisoinnista
laskettu **ei-kryptografinen** sisältötarkistussumma. Se ei varmista rasterien
historiallista alkuperää eikä korvaa tiedostojen SHA256-provenienssia.
Tarkistussumma ei tarvitse uusia riippuvuuksia, tiedostolukuja tai
tilapäisten raporttitiedostojen kirjoittamista.

Ajuri ei kirjoita tulostiedostoja tai alkuperäisiin aineistohakemistoihin.
Se ei käynnistä Slurmia tai Whiteboxia eikä tee rasterien uusia
kokotiedostotiivisteitä. Ilmoitetut lähdepolut ja ajantasaiset otsakkeet
eivät yksin todista historiallisen D8-laskennan koko provenienssia.

## Aikaisempi 11 × 11 inventaarion koesuunnitelma

**Historiallinen suunnitelma, säilytetty tutkimuksen jäljitettävyyttä varten.**
Käyttäjä on sittemmin toimittanut tämän inventaarion tulokset commitilta
`40509d5`: 16 poistumista ja 14 ennustettua vastaanottajaa. Alla säilytetään
ennen ajoa laadittu suunnitelma. Tämän haaran uusi tarkistus käyttää vain
14 vastaanottajaa eikä suorita tätä ikkuna-ajoa uudelleen.

Aiemmassa suunnitelmassa säilytettiin 20.10.2026 kokeen sama 11 × 11 ikkuna:
globaalit rivit ja sarakkeet 2995–3005, ydin 2996–3004 ja yhden solun halo.
Sijainti ei riipu 02B-kontakteista, pointereista tai reittien onnistumisesta.
Se vastaa 6000 × 6000 otsakkeiden keskussolua
`floor((nrow+1)/2), floor((ncol+1)/2)`, eli riviä ja saraketta 3000.
CLI pysähtyy, jos kokonaisruudukon mitat poikkeavat odotetusta; eri
ikkunaa ei valita. Ikkunaa ei myöskään siirretä tai suurenneta puuttuvien
yhtymien tai muiden tulosten vuoksi.

1. Sidotaan nykyisten rasterien lähdepolut, saatavilla olevat tunnisteet ja
   testikoodi. Varmennetaan todelliset mitat, yhteinen geometria, EPSG:3067,
   2 m resoluutio, yksi taso/rasteri, origo ja NoData. Todellisen CLI-ajon
   on vahvistettava 6000 × 6000 mitat; muuten koe pysähtyy.
   `01_input_manifest.csv`-tuottaja käyttää
   sarakkeita `key,value`, `01_input_QA.csv`-tuottaja `item,value`
   (`R/01_prepare_hydrology_inputs.R`). Terra-ajurin API-sopimus
   tarkistetaan ennen oikeaa ajoa: esimerkiksi `nlyr()` voi palauttaa doublen;
   lukumäärän loogista vertailua ei sidota integer-palautustyyppiin.
2. Pyydetään olemassa olevista LAND_WATER-D8-, RANTA10-vesiluokka-, järvi-ID-
   ja LAND_WATER-rastereista samat **121 solupaikkaa**, enintään **484
   palautettua rasteriarvoa**. Ei 36 miljoonan solun skannausta tai rasterien
   uusia kokotiedostotiivisteitä. TIFF-ajuri voi käsitellä pakattuja lohkoja
   suurempina kuin tämä palautettu näyte. `valid` määritellään erikseen
   äärellisestä LAND_WATER-arvosta, ei vesiluokan puuttumisesta.
3. Rakennetaan kaikkien 11 × 11 ikkunan kelvollisten maasolujen verkko.
   Keskimmäinen 9 × 9 on analyysiydin, ulkorengas yhden solun halo. Ytimen
   välittömät naapurit tulevat luetuiksi, mutta ulkopuolinen kertymä jää
   tuntemattomaksi. Ulkoreunan indegree on havaittu alaraja. Rajalla
   päättyvät havainnot merkitään rajautuneiksi, ei fyysisiksi katkoksiksi.
4. Kiinnitetään `max_steps=32`. Enintään 121 maasolua tarkoittaa enintään
   **3 872 reittisiirtymää** ja **3 993 muistissa olevien havaintojen kutsua**.
   Yksilöllisiä lähteviä graafireunoja on enintään 121. Reittihavainnot eivät
   käynnistä uusia rasterilukuja, koska matriisit on jo luettu. Säilytetään
   kaikki päättymisluokat ja neljän tapausluokan puuttumiset.
5. Muodostetaan yhtymä-, yhteisosuus- ja poistumisinventaariot jo valmiista
   `network`-oliosta ilman uusia jäljityksiä. Tarkistetaan uniikkien suorien
   poistumisten määrä, niiden lähtösolujoukkojen erillisyys ja kirjanpidon
   soveltuvuusehdot. Verrataan tulosta alustavaan lukuun 16; eroa ei korjata
   keinotekoisesti. Käyttäjän aiemmat 121 solun, 105 sisäisen maareunan,
   18 yhtymän ja 121 poistuvan reitin luvut ovat vertailun lähtönä,
   eivät uuden ajon tulokseksi valmiiksi asetettuja odotusarvoja.

Jo muistissa oleva saman ikkunan kelvollinen `network`-olio riittää
inventaariofunktion ajamiseen ilman mitään rasterilukua. Jos sitä ei ole
käytettävissä, erikseen hyväksyttävä ajuri lukee vain yllä mainitut neljä
ikkunaa; koko LOW:n onnistuneita skannauksia tai hydrologisia laskentoja
ei toisteta. Tässä työssä CSC-verkko-oliota ei ole saatu luettavaksi.

Tämä kiinteä ikkuna ei ole koko LOW:n edustava otos. Koe voi todentaa
nykyisen D8:n paikallista topologiaa, mutta ojan tai rummun olemassaolo,
virtaussuunta maastossa ja pienvesiluokitus tarvitsevat riippumatonta näyttöä.
CSC:llä jo oleva valmistettu DEM ja LAND_WATER-D8 riittävät menetelmäkokeen
lähtöpinnaksi; alkuperäistä SYKEn harvaa korjausrasteria tai DEM:n
uudelleenvalmistamista ei tarvita. Polton vaikutusta ei tämän perusteella
silti väitetä selvitetyksi. Järven 1847 eteläisen ja luoteisen reitin
ongelmia ei tutkita tässä uudelleen.

Tämän aiemman kokeen tarkoitus oli osoittaa, mitkä havaitut solut ja reunat
muodostavat paikalliset yhtymät ja mitkä lähtöreitit päättyvät samaan poistumiseen.
Se ei osoita ikkunan ulkopuolista reittiä, koko valuma-aluetta tai reitin
luonnollista/ojitettua alkuperää. Tämän haaran 14 vastaanottajan todellinen
CSC-luku odottaa erillistä hyväksyntää.
