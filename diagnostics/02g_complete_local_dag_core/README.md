# 02G.3: pieni täysin tunnetun paikallisen DAG:n lukumääräydin

[Issue #31](https://github.com/annasuuronen/MaaltaMerelle/issues/31).
Lähtöcommit `35808cf6fea0b74dcdc878ec9fb9629ee66f8ea5`, PR #30 / haara
`codex/low-02g-scalability-design-review-v1`. Uusi tutkimushaara:
`codex/low-02g-complete-local-dag-count-core-v1`.

`count_core.R` sisältää yhden Base R -rajapinnan:
`complete_local_dag_counts(graph, evidence)`. Se laskee vain ilmoitettujen
paikallisten maasolu-lähteiden numeerisen kertymän kokonaan tunnetussa
syklittömässä graafissa. Rajat ovat **27 ruudukkopaikkaa / 11 maasolua**,
2 m resoluutio ja EPSG:3067. Ydin ei lue tiedostoja tai rastereita eikä kutsu
`g02_accumulate`-, `g2r_*`- tai ensivesikontaktin havaintolukijaa.

## Mitä täydellisyys tarkoittaa tässä

Syöte on pieni synteettinen **koko ilmoitetun ruudukon soluinventaario**,
ei polkujäljitysten kanonisten reunojen unioni. Jokainen ruudukkopaikka on
erikseen havaittu kelvolliseksi LAND- tai WATER-soluksi. Näin mahdollinen
pois jäänyt ruudukkopaikka ei hiljaa katoa lähdejoukosta. Tämä ensimmäinen
versio on tarkoituksella tiukka: myös ilmoitettuun ruudukkoon sisältyvä
NoData pysäyttää laskennan. Ulkopuolista aluetta ei ole inventoitu eikä
sen tuontia oleteta nollaksi.

Graafin lisäksi vaaditaan erillinen `evidence`-soluinventaario. Sen tulee
olla rakennettu riippumattomasta synteettisestä solumäärittelystä, ei graafin
kertymäluvuista, reunojen unionista tai tuloksesta kopioimalla. Testeissä
graafi ja havaintoinventaario muodostetaan eri funktioissa fixture-määrittelystä;
odotetut kertymät lasketaan lisäksi kolmannella, lähteitä yksitellen seuraavalla
ID-orakkelilla. Uuden pääfixturen kaikki 27 paikkaa on määritelty synteettisesti
vedeksi tai maaksi; 11 maasolu-lähdettä kulkee yhteen ensivesisoluun.
Nämä ovat uusia ohjelmistotestin luokkia, eivät todellisen LOW:n havaintoja.

`complete=true`-kenttä ei kuulu sopimukseen. Sen lisääminen hylätään.
`STEP_LIMIT`, osittainen havaintostatus ja väärä `TRACE_EDGE_UNION`-alkuperä
hylätään, vaikka reunat näyttäisivät muodostavan kokonaisen ketjun.
Täydellisyys tarkistetaan koko solukattavuudesta, omistajuudesta,
riippumattomista ydin-/halohavainnoista, lähdeinventaarista ja rakenteesta.
Pelkkä oikea sopimuksen nimikään ei korvaa puuttuvia taulukoita.

Tämä on luotetun synteettisen syötteen sopimus. Rajapinta ei pysty
todentamaan ulkopuolisen tuottajan rehellisyyttä tai aineiston todellista
alkuperää, jos molemmat syötteet ja niiden provenienssi väärennetään.
Todellisen rasterihavainnon riippumattomuutta ei siten ole osoitettu tällä
prototyypillä, eikä sen ajamista todellisella aineistolla ole toteutettu.

## Syötesopimus

Tuntematon, puuttuva tai toistettu kenttä pysäyttää käsittelyn. Taulukoiden
rivi-/sarakejärjestys ja metatietokenttien järjestys eivät muuta tulosta.

| Osa | Tarkka sisältö |
| --- | --- |
| `graph` | `schema=02g.3-graph-v1`, `input_kind=EXPLICIT_SYNTHETIC_CELL_GRAPH`, `identity`, `grid`, `cores`, `nodes`, `edges`, `external_import=UNKNOWN` |
| `identity`, molemmissa syötteissä | Samat `run_id`, `graph_version`, `grid_version`, `pointer_version`, `water_version`, `ownership_version`; kaikki vaaditaan |
| `grid` | `grid_id`, `nrow`, `ncol`, `row_offset`, `col_offset`, `xmin`, `ymax`, `resolution_m`, `crs`. Tarkat kokonaislukuiset rajatut origot/offsetit; rivejä × sarakkeita enintään 27 |
| `cores` | `core_id`, `row_min`, `row_max`, `col_min`, `col_max` globaaleina koordinaatteina. Suorakulmiot kattavat koko ruudukon täsmälleen kerran |
| `nodes` | `cell_uid`, `global_row`, `global_col`, `owner_core`, `kind`, `water_class`, `pointer`, `valid`, `source_uid`. Yksi rivi ruudukkopaikalle; LAND:lla lähde-UID = solu-UID, WATER:lla lähde-UID on NA |
| `edges` | `from_uid`, `to_uid`, `d8_code`. Täsmälleen yksi reuna jokaiselta maasolulta, ei yhtään vedestä. Kohde ja Whitebox-suunta tarkistetaan samoista globaaleista riveistä/sarakkeista |
| `evidence` | `schema=02g.3-census-v1`, `input_kind=INDEPENDENT_SYNTHETIC_CELL_CENSUS`, `scope_contract=COMPLETE_DECLARED_LOCAL_DAG`, `observation_status=COMPLETE_CELL_CENSUS`, `identity`, `producer_id`, `available_cores`, `observations`, `source_inventory` |
| `observations` | `observer_core`, `cell_uid`, `pointer`, `water_class`, `valid`. Jokaiselle ytimelle kaikki omat solut ja yhden solun levyinen ruudukon sisäinen halo; vaadittu joukko johdetaan ydingeometriasta. Arvojen on vastattava graafia ja saman solun muita havaintoja |
| `source_inventory` | `source_uid`, `cell_uid`, `owner_core`, `source_units`. Kaikki ja vain omistetut maasolut, kerran kukin, `source_units=1`. Halo ei tuota lisäpanosta |

UID on `grid_id:global_row:global_col`. Vesiluokat 1/2/3 ovat tunnettuja
synteettisiä RANTA10-luokkia, NA tarkoittaa maata vain, kun `valid=TRUE`.
NaN ei kelpaa maaluokan merkiksi. Vesisolun UID on ruudukkotunnus, ei
keksitty järven tai jokialueen yksilöllinen kohdetunnus.

Maasolun pointerin on oltava yksi koodeista 1,2,4,8,16,32,64,128
(NE,E,SE,S,SW,W,NW,N). Veden omaa pointeria ei seurata: sen 0, NA tai
epäkelpo suuntakoodi 3 ei muuta ensikontaktia. Kentän numeerinen tyyppi ja
esitystarkkuus tarkistetaan silti. Maasolun 0/NA/virheellinen pointeri on STOP.

## Laskentamenetelmä ja tuloksen merkitys

Kaikki syöte-, havainto- ja omistajuustarkistukset tehdään ensin. Kahnin
jonopohjainen topologinen järjestys tarkistaa syklittömyyden. Käänteisessä
järjestyksessä varmistetaan, että jokainen solmu sulkeutuu tunnettuun
ensivesisoluun. Vasta sen jälkeen luodaan kertymävektori:

```
A_local(maa)  = 1 + sum(A_local(välittömät maavanhemmat))
A_local(vesi) =     sum(A_local(välittömät maavanhemmat))
paikallinen lähdeala = 4 × A_local  [m²]
```

Yksi lähtevä reuna ja DAG takaavat vanhempien lähdejoukkojen erillisyyden:
sama lähde ei voi haarautua kahteen vanhempaan tai palata sykliin.
Ensimmäinen vesi katkaisee graafin. Lopputase on **ensivesisolujen**
kertymien summa = V, ei kaikkien maa-/vesisolmujen kertymien summa = V.
Tunnetut vesisolut, joihin yksikään lähde ei saavu, saavat nollan.

Indeksit, seuraaja, sisääntuloaste, jono, topologinen järjestys,
ensivesi-indeksi ja lukumäärät ovat kiinteitä vektoreita. Ydin ei rakenna
kaikkien solujen lähde-ID-joukkoja tai lähdekohtaisia polkuja. Numeroina
käytetään tarkkoja double-kokonaislukuja: V ≤ 11 ja 4V ≤ 44; lähdeyksiköt,
lisäykset ja pinta-alat tarkistetaan. Epätarkat, liian suuret tai kompleksiset
numeeriset syötteet hylätään.

Topologinen numeerinen osa on O(N+E)-aikainen ja O(N+E)-tilainen, missä
N sisältää myös tunnetut vesisolut. Tämä ei ole väite koko validoinnin
O(V)-vaativuudesta: mukana ovat ydingeometriat, halo-havainnot, ID-haut ja
järjestyksen vakiointi. Tässä rajoitetussa versiossa N ≤ 27 ja E=V ≤ 11.
Skaalautuvuutta suuremmilla verkoilla ei ole mitattu.

Tulos on `LOCAL_COMPLETE_DAG_NUMERIC`,
`membership_mode=NOT_MATERIALIZED`. `nodes` ja `first_water` sisältävät vain
paikalliset määrät/pinta-alat ja ensivesi-UID:n. `external_import=UNKNOWN`;
`total_upstream_cells` ja `total_upstream_area_m2` pysyvät NA:na.
Identiteetit, havaintotuottaja, ydingeometria ja ruudukko säilyvät tuloksessa.
`CONTRACT_AND_STRUCTURE_VALID` koskee synteettistä paikallista sopimusta.

## PR #30:n hyväksyntä- ja STOP-ehdot

| Päätösmuistion ehto | Toteutettu tarkistus / kohdennettu näyttö |
| --- | --- |
| 1. Kertalaskenta, UID, omistajuus, yksi D8-seuraaja | Täysi UID-/koordinaattikattavuus, päällekkäisyyksien esto, erillinen lähdeinventaario, ei vesi-/halolähteitä, koodin geometrinen kohdetarkistus; C1 ja kaikki kahdeksan suuntaa |
| 2. DAG ja täydellisyys ennen laskentaa | Soluhavainnot, vaaditut halot ja saatavilla olevat ytimet; topologinen sulkeutuminen ja tunnetut ensivedet. Sykli/NoData/puuttuva havainto ei tuota osittaista täyttä tulosta |
| 3. Riippumaton orakkeli | Testien `explicit_source_oracle` kulkee fixturejen erikseen annettuja seuraajasoluja ja muodostaa lähde-ID-joukot vain testissä. Se ei kutsu tätä ydintä, D8-dekooderia, topologista järjestystä tai vanhaa kertymäkoodia |
| 4. Järjestys ja duplikaatit | Rivi-/sarake-/metatietojärjestyksen muunnokset antavat identtisen semanttisen tuloksen. Sama reuna uudelleen on hylkäys, ei toinen panos. Viestiprotokollaa ei toteuteta |
| 5. Paikallinen lähdetase | Ensivesiin päätyvät määrät summautuvat V:ksi. Ketjukoe erottaa tämän kaikkien solmujen lukujen summasta |
| 6. Tarkka numeerinen esitys | Enintään 27/11, täsmälleen yksi lähdeyksikkö, kokonaislukutarkistukset ja rajatut lisäykset. Testit sisältävät murto-/Inf-/liian suuret-/kompleksiset syötteet |
| 7. C2 ja tuntematon tuonti | Puuttuva census, `complete=true`, jälkiunionin alkuperä, STEP_LIMIT ja väärä havaintotyyppi tuottavat STOP:n. Ulkoista nollatuontia ei hyväksytä; kokonaistulos on NA ja kaikki tieteelliset lukitukset pysyvät |

STOP on `local_dag_stop`-virhe-ehto, jossa ovat `status=STOP`, `reason_code`,
`result_kind=NO_NUMERIC_RESULT`, syöte-/havaintoidentiteetit, saatavilla oleva
omistajuusmetadata ja tieteelliset tilat. Siinä ei ole solukohtaisia
kertymätuloksia. Syitä ovat esimerkiksi `CENSORED_EVIDENCE`, `NODATA`,
`MISSING_CORE`, `MISSING_REQUIRED_HALO`, `DUPLICATE_SUCCESSOR`,
`D8_GEOMETRY`, `CYCLE` ja `SOURCE_UNITS`. Testien kaikki odotetut STOP:t
on kirjattu [stop_cases.csv](stop_cases.csv)-tiedostoon.

C2:n vanha havaintomerkitys säilyy: ketjussa a→b→c→w ja K=1 vain c on
havaittu vedessä. Tässä ytimessä **erikseen kokonaan inventoitu** ketju voi
antaa paikalliseksi vesikertymäksi kolme. Sitä ei merkitä vanhan sensuroidun
havainnon korjaukseksi, jatkamiseksi tai samaksi tulokseksi. PR #30:n
katkaisutapahtumien laskentaa tai jäsenyysindeksiä ei ole lisätty.

## Ajetut testit ja resurssit

Paikallinen R 4.5.0, Pythonin standardikirjasto. Vain tämän hakemiston uudet
pienet testit ajettiin. Uudet fixturet ovat ketju, yhtymä, useat ensivedet,
kaikki kahdeksan suuntaa, 27/11-pääfixture ja pienemmät negatiiviset tapaukset.
Solutason DAG:n A→B→A-ydinrajanylitys testataan ilman tiiliviestejä.

| Sarjayritys | Tulos | Tapauksia / tarkistuksia / odotettuja STOP:ja | Koko sarjan aika | Lapsi-RSS / näytteistetty ryhmä-RSS |
| --- | --- | --- | --- | --- |
| 1 | PASS | 14 / 689 / 48 | 0,7642 s | 65,074 / 65,047 MiB |
| 2, numeeristen tyyppien rajaus | PASS | 14 / 709 / 52 | 0,8153 s | 65,074 / 65,047 MiB |
| 3, lopullinen laajennettu sarja | PASS | **15 / 739 / 53** | **0,6606 s** | **65,023 / 64,980 MiB** |

FAIL-, TIME_STOP- tai MEMORY_STOP-tuloksia ei esiintynyt. Odotetut STOP:t
ovat hylkäystestien onnistumisia, eivät hydrologisia PASS-tuloksia.
Ajat sisältävät fixturet, validoinnin, laskennan, orakkelin ja testit;
ne eivät ole erillisiä ydinalgoritmin benchmarkeja. Näytteistetty ryhmä-RSS
voi aliarvioida lyhyen huipun. Näistä pienistä sarjoista ei johdeta kansallisen
laskennan muisti-/aikaennustetta eikä vertailukelpoista nopeutusta PR #28:aan.

`results.json` / `results.csv` ja kaikki kolme lokia säilyttävät todelliset
yritykset, lähde-SHA256:t, tilat, mittaukset ja normalisoitujen lokien SHA256:t.
Raakalokin ennen normalisointia laskettu tiiviste säilyy myös metadatassa;
arkistoitu lokiteksti on normalisoitu. Esimerkki-CSV:t ovat vain synteettisiä.
Vanhoja 02G/02G.2-raportteja tai FAIL-lokeja ei muuteta.

`NOT_RUN`: vanhat laajat regressiokampanjat, 1 000/10 000 solun kokeet,
todelliset rasterit ja CSC. Testiajuri käyttää aiempaa muuttamatonta
resurssivalvojaa, ei aiempia R-testisarjoja. Yhteinen veloitettu suoritusbudjetti
on enintään 120 s kaikkien uusien yritysten kesken, lapsen osoiteavaruus
1 536 MiB ja ryhmä-RSS:n näytteistetty pysäytysraja 1 792 MiB. Ohjelmointitauot
eivät nollaa jo veloitettua suoritusaikaa. Puuttuva RESULT, nolla tapausta tai
nolla tarkistusta on virhe. RSS-näytteistys ei ole jatkuva ryhmämuistin kova katto.

Uuden sarjan ajaminen erillisessä kopiossa Base R:llä:

```sh
MM_RSCRIPT=Rscript python3 -B diagnostics/02g_complete_local_dag_core/tests/run_tests.py
```

Säilytä arkistoitu näyttö; myöhempi erillinen kampanja tarvitsee oman tuloshakemiston
tai kertakäyttöisen kopion ilman vain tämän hakemiston generoituja raportteja,
lokeja ja esimerkki-CSV:itä. Ydin ja testit eivät tarvitse terraa tai Whiteboxia.

## Ero 02G.2:een ja jäljelle jäävät rajat

02G.2 seuraa lähdetokeneita, säilyttää jäsenjoukot/polkuhistoriat ja tarkistaa
riippumattomat tiilikuitit. Tämä ydin käsittelee vain erikseen täysin tunnettua
paikallista graafia ja palauttaa numerot. Se ei muuta tai korvaa 02G.2:n
sensuroituja havaintoja, kuittausprotokollaa tai niiden turvallisuusrajoja.
Ei ole toteutettu jäsenyys-/lukumäärähybridin integraatiota, siirtopalvelua,
hajautettua aggregaatiota, levykertymää tai hyväksymisautomatiikkaa.

4 ha = 40 000 m² = 10 000 solua on vain kynnysmetatieto; kaikki paikalliset
reitit/kontaktit säilyvät alle kynnyksenkin. Pinta-ala ei ole virtaama tai
todiste uomasta. Tämä työ ei muodosta H-latvavesiherkkyyttä, todellista
4 ha:n uomaverkkoa, suojelu-/ennallistamisindeksiä, vesistökuormaa tai
metsänkäsittelyn vaikutusarviota. Hydrologinen riippumaton näyttö puuttuu.

Tuotanto-R, vanhat tutkimusprototyypit, `tests/`, työnkulut ja PR #30 pysyvät
muuttumattomina. CSC-/SSH-/Slurm-yhteyksiä, todellisia rasterilukuja ja
DEM/D8/STORAGE/vesimaski-/outlet-muutoksia ei tehdä. Todellisen LOW:n seuraava
erikseen hyväksyttävä portti on edelleen PR #22:n **14 lukittua vastaanottajaa /
56 palautettua rasteriarvoa**, varmennetulla yhteydellä ja syöteidentiteetillä.

`hydrological_validation=NOT_ASSESSED`
`channel_interpretation=NOT_ASSESSED`
`MODERATE=REVIEW_REQUIRED`
`NATIONAL=LOCKED`
