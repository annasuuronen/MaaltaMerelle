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
`test_incoming_02c_lake_d8.R` -tiedostoa. Varsinaisen geometria-ajon PASS odottaa Roihun tulosta; tässä toteutusympäristössä ei ole R-tulkkia.

**Ei DEM-, D8-, outlet- eikä syötetiedostojen muutoksia. NATIONAL LOCKED; MODERATE REVIEW_REQUIRED.**
