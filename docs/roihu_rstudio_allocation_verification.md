# Roihu RStudio: puuttuva varauksen todennus 17.10.2026

## Todettu este ja päätös

Käyttäjän todellinen yritys commitilla
`dfafea61a91df23cf8c7867a6be513b9b18b0026` pysähtyi ennen järvitutkimusta:
`Slurm fallback requires scontrol to verify the current allocation`.
Cgroup-muistitiedostot ja scontrol eivät olleet käytettävissä RStudio-
ympäristössä. `TECHNICAL_STATUS=BLOCKED`, yhteenvedosta poimittu `MEMORY=null`.
Uuden yrityksen job-ID:tä ei toimitettu; aiemman yrityksen tunnusta `2357699`
ei oleteta nykyiseksi.

**Tässä kontissa ei ole osoitettu turvallista, dokumentoitua korvaavaa
varauksen todennuskanavaa. Estoa ei ohiteta.** Ympäristömuuttuja, itse kirjoitettu
manifesti tai pelkkä `MemAvailable` ei osoita voimassa olevaa muistivarausta.
Emme etsi arvattuja Slurm REST -osoitteita, kopioi hostin binäärejä konttiin
tai käytä vanhaa scheduler-tulostetta tuoreena valtuutuksena.

`memory=null` oli lisäksi raportoinnin puute: epäonnistunut funktionpaluu
ei sijoittanut osittaista havaintoa `memory`-kenttään. Havainnot säilyivät
`memory_checks`-historiassa. Nyt viimeisin osittainen havainto säilytetään
molemmissa, ja puuttuva todennin näkyy kentissä
`slurm_allocation_verification=UNAVAILABLE`,
`blocker=NO_LIVE_ALLOCATION_VERIFIER`. Tuntematonta headroomia ei täytetä luvulla.

## CSC:n dokumentoima suoritusympäristö

Ohjeet tarkistettiin CSC:n virallisesta `CSCfi/csc-user-guide`-lähteestä,
commitista **`bcb14ae942ccddea19684b4bfbb4fe0442203f0c`**. Julkisten
docs.csc.fi-sivujen haku estyi tämän pilviympäristön välityspalvelimessa;
käytettiin saman ohjeiston virallista GitHub-lähdettä.

| Lähde | Ohjeen havainto ja merkitys |
| --- | --- |
| [r-env](https://docs.csc.fi/apps/r-env/) ([kiinnitetty lähde](https://github.com/CSCfi/csc-user-guide/blob/bcb14ae942ccddea19684b4bfbb4fe0442203f0c/docs/apps/r-env.md)) | “It runs in an Apptainer container.” RStudion sisäinen komentokuori ei takaa hostin työkalujen näkyvyyttä. R:n komentorivikäyttö laskentasolmulla dokumentoidaan erikseen: `module load r-env`, `start-r`. Tämä ei todista moduulien näkyvyyttä nykyisen kontin sisältä. |
| [Shell](https://docs.csc.fi/computing/webinterface/shell/) ([lähde](https://github.com/CSCfi/csc-user-guide/blob/bcb14ae942ccddea19684b4bfbb4fe0442203f0c/docs/computing/webinterface/shell.md)) | Login node shell on tavallinen login-solmun Linux-komentokuori; Compute node shell on erillinen laskentasolmun komentokuori. Login-solmulla tehdään vain kevyet käynnistys-/tarkistustoimet. |
| [Olemassa olevan työn laskentasolmulle liittyminen](https://docs.csc.fi/computing/running/interactive-usage/#connecting-to-a-compute-node-of-a-running-job) ([lähde](https://github.com/CSCfi/csc-user-guide/blob/bcb14ae942ccddea19684b4bfbb4fe0442203f0c/docs/computing/running/interactive-usage.md)) | CSC dokumentoi `srun --jobid=<jobid> --overlap --pty bash`. Työhön luodaan uusi askel; uutta varausta ei haeta. Tämä on eri toimenpide kuin srunin yrittäminen jo avatun sinteractive-istunnon sisältä, josta samassa ohjeessa varoitetaan. |
| [Muistitarpeen arviointi](https://docs.csc.fi/support/faq/how-much-memory-my-job-needs/) ([lähde](https://github.com/CSCfi/csc-user-guide/blob/bcb14ae942ccddea19684b4bfbb4fe0442203f0c/docs/support/faq/how-much-memory-my-job-needs.md)) | “seff won't show data for running jobs that have been launched without srun”. `seff` ja `sacct MaxRSS` kuvaavat tilastoitua käyttöä, eivät tämänhetkistä vapaata job-muistia. `ReqMem` on pyydetty määrä. Näitä ei lisätä automaattiseksi korvikkeeksi. |
| [RStudio](https://docs.csc.fi/computing/webinterface/rstudio/) ja [CSC Service Desk](https://docs.csc.fi/support/contact/) | RStudio käyttää lomakkeessa valittuja resursseja; käyttöliittymän tieto ei yksin ole ohjelmallisen tarkistimen tuore todennuslähde. Ratkaisemattomat sovellus-/ympäristöesteet ohjataan CSC:n tukeen. |

Näissä tarkistetuissa ohjeissa ei dokumentoida RStudio-kontin sisäistä
autentikoitua API:a, jolla tämä tarkistin voisi korvata sekä Slurm-asiakkaan
että cgroup-rajat. Tämä on tarkistetun dokumentaation raja, ei väite, ettei
CSC:llä voisi olla muuta tuettua järjestelyä.

## Turvallinen seuraava tarkistus

Uusi komento suoritetaan **Roihu-CPU:n web-käyttöliittymän Login node
shellissä**, ei RStudion Terminalissa. Se pyytää nykyisen RUNNING RStudio-
istunnon job-ID:n My Interactive Sessions -kortilta, kloonaa täsmällisen
toteutuscommitin ja kutsuu `scripts/roihu_existing_job_memory_check.sh`.

Skripti tarkistaa koodipinnauksen ennen srunia ja liittyy vain annettuun
olemassa olevaan työhön CSC:n dokumentoimalla tavalla. Koko host-esitarkistus
on rajattu 60 sekuntiin (+5 s lopetusvara). Se suorittaa Python-käynnistimen
lipulla **`--memory-preflight-only`**. Lippu ei avaa hydrologista syötejuurta,
lue rastereita tai raportti-CSV:tä, etsi Rscriptiä, lataa R:ää tai aja koetinta.
Se ei asenna ohjelmia eikä luo uutta Slurm-varausta.

Esitarkistus vaatii live-varmennuksen, vaikka kernelin muistiraja olisi
luettavissa: oman job-ID:n, UID:n, RUNNING-tilan, yhden solmun, nykyisen
hostnamen ja todellisen `AllocTRES mem` -varauksen pitää täsmätä. Jos
`SLURM_MEM_PER_NODE` periytyy, sen pitää täsmätä; jos sitä ei periydy uuteen
askeleeseen, varaus saadaan silti samasta varmennetusta Slurm-vastauksesta.
Puuttuva muuttuja ei siis ole uusi valtuutuskanava. Ilman live-vastausta
tarkistus pysähtyy edelleen.

Varauksen todentamisen jälkeen muistin arviointi säilyy erillisenä:
luettavat kernelin rajat ja käyttö sekä `MemAvailable`; tarvittaessa entinen
konservatiivinen koko solmun käyttöön perustuva alaraja, 2 GiB turvavara ja
vähintään 3 GiB headroom. Varausta ei tulkita vapaaksi muistiksi. Host-
konteksti ei takaa työkalujen tai muistinäytön saatavuutta: ne testataan,
ja kuormitettu solmu voi edelleen estää ajon.

`TECHNICAL_STATUS=MEMORY_PREFLIGHT_COMPLETE` tarkoittaa **vain** live-varauksen
ja muistin esitarkistuksen valmistumista. R/terra, järviaineistot ja
historiallinen provenienssi pysyvät `NOT_CHECKED`; järvikoetinta ei käynnistetä
automaattisesti. `REPORT=.../review_bundle.tar.gz` sisältää tämän tarkistuksen
havaintotiedot ja yhteenvedon. Jos askel ei käynnisty tai Python puuttuu,
raporttipakettia ei voida luvata. Virheilmoitus säilyy komentokuoressa.

Jos myös host-kontekstissa scontrol tai muistinäyttö puuttuu, **pysähdy**.
Suositeltu jatko on CSC Service Desk: pyydetään tuettu hostin Slurm-asiakas/
muistikirjanpito tähän RStudio-työhön tai CSC:n tuettu natiivi laskentasolmun
komentokuori. Tukipyyntöön voi liittää jo syntyneen raportin ja sovellus-
istunnon `output.log`-tiedoston CSC:n ohjeen mukaan. Viestiä ei lähetetä
automaattisesti eikä salaisuuksia kopioida raporttiin.

Nykyinen korjaus on testattu synteettisesti. Hostin R-konttiwrapperin ajoa
nykyisillä R-aliprosessin rajoilla ei ole mitattu Roihussa; siksi tässä ei
anneta uutta täyden järvitutkimuksen käynnistystä. Laskenta-/ikkuna-/aikarajoja
ei väljennetä tämän ympäristöesteen ratkaisemiseksi.

**MODERATE=REVIEW_REQUIRED; NATIONAL=LOCKED; continuation_authorized=false.**
