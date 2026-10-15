# Vertailu aikaisempaan kanoniseen hydrologiatestiin

Vertailukanta on `4bbf22bb39181c8a4c27ebc3e2769766043115b8`, joka oli
`baseline-no-structures`-haaran GitHub HEAD ennen arkistointia 15.10.2026.
Alla olevat lähdekoodirivit tarkoittavat tätä committia.
CSC-vaihe lisää diagnostiikkaa, suoritusmenettelyjä ja QA:ta tämän lähtötilanteen
päälle. Se ei osoita, että kokeelliset menettelyt olisi jo yhdistetty kanoniseen
R-putkeen tai että CSC-tulokset vastaisivat tieteellistä vertailuaineistoa.

## MODERATE resume v1 → v2

[Ensimmäinen versio](scripts/maaltamerelle_roihu_resume_moderate.sh) on
**korvattu** [v2:lla](scripts/maaltamerelle_roihu_resume_moderate_v2.sh).
Molemmat arkistoidaan muuttumattomina. Erot ovat luettavissa suoraan tiedostoista:

| Kohta | V1 | V2 |
| --- | --- | --- |
| D8:n arvovertailu FLT8S-muunnoksen jälkeen | `readValues(ref, ...)` lukee korkeusmallia ja vertaa korkeuksia D8-koodeihin (rivit 80–88). | Lukee `src`-D8:n ja vertaa sen koodeja muunnettuun `ptr`-D8:aan (rivit 75–102). |
| Geometria ja NoData | Vertaa muunnoksen jälkeistä geometriaa pintaan; väärä arvoreferenssi sekoittaa myös maskitarkistuksen merkityksen. | Geometria sekä D8-lähteeseen että pintaan; erilliset lähde–pointer- ja pinta–pointer-maskit. Kaikkien ero- ja virhekoodilaskurien on oltava nolla 36 miljoonalla solulla. |
| Tulosten säilytys | `moderate_resume_20261014`. | Erillinen `moderate_resume_20261014_v2`; v1:n ja alkuperäiset tulokset säilyvät. |
| `status()`-funktion PASS-polku | `$PASS` määritellään vain generoidun Slurm-skriptin sisällä; ulomman `status()`-funktion viite on määrittelemätön `set -u`:lla (rivi 210). | Myös ulompi kuori määrittelee `PASS`-polun (rivi 23). |
| Vaadittu vaihemerkintä | `02D.8 HARD QA: PASS`. | `02D.7E HARD QA: PASS`; muut kolme vaadittua merkintää säilyvät (rivi 174). |

Molemmat viimeisen rivin vaihemerkinnät esiintyvät vertailukannan lähdekoodissa:
[02D.8](../../../R/02D8_final_spill_evidence.R#L84) ja
[02D.7E](../../../R/02_build_baseline_hydrology.R#L12531).
Merkinnän vaihtoa ei siis voi selittää väitteellä, ettei aikaisempaa merkintää
olisi lähdekoodissa. Todellinen ajokonteksti ja mahdollinen keskeytyskohta
vaativat v1:n ja v2:n Slurm-lokit. Skriptien ero todentaa korjauksen sisällön,
mutta ei yksin minkään CSC-ajon onnistumista.

## Jo kanonisessa lähdekoodissa

| Menetelmä | Lähde vertailukannassa | CSC-vaiheen suhde |
| --- | --- | --- |
| Whitebox-D8-koodaus `esri_pntr=FALSE`; FLT8S, DEFLATE ja BIGTIFF | [02B, rivit 704–754](../../../R/02_build_baseline_hydrology.R#L704) | CSC-kokeet ja v2-muunnos käyttävät samaa koodausta ja muotoa; uutta suuntakoodausalgoritmia ei lisätä. |
| Valmiiden rasterien uudelleenkäyttö `OVERWRITE=FALSE` | [Konfiguraatio, rivi 95](../../../R/00_pipeline_config.R#L95); [02A, rivi 175](../../../R/02_build_baseline_hydrology.R#L175); [02B, rivit 712–715](../../../R/02_build_baseline_hydrology.R#L712) | CSC-jatkoajo valmistaa erilliset syötetiedostot näitä olemassa olevia ehtoja varten. |
| CSC-polut, alueen parametrit ja `HYDRO_RUN_ROOT`-ylikirjoitus | [Konfiguraatio, rivit 165–180 ja 235–247](../../../R/00_pipeline_config.R#L165) | Jatkoskriptit asettavat jo tuetut muuttujat MODERATE-alueelle. |
| WATER_STORAGE-täyttö `fix_flats=FALSE` | [02A, rivit 305–335](../../../R/02_build_baseline_hydrology.R#L305) | Fill-uusintakoe toistaa menetelmää erillisellä tuloksella. LAND-täytön `fix_flats=TRUE` on eri vaihe (rivit 230–239). |
| FillDepressions yhdellä työntekijällä ja enintään yksi uusinta | [02A-apuri, rivit 22–47](../../../R/02A_whitebox_fill_retry.R#L22); [testi](../../../tests/whitebox_fill_retry.R) | Tämä oli jo kanoninen korjaus, ei uusi CSC-tuotantokorjaus. |
| Korotetut komponentit, `1e-7`-toleranssi ja järvikohtainen 02D.4-yhteenveto | [02D.4, rivit 4793–5099](../../../R/02_build_baseline_hydrology.R#L4793) | CSC-auditointi laskee riippumattomat soluluvut olemassa olevista pinnoista. |
| Valinnainen rasteriregressio: geometria, NA-maskit, muuttuneet solut ja maksimiero | [02A-vertailu, rivit 374–539](../../../R/02_build_baseline_hydrology.R#L374) | Ei sama asia kuin CSC:n kahden D8-kokeen arvovertailu tai LOW/MODERATE-provenienssiauditointi. |
| 02E:n rinnakkaiset ehdokkaat ja 02F:n eksplisiittiset päätepisteluokat | [02E](../../../R/02E_water_connected_candidates.R), [02F](../../../R/02F_water_connected_route_diagnostics.R), [02F-testit](../../../tests/water_connected_route_diagnostics.R) | Jatkoajo kutsuu näitä vaiheita; ei valitse lopullisia purkautumisreittejä. |
| `outlet_selection=UNASSIGNED`; NATIONAL-lukitus | [02D.8, rivit 74–78](../../../R/02D8_final_spill_evidence.R#L74); [konfiguraatio, rivit 191–198](../../../R/00_pipeline_config.R#L191) | Rajaukset säilyvät. |

## CSC-vaiheessa lisätyt menettelyt, joita ei ole kanonisessa R-putkessa

| CSC-menettely | Mitä se lisää | Mitä se ei vielä todista |
| --- | --- | --- |
| D8-diagnostiikka ja `shared_1` / `shared_4` / `local_1` -matriisi | Erottaa R-kääreen, suoran binäärin, työntekijämäärän ja solmukohtaisen tilapäislevyn vaikutuksia; rajattu timeout. | Metatietojen tarkistus ei osoita arvojen tai hydrologian oikeellisuutta. |
| D8-kokeiden lohkoittainen kaikkien solujen vertailu | Kahden itsenäisen pointer-rasterin arvot, sallitut koodit ja jakaumat. | Kahden kokeen yhtäläisyys ei ole riippumaton tieteellinen vertailureferenssi. |
| Korjattu v2-muunnoksen jälkiluku | D8-arvojen ja kahden maskisuhteen tarkistus FLT8S-kirjoituksen jälkeen. | Kanoninen 02B kirjoittaa muunnoksen, mutta ei sisällä tätä koko rasterin jälkiluku-QA:ta. V2:n korjaus koskee CSC-apuskriptiä, ei osoitettua kanonisen D8-algoritmin virhettä. |
| Eristetty jatkoajo ja ajonäytön portit | Valmiiden 01/02A-tuotteiden kopiointi, kopioiden tavutarkistus, pointerin odotettu SHA256, Slurm-tila ja QA-merkinnät; alkuperäiset tuotokset säilyvät. | `COMPLETED` tai raporttimerkintä ei yksin osoita tieteellistä vastaavuutta. |
| Riippumaton MODERATE 02D.4-auditointi | Pintojen ja järvimaskin korotettujen solujen uudelleenlaskenta sekä vertailu yhteenvetoon. | Auditointi raportoi poikkeamat; se ei vaadi niitä nollaksi eikä korjaa niitä. |
| LOW/MODERATE storage-provenienssi | Alkuperäisten 02A-pintaparien korotukset/laskut, NA-erot, aikaleimat, koot, SHA256:t ja valinnainen GDAL-metatieto. | Valmistumismarkkeri ei hyväksy pinnan hydrologista sisältöä. |
| Eristetty WATER_STORAGE-fill-uusintakoe | Sama binääri, alkuperäinen menetelmä, yksi työntekijä, tuoreen ja vanhan pinnan sekä järvilukujen vertailu. | QA ei vaadi tuoreen ja vanhan pinnan yhtäläisyyttä eikä vahvista GitHub-referenssin vastaavuutta. |

Nämä menettelyt säilytetään tässä dokumentoituina CSC-kehityksen tuloksina.
Niitä ei siirretä automaattisesti `R/`- tai `tests/`-hakemistoihin. Mahdollinen
myöhempi yhdistäminen vaatii ensin olemassa olevat CSC-tulosraportit, niiden
poikkeamien arvioinnin sekä erillisen koodimuutoksen tarkistuksineen.
