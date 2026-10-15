# CSC-raporttien esivalmistelu ja myöhempi käsittely

## Vaihe 1: paikallinen sopimuksen tarkistus

Tämä toteutus tarkistaa paikallisia JSON-manifesteja ja raporttien sopimuksia.
Se ei muodosta CSC-yhteyttä, käytä CSC-tunnuksia, käynnistä Slurm-työtä,
kerää CSC-tiedostoja eikä suorita manifestin tai raportin sisältämiä komentoja.
CSC-työmäärä on tässä vaiheessa **0 työtä, 0 lähetystä ja 0 uusintaa**.
GitHubin kevyt PR-tarkistus on eri asia kuin CSC-laskenta.

Työ on erotettu hydrologian paikallisista muutoksista haaraan
`codex/csc-preflight-phase-1` ja työhakemistoon
`/workspace/MaaltaMerelle-csc-preflight-phase-1`. Sen lähtökohta on
`baseline-no-structures`-haaran commit
`feee323ca8d236ea004f7730b1d1d985ca9c4bf1`. Alkuperäisen työhakemiston
neljä keskeneräistä 02D.4-muutosta (kaksi R-tiedostoa, testi ja ohje)
eivät kuulu tähän muutokseen. `main`-haaraa,
EIFFEL-projektia, tuotannon `R/`-tiedostoja ja vanhaa `tests/`-hakemistoa
ei muuteta. CSC-automaation testit sijaitsevat `automation/csc/tests/`-hakemistossa.

Historiallisten 14.10.2026 CSC-ajojen ilmoitettu lähdekoodi on commit
`4bbf22bb39181c8a4c27ebc3e2769766043115b8`. Tämä on raporttien
`commit_sha`, jos näyttö koskee juuri näitä ajoja, ei uuden automaation
lähtöcommit eikä sen tuleva HEAD. Manifestin ja raportin `commit_sha`-arvojen
on vastattava toisiaan. Tarkistin ei päättele todellisen ajon lähdecommittia
arkiston HEADista. Synteettinen aineisto voi käyttää lähtöcommittia, mutta
se ei ole näyttö historiallisesta CSC-ajosta. Näitä identiteettejä ei saa
korvata toisillaan tai liikkuvalla `HEAD`-arvolla.

`CONTRACT_VALID` tarkoittaa vain tarkastetun tietosopimuksen kelvollisuutta.
Se ei ole ajolupa, hyväksyntä, raportin aitoustodistus eikä hydrologinen PASS.
`DRAFT` ja `READY_FOR_REVIEW` kuvaavat tarkasteluvalmiutta; kumpikaan ei
anna suoritus- tai siirto-oikeutta. Oikea hyväksyntä annetaan erikseen tämän
työkalun ulkopuolella, konkreettiseen pakettiin ja rajattuun toimintaan sidottuna.

## Paikalliset tiedostot ja käyttö

Ohjelma, skeemat, pienet esimerkit ja testit ovat `automation/csc/`-hakemistossa.
Skeemat ja komentorivin ohje ovat kenttien tarkka määrittely. Tämä ohje kuvaa
niiden käyttötarkoituksen ja turvallisuusrajat.

Manifestin ainoa sallittu toiminto on `READ_EXISTING_CSC_REPORTS`.
Se kuvaa olemassa olevien pienten raporttien myöhempää, erikseen hyväksyttävää
lukemista. Se ei kuvaa uutta D8-, FillDepressions-, jatko- tai NATIONAL-ajoa.
Skeema ei tarjoa yleistä komentoa, mielivaltaisia ympäristömuuttujia,
automaattista uudelleenyritystä tai CSC-tunnuksia.

Vaihe 1 on tietosopimuksen tarkistin. Se tarkistaa JSONin rakenteen,
viitteiden keskinäisen johdonmukaisuuden ja pyydettäessä paikallisten
lähdetiedostojen tavut. Se ei jäsennä Slurm-lokin tai QA-CSV:n sisältöä
eikä varmista raportissa väitettyjä scheduler-tiloja, testituloksia tai
diagnostisia lukumääriä niiden alkuperäisistä lähdeteksteistä.

Tarkistuksessa erotetaan ainakin:

| Tieto | Merkitys |
| --- | --- |
| Repositorio ja haara | Vain `annasuuronen/MaaltaMerelle`, ID `1407101587`, `baseline-no-structures`. |
| Lähdecommit | Raporttien tuottamiseen käytetyn hydrologiakoodin tarkka identiteetti. |
| Manifesti ja tiivisteet | Tarkasteltavan paketin sekä nimettyjen tiedostojen täsmälliset tavut. |
| Raporttipolut ja kokorajat | Yksilöidyt pienet raportit hyväksytyn hakemistorajan sisällä. |
| Resurssirajat | Tässä vaiheessa kaikki CSC-töiden ja uusintojen määrät ovat nollia. |
| Valmiustila | Luonnoksen tila; ei hyväksyntä. |
| Raportin väitteet | Lähde, työ-ID, havainto, QA ja epävarmuudet erillisinä tietoina. |

JSONin kaksoisavaimet hylätään: tiedoston kahdesta samannimisestä kentästä
ei valita hiljaisesti viimeistä. Virheelliset tiivisteet, väärät lukitut
identiteetit, tuntemattomat tai ristiriitaiset kentät ja ohitusyritykset
eivät muutu hyväksyttäviksi valmiustilaa vaihtamalla.

Polkuja käsitellään tietoina. Absoluuttiset siirtokohteet, hakemistorajan
ylittäminen, `..`-osat, komentotulkille merkitykselliset polut ja
symbolisten linkkien kautta tapahtuva rajan kierto eivät kuulu sopimukseen.
Pelkkä `.csv`- tai `.log`-pääte ei riitä: siirrettävän tiedoston on oltava
nimenomaisella sallittujen raporttien listalla ja kokorajojen sisällä.
Rastereita, GeoPackageja, tunnustiedostoja, ympäristövedoksia tai kokonaisia
CSC-hakemistoja ei siirretä tällä toiminnolla GitHubiin.

SHA256-tiiviste sitoo tarkastelun tavuihin ja auttaa tunnistamaan muutokset
sekä siirtovirheet. Samassa paketissa toimitettu tiiviste ei itsessään
todista tiedoston alkuperää tai väitteiden totuutta. Paikallinen tarkistus
ei todista CSC-koneen tämänhetkistä tilaa.

Semanttinen `fingerprint` lasketaan RFC 8785 -kanonisoidusta JSONista.
Siihen sisältyvät repositorio, haara, lähdecommit, sopimus- ja parametriversiot,
ajotyyppi, sallittu parseritunniste, parametrit, nollaresurssirajat sekä
aineistot tunnisteineen, tiivisteineen, tiivisteiden alkuperineen ja
vaadittuine läsnäoloineen. Aineistot järjestetään tunnisteen mukaan.
Pyyntö-UUID, aikaleima, luonnostila, hyväksyntäviite ja fyysinen sijainti
eivät muuta tätä aineiston ja parametrien tunnistetta.

Erillinen `request_digest` sitoo koko konkreettisen manifestin myös polkuihin,
UUID:hen, aikaan ja tilaan; vain hyväksyntäviite jätetään siitä pois.
Kumpikaan tiiviste ei todenna hyväksyjää eikä varaa tai deduplikoi CSC-työtä.
Vaiheen 1 tarkistin ei ylläpidä ulkoista ajorekisteriä.

JSON-dokumentin kokoraja on 1 MiB. Manifestin pienraporttirajat voivat olla
enintään 5 MiB/tiedosto ja 25 MiB/paketti. Tarkistin rajoittaa myös JSONin
syvyyttä ja solmumäärää, hylkää ei-äärelliset numerot ja käyttää vain
paikallisia skeemaviitteitä. Nämä ovat luku- ja tarkistusrajoja,
eivät lupia siirtää tiedostoja tai käynnistää laskentaa.

### Komentorivi ja kevyet testit

Käytä Python 3.12:ta Linux x86_64 -alustalla ja erillistä virtuaaliympäristöä.
Nykyinen `rpds-py`-wheel ja sen lukittu tiiviste koskevat tätä alustaa;
muita Python-versioita tai käyttöjärjestelmiä ei ole tässä lukossa luvattu.
Riippuvuudet on
lukittu `requirements-preflight.lock`-tiedostossa versioihin ja ladattujen
wheel-pakettien SHA256-tiivisteisiin. Asennus ei salli lähdepaketteja tai
tiivisteettömiä riippuvuuksia:

```sh
python3.12 -I -B -m venv /tmp/maaltamerelle-csc-preflight-venv
/tmp/maaltamerelle-csc-preflight-venv/bin/python -I -B -m pip --isolated install --require-hashes --only-binary=:all: --no-input --disable-pip-version-check --retries 0 --timeout 30 --requirement automation/csc/requirements-preflight.lock
/tmp/maaltamerelle-csc-preflight-venv/bin/python -I -B automation/csc/validate_manifest.py --schemas-only
/tmp/maaltamerelle-csc-preflight-venv/bin/python -I -B automation/csc/tests/run_tests.py
```

Manifesteja ja paikallisia raportteja tarkistetaan erikseen:

```sh
/tmp/maaltamerelle-csc-preflight-venv/bin/python -I -B automation/csc/validate_manifest.py --kind manifest path/to/manifest.json
/tmp/maaltamerelle-csc-preflight-venv/bin/python -I -B automation/csc/validate_manifest.py --kind report path/to/report.json --manifest path/to/manifest.json
/tmp/maaltamerelle-csc-preflight-venv/bin/python -I -B automation/csc/validate_manifest.py --kind report path/to/report.json --manifest path/to/manifest.json --bundle-root /path/to/already-transferred-reports
```

`--bundle-root` osoittaa jo paikallisesti olevan raporttipaketin hakemistoon;
se ei muodosta verkkoyhteyttä tai kopioi tiedostoja CSC:ltä. Suhteelliset
raporttipolut ratkaistaan vain tämän hakemiston sisällä, ja luettujen pienten
tiedostojen koot ja tiivisteet tarkistetaan. Ilman pakettia lähteiden omat
väitteet eivät muutu itse mitatuksi näytöksi. Raportissa lueteltuja rastereita
ei avata tämän avulla.

Paketissa fyysinen rakenne on esimerkiksi
`<bundle-root>/CSC_HYDRO_4BBF22B/reports/qa.csv`, kun manifestin
`root_id` on `CSC_HYDRO_4BBF22B` ja `relative_path` on `reports/qa.csv`.
Juuren tunniste ei itsessään todista CSC-hakemiston olemassaoloa.

Raportin tarkistustulos kertoo `verified_source_count`-kentässä todella
luettujen paikallisten lähdetiedostojen määrän. `content_verification` on
`NOT_CHECKED`, jos yhtään saatavilla olevaa lähdettä ei luettu;
`VERIFIED_AVAILABLE_REPORTS`, jos vain saatavilla oleva osajoukko kaikista
raportin lähteistä tarkistettiin; ja `VERIFIED_LOCAL_REPORTS`, jos kaikki
raportin lähteet tarkistettiin. Pelkkä `--bundle-root`-valinta ei tuota
vahvistettua tilaa. Nämä tilat kuvaavat tavujen, kokojen ja tiivisteiden
tarkistusta, eivät lokin sisällön tulkintaa tai väitetyn QA:n vahvistamista.

CLI kirjoittaa tarkistuksen tuloksen lokiin; se ei julkaise raportteja,
luo GitHub-artifactia tai kommentoi PR:ää. Synteettiset esimerkit ovat
testiaineistoa, eivät CSC:n todellisia loki- tai QA-havaintoja.
Puuttuva vaadittu tieto tuottaa hylkäyksen tai `DRAFT_INCOMPLETE`-tilan,
ei `CONTRACT_VALID`-tulosta. Nollan testin discovery palauttaa virheen;
sitä voi tarkistaa komennon `run_tests.py --pattern no_tests_selected_*.py`
odotetulla epäonnistumisella.

## GitHub Actions ja vanhojen työnkulkujen yhteentörmäykset

Uusi kevyt esivalmistelutarkistus kohdistuu PR:iin, jonka kohdehaara on
`baseline-no-structures`. Siinä ei ole `paths`- tai `paths-ignore`-suodatinta:
vakioniminen tarkistus antaa tuloksen jokaiselle tällaiselle PR:lle myös silloin,
kun muutos ei koske automaatiota. Näin sen voi asettaa haarasuojauksessa
pakolliseksi ilman polkusuodatuksen aiheuttamaa odottamaan jäävää tarkistusta.
Työnkulku ei itsessään muuta haarasuojausta tai GitHubin oikeuksia.

Tarkistuksen aikaraja on viisi minuuttia. Samalle PR:lle saapuva uusi versio
peruuttaa vain saman PR:n aiemman esivalmistelutarkistuksen; muiden PR:ien
tarkistuksia tai hydrologiatöitä ei peruuteta. Käyttöoikeus on
`contents: read`, checkout kohdistuu tarkastettavan PR-version SHA:han ja
`persist-credentials` on `false`. `actions/checkout` on lukittu julkaisuun
v4.2.2 liittyvään tarkistettuun commitiin
`11bd71901bbe5b1630ceea73d27597364c9af683`.
Työnkulku ei sisällä CSC-tunnuksia,
CSC-yhteyksiä, työn lähetystä, automaattisia uusintoja tai dispatch-kutsuja.
Se ei käynnisty pushilla tai `workflow_dispatch`-pyynnöllä.
Testien tulosteet näkyvät Actions-lokissa myös testin epäonnistuessa;
erillistä raportin julkaisu- tai artifact-upload-askelta ei ole.

### Ensimmäinen PR ja pakollinen tarkistus

Paikallinen toteutus ei käynnistä Actionsia. Ensimmäinen GitHub-kokeilu
edellyttää käyttäjän erillistä hyväksyntää pushille ja PR:n avaamiselle.
Silloin haara julkaistaan vain kehityshaaraan ja PR kohdistetaan haaraan
`baseline-no-structures`. Uusi `pull_request`-työnkulku on mukana PR:n
yhdistämisversiossa, jossa GitHub arvioi tämän tapahtuman työnkulun;
uuden työnkulun testaaminen ei vaadi sen siirtämistä `main`-haaraan.
Tämä ei perustu manuaalisen `workflow_dispatch`-toiminnon saatavuuteen
oletushaarassa. `pull_request_target`-tapahtumaa ei käytetä.

Ennen ensimmäistä PR:ää tarkistetaan GitHubin Actions-asetukset ja mahdollinen
ensikertalaisen tai ulkopuolisen tekijän työnkulun hyväksyntävaatimus.
Yhdistämisristiriita, estetty Actions tai puuttuva palvelun hyväksyntä voi
estää ajon. Tällöin este selvitetään eikä vaihdeta etuoikeutettuun triggeriin.
PR-koodi on epäluotettua myös kevyessä tarkistuksessa: jobilla ei saa olla
CSC-tunnuksia, salaisuuksia tai kirjoitusoikeuksia.

Vakioniminen `CSC preflight / validate` rekisteröidään pakolliseksi
tarkistukseksi vasta sen ensimmäisen oikean PR-ajon ja tarkistusnimen
varmistamisen jälkeen. Nykyinen toteutus ei muuta sääntöjä. Työnkulussa
ei ole polkusuodatinta, jobin `if`-ohitusta tai draft-PR:n ohittavaa ehtoa;
polkumuutos ei siksi jätä pakollista tarkistusta odottamaan. Mahdolliset
merge queue -vaatimukset on arvioitava erikseen ennen käyttöönottoa, koska
tämä ensimmäinen versio tukee vain `pull_request`-tapahtumaa.

Alla on lähtöcommitin 15 vanhan työnkulun yhteentörmäysmatriisi. Merkintä
”oma tiedosto” tarkoittaa kyseisen olemassa olevan työnkulun tiedostoa,
ei uutta esivalmistelutyönkulkua. Yhdelläkään näistä ei ole PR-triggeriä.

| Vanha työnkulku | Push-polkurajaus / muu automaattinen käynnistys | Tämän muutoksen polkuosuma |
| --- | --- | --- |
| `audit-02d8-schema.yml` | Oma tiedosto | Ei |
| `audit-natural-evidence.yml` | Oma tiedosto | Ei |
| `audit-partial-gradient.yml` | Oma tiedosto | Ei |
| `audit-r-source-graph.yml` | `R/**`, oma tiedosto | Ei |
| `audit-r-syntax.yml` | `R/**`, `tests/**`, oma tiedosto | Ei |
| `audit-validation-fixtures.yml` | Oma tiedosto | Ei |
| `audit-workflow-safety.yml` | Oma tiedosto | Ei |
| `continue-validation-gradient.yml` | `R/**`, `tests/**`, oma tiedosto, `test-natural-reference.yml` | Ei |
| `retry-hydrology-infra.yml` | Neljän nimetyn hydrologiatyön valmistumisen `workflow_run` | Ei tämän muutoksen käynnistämää hydrologiatyötä |
| `test-low-transfer.yml` | Nimetyt tuotannon R- ja testitiedostot, oma tiedosto | Ei |
| `test-moderate-transfer.yml` | Nimetyt tuotannon R- ja testitiedostot, oma tiedosto | Ei |
| `test-natural-reference.yml` | `R/**`, `tests/**`, oma tiedosto | Ei |
| `test-portability-matrix.yml` | Nimetyt tuotannon R- ja testitiedostot, oma tiedosto | Ei |
| `test-sulku-11.yml` | `R/**`, `tests/**`, oma tiedosto | Ei |
| `verify-low-coastline.yml` | Oma tiedosto | Ei |

Vanhoja 15 työnkulkua ei muokata eikä niiden triggereitä heikennetä.
`[skip ci]`-ohitusta ei käytetä. Muutoksen polut ovat `automation/csc/**`,
`docs/csc/AUTOMATION.md` ja uusi esivalmistelutyönkulku. Myöhempi yhdistäminen
`baseline-no-structures`-haaraan ei näillä poluilla osu vanhoihin push-suodattimiin.
Testien sijoittaminen `automation/csc/tests/`-hakemistoon säilyttää tämän eron;
niiden siirtäminen juuren `tests/`-hakemistoon muuttaisi johtopäätöksen.
Muu samanaikainen muutos, erikseen käynnistetty vanha työnkulku tai tuleva
triggerimuutos vaatii uuden arvion.

## CSC-näytön tulkinta

[Vuoden 2026-10-14 arkisto](2026-10-14/README.md) ja sen kahdeksan skriptiä
säilyvät muuttumattomina. Arkistoskriptien `check`- ja `status`-toiminnot eivät
lähetä työtä, mutta esimerkiksi D8-tarkistus voi lukea suuria rastereita niiden
tiivisteitä laskiessaan. Niitä ei suoriteta automaattisesti esivalmisteluna.
Vanhat lähdecommitin lukitukset ja historiallisiin töihin sidotut polut eivät
ole uuden yleiskäyttöisen suoritusrajapinnan asetuksia.

Raportin on erotettava käyttäjän ilmoittama suoritus, toimitetusta tiedostosta
tarkistettu havainto, Slurm-tila, prosessin paluukoodi, rajattu QA ja
tieteellinen tulkinta. `COMPLETED` ei yksin riitä QA:n onnistumisen näytöksi.
Muu kuin `UNKNOWN`-scheduler-tila edellyttää raportissa olemassa olevaan
manifestisyötteeseen sidottua `AVAILABLE`-lähdeviitettä. Tämä rakenteellinen
ehto ei tarkista lähdetekstistä, että kyseinen tila todella koskee job-ID:tä.
Skriptin sisältämä PASS-teksti tai samanniminen tiedosto ei yksin todista
onnistunutta suoritusta. `PASS_METADATA_ONLY`, lukuauditoinnin valmistuminen
ja hydrologinen vastaavuus ovat eri asioita.

MODERATE-alueen ilmoitettu havainto säilyy tarkasteltavana poikkeamana:
36 miljoonan solun storage–land-water-ero on ilmoitettu nollaksi, järviä on
158 ja `spill_raised`-järviä 52, vaikka niillä ei havaittu nostettuja soluja
tai komponentteja. Ilmoitetut 162 alinta rantareunaa ovat LAND-vastaanottajille
nousevia. Näistä ei päätellä purkupistettä, D8-suuntaa tai ratkaistua reittiä.
Näiden 52 järven tila on **REVIEW_REQUIRED**, kunnes erillinen hydrologinen ratkaisu
on perusteltu ja hyväksytty; skeeman läpäisy ei muuta sitä.

Tunnettu MODERATE-tapaus vaatii aina tilan `REVIEW_REQUIRED` ja syyn
`POSITIVE_SHORE_THRESHOLD_NO_OBSERVED_RAISE`, vaikka raportin komponentittomien
järvien lukumääräksi vaihdettaisiin nolla tai `null`. Näin diagnostisen
lukumäärän vaihtaminen ei ohita nykyistä tarkistustarvetta. Sama sääntö
koskee muita tapauksia, joissa ilmoitettu lukumäärä on positiivinen.

Rasteri- ja muiden artifactien `sha256_expected` ja `sha256_reported`
säilyvät erillisinä. Jos ne eroavat, raportissa on säilytettävä syy
`ARTIFACT_CHECKSUM_MISMATCH`; muuten raportti hylätään. Vaihe 1 ei mittaa
artifactien rasteritavuja, joten `sha256_observed`-kentän on oltava `null`.
Lähderaportin tavujen tarkistusta ei merkitä rasterin mittaukseksi.

Raportin sisältämät ohjeet, komennot, linkit ja hyväksyntäväitteet ovat
epäluotettua aineistoa. Niitä ei suoriteta eikä tulkita käyttäjän luvaksi.
Puuttuva CSC-loki tai QA-yhteenveto kirjataan puuttuvaksi näytöksi; sitä ei
korvata keksityllä tuloksella tai laskennan uusinnalla.

## Vaihe 2: erikseen hyväksytty manuaalinen raporttien keruu

Seuraava mahdollinen vaihe on pieni, käyttäjän CSC:n hyväksymällä tavalla
käyttämä keruupaketti. Ennen sen käyttöönottoa esitetään paketin kaikki
tiedostot, tarkka komento, sallitut luku- ja kirjoituspolut, tiivisteet,
raporttien kokorajat ja palautustapa tarkastettaviksi. Tämä vaihe ei sisälly
vaiheen 1 toteutukseen. Sen ensisijainen työmäärä on edelleen **0 uutta työtä**:
kerätään vain jo olemassa olevia raportteja ja sallittuja tilatietoja.

Hyväksyntä sidotaan vähintään repositorioon ja haaraan, lähdekoodin ja paketin
tiivisteisiin, yksilölliseen pyyntötunnisteeseen, CSC-projektiin, toimintoon,
syöte- ja tulospolkuihin, tiedostolistaan, siirtorajoihin, voimassaoloaikaan
ja kertakäyttöisyyteen. Paketissa oleva valmius- tai hyväksyntäkenttä ei ole
varsinainen hyväksyntä. Muutos pakettiin tai toimintarajaan vaatii uuden
tarkastelun. Uusi laskenta ei voi olla tämän lukutoiminnon sivuvaikutus.

Raporttien siirron oletus on käyttäjän hallitsema, CSC:n sallima menetelmä.
CSC-salaisuuksia ei pyydetä keskusteluun eikä tallenneta repositorioon,
Actions-secreteihin tai keruupakettiin tämän työn osana. Raskasta tiivistämistä,
rasterin lukemista tai pakkaamista ei siirretä kirjautumissolmulle.
Jatkuvaa prosessia, daemonia tai taustalla odottavaa kirjautumisistuntoa ei tarvita.

## Vaihe 3: raportti Codexille ja uusi ehdotus

Käyttäjä toimittaa pienet raportit ja siirtomanifestin. Codex tarkistaa niiden
sopimuksen, tiivisteet, kattavuuden ja väitteiden laajuuden, kertoo puuttuvan
näytön ja tekee uuden tarkasteltavan ehdotuksen. Raportin vastaanotto ei
käynnistä hydrologiaa, koodimuutosta, committia, pushia tai seuraavaa CSC-työtä.
Ei valita perusteetonta purkupistettä, keksitä D8-suuntaa, lisätä rakenteita
baseline-reititykseen tai avata NATIONAL-lukitusta.

Mahdollinen CSC:n hyväksymä API tai palvelutunnus on tätä myöhempi erillinen
vaihe. FirecRESTin saatavuutta tai robottitunnuksen sallittavuutta ei oleteta.
Ensin selvitetään CSC:n kanssa tuettu palvelu, tunnistautuminen, valtuudet,
salaisuuksien säilytys ja vanheneminen, lokitus, projektin laskutusrajat,
kirjautumissolmun käyttö sekä sallitut siirto- ja verkkoyhteydet.

## Keskeytys, toisto ja palautuminen

Sama pyyntötunniste ja samat tiivisteet tarkoittavat samaa käsiteltävää
raporttipakettia. Ne eivät tarkoita uutta ajoa. Sama tunniste eri sisällöllä
on ristiriita, joka tutkitaan. Vaiheen 1 tarkistin ei ylläpidä CSC:n
suorituskirjanpitoa tai takaa hajautettua täsmälleen kerran -suoritusta.

Katkenneessa siirrossa jatketaan vain puuttuvien tai tiivisteeltään virheellisten
raporttien siirtoa. Onnistuneet tiedostot säilytetään. Puuttuva raportti ei
anna lupaa suorittaa alkuperäistä laskentaa uudelleen. Jos myöhempi
lähetysrajapinta joskus otetaan käyttöön, epäselvä työn vastaanottokuittaus
selvitetään pyyntötunnisteen ja Slurm-tilan avulla ennen mahdollista uutta
lähetystä; automaattinen uusinta ei ole palautumiskeino.

Palautuminen tarkoittaa tämän uuden tarkistimen käytön lopettamista tai sen
erillisen paikallisen muutoksen peruuttamista. Alkuperäisiä CSC-syötteitä,
vanhaa checkoutia, hydrologiatuloksia tai näyttöaineistoa ei poisteta tai
korvata. Raportteja ei siivota automaattisesti. Mahdollisen tulevan työn
peruutusoikeus on rajattava hyväksyttyyn pyyntöön ja sen tiedossa olevaan
työ-ID:hen; tilin tai projektin kaikkien töiden peruutus ei kuulu siihen.
