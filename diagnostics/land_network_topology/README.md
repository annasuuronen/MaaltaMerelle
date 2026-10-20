# Rajatun maa-alueen D8-verkon topologia

Base R -tutkimusprototyyppi käsittelee **kaikki valmiiksi syötetyn pienen
ikkunan kelvolliset maasolut**. Se ei edellytä RANTA10-kontaktia eikä lue
CSV:tä tai rastereita. Erillinen, vain lukeva R/terra-ajuri valmistelee
matriisit yhdestä ennalta määrätystä LOW-ikkunasta; sitä ei ole ajettu
todellisilla CSC-aineistoilla. Ei Whitebox-ajoja, uutta D8:aa,
kertymälaskentaa tai oja-/pienvesiluokitusta.

`hydrological_validation=NOT_ASSESSED`; `channel_interpretation=NOT_ASSESSED`.
**MODERATE=REVIEW_REQUIRED; NATIONAL=LOCKED.**

## Lähtö ja rajaus

- Haara: `codex/low-land-topology-core-halo-readonly-v1`.
- Lähtö on PR #19:n `63cfcb6701322f07e940c949ecc994c775fa410f`.
  Sen verkkoydin perustuu PR #17:n `753ac0d5`-commitiin.
- Draft PR:n kohde on **`codex/low-land-network-topology-v1`**. PR #18:n
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

## Syöte ja käyttö

Lataa repositorion juuresta olemassa olevat riippuvuudet tässä järjestyksessä:

```r
source("diagnostics/low_d8_scope/lake_1847_focus_core.R")
source("diagnostics/land_first_water/first_water_contact.R")
source("diagnostics/land_d8_continuity/trace_land_d8_route.R")
source("diagnostics/land_network_topology/land_network_topology.R")

network <- build_land_d8_network(
  pointer, water_class, valid, grid, provenance,
  lake_id = NULL, max_steps = 32L
)
table(network$route_summary$route_status)
window_cases <- select_land_network_cases(network) # aiempi oletus: koko ikkuna
core_cases <- select_land_network_cases(network, scope = "core")
halo_cases <- select_land_network_cases(network, scope = "halo")
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

Uudessa haarassa paikallisesti 20.10.2026 suoritetut tarkistukset
(Base R 4.5.0):

| Testijoukko | Todellinen tulos |
| --- | --- |
| Verkkotopologia ja ydin-/halo-regressiot | 46 PASS, 0 FAIL |
| Rajatun LOW-ajurin testit | 23 PASS, 0 FAIL, NOT_RUN=0 |
| PR #17:n maareitit | 23 PASS, 0 FAIL |
| PR #16:n ensikontakti | 26 PASS, 0 FAIL |
| LOW `test_lake_1847_focus.R` | PASS |
| Tuotannon 02F `water_connected_route_diagnostics.R` | PASS |

Lähtöcommitin `63cfcb67` verkkotestijoukossa oli 29 läpäissyttä tapausta.
Uusi joukko säilyttää nämä ja lisää 17 ydin-/halo-tapausta.

Ajurin 23 tarkistuksesta 20 käytti synteettisiä metadata-/lukijasyötteitä.
Kolme terra-integraatioryhmää testasi 20 × 24 GeoTIFFien rajatun 11 × 11
luvun ja rivijärjestyksen, virheellisten geometrioiden hylkäyksen ennen
arvolukua sekä CLI:n commit-sidonnan erillisessä tilapäisessä Git-fixturessä.
Väärä commit-lukitus ja likainen työpuu hylättiin.

Paikallinen terra oli 1.8.29, Rcpp 1.0.14 ja GDAL 3.10.3. GEOS ilmoitti
koostamisversioksi 3.13.0 ja ajonaikaiseksi versioksi 3.13.1; tästä syntyi
varoitus, mutta nämä paikalliset testit läpäisivät. Paikallinen `nlyr()`
palautti doublen. Nämä tarkistukset eivät todista CSC:n terra-version
1.9.34 tai todellisten LOW-rasterien toimivuutta.

Nämä ovat synteettisiä regressioita. Ne eivät ole CSC-ajon tai todellisen
ojaverkon hydrologisen oikeellisuuden hyväksyntä.

## Rajattu vain lukeva LOW-ajuri

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

Tulevan erikseen hyväksyttävän käytön komentomuoto on:

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
commit-SHA:han. Tätä komentoa ei ole ajettu todellisilla LOW-rastereilla
tässä tehtävässä.

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

Ajuri ei kirjoita tulostiedostoja tai alkuperäisiin aineistohakemistoihin.
Se ei käynnistä Slurmia tai Whiteboxia eikä tee rasterien uusia
kokotiedostotiivisteitä. Ilmoitetut lähdepolut ja ajantasaiset otsakkeet
eivät yksin todista historiallisen D8-laskennan koko provenienssia.

## Yksi myöhemmin hyväksyttävä todellisen LOW:n koe

**Ajuri on valmisteltu; todellista CSC-koetta ei ole suoritettu eikä tämä ole
ajolupa.** Valitaan yksi kiinteä
11 × 11 ruudukkoikkuna maantieteellisesti, riippumatta 02B-kontakteista,
pointereista tai reittien onnistumisesta. Keskussolu on todellisista
rasteriotsikon mitoista `floor((nrow+1)/2), floor((ncol+1)/2)`; parillisilla
mitoilla tämä on neljän keskisolun luoteinen. Ikkunaa ei siirretä tai
suurenneta, jos siinä on vettä, ei maareunoja tai ei yhtymää.

1. Sidotaan nykyisten rasterien lähdepolut, saatavilla olevat tunnisteet ja
   testikoodi. Varmennetaan todelliset mitat, yhteinen geometria, EPSG:3067,
   2 m resoluutio, yksi taso/rasteri, origo ja NoData. Molempien mittojen
   on riitettävä 11 × 11 ikkunalle; muuten koe pysähtyy eikä ikkunaa pienennetä.
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

Jos otsakkeet vahvistavat 6000 × 6000 solun ruudukon, keskussolu on
globaalilla rivillä 3000 ja sarakkeessa 3000, ikkuna riveillä ja sarakkeilla
2995–3005 sekä ydin riveillä ja sarakkeilla 2996–3004. Offsetit lasketaan
otsakkeista; näitä lukuja ei käytetä eri kokoisen ruudukon oletuksena.

Tämä kiinteä ikkuna ei ole koko LOW:n edustava otos. Koe voi todentaa
nykyisen D8:n paikallista topologiaa, mutta ojan tai rummun olemassaolo,
virtaussuunta maastossa ja pienvesiluokitus tarvitsevat riippumatonta näyttöä.
CSC:llä jo oleva valmistettu DEM ja LAND_WATER-D8 riittävät menetelmäkokeen
lähtöpinnaksi; alkuperäistä SYKEn harvaa korjausrasteria tai DEM:n
uudelleenvalmistamista ei tarvita. Polton vaikutusta ei tämän perusteella
silti väitetä selvitetyksi. Järven 1847 eteläisen ja luoteisen reitin
ongelmia ei tutkita tässä uudelleen.

Todellista tutkimusikkunaa ei ole luettu tai analysoitu tällä prototyypillä.
CSC-koe ja uusi todellisen aineiston rasteriluku odottavat erillistä hyväksyntää.
