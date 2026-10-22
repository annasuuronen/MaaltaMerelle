# S1: Valtakunnallisen evidenssiluokittimen toteutussopimus

**Status: DESIGN_ONLY.** Tämä määrittely täydentää dokumenttia NATIONAL_ROUTING_DECISION_CONTRACT_V1.md. S1 on eristetty luokitin, ei valtakunnallista mallia muuttava algoritmi. NATIONAL=LOCKED, MODERATE=REVIEW_REQUIRED, hydrological_validation=NOT_ASSESSED, channel_interpretation=NOT_ASSESSED.

## 1. S1:n raja

Toteuta vain deterministinen, sivuvaikutukseton Python 3 -moduuli, joka saa jo olemassa olevia normalisoituja 02C–02F- ja apuaineistohavaintoja (testissä synteettisiä). Ei CSC-ajoja, RANTA10:n vektorilaskentoja, rasterilukuja, DEM/D8/STORAGE/maskin kirjoitusta, uutta flow accumulationia eikä purkupistevalintaa. Älä kytke luokitinta nykyiseen tuotantoputkeen.

Luokittimen output ei koskaan sisällä hyväksyttyä ulosvirtausta tai oikeutta muuttaa reititystä. Mahdolliset incoming VALIDATED / APPROVED / OUTLET_SELECTED / routing_authorized=true -yritykset torjutaan.

## 2. Ehdotettu puhdas rajapinta

- validate_observation(mapping) -> immutable Observation: validoi pakolliset identiteetit, ruudukon/CRS:n, syötteen provenienssin, tietotyyppien ja numeerisen äärellisyyden. SOURCE_ROLE on yksi INPUT, AUXILIARY, INDEPENDENT_REFERENCE. Puuttuva pakollinen identiteetti tai lähderooli on STOP.
- classify(observation) -> immutable Decision: kanoninen case_key, case_type, decision_state, kaikki reason_codes, evidence_gaps, source_roles, provenance, schema_version=s1.0, routing_authorized=false. Mahdollista erottaa lake-to-lake-ehdokastyyppi varsinaisesta päätöstilasta.
- group_routes(records) -> immutable grouped result: yksilöllisyys (origin_lake_id,start_receiver_cell), erillinen päätepisteryhmittely (origin_lake_id,terminal_cell), alkuperäiset route_id:t ja niiden kokonaismäärät säilyvät. Älä tulkitse kuutta 02F-alkua kuudeksi riippumattomaksi uomaksi.
- to_plain_mapping(result) -> stable JSON-compatible mapping. Kirjastossa ei I/O-funktioita eikä muuttuvia globaaleja valintatiloja.

Älä tee kansallisia etäisyys- tai korkeuserokynnyksiä LOW:n 38,12m järvivälistä, 0,07m järvikorkeuserosta tai SYKEn 0,04m rantaviivaetäisyydestä. Ei aineistojen kelluvaa ID-pyöristystä tai hiljaisia NULL→0-muutoksia.

## 3. Tila ja deterministinen etusijajärjestys

Mahdolliset decision_state-arvot S1:ssä: OBSERVED, CANDIDATE, REVIEW_REQUIRED, REJECTED, NOT_ASSESSED. VALIDATED ei ole tässä vaiheessa mahdollista.

Päätössäännöt:
1. SCHEMA_STOP: puuttuvat/ristiriitaiset pakolliset lähdetiedot, CRS/ruudukon ristiriita, mahdoton solutunnus, väärä route-ID:n yhdistäminen, validoiduksi väitetty status, laiton output-authorization.
2. REVIEW_REQUIRED: MIXED-vesinaapuri, D8_ZERO_INTERIOR johon ehdotetaan toimivaa ulosvirtausta, summary-only reittiä väitetään jatkuvaksi, syklinen reitti, ristiriitaiset vastaanottajat, avoin ruuturajaliitos, puuttuva hyväksyntään tarvittava korkeusepävarmuus.
3. CANDIDATE: yksilöity lähtö ja mahdollinen vastaanottaja, mutta vain ehdokasevidenssiä; ei reititysoikeutta.
4. OBSERVED: raakaluokka, vektoriosuma, geometrinen vastaavuus tai apuaineiston vertailu ilman riittävää suunnattua hypoteesia.
5. NOT_ASSESSED: tärkeä tieteellinen tieto puuttuu vaikka syöteskeema on ehjä, esim. täydellinen soluketju tai riippumaton validointi.
6. REJECTED: vain eksplisiittisesti osoitettu ristiriita; puuttuva kartoitettu jokiviiva tai SYKE-piste ei riitä hylkäämään.

Säilytä kaikki reason_codes ja evidence_gaps; valitse tiukin turvallinen tila, älä viimeksi osunutta if-haaraa. Tilan ja havaintotyypin välinen suhde on dokumentoitava, esim. lake-to-lake-ehdokas voi olla REVIEW_REQUIRED.

## 4. Syytunnisteet

Vähintään seuraavat pysyvät tunnisteet:
LAND_D8_ZERO_TERMINAL; MIXED_WATER_NEIGHBORS; BOUNDARY_FOOTPRINT_ONLY; MAPPED_LINE_GAP; SYKE_AUXILIARY_MATCH; MULTIPLE_STARTS_ONE_TERMINAL; ROUTE_GEOMETRY_SUMMARY_ONLY; TILE_CROSSING_UNVERIFIED; CYCLE_OR_RETURN; INDEPENDENCE_UNVERIFIED; LOW_GRADIENT_UNCERTAIN; COMPONENTLESS_OBSERVATION.

Jokaisen syykoodin tulee olla jäljitettävissä havaintokenttään. Nämä ovat evidenssikoodeja, eivät automaattisesti korjattavia DEM-/D8-virheitä. Tuntemattomia syykoodeja ei saa muuttaa hiljaisesti hyväksynnäksi.

## 5. Vähintään 30 synteettistä tarkistusta / testiä

A. Skeema/provenienssi: oikea 2m 6000×6000 ruudukko; väärä bbox STOP; väärä EPSG STOP; lähderooli INPUT ei muutu INDEPENDENT_REFERENCE; puuttuva lähderooli STOP.
B. 02C: LAKE_ONLY/SAFE_LAKE_CONNECTOR pysyy havainnossa; class1+class3 MIXED johtaa REVIEW_REQUIRED; componentless pysyy havainnossa.
C. Rasteri/vektori: solun 2m jalanjälki osuu veteen, keskipiste ei; ei automaattista maskivirhettä eikä uudelleenluokittelua.
D. Järvien väliset ehdokkaat: 38m gap ja 7cm ero eivät anna hyväksyntää; kartasta puuttuva jokiviiva ei yksin aiheuta REJECTED-tilaa; D8_ZERO-päätesolu johtaa REVIEW_REQUIRED.
E. SYKE: purkupiste järven rantaviivalla saa vain AUXILIARY_MATCH-tason evidenssiä, ei riippumatonta vahvistusta; sama valuma-alue-ID ei todista virtaussuuntaa.
F. Kuusi 02F-reittialkua yhteen päätesoluun: kuusi yksilöllistä route_id:tä säilyy ja yksi yhteinen terminaaliongelma; ristiriitainen route-ID STOP.
G. Syklit/ruuturajat: D8_CYCLE, RETURNS_TO_ORIGIN_LAKE ja unverified cross-tile -> REVIEW_REQUIRED, ilman kuvitteellisia naapureita.
H. Puuttuva näyttö: 02F-yhteenveto ilman välisoluja säilyy SUMMARY_ONLY; korkeusmittauksen epävarmuutta ei oleteta nollaksi; puuttuva vastaanottaja ei muutu hyväksytyksi purkureitiksi.
I. Determinismi: syötteen rivijärjestyksen, sanakirja-avainten ja samanaikaisten syykoodien järjestyksen vaihtaminen ei muuta päätöstä tai pudota route-ID:tä.
J. Negatiivinen turvallisuus: VALIDATED / routing_authorized=true -yritelmät STOP; kirjaston import ei tee tiedostokirjoituksia, CSC-ajoja, rasterimuutoksia tai verkkokutsuja.

Kaikki tulokset tarkistavat routing_authorized=false. Testissä käytetään vain pieniä synteettisiä fixturejä. Todelliset LOW-havainnot voivat olla esimerkkien rakenteellinen lähtökohta, mutta niitä ei saa käyttää yleispätevinä numeerisina kynnysarvoina.

## 6. Codexin toimitus ja hyväksyntä

Uusi haara canonical repo annasuuronen/MaaltaMerelle, lähtökohtana tämän suunnittelun tarkka HEAD; esimerkiksi codex/national-s1-pure-evidence-classifier-v1, uusi pinottu draft PR pohjalla codex/national-routing-decision-contract-design-v1.

Sallitut uudet tiedostot:
- diagnostics/water_connected_graph_design/decision_contract_v1.py
- diagnostics/water_connected_graph_design/test_decision_contract_v1.py
- diagnostics/water_connected_graph_design/DECISION_CLASSIFIER_S1.md

Nykyisiin hydrologia-R-skripteihin, 02C–02F-diagnostiikkoihin, muihin testeihin, maskiin, DEM:iin, D8:aan, STORAGEen, SYKE-pisteisiin, GitHub baseline-haaraan tai avoimiin PR:iin ei saa koskea. Dokumentoi mahdolliset perustellut poikkeukset ja pysähdy ennen poikkeuksen tekemistä.

Testaa uudet unittestit sekä asianmukaiset nykyiset synteettiset regressiot. Raportoi PASS/FAIL/NOT_RUN, muutosluettelo, provenienssi ja jäljelle jäävät tieteelliset aukot. Vähintään 30 merkityksellistä synteettistä assertionia eri testiryhmistä; mieluummin erilliset nimetyt tapaustestit ja negatiiviset torjunnat. Älä keksi PASSia ajamattomille testeille.

Tee vain uusi draft PR. Ei mergeä, ei tuotantoaktivointia, ei päätöstä NATIONAL-lukon avaamisesta.

## 7. S2–S4 jäävät myöhemmäksi

S2: olemassa olevan D8:n sparse/read-only väliaskelten arviointi rajatulla CSC-alueella.
S3: LOW:sta erillinen maantieteellisesti kerrostettu ja riippumaton hydrologinen validointi.
S4: erillinen tieteellinen hyväksyntä sekä mahdollinen WATER_CONNECTED-rakentaminen. Nykyinen S1 ei suorita näitä.
