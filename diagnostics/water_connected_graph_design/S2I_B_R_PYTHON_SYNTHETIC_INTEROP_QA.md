# S2I-B — R/Python synteettisen 02F-arvoprotokollan yhteensopivuus

**SYNTHETIC_ONLY · NOT_AUTHENTICATED · NO_RUN_AUTHORIZATION**. Pohja: S2I-A draft PR #71, commit `e7e908a8df5685510001f6bee1af50785fb57862`. Tämä vaihe lisää vain riippumattoman Base-R-kirjoittimen, kolme synteettistä erätapausta tuottavan fixture-ajurin ja Pythonissa tapahtuvan **täsmällisen tavutason** vertailun S2I-A:n nykyiseen lukijaan/kirjoittimeen. S2E:n, S2F:n ja 02F:n aiempia koodeja ei muokata eikä vanhoja hyväksyttyjä kokeita toisteta.

## Tiedostot ja rajapinnat

- `s2i_b_synthetic_wire_writer.R` — Base R -muistissa toimivat `s2ib_byte`, `s2ib_int32`, `s2ib_float64`, `s2ib_float64_raw` ja `s2ib_encode_batch` tuottavat **raw-vektorin**. Koodi ei käytä terraa, rastersyötteitä, R:n `serialize()`-protokollaa tai verkkoyhteyttä. Jokaisen erän natiivi tagi ja bittikuviot tarkistetaan. Raaka Float64 sallii eksplisiittisen NaN-payloadin.
- `test_s2i_b_synthetic_emit.R` — käyttää pelkkiä 3×3-fixturejä ja 02F:n kyselyjärjestystä WATER_CLASS→LAKE_ID→POINTER. Tulostaa vain yhdeksän rivin heksamuotoiset synteettiset erät sekä neljän odotetun STOP-poikkeuksen yhteenvedon. Ei kutsu varsinaista 02F-funktiota.
- `test_s2i_b_cross_language.py` — muodostaa vertailutavut **erillisellä S2I-A:n Python-koodauksella**, ajaa R-fixturen vain opt-in-asetuksella `MM_S2IB_RSCRIPT=/absoluuttinen/polku/Rscript`, vertailee yhdeksän erän jokaisen tavun, purkaa R-tavut ja tarkistaa häviöttömän paluukoodauksen, täsmälliset bittitagit ja R:n STOP-testit. Ilman Rscript-asetusta neljä R-integraatiotestiä merkitään `skipped/NOT_RUN`, eivät PASS. Pythonin omat kolme vertailu- ja rakennekoetta suoritetaan silloinkin.

S2I-A:n jo olemassa olevaa `s2i_a_synthetic_value_protocol.py`-tiedostoa ei muuteta eikä lisätä PR:n muutoksiin. Se on tämän S2I-B-haaran **pinottu lähderiippuvuus**.

## Versioitu siirtomuoto

Tasan S2I-A:n `MM-S2IA\0`, versio 1: UUID4 run + attempt (16+16 tavua), ASCII-grid-ID, row/col (uint16), EPSG:3067/2 m -origo (int32), järjestysnumero (uint16), rasterirooli (uint8), n (uint16), jonka jälkeen kutakin pyyntöä kohti cell-ID (uint16), tagi (uint8), ja roolikohtaiset raakaarvot. Kaikki monen tavun kokonaisluvut ja Float64-bitit **little-endian**. Ei automaattista float-arvojen pyöristämistä tai lajiluokkien tulkintaa. Sallittu Byte NoData=255, Int32 NA_INTEGER=-2147483648, IEEE754 R NA_real_ = `a20700000000f07f`; NaN-payload, -0 ja ±Inf säilyvät, Int32-järvi-ID 16777217 ei muutu Float32:ksi. R:n luonnollisten lukutyyppien ja Pythonin serialisointien vastaavuus on testattava todellisella R 4.6.1 -ajolla, ei oletettava.

Kolme nimettyä vertailuparia (jokaisessa kolme erää): `core` (duplikaattisolut, Byte NoData, NA_INTEGER, negatiivinen nolla, R NA, erillinen NaN-payload), `special` (±Inf, suuri ja negatiivinen Int32, 0.25), `directions` (kaikki kahdeksan Whitebox D8-koodia **pelkkinä arvoina**, ei virtaussiirtyminä). Testi vaatii 9/9 erän täsmälleen saman tavujonon ja neljä tarkoituksellista R STOP-tapausta.

## Ajo ja todistusrajat

```sh
# Repositorion juuresta, kun Rscript 4.6.1 ja Python 3.10+ ovat käytössä:
MM_S2IB_RSCRIPT="$(command -v Rscript)" PYTHONDONTWRITEBYTECODE=1 \
  python3 -B -m unittest discover -s diagnostics/water_connected_graph_design \
  -p test_s2i_b_cross_language.py -v
```

R-kieliympäristö **ei ollut käytettävissä ensimmäisen paikallisen Python-suorituksen aikana**. Sen vuoksi R:n neljän opt-in-testin tulos on siinä suorituksessa `NOT_RUN`; kolmen Pythonin puhtaan vertailutestin alustava tulos on PASS. GitHubiin lisäämisen jälkeen sama haara testataan tarvittaessa Roihun `module load r-env/461` -ympäristössä *vain* synteettisillä arvoilla. Mikään testaamatta oleva R-interoperabiliteetti ei muutu PASS-väitteeksi dokumenttia lukemalla.

Vaikka kaikki seitsemän testiä myöhemmin läpäisisivät, tuottaja- tai kuluttajaketjua **ei ole autentikoitu**. Kumpikin osapuoli koodaa fixturestä sille syötetyt samat synteettiset luvut; ei riippumatonta ajonaikaista todistajaa, tuotanto-terra-kytkentää, suojattua snapshotia, oikean 02F-ajon tietueita, historiallisten rasterinlukujen palauttamista tai ajolupaa. `RECORDED_UNVERIFIED` on edelleen paras sallittu itse ilmoitetun tietueen status; `HISTORIC_02F_EFFECTIVE_D8=NOT_ASSESSED`. Yhteensopiva binäärimuoto on vasta välttämätön pohja myöhemmälle S2I-C:n erilliselle luotetulle havainto-/tallennusrajalle.

**NATIONAL=LOCKED · MODERATE=REVIEW_REQUIRED · hydrological_validation=NOT_ASSESSED · channel_interpretation=NOT_ASSESSED · routing_authorized=false · outlet_selection=UNASSIGNED.** Draft only; do not merge or käynnistä CSC:n hydrologisia ajoja.