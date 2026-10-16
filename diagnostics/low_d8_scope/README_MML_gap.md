# LOW: järven 1847 MML–RANTA10-erotusalue, nollasoluryhmät ja 02E/02F-evidenssi

**CSC Roihu 16.10.2026 — todellinen paikallinen read-only R-testi ja aineistoajo PASS.**
Vertailujärvi 1898. Testi perustuu lukittuun LOW-ruutuun
`E200000_N6900000` ja MML:n vuoden 2025 `MTK-vakavesi_25-04-03.gpkg`
-`jarvi`-tasoon.

## Testattu toteutus

Roihussa ajettu v1 `run_mml_gap_components.R` pysähtyi virheeseen
`BAD_02E_02F_SCHEMA_OR_OUTLET_SELECTION` ennen oikeita aineistotuloksia.
Syynä oli tutkimusskriptin oma virheellinen 02F:n
`lake_objectid`-sarakeoletus, **ei** osoitettu 02E:n outlet-muutos.
02F:n varsinainen reittitaulukko käyttää
`origin_lake_objectid`-saraketta; 02E:n ehdokkailla on
`lake_objectid`. Tämä korjattiin erilliseen v2-pakettiin,
joka testattiin Roihussa onnistuneesti.

Roihussa todetut:
- `PASS: MML-only geometry difference and 8-neighbour distinct-zero clustering`
- `PASS: actual 02E/02F CSV origin_lake_objectid schema and UNASSIGNED invariants`
- `PASS: canonical 02E/02F CSV schema (origin_lake_objectid), outlets UNASSIGNED`
- `PASS: LOW MML-only gap and 02E/02F evidence audited without data modifications`
- `========== LOW MML GAP CHECK DONE ==========`

Kolme GitHubin R-tiedostoa vastaavat **tavu tavulta** Roihussa ajettua
`MaaltaMerelle_LOW_MML_gap_1847_1898_20261016_v2.zip`-pakettia:
- `mml_gap_component_core.R`, blob
  `4f84b1df438fb849380dbf59a16abd02edb61a7f`
- `test_mml_gap_components.R`, blob
  `27c4468ae665c603a34938a8b02515d393ad7ae6`
- `run_mml_gap_components.R`, blob
  `be139ac741f3a4226fe3b8cc0eecbca09b974eea`

Riippuvuus: olemassa oleva `lake_to_land_d8_core.R`.
Ohjelma lukee vain kahden järven rajatut D8-, RANTA10-vesiluokka-
ja järvi-ID-rasteri-ikkunat (enintään 500 000 solua/rasteri/ikkuna),
niiden RANTA10- ja MML-vektorit sekä valmiit
`02E_water_connected_candidate_evidence.csv`,
`02E_water_connected_candidate_spill_edges.csv` ja
`02F_water_connected_route_evidence.csv`.
Se ei kirjoita aineistoja eikä laukaise D8-reititystä tai koko LOW:n
skannausta.

## Vahvistetut tulokset

| Mittari | Järvi 1847 | Järvi 1898 (kontrolli) |
| --- | ---: | ---: |
| Paikallisen ikkunan solut | 65 670 | 8 235 |
| Välittömän D8=0:n erilliset maavastaanottajat | **88** | **26** |
| Järvestä suoraan niihin tulevat D8-osoittimet | **197** | **55** |
| MML:n yksinomainen vesialue, m² (`MML \ RANTA10`) | **8 358.843** | **99.095** |
| RANTA10:n yksinomainen alue, m² (`RANTA10 \ MML`) | **6 842.21** | **3 323.801** |
| MML:n ja RANTA10:n polygonileikkaus, m² | 87 583.41 | 4 372.146 |
| Erillisiä nollasolukeskuksia MML:n yksinomaisella alueella | **88/88** | **0/26** |
| Mediaanietäisyys RANTA10-rajaan, m | 1.9938 | 2.3545 |
| Mediaanietäisyys MML-rajaan, m | 4.6485 | 9.2479 |
| D8=0-vastaanottajien 8-naapuruusryhmät | **21** | **25** |
| 02E:n kaikkia spill-ryhmiä | **20** | **12** |
| 02E:n mukaan otettuja rinnakkaisia ehdokasryhmiä | **0** | **1** |
| 02E:n review-lipullisia ryhmiä | 0 | 0 |
| 02E:n mukaan otettuja spill-reunoja | **0** | **5** |
| 02F:n erillisiä ehdokasvastaanottajareittejä | **0** | **3** |
| 02E-purkupistevalinta | UNASSIGNED | UNASSIGNED |

1847:n kuusi suurinta **8-naapuruusryhmää** sisältävät
**15 + 13 + 11 + 10 + 10 + 8 = 67 / 88** erillistä nollasolua
(76.1 %) ja vastaanottavat niihin yhteensä
**32 + 23 + 17 + 20 + 18 + 17 = 127 / 197**
suoraa järvi-D8-osoitinta (64.5 %).
Muut 15 ryhmää kattavat loput 21 nollasolua.

1898:n suurimmassa ryhmässä on kaksi nollasolua ja
muissa 24 ryhmässä yksi nollasolu. Sillä 02E:n viisi
kandidaattireunaa muodostavat 02F:ssä kolme
erillistä reittiä, joiden kaikkien terminaaliluokka on
`REACHES_RIVER_AREA`. Tämä ei tarkoita, että luonnollinen
järven purkupiste olisi hyväksytty. 1898:n erillisen
D8=0-vastaanottajan geometrinen etäisyys lähimpään 02E:n
spill-vastaanottajaan: mediaani **73.1413 m**, minimi
**24.3311 m**.

## Mitä tuloksista voi ja ei voi päätellä

1847:n 88 erillistä välittömästi D8=0-vastaanottavaa **maasolua**
ovat kaikki MML:n 2025 `jarvi`-polygonissa, mutta RANTA10:n
järvipolygonin ulkopuolella. Edellinen, riippumaton
`touches=TRUE`-QA varmisti, että RANTA10:n alkuperäinen
järvi-ID-rasteri vastaa näiden järvien paikallista
vektorirasterointia; tämä diagnoosi kohdistaa eron
**lähdegeometrioihin**, ei RANTA10-rasteroinnin epäjohdonmukaisuuteen.

21 ryhmää ovat **8-naapuruusryhmiä erillisistä D8=0-soluista**:
ne eivät ole MML-erotuspolygonin komponentteja, valuma-alueita,
koko alavirran reittejä eivätkä purkupaikkoja.

1847:n 02E:ssä on **20 spill-ryhmää mutta yhtäkään mukaan otettua
rinnakkaisehdokasta ei ole**. Siksi saman rajatun 02E-ehdokasjoukon
02F-taulukossa ei ole 1847:n reittejä. **Tämä ei todista,
ettei järvellä olisi luonnollista hydrologista purkuyhteyttä**;
02E:n kriteereihin pääsemättömät ryhmät ja MML/RANTA10:n
rannan geometriavaihtelut edellyttävät tieteellistä tarkastelua.
Edes vertailujärven 1898 jokialueen saavuttava reittiluokitus
ei merkitse outletin hyväksyntää.

**Seuraava rajattu tutkimus:** tutki 1847:n **20:n 02E-ryhmän
`evidence_status`-, `evidence_class`- ja
`has_external_evidence`-jakauma** olemassa olevista CSV:istä,
ja sitä vastaava alkuperäinen 02D.8-evidenssi ennen kuin
jatkotutkimuksen suunta tai mahdollinen riippumaton purku
tulkitaan. Älä valitse automaattisesti MML-rantaa, korjaa
D8:aa tai johda outletia nollasolujen keskittymisestä.

## Rajattu uusintatesti Roihussa (ei yleensä tarvitse ajaa uudelleen)

```bash
D=diagnostics/low_d8_scope
B=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000/02_baseline
module load r-env/461
Rscript --vanilla "$D/test_mml_gap_components.R" &&
  Rscript --vanilla "$D/run_mml_gap_components.R" "$B"
```

NATIONAL **LOCKED**; MODERATE **REVIEW_REQUIRED**;
`SCIENTIFIC_STATUS: REVIEW_REQUIRED`.
Ei muutoksia DEM-, D8-, vesimaski-, STORAGE-,
outlet- tai tuotannon R-koodiin. PR #12 on luonnos.
