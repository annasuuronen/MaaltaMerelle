# S2I-A — synteettinen häviötön 02F-arvoprotokolla (v1)

**Kooditoteutus, mutta vain synteettinen ja muistissa:** ei alkuperäisen LOW:n arvoja, ei CSC:tä, ei R-/terra-kytkentää, ei tuottaja-/kuluttajaleimoja, ei todistajaa, ei oikeita tiedosto- tai verkkolukuja. Tämä toteuttaa vain [S2I-valmistelun #69](https://github.com/annasuuronen/MaaltaMerelle/pull/69) ensimmäisen koodivaiheen. [S2D #57](https://github.com/annasuuronen/MaaltaMerelle/pull/57) on edelleen tulevien hallittujen ajojen pääsopimus. [S2E #59](https://github.com/annasuuronen/MaaltaMerelle/pull/59) on erillinen synteettinen tietueskeema, eikä sitä muuteta. [S2F #61](https://github.com/annasuuronen/MaaltaMerelle/pull/61) on erillinen Base-R:n synteettinen havainnoija: tällä koodilla **ei** vielä ole R-kirjoitinta tai S2F-integraatiota.

Tämän moduulin `encode_batch()` ja `decode_batch()` koodaavat *kutsujan jo antamat* synteettiset, tyyppitarkat 02F:n callback-lukuerät. `make_synthetic_claim()` ja `verify_synthetic_claim()` vertaavat niistä muodostettavan **itse ilmoitetun** JSON-tietueen arvoja kutsujan antamiin eriin. SHA256 ei ole historiallinen D8-tiiviste, todellinen rasterinlukutodiste eikä riippumaton allekirjoitus. Todellinen lähdeketju pysyy `NOT_ASSESSED`.

## 1. Binäärinen siirtomuoto `MM-S2IA` v1

Protokollan **pakollinen byte order** on little-endian. Tietue on yksiselitteinen, eikä lukija hyväksy lisätavuja tai puuttuvia tavuja:

| Kenttä järjestyksessä | Koko, tyyppi |
| --- | --- |
| Tunniste | 8 tavua: ASCII `MM-S2IA` + NUL |
| Versio | uint8 = 1 |
| `run_id` | 16 UUID4-tavua, canonical lower-case UUID-string -rajapinta |
| `attempt_id` | 16 UUID4-tavua, ei sama kuin run_id |
| `grid_id`-pituus | uint8, 1–32 |
| `grid_id` | ASCII, `[a-z][a-z0-9_-]{0,31}` |
| Rivejä, sarakkeita | uint16 + uint16, kumpikin 1–9 |
| X- ja Y-origo | int32 + int32; vain ilmoitettu EPSG:3067, 2 m, affine `[x,2,0,y,0,-2]` |
| `sequence` | uint16, 1–24 |
| Rasterirooli | uint8: 1=WATER_CLASS, 2=LAKE_ID, 3=POINTER |
| `count` | uint16, 1–32 |
| Jokainen pyydetty alkio, **alkuperäisessä järjestyksessä** | uint16 solu-ID (1-pohjainen rivijärjestys), uint8 tyyppitag, tavut alustan mukaan |

Tagit: `FINITE=1`, `R_NA=2`, `NAN=3`, `POS_INF=4`, `NEG_INF=5`, `NA_INTEGER=6`, `NODATA=7`. Aineistomääritys on tässä *tarkoituksella synteettinen ja tarkka*: WATER_CLASS = Byte (1 tavu, NoData=255), LAKE_ID = Int32 (4 tavua, R NA_INTEGER = −2147483648), POINTER = Float64 (8 tavua, raw IEEE754). Float64-senttinel R NA_real_ on täsmälleen `0x7FF00000000007A2` uint64:nä; muut NaN-bittikuviot ovat erillinen `NAN`. Infinity-merkit, NaN-payload, +0 ja −0 säilyvät bitteinä. Int32 `16777217` säilyy, eikä arvoja muunnetta Float32-muotoon. Validin Byte-arvon `0` ei ole sama kuin NoData. Kyseessä ei ole yleinen terra-rasterimuoto eikä EPSG-tietokannan tarkistin; grid-koordinaatit ovat ilmoitettuja synteettisiä metatietoja.

Jokaisella erällä on oma järjestysnumero sekä rooli. Kolmen erän natiivi 02F-järjestys on `WATER_CLASS` → `LAKE_ID` → `POINTER`. Kunkin kolmen kutsun solulistan on vastattava toisiaan täsmälleen. Duplikaattisolut *säilytetään*, niitä ei yhdistetä. Enintään 24 erää, 32 arvoa/erä, 512 arvoa/koko väite, 81 solua/grid, 4096 tavua/erä ja 8192 tavua JSON-tietueelle. Nämä ovat pienille synteettisille testeille asetetut rajat, **eivät** LOW:n tuotantoresurssirajat.

`encode_batch(Batch)` palauttaa jäädytetyn `EncodedBatch(data, synthetic_sha256, evidence_scope="SYNTHETIC_ONLY", authentication="NOT_ASSESSED")`. `decode_batch(bytes)` palauttaa jäädytetyn `Batch`-olion ja vaatii uudelleenkoodauksen täydellisen byte-identtisyyden. Raw Float64-bittikuvio on kutsujan vastuulla; tämän moduulin oma API ei lue R:n muistia eikä aineistoja.

## 2. Itse ilmoitettu, suojattu JSON-väite

`make_synthetic_claim(tuple[bytes], declared_status="COMPLETE_CLAIM" | "INCOMPLETE")` palauttaa rajatun ASCII-JSON:n, jossa avaimet ovat aakkosjärjestyksessä, välilyönnit poistettu eikä ylimääräisiä avaimia sallita. `verify_synthetic_claim(raw, observed)` hylkää epäkanoniset tavut, kaksoisavaimet, väärät versiot, epäkelvot UUID:t, kaikki todellisen ajon/todistajan väitteet, väärän hashin, tietueiden ristiriitaisen järjestyksen tai puuttuvan tripletin.

Hyväksytyn *rakenteen* tulos on **ainoastaan** `RECORDED_UNVERIFIED`, perusteena `NO_INDEPENDENT_WITNESS`. Keskeneräiset tai ristiriitaiset väitteet ovat `STOP`. Toiminto ei voi palauttaa `VERIFIED_IN_DECLARED_SCOPE`, eikä se muodosta todistajaa tai run-ID-rekisteriä. Erätiiviste identifioi vain **käyttäjän jo antamat synteettiset tavut**, ei niiden todellista alkuperää. Molemmat argumentit tulevat samalta kutsujalta, joten ristiriidaton itse ilmoitettu tieto ei todista itsenäistä havainnointia.

Kiellettyjen tieteellisten päätösten tila säilyy: `NATIONAL=LOCKED`, `MODERATE=REVIEW_REQUIRED`, `hydrological_validation=NOT_ASSESSED`, `channel_interpretation=NOT_ASSESSED`, `routing_authorized=false`, `outlet_selection=UNASSIGNED`, `RUNTIME_INPUT_LINEAGE=NOT_ASSESSED`, `SOURCE_AUTHENTICATION=NOT_ASSESSED`, historiallinen 02F `STOP`.

## 3. Käyttö ja todellinen testaus

Python-stdlib, **ei asennusta eikä verkkoyhteyttä**. Repositorion juuresta:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s diagnostics/water_connected_graph_design -p test_s2i_a_synthetic_value_protocol.py -v
```

Testit käyttävät sisäisiä, korkeintaan 3×3-vahvoja synteettisiä erinäytteitä; yhtään alkuperäistä CSC-polun rasteria ei avata. Testiajon `OK` ja nimettyjen testien määrä kirjataan PR-kuvaukseen vasta toteutuneen ajon perusteella. Testit sisältävät todellisen koodaus/purkukierroksen, nolla/NA/NaN/Inf/negatiivinen nolla, suuren Int32-järvitunnisteen, kaikki kahdeksan Whitebox-koodia **arvoina ilman D8-siirtymälaskentaa**, kutsujärjestyksen ja solulistojen väärentämisen, SHA256-vaihdon, ristiriitaisen run/attempt ID:n, UTF-8/kaksoisavain-/schema-vääristymät, resurssirajat sekä väärennetyt todistajat ja tieteelliset hyväksynnät.

Testi valvoo myös, ettei moduuli tuo rasteri-, tiedosto-, OS-, prosessi- tai verkko-API:a; varsinainen käyttöliittymä on puhtaasti muistissa. Testaaminen ei tarkoita virallista turvallisuusauditointia, riippumatonta todistajaa tai R/Python-koodauksen samanlaisuuden todentamista.

## 4. Seuraavat erikseen hyväksyttävät vaiheet

**S2I-B:** vertaa R 4.6.1:n synteettisiä callback-tyyppibittejä ja pyydettyjä soluja *tähän määriteltyyn byte-protokollaan* riippumattomalla R-kirjoittimella. R:n `serialize(version=2)` ei sellaisenaan ole tämä siirtomuoto. Vasta sen jälkeen suunnitellaan versioidun snapshotin ja todellisen 02F-kuluttajan turvallinen raja sekä riippumattoman allekirjoittajan ja verifioijan erilliset toteutukset (S2I-C–F). Ei hyväksyttyä CSC-pilottia, D8-tulkintaa tai tuotantointerfacea vielä.

**Tämän PR:n sallitut muutokset:** tämä dokumentti sekä uusi synteettinen Python-moduuli ja sen testit. Ei nykyisten moduulien muokkauksia, ei D8/DEM/STORAGE/water-maskeja, ei uusiin hydrologisiin ajoihin johtavaa koodia. Kaikki PR:t pysyvät draft-tilassa. Ei yhdistämistä.