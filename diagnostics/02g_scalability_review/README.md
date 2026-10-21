# 02G: skaalautuvuuden ja muistinkäytön menetelmäpäätös

[Issue #29](https://github.com/annasuuronen/MaaltaMerelle/issues/29),
21.10.2026. Tämä toimitus sisältää vain katselmointidokumentit.

**Päätös:** lukumäärä-/jäsenyyshybridi on perusteltu jatkosuunta. Seuraavaksi
ehdotetaan vain yhtä pientä toteutusta: erillistä, täysin havaitun paikallisen
DAG:n numeerista lukumääräydintä. Nykyiset sensuroidut lähdejäsenyydet ja
tiilikuitit säilyvät erillisenä auditointinäyttönä. Niitä ei muuteta täydellisen
verkon kertymäksi. Tässä tehtävässä tätä ydintä **ei toteuteta tai testata**.
Hajautettu koko valuma-alueen laskenta ei vielä saa toteutusvalmiutta.

Uusi haara: `codex/low-02g-scalability-design-review-v1`.
Tarkka lähtöcommit: `98f1c83978276dd6d938d37b7244bf50739681e8` (PR #28).
Lähtöhaara: `codex/low-02g-independent-tile-receipts-v1`.
PR #25:n aineisto luetaan commitista
`08a7b17f856aa266cd989a3c9c2bb9734e623900`. Aiempia haaroja ei yhdistetä.

| Dokumentti | Arvioitava sisältö |
| --- | --- |
| [complexity_and_invariants.md](complexity_and_invariants.md) | Toteutuksen aika-, tila- ja I/O-malli; neljä erillistä tulostavoitetta; kertalaskennan ehdot |
| [alternatives_decision.md](alternatives_decision.md) | Kuuden vaihtoehdon vertailu, valittu seuraava muutos ja sen hyväksyntä-/STOP-ehdot |
| [counterexamples.md](counterexamples.md) | Käsin johdetut pienet vastaesimerkit; eivät uusia suoritettuja testejä |

<a id="measurements"></a>
## Aiempi mitattu näyttö

Luvut on luettu arkistoiduista raporteista, ei mitattu uudelleen tässä työssä.

| Aineisto | Rajaus | Arkistoitu tulos | Kesto | Raportoitu lapsi-RSS / näytteistetty ryhmä-RSS |
| --- | --- | --- | --- | --- |
| 02G / PR #25 | 1 000 solun fan-fixture, askelraja 32 | PASS, 3 007 tarkistusta | 4,4623 s koko koe; 3,786 s laskenta; 0,430 s orakkeli | 144,812 / 144,742 MiB |
| 02G / PR #25 | Valinnainen 10 000 solua | `NOT_RUN_RESOURCE_GATE` | Ei mittausta | Ei mittausta |
| 02G.2 / PR #28 | Pieni sarja, pääfixture 27 ruudukkopaikkaa / 11 maasolua | 12 tapausta / 2 293 tarkistusta PASS | 1,9807 s koko sarja | 65,250 / 130,898 MiB |

Ensimmäisen rivin lähteet ovat [CSV:n viimeinen rivi][M1],
[koeloki][M2] ja [koeohjelma][M3]. Palautetun 02G-tulosolion
`object.size` on 3,163429 MiB; se **ei** ole prosessin muistihuippu eikä sisällä
kaikkia reittejä, orakkelia, väliaikaisia olioita tai R-ympäristöä.
02G.2:n lähteet ovat [CSV][M4] ja [pienen sarjan rajaus][D2].
Ryhmämittaus sisältää vastaanottajan erillisen R-prosessin.

10 000 solun väliin jättäminen on resurssiportin päätös: testiajuri kirjasi
konservatiivisen 15-kertaisen RSS-projektion ([A4], rivit 31–35), ja nykyinen
02G-konstruktori rajaa ruudukon 1 000 paikkaan ([A1], rivit 3–8).
Kyse ei ole mitatusta muistivirheestä, 10 000 solun skaalaustuloksesta tai
todistetusta lineaarisesta kasvusta. RSS:n vakio-osuutta ja datan osuutta ei ole
näillä mittauksilla erotettu. 02G.2 ei sisällä 1 000+ solun koetta.

02G:n yksi alkuvaiheen FAIL sekä 02G.2:n kaksi alkuvaiheen FAIL-lokia ja kaikki
myöhemmät PASS-tulokset säilyvät alkuperäisissä hakemistoissa ([D1], [D2]).
Tämä katselmointi ei tuota uusia algoritmien PASS-lukumääriä tai resurssimittauksia.

<a id="sources"></a>
## Lähteet ja viittaustapa

Alla olevat tunnukset sitovat toteutusväitteet tiedostoon, funktioon ja
muuttumattomaan committiin. Muut dokumentit ilmoittavat lisäksi rivialueen.
A-lähteet ovat commitissa `08a7b17f856aa266cd989a3c9c2bb9734e623900`;
B-, R- ja S-lähteet commitissa `98f1c83978276dd6d938d37b7244bf50739681e8`.
Teoreettinen johtopäätös ja seuraavan vaiheen ehdotus erotetaan nykykoodin
havainnosta; big-O ei ole mitattu MiB-arvo.

| Tunnus | Tiedosto / funktiot / tarkastettu alue |
| --- | --- |
| [A1] | `accumulation.R`: `g02_observe` 32–45, `g02_from_network` 49–54, `g02_accumulate` 55–170 |
| [A2] | `tiles.R`: `g02_layout` 7–24, `g02_tile_accumulation` 25–92 |
| [A3] | `tests/support.R`: riippumaton `reference` 38–58 ja `verify` 59–83 |
| [A4] | `tests/run_tests.py`: kokeiden ja resurssiportin määritys 17–43 |
| [A5] | `tests/test_tiles.R`: 27 paikan fixture ja kaksi/kolme tiiltä, vertailut ja puuttuva naapuri 4–76 |
| [B1] | `messages.R`: sopimus 3–16, aktori 17–29, eteneminen 49–92, vastaanotto/kuitti 93–161, koonti 162–250 |
| [B2] | `tests/oracle.R`: fixture 3–23 ja riippumaton `r_reference` 29–57 |
| [B3] | `tests/test_protocol.R`: orakkelivertailu 49–90, prosessieristys 92–105, virheet ja jatkaminen 106–213 |
| [B4] | `tests/receive_worker.R`: vain vastaanottajan tila ja yksi viesti, RDS-luku/-kirjoitus 1–11 |
| [R1] | `trace_land_d8_route.R`: havaintojen kasvatus 48–55, havainto-/polku-/siirtymätaulut 66–113 |
| [R2] | `lake_1847_focus_core.R`: `l1847_trace`, sykli/pointeri/askelraja ja D8-eteneminen 71–100 |
| [S1] | `synthetic_scale/run_validation.py`: `run_one`, aikarajat, RSS-näytteet ja mittareiden tallennus 62–133 |
| [D1] | PR #25:n README: merkitykset, resurssirajaus, aiemmat epäonnistumiset |
| [D2] | PR #28:n README: protokolla, erillinen vastaanotto, tulokset ja puuttuvat tuotantoedellytykset |

## Toimituksen tarkistus ja rajat

Tarkistukset tässä työssä ovat dokumenttien lähdeviitteiden, raporttilukujen,
paikallisten linkkien, muuttuneiden polkujen ja `git diff --check` -tarkistuksia.
R-testejä tai stressikampanjoita ei ajeta. Muutoksia saa olla ainoastaan tämän
hakemiston neljässä Markdown-tiedostossa. Tuotanto-R, tutkimusprototyypit,
aiemmat raportit/lokit, `tests/` ja työnkulut säilyvät koskemattomina.

CSC-, Slurm- ja SSH-yhteyksiä, rasterilukuja tai DEM/D8/STORAGE/vesimaski- tai
outlet-muutoksia ei tehdä. [Issuen #29](https://github.com/annasuuronen/MaaltaMerelle/issues/29)
mukainen seuraava erikseen hyväksyttävä todellisen LOW-aineiston portti on
edelleen PR #22:n **14 lukittua vastaanottajasolua / 56 palautettua arvoa**,
kun yhteys ja syöteidentiteetti on varmennettu. Tämä dokumentaatio ei anna
siihen eikä seuraavan algoritmin toteutukseen uutta ajolupaa.

`hydrological_validation=NOT_ASSESSED`
`channel_interpretation=NOT_ASSESSED`
`MODERATE=REVIEW_REQUIRED`
`NATIONAL=LOCKED`

[A1]: https://github.com/annasuuronen/MaaltaMerelle/blob/08a7b17f856aa266cd989a3c9c2bb9734e623900/diagnostics/02g_accumulation_tile/accumulation.R
[A2]: https://github.com/annasuuronen/MaaltaMerelle/blob/08a7b17f856aa266cd989a3c9c2bb9734e623900/diagnostics/02g_accumulation_tile/tiles.R
[A3]: https://github.com/annasuuronen/MaaltaMerelle/blob/08a7b17f856aa266cd989a3c9c2bb9734e623900/diagnostics/02g_accumulation_tile/tests/support.R
[A4]: https://github.com/annasuuronen/MaaltaMerelle/blob/08a7b17f856aa266cd989a3c9c2bb9734e623900/diagnostics/02g_accumulation_tile/tests/run_tests.py
[A5]: https://github.com/annasuuronen/MaaltaMerelle/blob/08a7b17f856aa266cd989a3c9c2bb9734e623900/diagnostics/02g_accumulation_tile/tests/test_tiles.R
[B1]: https://github.com/annasuuronen/MaaltaMerelle/blob/98f1c83978276dd6d938d37b7244bf50739681e8/diagnostics/02g_independent_tile_receipts/messages.R
[B2]: https://github.com/annasuuronen/MaaltaMerelle/blob/98f1c83978276dd6d938d37b7244bf50739681e8/diagnostics/02g_independent_tile_receipts/tests/oracle.R
[B3]: https://github.com/annasuuronen/MaaltaMerelle/blob/98f1c83978276dd6d938d37b7244bf50739681e8/diagnostics/02g_independent_tile_receipts/tests/test_protocol.R
[B4]: https://github.com/annasuuronen/MaaltaMerelle/blob/98f1c83978276dd6d938d37b7244bf50739681e8/diagnostics/02g_independent_tile_receipts/tests/receive_worker.R
[R1]: https://github.com/annasuuronen/MaaltaMerelle/blob/98f1c83978276dd6d938d37b7244bf50739681e8/diagnostics/land_d8_continuity/trace_land_d8_route.R
[R2]: https://github.com/annasuuronen/MaaltaMerelle/blob/98f1c83978276dd6d938d37b7244bf50739681e8/diagnostics/low_d8_scope/lake_1847_focus_core.R
[S1]: https://github.com/annasuuronen/MaaltaMerelle/blob/98f1c83978276dd6d938d37b7244bf50739681e8/diagnostics/land_network_topology/synthetic_scale/run_validation.py
[D1]: https://github.com/annasuuronen/MaaltaMerelle/blob/08a7b17f856aa266cd989a3c9c2bb9734e623900/diagnostics/02g_accumulation_tile/README.md
[D2]: https://github.com/annasuuronen/MaaltaMerelle/blob/98f1c83978276dd6d938d37b7244bf50739681e8/diagnostics/02g_independent_tile_receipts/README.md
[M1]: https://github.com/annasuuronen/MaaltaMerelle/blob/08a7b17f856aa266cd989a3c9c2bb9734e623900/diagnostics/02g_accumulation_tile/results.csv#L22
[M2]: https://github.com/annasuuronen/MaaltaMerelle/blob/08a7b17f856aa266cd989a3c9c2bb9734e623900/diagnostics/02g_accumulation_tile/prototype_performance_attempt4.log#L1
[M3]: https://github.com/annasuuronen/MaaltaMerelle/blob/08a7b17f856aa266cd989a3c9c2bb9734e623900/diagnostics/02g_accumulation_tile/tests/performance.R#L5-L14
[M4]: https://github.com/annasuuronen/MaaltaMerelle/blob/98f1c83978276dd6d938d37b7244bf50739681e8/diagnostics/02g_independent_tile_receipts/results.csv#L6
