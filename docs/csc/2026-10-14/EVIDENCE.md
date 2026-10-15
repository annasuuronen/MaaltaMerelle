# CSC-ajojen näyttö ja puuttuvat tulosraportit

## Näytön tila 15.10.2026

Käyttäjän mukaan kaikki kahdeksan arkistoitua skriptiä kehitettiin ja niitä
käytettiin oikeissa CSC Roihu -testeissä 14.10.2026. Tämä ilmoitus säilytetään
kehityshistoriana. Skriptit eivät ole uusi testaamaton toteutusehdotus.

Toimitettu aineisto sisältää kuitenkin vain skriptit: ei varsinaisia CSC
Slurm-lokeja, schedulerin kirjanpitoa, QA-CSV-tiedostoja, PASS-tiedostoja tai
mittaamalla tuotettua rasterien tiivistemanifestia. Niitä ei löytynyt myöskään
tarkistetusta lähdecheckoutista tai paikallisista liitteistä. `/scratch`- ja
`/projappl`-CSC-hakemistoihin ei ole tässä tarkistuksessa pääsyä. Työtilan
`/workspace/hydro-env`-LOCAL_TEST-tulokset ovat eri ympäristöstä ja ajosta;
niitä ei käytetä 14.10.2026 CSC-ajojen todistamiseen.

**Vahvistettuja yksittäisiä CSC PASS-tuloksia: ei vielä yhtään.** Tämä tarkoittaa
puuttuvaa ajonäyttöä, ei väitettä, ettei ajoja olisi tehty tai etteivät ne olisi
onnistuneet. Myöskään yksittäisten ajojen epäonnistumisia tai ajoaikoja ei
johdeta pelkästään skriptitekstistä. V1:n koodivirhe on todettu vertailulla;
sen todellinen CSC-suoritus ja päättymistapa edellyttävät omaa lokia.

Käyttäjä täsmensi 15.10.2026, että alkuperäiset skriptit ovat suoraan
`/scratch/project_2004707/pienvedet/`-hakemistossa ja että hän aikoo järjestää ne
hakemistoon `/scratch/project_2004707/pienvedet/csc_scripts_20261014/`.
Skriptien tuloshakemistojen tai yksittäisten tiedostojen olemassaoloa hän ei ole
vielä tarkistanut Roihulta. Alla oleva luettelo on siis **odotettujen polkujen
luettelo**, ei toimitettujen tai löydettyjen tulosten inventaario.
Arkistointi tehdään nyt odottamatta lokien saapumista; Roihun todelliset
hakemistot, aiemmat jobit ja QA tarkistetaan erikseen ennen uusia testejä.

## Tarvittavat olemassa olevat pienet tiedostot

Alla `H` tarkoittaa hakemistoa
`/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02`.
`<jobid>` täytetään vasta toimitetun job-ID-tiedoston perusteella.

| Ajo / menettely | Pyydettävät tiedostot suhteessa `H`:hon | Mitä niistä tarkistetaan |
| --- | --- | --- |
| Alkuperäinen neljän alueen ajo | `logs/hydro_2264131_*.log` sekä olemassa oleva alkuperäinen ajomanifesti ja scheduler-raportti | Mihin vaiheeseen kukin alue pääsi, virheet ja lähde-/syöteversiot. Job-ID on skriptiin kirjattu viite, ei tässä todennettu ajo. |
| D8-diagnostiikka | `d8_diagnostic/probe.jobid`, `probe_<jobid>.log` | Todellinen job-ID, Whitebox-versio ja geometria-QA; viite `2285854` tarkistetaan raportista. |
| Kolmen tilan D8-vertailu | `d8_compare_20261014/compare.jobid`, `compare_<jobid>_{0,1,2}.log`, `{shared_1,shared_4,local_1}/result.txt` | Jokaisen tilan toteutunut tulos, timeout/exit ja metatiedot; `shared_4`:n onnistumista ei oleteta. |
| D8-arvo-QA | `d8_value_qa_20261014/qa.jobid`, `qa_<jobid>.log`, `results/qa.csv` | 36 miljoonaa solua, arvoerot, virhekoodit ja myös raportoidut maskierot. |
| MODERATE v1 (korvattu) ja v2 | Kummastakin `moderate_resume_20261014{,_v2}/resume.jobid`, `resume.log`, `validated_d8_report.csv` sekä mahdollinen `CSC_MODERATE_RESUME_PASS.txt` | Erottuvat yritykset ja korjaus, muunnoksen QA, jatkoajon vaihemerkit, todellinen valmistumistila. Tiedoston puuttuminen kirjataan, sitä ei luoda jälkikäteen. |
| V2:n pienet tulosyhteenvedot | `moderate_resume_20261014_v2/run/02_baseline/02D_lake_depression_component_summary.csv`, `02D_spill_group_diagnostic.csv`, `02D8_final_spill_evidence.csv`, `02E_water_connected_QA.csv`, `02F_water_connected_route_QA.csv`, `02F_water_connected_route_summary.csv` | 02D.4-poikkeamat, ehdokkaiden säilyminen, 02E-raporttiin sisältyvä maski-QA ja reittien päätepisteluokat. |
| MODERATE 02D.4-auditointi | `moderate_02d4_audit_20261014/job_id.txt`, `audit_<jobid>.log`, `summary.csv`, `lake_audit.csv` | Pintojen eroista riippumattomasti lasketut soluluvut, järvikohtaiset poikkeamat, laskut ja NA-erot. |
| LOW/MODERATE storage-provenienssi | `storage_provenance_20261014/jobid`, `audit_<jobid>.log`, `comparisons.csv` ja olemassa olevat `*_gdalinfo.txt` | Rasteriparien poikkeamat sekä lokiin tallennetut koot, aikaleimat, SHA256:t ja työkaluversion tiedot. |
| MODERATE fill-uusintakoe | `moderate_fill_recheck_20261014/slurm_jobid`, `job_<jobid>.log`, `summary.csv`, `lake_summary.csv` | Toteutunut Whitebox-komento/exit, tuoreen ja vanhan pinnan erot, järvikohtaiset nostot, maskit ja mahdollinen aleneminen. |

Lisäksi tarvitaan jo tallennetut `sacct`-tiedot: JobID (myös array-tehtävät ja
batch-step), State, ExitCode, Start, End, Elapsed ja MaxRSS. Tulos sidotaan
job-ID:hen, lähdecommittiin, syötteiden tunnisteisiin ja työkaluversion tietoihin;
pelkkä yksittäinen PASS-rivi ilman ajokontekstia ei riitä.

Suuria rastereita ei siirretä GitHubiin. Toimita niiden olemassa olevat
SHA256-/koko-/polkumanifestit ja yllä olevat pienet raportit. `artifacts.tsv`:n
tyhjiä tiivisteitä täydennetään vain todellisesta mittausnäytöstä. Raporttien
hankkiminen ja valmiiden tiedostojen tiivisteiden lukeminen eivät edellytä
hydrologisten laskentojen uusimista. Tässä tehtävässä ei lähetetä uusia jobeja.

## PASS-merkintöjen tulkintarajat

- D8-koematriisin `PASS_METADATA_ONLY` vaatii luettavan, oikean kokoisen ja
  geometrialtaan täsmäävän rasterin. Se ei tarkista kaikkia D8-arvoja.
- `D8_VALUE_QA_PASS` vaatii kahden pointerin arvojen yhtäläisyyden ja sallitut
  koodit `0,1,2,4,8,16,32,64,128`. `input_vs_pointer_na_mask_mismatches`
  kirjoitetaan CSV:hen, mutta kyseinen skripti ei vaadi sitä nollaksi.
  Markerista ei siksi yksin voi päätellä lähdepinnan ja pointerin maskien yhtäläisyyttä.
- V2:n `RESUME_D8_FLT8S_VALUE_QA_PASS` vaatii myös molempien maskivertailujen
  nollatuloksen. `CSC_MODERATE_RESUME_PASS.txt` rajaa tuloksensa suoritukseen ja
  QA-merkintöihin (`not_scientific_equivalence`). Sen sisällön toteutuminen
  tarkistetaan CSV:stä ja täydestä ajolokista, ei skriptin tulostustekstistä.
- `AUDIT_COMPLETED_READ_ONLY` ei vaadi 02D.4-solulukueroja, laskuja tai
  poikkeusjärvien lukumäärää nollaksi. Lukuarvot on arvioitava erikseen.
- `AUDIT_PASS_READ_ONLY` tarkoittaa storage-provenienssiraportin valmistumista;
  se ei vaadi pintaparien identtisyyttä tai hydrologista hyväksyntää.
- `FRESH_FILL_COMPARISON_QA_PASS` vaatii täsmäävän geometrian ja NA-maskit sekä
  ettei pinta alene. Se ei vaadi tuoreen ja vanhan WATER_STORAGE-pinnan
  yhtäläisyyttä, eikä vahvista tieteellistä vastaavuutta GitHub-referenssiin.
- Joidenkin precheckien ilmaus ”unchanged inputs” on vahvempi kuin niiden
  todellinen tarkistus: tiedoston olemassaolo sekä lähdecommitin/binäärin
  tarkistus eivät yksin todista syöterasterien muuttumattomuutta.

## Tiivisteiden erottelu

| Kohde | Liitteisiin kirjattu SHA256 | Näytön tila |
| --- | --- | --- |
| D8-kokeet `shared_1/d8_pointer.tif` ja `local_1/d8_pointer.tif` | `816f6c1b80a8e1a03394bbc13927de1a1d7a053193357880c7c23b4b6d763281` | Molempien resume-skriptien **odotettu** tiiviste. CSC-rastereita tai mitattua tiivistelokia ei ole toimitettu. |
| `/projappl/project_2004707/whitebox/WBT/whitebox_tools` | `96bb47a9d1f0fe8a3cb46df524242c990eab9bc2ae1930e540e09328331172e4` | Storage- ja fill-skriptien **odotettu** binääritiiviste. CSC-binäärin toteutunutta tiivistettä ei ole tässä mitattu. |
| Kahdeksan arkistoitua `.sh`-tiedostoa | [SHA256SUMS](SHA256SUMS) | Tässä arkistoinnissa liitteistä mitatut ja kopioihin verratut todelliset tiivisteet. |

## Seuraava hyväksymisvaihe

Kun olemassa olevat raportit saadaan, ne voidaan liittää pieninä teksti-/CSV-
tiedostoina alkuperäisine tiivisteineen ja täydentää tuloskohtainen näyttötaulukko.
Ennen sitä 02D.4-/storage-poikkeaman syytä, kokeiden vastaavuutta tai CSC-
validoinnin valmistumista ei julisteta ratkaistuksi. Lopullinen D8,
virtauskertymä ja NATIONAL pysyvät tämän arkistointityön ulkopuolella.
