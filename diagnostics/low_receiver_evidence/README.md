# LOW PR #22: jäädytetty havainto ja yksi offline-testikerta

[Issue #33](https://github.com/annasuuronen/MaaltaMerelle/issues/33),
[draft PR #34](https://github.com/annasuuronen/MaaltaMerelle/pull/34).
Haara `codex/low-pr22-receiver-evidence-one-shot-v1` perustuu täsmälleen
PR #22:n commitiin `effab29aa4d44ecc897efc0c91c96f3bfc1b4db6`.
Vain tämän uuden hakemiston toteutus muuttuu. Vanhoja tutkimusmenetelmiä,
testejä, raportteja, tuotantokoodia tai rastereita ei muuteta.

## Havainnon alkuperä ja rajat

Käyttäjän 21.10.2026 toimittama [PR #22:n konsoliraportti](https://github.com/annasuuronen/MaaltaMerelle/pull/22)
raportoi `LOCAL_GIT_CLEAN`, EPSG:3067 / 2 m / 6000×6000 -otsakkeiden
geometrisen yhteensopivuuden, neljä rasterikutsua, 14 vastaanottajasolua,
56 palautettua arvoa ja nolla jatkojäljitysaskelta. Nämä ovat **käyttäjän
raportoimia CSC-havaintoja**. Tässä ympäristössä ei ole luettu CSC:n
tiedostoja eikä alkuperäistä rasteria ole tarkistettu uudestaan.

[observed_receivers_20261021.csv](observed_receivers_20261021.csv) säilyy
muuttumattomana konsolista kirjattuna havaintona: 14 LAND-solua,
kelvolliset Whitebox-pointerit, 0 WATER- ja 0 NoData-solua. Korkeudet ovat
**konsolin tulostustarkkuutta**, eivät alkuperäisiä täyden tarkkuuden arvoja.
Noin 0,221 m arvoista ei päätellä luonnollista kaltevuutta tai korkeusmallin
absoluuttista oikeellisuutta.

[observation_provenance.json](observation_provenance.json) sitoo kopion
lähdecommitit, raporttilinkin, ilmoitetun geometrian ja lukubudjetin sekä
molempien CSV-tiedostojen SHA256-tiivisteet. Testit lukitsevat jokaisen
metatietokentän ja hylkäävät myös tuntemattomat/toistetut JSON-avaimet.
Tiiviste todistaa versionhallintaan tallennetun kopion eheyden; se ei
allekirjoita alkuperäistä konsolitulostetta tai rasteria. Historiallinen
D8-provenienssi on edelleen `UNKNOWN/INCOMPLETE`, ja Adler32 `0f39c62a`
on käyttäjän ilmoittama, **ei uudelleen laskettu**.

| Tiedosto | SHA256 |
| --- | --- |
| Alkuperäinen `../land_network_topology/low_boundary_receivers_targets.csv` | `965eec1ea145adc346e52413f2539ec9fe17d82eeab7cf709fafa37f7696bf57` |
| Muuttumaton havainto-CSV | `176558ec8306afdee35d7932d56faa5979313c5b8a748f2613ab11b76ee62683` |

Kaikki alkuperäiset 16 lähtöriviä ja 14 vastaanottajaa pysyvät lukittuina.
Yhteisten vastaanottajien (3000,2994) ja (3006,3002) ilmoitetut määrät ovat
20 ja 32. Yhteensä 121 raportoitua lähdereittiä **ei ole validoitu
virtauskertymä**, yksilöllinen lähdejäsenyysjoukko tai valuma-alue.

Pointeri 128 solussa (3000,2994) osoittaa jo havaittuun (2999,2994):ään.
Sen pointeri 64 osoittaa näytejoukon ulkopuolelle (2998,2993). Tämä on
solukoordinaateista johdettu geometrinen yhden askeleen päätelmä, ei uusi
rasterihavainto tai todennettu hydrologinen purkureitti. Jälkimmäistä solua
tai muita uusia todellisia soluja ei lueta tällä paketilla.

## Riippumaton katselmointi ja korjaukset

Alkuperäinen ajuri ei vaatinut odotettua commit-SHA:ta, valvonut muistia,
aikarajannut terra-riippuvuuden latausta tai raportoinut kaikkia kesken
jääneitä vaiheita. Se myös uusi kaikki historialliset 21 R-testiryhmää.
CSV-lukija salli ylimääräisiä/puuttuvia sarakkeita ja epäkanonisia lukuja;
metatietojen provenienssia ei ollut sidottu erilliseen sopimukseen.

Nykyinen ajuri vaatii täyden ulkoa annetun commitin, oikean originin ja
haaran, PR #22 -lähtöcommitin esi-isyyden ja puhtaan checkoutin (myös
ignoroidut tiedostot). Se tarkistaa lähde- ja havainto-CSV:n tiivisteet,
kaikkien versionhallittujen tiedostojen tiivisteet ennen/jälkeen sekä
molempien lähdecheckoutien muuttumattomuuden. Raportit menevät uuteen,
checkoutien ulkopuoliseen hakemistoon. Jo olemassa olevaa tuloshakemistoa
kieltäydytään käyttämästä tai ylikirjoittamasta.

## Neljä erillistä testikokonaisuutta

1. **34 Python-havaintotestiä.** Solukohtaiset kenttämuunnokset,
   puuttuvat/ylimääräiset/toistetut rivit ja kentät, saman kokonaissumman
   säilyttävät väärennetyt lähdemäärät, kaikki kahdeksan Whitebox-suuntaa
   riippumattomasti numeroidulla ei-neliöruudukolla, rajan yli kiertyminen,
   NoData/NaN/Inf, väärät kelvolliset pointerit, rivijärjestys ja provenienssi.
2. **32 ajurin turvatestiä.** Väärä commit/origin/haara, dirty/ignored,
   sisältömuutos, nollatestit, osittainen NOT_RUN, toistettu yhteenveto,
   puuttuva R/ohjelma, väärä R-versio, aikakatkaisu, muistiraja, lokiraja,
   erillisen prosessiryhmän lapsen muisti, jälkeläisten pysäytys,
   tulospolun/symlinkin esto ja riippumattomien testien jatkuminen virheessä.
   Orkestraation väärennetyt pienet ohjelmat ovat testifixtureita; niiden
   tuloksia ei esitetä varsinaisina R-/CSC-testituloksina.
3. **6 uutta terra-yhteensopivuusryhmää.** Vain tilapäisiä 12×13 synteettisiä
   GeoTIFFejä: täsmälliset 14 numeroindeksiä, järjestys, NoData, solukeskukset,
   väärät indeksit, 4×14 palautetun arvon sopimus ja yhteisen geometrian
   virheet. Alkuperäisen CLI:n tai koko 11×11-ikkunan testiä ei uusita.
   Neljä 14 arvon lukua koskevat tässä vain generoituja pieniä fixtureita.
4. **PR #32 / 02G.3 erillisenä.** Täsmällinen
   `fb5c673b5fb08652e846191074095627b364d7db`, erillinen puhdas checkout.
   Ajuri arkistoi vain sen `diagnostics/02g_complete_local_dag_core`-yksikön
   tilapäiskopioon ja suorittaa olemassa olevan 15 tapauksen / 739 tarkistuksen /
   53 odotetun STOP:n Base R -sarjan kerran. Sen kirjoittamat synteettiset
   esimerkki-CSV:t jäävät kopioon; alkuperäiset tulokset säilyvät.
   Vanhaa kampanja-ajuria tai laajoja testejä ei ajeta. Tämän kokonaan
   tunnetun 27 paikan / 11 maalähteen DAG:n numeerisia lukuja ei yhdistetä
   PR #22:n 121 raportoituun lähdereittiin. STEP_LIMIT-havaintoja ei jatketa.

## Yhden istunnon resurssit, riippuvuudet ja tulostus

`one_shot_roihu.sh` säilyttää olemassa olevan sisäänmenon ja kutsuu uutta
Python-standardikirjaston valvojaa. Tarvitaan Linux `/proc`, Bash, Git,
host-Python 3 (vähintään 3.8), Rscript ja terra. Ei pip/R-pakettiasennuksia,
Whiteboxia, SSH-/FirecREST-asiakasta tai Slurmia. Lähteiden GitHub-nouto
tehdään **ennen** offline-testejä, kahteen erilliseen checkoutiin.

Host-Pythonin absoluuttinen polku tallennetaan `MM_HOST_PYTHON`-muuttujaan
**ennen** `module load r-env/461` -komentoa. Itse ajuri ei lataa moduuleja.
Roihu-komento vaatii R 4.6.1 / terra 1.9.34; versiot kirjataan ja poikkeama
pysäyttää hyväksynnän. Paikallinen vertailu käyttää omaa ilmoitettua versiota.

| Vaihe | Aikaraja |
| --- | --- |
| Havaintotestit | 45 s |
| Valvojan testit | 60 s |
| R/terra-riippuvuuksien lataus | 30 s |
| Pieni terra-yhteensopivuusjoukko | 90 s |
| PR #32:n erillinen yksikkö | 30 s |
| Koko offline-paketti | 300 s; viimeiset 30 s varataan loppuvarmistuksille |

Git-kutsuilla on lisäksi enintään 10 s raja ja koko paketin jäljellä oleva
budjetti. Prosessi ja jälkeläiset pysäytetään aikakatkaisussa, virheessä
ja lopuksi; automaattisia uusintoja ei ole. Muistipysäytysraja on **2 GiB**
lapsipuun yhteenlaskettua RSS:ää, näytteistys 20 ms. Myös eri prosessiryhmään
siirtyneet jälkeläiset huomioidaan. Muistirajan ylittyminen estää uusien
vaiheiden käynnistyksen. Jaetut sivut voivat tulla lasketuiksi useammin;
näytteistys voi aliarvioida lyhyen huipun. Tämä ei ole jatkuva cgroupin
kova allokointiraja tai resurssivaraus. Fixturet ovat tarkoituksella pieniä.
Yhden vaihelokin pysäytysraja on 4 MiB; laskentakirjastojen säikeet rajataan yhteen.

Tulosteen alussa on **täsmälleen yksi** `TULOKSET ALKAVAT`.
Varsinaiset testilokit ovat ulkoisessa tuloshakemistossa; niiden mahdolliset
merkkijonot eivät monista päätulostetta. `summary.json` sisältää commitit,
versiot, vaihekohtaiset PASS/FAIL/NOT_RUN-tilat, tarkistusmäärät, syyt,
ajat ja näytteistetyt RSS-luvut. Nolla testiä, puuttuva/toistettu yhteenveto,
FAIL, ohitettu testi tai yksikin NOT_RUN estää kokonais-PASS:n. Puuttuvan
R:n tapauksessa esimerkiksi Python-vaiheet voidaan silti todeta PASS:ksi.
Vastaava ennakkovarmistusvirhe näkyy kokonais-FAIL:na ja vaiheiden NOT_RUN:na.

Ajotapa on yksi tämän PR:n julkaisuraportissa annettu commit-lukittu
Roihu Login node -komento. Se kloonaa tämän haaran ja PR #32:n **erikseen**,
tallentaa host-Pythonin, lataa R-moduulin ja kutsuu kerran:

```bash
bash "$MM_WORK/evidence/diagnostics/low_receiver_evidence/one_shot_roihu.sh" \
  --expected-commit "$MM_PIN" --report-dir "$MM_WORK/reports" \
  --pr32-repo "$MM_WORK/pr32" \
  --expected-r-version 4.6.1 --expected-terra-version 1.9.34
```

Sama terminaali-istunto ei tarkoita koodien yhdistämistä. CSC-yhteyttä,
Slurm-ajoa tai olemassa olevia scratch-rastereita ei käynnistetä/lue ajurissa.
Roihun kirjautumisessa säilyy käyttäjän olemassa oleva `ssh csc-roihu` ja
Certificate Helper -käytäntö; tätä toteutusta varten ei vaihdeta avaimia.

## Todellinen testinäyttö ja avoimet portit

Kehitysvaiheen paikalliset testit: 34 havainto-, 32 valvoja- ja 6 terra-ryhmää
läpäisty R 4.5.0 / terra 1.8.29 -ympäristössä. Ensimmäinen uusi terra-koe
oli 5 PASS / 1 FAIL: fixture odotti NA_real_-esitystä ja GeoTIFF palautti
NaN:n. Molempien puuttuvuusmaski ja jokainen ei-puuttuva arvo tarkistetaan
nyt erikseen; korjattu sarja on 6 PASS / 0 FAIL / 0 NOT_RUN. Tuotantokoodia
muuttamalla tai puuttuvaa solua hyväksymällä tätä ei korjattu.

Koko Bash → host-Python → R -ketju on nyt suoritettu paikallisesti puhtaista,
lukituista Git-versioista. Molempien lähdecheckoutien loppuvarmistus läpäisi.
Kaikki uudet ajot säilyvät [local_validation](local_validation/)-hakemistossa;
[validation_record.json](local_validation/validation_record.json) sitoo lokien
tiivisteet ja kertoo myös kehitysvaiheen FAIL-havainnosta. Aiempiin tuloksiin
tai muiden PR:ien raportteihin ei kirjoitettu.
Raakalokit säilyvät tavutasolla alkuperäisinä, myös R-tulosteen rivien
loppuvälilyönnit. Vain tämän uuden lokihakemiston `*.log`-tiedostoilta on
rajatulla `.gitattributes`-määrityksellä poistettu tekstin whitespace-lint;
ohjelmakoodi, JSON ja Markdown tarkistetaan normaalisti. Lokien omat
SHA256-tarkistukset säilyvät voimassa.

| Paikallinen one-shot | Testattu toteutuscommit | Havainto / valvoja / terra / erillinen DAG | Tila | Koko aika |
| --- | --- | --- | --- | --- |
| 1 | `6d64d3ad32ea8803e7835d4c9b55778c70c8e9dd` | 34 / 31 / 6 / 15 | 4 PASS, 0 FAIL, 0 NOT_RUN | 9,0338 s |
| 2, lopullinen ajurikoodi | `fb91328073b7322dd6784eeb745f20708f0f0826` | 34 / 32 / 6 / 15 | 4 PASS, 0 FAIL, 0 NOT_RUN | 9,4443 s |

Toinen paikallinen tarkistus oli perusteltu ajurin lähdekoodimuutoksella:
PR #32:n täsmällinen yhteenveto tarkistetaan ennen vaiheen PASS-tulostusta,
sille lisättiin hylkäystesti ja tar-purkusuodatin määriteltiin eksplisiittisesti.
Ensimmäisen ajon Python-deprekaatiovaroitus säilyy alkuperäisessä lokissa;
se ei ollut testivirhe. Molemmat ajot käyttivät R 4.5.0 / terra 1.8.29 / Python
3.12.14 -ympäristöä ja erillistä lukittua PR #32 -checkoutia. Raportointicommit
lisää vain tämän näyttöaineiston ja dokumentaation; testatun koodin SHA256:t
varmistetaan samoiksi kuin toisessa ajossa.

| Lopullinen paikallinen vaihe | Tapauksia | Aika | Näytteistetty lapsipuun RSS-huippu |
| --- | --- | --- | --- |
| Havaintosopimus | 34 PASS | 0,2069 s | 16,00 MiB |
| Valvojan turvatestit | 32 PASS | 2,0549 s | 58,29 MiB |
| Pieni terra-yhteensopivuus | 6 PASS | 3,3997 s | 187,91 MiB |
| PR #32 erillisestä versiosta | 15 PASS, 739 tarkistusta, 53 odotettua STOP:ia | 0,6736 s | 64,92 MiB |

Yhteensä lopullisessa paketissa **87 onnistunutta ohjelmistotapausta**;
odotetut hylkäykset ovat turvatestien onnistumisia. Lisäksi bounded R/terra
riippuvuustarkistus läpäisi. Mittaukset sisältävät testien työtä, eivät ole
pelkän ydinalgoritmin benchmark tai CSC:n resurssiennuste. Laajoja aiempia
regressiokampanjoita, Whiteboxia, todellisia rastereita ja CSC:tä ei ajettu.
**Roihun uuden one-shotin suoritus on NOT_RUN**. Paikallinen terra 1.8.29
PASS ei todista CSC:n terra 1.9.34 -yhteensopivuutta.

Seuraava todellisen aineiston jatkosolu-/pointerikoe vaatii erillisen
rajauksen ja hyväksynnän. Nykyinen lupa ei laajenna jo suoritettua 56 arvon
CSC-lukua. Luonnollisen uoman, purkupisteen, DEM-korkeuden tai historiallisen
Fill/D8-provenienssin hyväksyntää ei tehdä tämän paketin perusteella.

GitHubin olemassa olevat hydrologia-push-triggerit rajautuvat
`baseline-no-structures`-haaraan. CSC-preflightin PR-kohde on samoin tämä
haara; PR #34:n kohde on PR #22:n tutkimushaara. Oletushaaran MODERATE
jatkotyönkulku rajautuu `codex/moderate-02d4-diagnosis`-haaraan.
Tämän hakemiston päivitys ei täytä näitä raskaan hydrologian laukaisuehtoja.
Työnkulkuja tai automaattista Codex-korjausketjua ei muuteta eikä käynnistetä.

```text
hydrological_validation=NOT_ASSESSED
channel_interpretation=NOT_ASSESSED
MODERATE=REVIEW_REQUIRED
NATIONAL=LOCKED
```
