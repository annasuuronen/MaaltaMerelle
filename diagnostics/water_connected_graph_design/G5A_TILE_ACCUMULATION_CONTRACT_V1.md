# G5A – ruuturajat ylittävän D8-virtauskertymän testisopimus v1

**Tila:** DESIGN_ONLY / SYNTHETIC_ONLY / NOT_HYDROLOGICALLY_VALIDATED. Tämä dokumentti kuvaa valtakunnallisen MaaltaMerelle-menetelmän kertymän matemaattisen oikeellisuuden tarkistusta **ilman** oikean D8:n rakentamista, CSC-lukuja tai aktiivisten järvipurkuyhteyksien valintaa. Pinottu S2C:n draft PR #52:n jälkeen. Hyväksytyn mallin vaiheita ei muuteta.

## 1. Miksi tämä vaihe?

S1 luokittelee geometriasta ja D8:sta saatavia havaintoja, S2A jäljittää pienen annetun D8-ikkunan, S2B ottaa synteettisiä rajattuja rasteri-ikkunoita ja S2C voi vain tarkistaa alkuperäisen LOW:n metatietoja; S2C ei vahvista alkuperäisen 02F-ajon käyttämää D8-versiota (RUNTIME_INPUT_LINEAGE=NOT_ASSESSED) ja sen lopputulos on tietoisesti STOP. S1–S2C eivät vielä ole WATER_CONNECTED-pinta, valmis D8 eivätkä virtauskertymän laskenta.

Repositoriossa on jo `diagnostics/water_connected_graph_design/graph_oracle.py`, jonka `synthetic_accumulation` testaa pienille, suljetuille hypoteettisille DAG-verkoille solujen omistajuutta, pinta-alan siirtymistä, järven yksittäistä kontribuutiota, sykliä ja virheellisiä monipuruja. **Älä tee toista samanlaista kertymäalgoritmia.** G5A:n puuttuva itsenäinen sopimus koskee **ruutujen välisiä rajaliitoksia, alueen omistajuuden erottamista haloista ja riippumatonta ositettuun vs. koko verkkoon perustuvaa kertymätarkistusta**.

## 2. Suureet ja hydrologiset rajat

Kiinteällä 2m × 2m tutkittavalla ruudukolla yhden kokonaisen rasterisolun paino on `a=4 m²`. Tämä on rasteripohjainen kontribuutio, **ei** järven täsmällinen vektoripinta-ala eikä virtaama `m³/s`.

Topologisesti hyväksyttyyn synteettiseen DAG-kaareen perustuva kumulatiivinen yläpuolinen ala:

`A(v) = 4 m² × n_unique_owned_cells(v) + Σ(u→v) f(u,v) A(u)`.

D8:n yksilähtöisessä maanpintasolussa `f=1`; mahdollisia järven useita **samanaikaisia** purkuja ei saa päätellä kahdesta samanaikaisesta ehdokkaasta. Haarautumista saa mallintaa vain täysin erikseen annetulla, lähteen todentamalla painojoukolla, joka täyttää `Σ f=1`. G5A:ssa käytetään `fractions.Fraction`-tarkkuutta, eikä esitetä kansallisen korkeusmallin tarkkuutta näiden pinta-alaidentiteettien avulla.

Suljetussa testiverkossa, jossa jokaisella sisäisellä solmulla on perusteltu ulosmeno ja reitit päättyvät vain nimettyihin terminaaleihin, `Σ A(terminaaleissa) = 4 m² × kaikkien yksikäsitteisesti omistettujen solujen määrä`. Jos verkossa on avoimia ylärajoja, tuntematonta rajatulovirtausta tai puuttuva purku, **ei** saa ilmoittaa valtakunnallisesti täydellistä kertymää eikä meriyhteyttä.

## 3. Nimenomainen kaksiruutuinen testimalli

Jaa pieni synteettinen verkko laattoihin `TILE_A` ja `TILE_B`, joissa on:
- fyysiset omistajasolut `owner_tile_id`-kentällä; halon/naapuriruudun solut ovat **viitteitä**, eivät uutta rasteripinta-alaa;
- `LAND`-, `LAKE`- ja tarvittaessa `RIVER_REACH`-solmut sekä erilliset `BOUNDARY`- ja `COAST`-viittaukset; nämä eivät saa itsestään lisätä uusia pinta-alasoluja;
- ruuturajan ylittävä siirtymätietue `(upstream_tile, downstream_tile, from_node, to_node, from_cell, to_cell, transfer_id, provenance_status)`, jonka molemmat päät ja soluidentiteetit tarkistetaan;
- omistajuus- ja solumääräauditointi, jossa kahden ruudun sisäiset / halo-IDs eivät aiheuta kaksoislaskentaa;
- kielletty kaksoisinjektio: saman yläpuolisen alueen ei saa tulla lasketuksi sekä koko verkon alkuperäisistä solmuista että erillisenä rajakertymälukuna;
- eksplisiittinen `UPSTREAM_UNKNOWN` ja `TILE_BOUNDARY_UNRESOLVED`-tila avoimelle testille.

**Kokonaisverkon riippumaton vertailu:** yhdistä vain testin eksplisiittisesti määrittelemät ja tarkistamat omistajasolmut sekä kaaret ja anna tulos olemassa olevalle `graph_oracle.synthetic_accumulation`-funktiolle. Tee erikseen ositettujen ruutujen kirjanpito ja vertaa suljetussa testissä molempia laskentatapoja `Fraction`-tarkasti. Älä käytä samaa topologista kertymäfunktiota kummankin testin "riippumattomana orakkelina": ositetun kirjanpidon tulee olla erillinen tai sillä tulee olla pieni brute-force polkuenumerointi riippumattomana vastineena.

## 4. Pakolliset virhetilat

- `DUPLICATE_CELL_OWNERSHIP` – sama 2m rasterisolu omistetaan kahdessa ruudussa tai omistetaan uudelleen halon kautta;
- `MISSING_OR_DUPLICATE_TRANSFER` – rajasiirtymä puuttuu, esiintyy kahdesti tai kaksi eri vastaanottajaa on ristiriidassa;
- `TILE_BOUNDARY_UNRESOLVED` – ulospäin vievän reitin vastaanottajasolua ei voida osoittaa naapuriruudusta;
- `UPSTREAM_UNKNOWN` – ulkopuolisen valuma-alueen kertymää ei tunneta;
- `BOUNDARY_NOT_COAST` – ruuduraja tai validioimaton lähtö ei ole todistettu meriyhteys;
- `INVALID_FLOW_SPLIT` – järven vaihtoehtoiset purku-ehdokkaat tulkittiin virheellisesti yhtäaikaisiksi tai jako ei summaudu yhteen;
- `CROSS_TILE_CYCLE` – kahden ruudun yksittäiset paikallisgraafit voivat olla syklittömiä, vaikka niiden yhdistelmässä on sykli;
- `SHARED_UPSTREAM_COUNTED_TWICE` – kahteen haaraan jakaantuva ja myöhemmin yhtyvä verkko kirjaa saman yläpuolisen alueen kaksinkertaisesti.

Palauta tyypitetty STOP tai `NOT_ASSESSED` (tuntematon syöte) erottaen toisistaan varsinainen ristiriita, incomplete-data ja testiajon virhe. Tarkistukset eivät saa korjata lähtöverkkoa automaattisesti.

## 5. Testimatriisi ennen mitään CSC-käsittelyä

Vähintään 40 nimettyä synteettistä testiä / merkityksellistä assertionia:
1. yhden ruudun valmis synteettinen D8-graafi vertautuu nykyiseen graafiorakkeliin;
2. kaksi ruutua + yksi uniikki rajasiirtymä, alueen jatkuvuus 4m²-kertaluokassa;
3. kahdesta alijuoksusta yhtyvä joki ruuturajan jälkeen: alkuperäinen alue ei tuplaannu;
4. järvi useine omistajapikseleineen: laske jokainen pikseli täsmälleen kerran, eivätkä halo-järvipikselit lisää alaa;
5. kaksi tai useampia rajasiirtymiä ja virtausten liittyminen toisessa ruudussa;
6. rajaliitos takaisin alkuruutuun ja sen aiheuttama **cross-tile cycle**;
7. rivijärjestyksen, laattojen käsittelyjärjestyksen ja kaarien järjestyksen vaikutuksettomuus;
8. avoin yläraja ilman rajakertymää pysyy UNKNOWN, eikä siitä synny maanlaajuista PASSia;
9. rajaulosmeno ilman merireferenssiä ei saa `COAST`-luokkaa;
10. yksi pinta-alalähde ei saa esiintyä sekä graafin sisäisenä että syötettynä upstream-virtana;
11. kaksoissiirtymä, puuttuva siirtymä, väärä vastaanottaja, väärä omistaja, negatiivinen tai epäkelpo rajasiirtymä;
12. samanaikaiset järven ulosvirtauskaaret ilman osuusmääritystä -> STOP; eksplisiittiset rationaaliset osuudet 1/4 + 3/4 -> säilyminen; osuudet 1/4 + 1/4 -> STOP;
13. synteettisen maskin ja ownership-taulukon ristiriita;
14. keskeneräinen reitti, 02F:n `D8_ZERO_INTERIOR` tai `RETURNS_TO_ORIGIN_LAKE` ei kelpaa aktiiviseksi kaareksi ilman muuta erillistä hyväksyntää;
15. kaikki ulostulot ovat immutable, `routing_authorized=false` ja `hydrological_validation=NOT_ASSESSED`.

Suositeltava lisävarmistus: generoi rajattu määrä pieniä (enintään 12–20 solmua) satunnaisia DAG-fixturejä **kiinteällä satunnaissiemenellä** ja vertaa topologista kertymää riippumattomaan hitaaseen eksaktiin polkulaskentaan. Testien on pysyttävä nopeina ja toistettavina ilman GIS-riippuvuuksia.

## 6. Toimitusten rakenne

Codexin seuraavan erillisen toteutus-PR:n **sallitut uudet tiedostot**:
- `diagnostics/water_connected_graph_design/tile_accumulation_contract_v1.py`
- `diagnostics/water_connected_graph_design/test_tile_accumulation_contract_v1.py`
- `diagnostics/water_connected_graph_design/G5A_TILE_ACCUMULATION_QA.md`

Yksinomaan Python-standardikirjasto ja repositorion **nykyinen** `graph_oracle.py` sallitaan. Älä muuta `graph_oracle.py`-tiedostoa, sen testejä, S1/S2A/S2B/S2C-moduuleja tai R-pipelinea. Suorita uudet synteettiset testit ja aiemmat `test_graph_oracle.py`-testit, raportoi PASS/FAIL/NOT_RUN. Tee vain uusi pinottu **draft PR**. Ei mergeä.

## 7. Erilliset hyväksyntäportit ja jäljelle jäävä työ

**S2C:n todellinen alkuperäketju on edelleen ratkaisematon.** Nykyisen 02F-CSV:n todellista käytettyä pointer-versiota ei voi todistaa jälkikäteen pelkällä polulla, tiedoston aikaleimalla tai nykyisellä source-hashilla. G5A ei saa kiertää tätä STOPia eikä suorittaa rasteriarvojen lukua.

Tulevan uuden, uudelleen tuotettavan ajon on kirjattava alkuperäisen producer-ajon commit, suoritusympäristö, jokaisen käytetyn input-rasterin versio/tiiviste, pointer-konventio, RANTA10-maskit, config ja run-ID **ajon aikana**. Tämä antaa uuden ajon autentikoitavan provenienssin, mutta ei takautuvasti todista historiallista LOW-ajoversiota. Toteutusta varten tarvitaan erillinen hyväksytty tehtävä; alkuperäisiä tiedostoja tai historiallisen ajon metadataa ei saa jälkikäteen kirjoittaa uusiksi.

Ennen VALTAKUNNALLISTA loppu-D8:aa ja accumulationia tarvitaan: erikseen hyväksytty vesistöverkko ja järvipurut, täysin tunnistettu solujen omistajuus, yhtenäinen raja-/haloidentiteetti, koko verkon syklittömyys, ruuturajakertymien tarkistus, riippumaton hydrologinen validointi ja suorituskyvyn arviointi useilla toisistaan riippumattomilla alueilla.

**Tieteelliset lukot:** `NATIONAL=LOCKED` · `MODERATE=REVIEW_REQUIRED` · `hydrological_validation=NOT_ASSESSED` · `channel_interpretation=NOT_ASSESSED`.
