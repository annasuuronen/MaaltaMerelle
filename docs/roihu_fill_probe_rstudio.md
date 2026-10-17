# MODERATE: yksi rajattu RStudio-diagnostiikkapaketti

Lähtöversio: PR #7, `50f7d5a80c52dde020594ca84c724a7c27adf020`.
Mittausnäyttö: `docs/moderate_roihu_readonly_review_20261016.md`
commitissa `de3d3808bd657c680134b578524ce4ddd4863a0c`.
Käyttäjän raportoima Roihu-käynnistys 17.10.2026 jobissa `2357699`
pysähtyi ennen järvikoetinta piilotettuihin cgroup-muistitiedostoihin.
Raporttipaketti muodostui; hydrologisia havaintoja ei syntynyt. Alla oleva
muistintarkistuksen korjaus on valmisteltu synteettisesti, ei ajettu Roihussa.

`scripts/roihu_probe_rstudio.sh` käynnistetään **jo varatun RStudio-laskentasolmun
Terminalissa**. Se käyttää istunnon PATHista löytyviä Python 3:a, Gitiä ja
Rscriptiä sekä R:n terra-pakettia. Se ei asenna paketteja, lataa moduuleja,
käytä sbatchia tai kutsu Whiteboxia. Muistivaramenetelmä saa tehdä vain oman
varauksen rajatun read-only `scontrol --oneliner show job ID` -kyselyn. Alkuperäinen
`roihu_moderate_validation.sbatch` ja historialliset CSC-skriptit säilyvät.

## Mitä uusi mittaus erottaa

49 sisäjärven kohdalla tutkitaan koko ID:n erillisiä 8-naapurikomponentteja,
tarkkojen pit-ehdokkaiden lukumäärää ja yksittäisestä pitistä alkavan rajatun
paikallishaun alempaa naapuria, etäistä ei-finiittistä kontaktia sekä
ikkuna-/työrajaan pysähtymistä. Raportti sisältää alkuperäisen rasterin
rivi-/sarakekoordinaatit. Vakioitu 32 solun reunus on havaintoikkuna;
kauempana oleva NoData-yhteys voi jäädä sen ulkopuolelle.

Koetin ei toisinna Whiteboxin kaikkien pitien yhteistä käsittelytilaa eikä
osoita luonnollista outletia. `fix_flats=FALSE` ei yksin selitä täyttymättömyyttä.
Järven tasaisuus toleranssilla ei takaa tasaisuutta algoritmin tarkassa
vertailussa. Jo valmistuneita rantanaapuri-, STORAGE-ero- tai D8-auditointeja
ei toisteta. 52 järven todellista yhteistä syytä ei päätellä tästä mallista.

## Provenienssisopimus ja puutteet

Nykyinen **havaintoaineisto** sidotaan seuraavasti ennen ikkunalukua:

- Puhdas checkout, myös untracked-tiedostot, ja ulkoa komennossa annettu täysi
  commit-SHA. Liikkuva haaranimi ei riitä koodiversioksi.
- Kaksi täsmällistä rasteripolkua: V2:n LAND_WATER ja alkuperäinen järvi-ID.
  Niiden todelliset SHA256-tiivisteet verrataan 16.10. raportin ulkoisiin
  tiivisteisiin. Tämä on yksi rajattu tiedostotavujen läpikäynti kummallekin,
  enintään 1 GiB/tiedosto; rasteriarvoja ei tällöin pureta muistimatriisiksi.
- Nykyisestä 02D.4-yhteenveto-CSV:stä otetaan enintään 5 MiB:n tilannekuva ja
  mitataan sen SHA256. CSV:lle **ei ole aiemmin riippumattomasti raportoitua
  tiivistettä**: uusi tiiviste on tämän havaintoajon sidonta, ei historiallinen
  aitoustodistus. Luokittelija tarkistaa kaikki vaaditut sarakkeet ja ristiriidat.
- Rasterien laite/inode/koko/mtime/ctime sekä CSV tarkistetaan uudelleen lopuksi.
  Muutos mitätöi havaintojen kelpoisuuden. GDAL-sivutiedostoja ei hyväksytä.

Alkuperäisen **STORAGE-tuotantoajon** provenienssi on eri kysymys. Pieni,
koodissa lueteltu joukko alkuperäisiä QA-raportteja, V2:n resume-lokia,
resume-skriptiä, olemassa olevia provenienssiraportteja ja 16.10. raportteja
inventoidaan. Alkuperäisen MODERATE-lokin odotuspolku on
`hydro_01_02/logs/hydro_2264131_1.log` arkistoidun D8-diagnostiikan perusteella;
sen olemassaoloa tai sisältöä ei ole tässä tarkistettu. Tuntemattoman
alkuperäisen ajomanifestin/välimuistimanifestin tarkkaa nimeä ei arvata eikä
tiedostoja etsitä wildcardilla. Käynnistin ei seuraa job-ID-tiedoston sisältöä
uusien tiedostopolkujen avaamiseksi.

Inventaario erottaa `NOT_CHECKED`, `MISSING`, `UNREADABLE` ja `AVAILABLE`.
Yli 5 MiB:n vanhasta lokista luetaan vain metadata ja kirjataan `NOT_CHECKED` /
`SIZE_LIMIT`. Pienistä lokeista tallennetaan SHA256 sekä rajattu määrä
tyyppitunnisteita ja rivinumeroita; raakalokeja, komentorivejä tai ympäristön
arvoja ei kopioida. WATER_STORAGE-rastereista kerätään vain metadata
(`NOT_CHECKED`, `METADATA_ONLY`),
ei uutta arvovertailua. Alkuperäisen ja V2:n kopioiden samuus ei todista
riippumatonta täyttöajoa. Pelkkä lokitunniste, mtime tai binääritiivisteen
esiintyminen tekstissä ei todista toteutunutta käskyä ja onnistunutta loppua.

`provenance_gaps.json` luettelee tarvittavat alkuperäisen komennon, oikeasti
ajetun binäärin/version, exit-tilan, input/output-sidonnan sekä
OVERWRITE-/tiedoston-olemassaolo-/cache-päätöksen todisteet. Automaatti säilyttää
`historical_provenance=INCOMPLETE` ja `historical_attribution_authorized=false`,
vaikka kaikki ehdokasraportit löytyisivät. Ihmistarkastus ratkaisee niiden
tulkinnan. Puuttuva **nykyisen syötteen sidonta** estää koettimen kokonaan;
puuttuva **historiallinen ajotodiste** estää historiallisen syypäätelmän,
mutta ei varmennettujen nykyisten ikkunoiden itsenäistä havainnointia.

## Ennalta määrätty valinta ja rajat

1. Vaaditaan 158 ristiriidatonta yhteenvetoriviä, nolla mitattua korotussolua /
   komponenttia ja täsmälleen 52 `POSITIVE_THRESHOLD_NO_OBSERVED_RAISE`-riviä.
2. Suljetaan pois raportoidut kolme reunajärveä **203439, 203443, 203444**.
   Jäljelle on jäätävä 49 yksilöllistä ID:tä, jotka käsitellään ID-järjestyksessä.
   Koko 49 ID:n aiempaa riippumatonta luetteloa ei ole GitHub-raportissa.
3. Varmennetusta ID-rasterista luetaan yksi läpikäynti enintään 65 536 solun
   rivierissä. Näin saadaan kunkin kokonaisen ID:n solumäärä ja kaikkia erillisiä
   osia kattava bbox. Korkeusrasterista luetaan tässä vaiheessa vain header.
   Solumäärän poikkeama tai odottamaton ulkoreunakosketus estää kyseisen järven.
4. Bboxiin lisätään kiinteä 32 solun reunus rasterirajoihin asti. Enintään
   250 000 solua/ikkuna, 4 miljoonaa ikkunasolua koko ajossa päällekkäisyydet
   mukaan lukien. Liian suurta bboxia ei pienennetä osittaiseksi ID:ksi.
   `windows.csv` tallennetaan ennen yhtäkään korkeusikkunan lukua.
5. Olemassa oleva `probe_fill_hypotheses_readonly.R` suoritetaan per ID,
   enintään 2 000 haun käsiteltyä solua/järvi, yhteensä enintään 98 000.
   Maskin osat eritellään; koettimen 100 komponentin lisäraja säilyy.

Koko rasterin koko on enintään 36 miljoonaa solua; oikeassa profiilissa
vaaditaan 6000 × 6000, 2 m, EPSG:3067 ja yhdenmukainen geometria. Kaikki
polkukomponentit tarkistetaan symlinkkien ja polkukierron varalta. Syötepuut
oletetaan luotettujen ylläpitäjien hallitsemiksi; näitä read-only-tarkistuksia
ei esitetä suojana vihamielistä samanaikaista hakemistovaihtoa vastaan.

Ennen ajoa ja joka ikkunaa vaaditaan vähintään 3 GiB varmennettua
muistiheadroomia. Menetelmä ja kaikki arvot kirjataan `summary.json`-tiedoston
`memory_checks`-listaan, myös estyneessä tarkistuksessa:

1. **`CGROUP_V2`:** `/proc/self/cgroup`-tiedoston todellinen job-/task-polku
   luetaan ensin `/sys/fs/cgroup`-liitoksen alta. Sitten tarkistetaan rajat ja
   käyttö vanhemmista liitoksen juureen asti. Polkukierron tai symlinkin kautta
   ei avata tiedostoja. Puuttuva ja lukukelvoton tiedosto kirjataan erikseen.
   Virheellinen numeerinen tieto pysäyttää ajon. Pelkkä luettava liitoksen
   juuritason pari ei korvaa piilotettua job-rajaa oikeassa Slurm-profiilissa.
2. **`SLURM_VERIFIED_NODE_BOUND`:** jos jobkohtainen muistikirjanpito ei ole
   luettavissa, vaaditaan job-ID:n vastaavuus kernelin `job_ID`-jäsenyyteen,
   numeerinen `SLURM_MEM_PER_NODE` ja Slurm-ohjaimen vahvistama oma RUNNING-
   varaus samalla yhdellä laskentasolmulla. UID:n, job-ID:n, solmun ja
   `AllocTRES mem` -varauksen on täsmättävä. Ympäristömuuttujat eivät yksin
   valtuuta ajoa. Kyselyä rajoittavat 5 s ja tulosteen kokorajat; siitä
   tallennetaan vain tarvittavat valitut arvot. Varmennustieto kelpaa enintään
   30 s; solmun muistihavainto luetaan aina uudelleen.
3. Piilotetun job-käytön tilalle ei keksitä lukua. Konservatiivinen yläraja
   on **koko solmun käytetty fyysinen muisti** `MemTotal - MemFree`.
   Se sisältää myös muiden jobien muistin, kernelin ja välimuistin.
   Headroomin alaraja on
   `max(0, min(varaus, luettavat cgroup-maksimit) - solmun_käyttö - 2 GiB)`.
   Lopullinen hyväksyttävä määrä on pienempi tästä ja `/proc/meminfo`-
   tiedoston `MemAvailable`-arvosta sekä luettavista cgroup-headroomeista.
   **32 GiB:n varaus ei siten tarkoita 32 GiB vapaata muistia.**

Varamenetelmä on tarkoituksella tiukka: kuormitettu solmu tai suuri
välimuisti voi estää ajon, vaikka jobilla todellisuudessa olisi riittävästi
tilaa. Esimerkiksi 32 GiB:n varaus ja solmun 8 GiB käyttö antavat enintään
22 GiB headroomia; 31 GiB käyttö antaa nollan. Nämä ovat synteettisiä
esimerkkejä, eivät Roihulta mitattuja arvoja. Jobin todellista cgroup-käyttöä
tai piilotettua kernelin rajaa ei väitetä mitatuksi. Mikään hetkellinen
mittaus tai turvavara ei takaa tulevaa saatavuutta. Riittämätön näyttö,
puuttuva scontrol tai ristiriitainen varaus pysäyttää ajon ennen rasterilukua
ja säilyttää puutteet raportissa; per-CPU- ja monisolmuvarauksia ei arvata.

R-aliprosessin osoiteavaruus on edelleen
enintään 2 GiB, CPU-aika 120 s ja seinäkelloaika 180 s/vaihe;
koko ketjun työbudjetti 900 s. Jokaisen R-tulos-/lokitiedoston kirjoitusraja
on 128 KiB. Tulostilaa vaaditaan 1 GiB; terra-väliaikaistiedostot ohjataan
uuteen yksityiseen raporttihakemistoon. Paketti on enintään 24 MiB ennen gzipiä.
Varauksen numeerinen `SLURM_JOB_ID` vaaditaan; mitään uutta varausta ei tehdä.

## Käynnistys ja raportti

Käytä PR:n valmistumisen yhteydessä annettua yhtä commit-pinnattua komentoa.
Se luo uuden yksityisen hakemiston `/scratch/project_2004707/pienvedet/` alle,
kloonaa erillisen koodikopion, checkouttaa täsmällisen SHA:n ja kutsuu:

```bash
bash "$MM_RUN/code/scripts/roihu_probe_rstudio.sh" \
  --expected-commit "$MM_PIN" --output-parent "$MM_RUN/reports"
```

GitHubista kloonaaminen kuuluu bootstrap-komentoon. Diagnostiikan Slurm-
varamenetelmä voi tehdä oman varauksen read-only ohjainkyselyn; se ei luo
varausta tai käynnistä CSC-työtä. Tuotannon `/projappl`-checkoutia ei muuteta. Polut tai
syötetiivisteet eivät ole komentoriviltä vaihdettavissa oikeassa profiilissa.
`--synthetic-fixture` on vain CI:n tilapäisaineistoille: se hylkää CSC-juuret.

Tulostettu `REPORT=.../review_bundle.tar.gz` on yksi oikea gzip-tar-arkisto.
Se sisältää yhteenvedon, inventaarion, sidonnat, provenienssipuutteet,
readiness-luokat, ikkunasuunnitelman ja jokaisen yritetyn koettimen rajatun
CSV:n/teknisen stderr-lokin. Rastereita, lähde-CSV:tä, alkuperäisiä raakalokeja
tai väliaikaishakemistoa ei pakata. Arkiston SHA256 on sen vieressä.

Exit 0 tarkoittaa kaikkien 49 ikkunahavaintojen teknistä valmistumista.
Exit 2 tarkoittaa estettyä/osittaista havaintoketjua; jos turvallinen uusi
raporttihakemisto voitiin luoda, myös epäonnistumisesta jää raporttipaketti.
Väärä tai turvaton tulostusjuuri hylätään ennen minkään syötteen lukemista.
`summary.json` kertoo osittaiset, estetyt ja virheelliset havainnot erikseen.
Molemmissa tapauksissa paketin päätöstila on `NEEDS_EVIDENCE`,
`hydrological_success=NOT_ASSESSED`, `continuation_authorized=false`.

**MODERATE=REVIEW_REQUIRED; NATIONAL=LOCKED.** Tuotannon 02D.5-porttia ei muuteta.

## Kevyt tarkistus

`python3 -I -B tests/roihu_memory.py` tarkistaa muistimekanismin itsenäisesti
ilman R:ää tai oikeita Slurm-/CSC-kyselyitä. Roihu-regressiossa job-ID,
32768 MiB:n varaustieto ja kernelin cgroup-merkkijono vastaavat täsmälleen
käyttäjän havaintoa; lisäarvot ja ohjainvastaukset ovat synteettisiä.

`python3 -I -B tests/roihu_probe_bundle.py` suorittaa myös nämä muistiregressiot
ja koko ketjun oikeilla
pienillä terra-rasteilla ja tilapäisillä Git-checkouteilla. Ajuri epäonnistuu
myös nollalla löydetyllä testillä. CI suorittaa sen kerran olemassa olevan
geometry-jobin kautta. Vanhoja workflowita ei muuteta eikä vanhoja 64/22/WBT-
testejä käynnistetä manuaalisesti uudelleen. Pushin normaali PR-CI säilyy.
