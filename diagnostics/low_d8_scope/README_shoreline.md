# LOW 02C: 22 lähdejärven rantaviivapituuteen suhteutettu tarkistus

Lisädiagnostiikka MaaltaMerelle GitHub PR #12:een, read-only.

**Riippumaton nimittäjä:** RANTA10:n `lakes`-vektoripolygonien alkuperäinen rantaviiva 12×12 km:n LOW-tutkimusruudun sisällä, kilometreinä; ruuturajan kanssa täsmälleen yhtyvät keinotekoiset segmentit vähennetään. Numerointiin käytetään todellisesta 02C D8-osoitinraportista vahvistettuja 22 järvitunnusta, ei oletettuja järvi-ID:itä.

Raportoi per lake: `zero_cells`, `d8_edges`, `shoreline_km`, `zero_cells_per_shore_km`, `d8_edges_per_shore_km`, `touches_tile_edge`, `excluded_tile_border_m`. Jos rasterin sisäinen vektorirantaviivan pituus on 0, suhdeluku jää `NA`.

**Tulkintarajat:** Mittari on 02C-otosperusteinen paikallisten D8-katkosten lukumäärä suhteessa vektorirantaviivan pituuteen, **ei** mallin hydrologinen virheprosentti, rasterin pikselirantaviivan laskenta, järvien outletien korjaustarve eikä kaikkien LOW-reitityskatkosten määrä. RANTA10-geometrian clipping/rajaus on tarkastettava, etenkin jos `touches_tile_edge=TRUE`. Vektorirantaviivan metriarvo on EPSG:3067-tasokoordinaatiston pituus; kuvaa järven rannat ja mahdolliset saaren rannat polygonin mukaan. Jos GPKG:tä tai järveä puuttuu, ajo pysähtyy eikä korvaa arvoja keksityillä luvuilla.

CSC Roihu login-solmulla (rajattu rasteriluku, samat 846 ikkunaa kuin aiemmin):

    D="$HOME/low_d8_perimeter_20261016/diagnostics/low_d8_scope"
    B="/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000/02_baseline"
    Rscript --vanilla "$D/test_lake_shoreline_rates.R" && Rscript --vanilla "$D/run_lake_shoreline_rates.R" "$B"

Käytä lisäksi kolmea samaan hakemistoon paketoitua jo Roihussa validoitua read-only
`incoming_02c_lake_d8.R`, `run_incoming_02c_lake_d8.R` ja
`test_incoming_02c_lake_d8.R` -tiedostoa. Geometrian ja suhdelukujen synteettiset testit läpäisivät Roihussa. Ensimmäinen oikean aineiston normalisointiyritys keskeytyi käynnistysvirheeseen: lähde-D8-ajon status-silmukka muutti `d`-hakemistomuuttujan data.frame-olioksi (`source()`: length 7). Korjattu ajuri käyttää pysyvää `shoreline_script_dir_02c`-hakemistomuuttujaa ja regressiotesti varmistaa tämän. **Korjatun ajurin todellinen CSC Roihu -ajo PASS (16.10.2026):**
`PASS: shoreline runner preserves source paths after D8 status loop`,
`PASS: vector shoreline geometry incl. clipped tile border`,
`PASS: lake shoreline rate normalization, ID join and fail-closed cases`,
ja `========== VECTOR SHORELINE CHECK DONE ==========`.
Aiemmat lähdejärvi-D8-summat toistuivat: 22 järveä, 535 nollapäätesolua,
1 273 järvestä tulevaa osoitinta, 1 745 luettua rasterisoluarvoa 846 ikkunassa.

Todellisen RANTA10-vektorigeometrian sisäinen rantaviiva, ruuturajalla leikatut
keinotekoiset rajasegmentit pois laskettuna:

| RANTA10 objectid | Nollapäätesoluja | D8-osoittimia | Rantaviivaa km | Solua / km | Osoitinta / km | Ruuturaja |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 3181 | 317 | 785 | 12.771398 | 24.8211 | 61.4655 | kyllä; pois rajasegmenttiä 1938.335 m |
| 1847 | 88 | 197 | 2.409055 | 36.5288 | 81.7748 | ei |
| 1898 | 26 | 55 | 0.445505 | 58.3608 | 123.4555 | ei |
| 1887 | 8 | 18 | 0.126766 | 63.1086 | 141.9944 | ei |
| 1832 | 15 | 32 | 0.287172 | 52.2336 | 111.4316 | kyllä; pois rajasegmenttiä 58.685 m |
| 1894 | 10 | 19 | 0.267766 | 37.3460 | 70.9574 | ei |

22/22 polygonin pituudet olivat positiiviset; ruudun reunaa koski 2 järveä
(3181 ja 1832); `LAKES_WITHOUT_INTERIOR_SHORELINE=0`.
Kaksi absoluuttisesti suurinta lähdejärveä 3181 ja 1847 kattavat
405/535 = 75,7 % katkeavista nollasoluista, mutta niiden normalisoidut
tiheydet ovat 24,82 ja 36,53 solua/rantakm. 1847:n luku on noin 47 % suurempi;
3181:n tiheys on sijalla 12/22, 1847 sijalla 7/22 (järjestys
nollapäätesolua/km, suurimmasta pienimpään).

**Rajaukset:** normalisointi on *D8-nollapäätesoluja per RANTA10-vektorirantakm
ruudun sisällä*, ei virheprosentti eikä koko järven tai koko LOW:n virheaste.
Lyhyillä rantaviivoilla suhdeluku on herkkä yksittäisille soluille.
Ruutuun rajautuvien järvien osalta rajattua rantaviivaa ei pidä tulkita
koko järven rantaviivaksi. Seuraavaksi tulee harkita riippumatonta
nimittäjää (esim. kaikki järvestä maalle todella tulevat D8-osoittimet),
rajatapausten herkkyyttä ja valittujen järvien rantakorkeuden käsittelyä
ennen hydrologista hyväksyntää. Ei uusia D8-, DEM- tai outlet-muutoksia.

**Ei DEM-, D8-, outlet- eikä syötetiedostojen muutoksia. NATIONAL LOCKED; MODERATE REVIEW_REQUIRED.**
