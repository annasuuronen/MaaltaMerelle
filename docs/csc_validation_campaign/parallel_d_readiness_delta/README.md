# Neljän alueen valmius: vain muuttunut näyttö ja avoimet portit

**2026-10-24 — DOCUMENTATION_ONLY / NO_EXECUTION_AUTHORIZATION.** Tämä on
[issue #81:n](https://github.com/annasuuronen/MaaltaMerelle/issues/81) työvirta D,
[issue #26:n uuden rinnakkaisohjeen](https://github.com/annasuuronen/MaaltaMerelle/issues/26)
mukainen lisäys. Lähtö on PR #27:n tarkka
`cad5e0b8471c3ad7f0ac6e525a226b29268d2d2f`.

Alkuperäinen yhdeksän rivin testimatriisi, runner ja niiden 11 testiä säilyvät
muuttumattomina. Niitä ei ajettu uudelleen. Tämä lisäys ei muodosta toista
ajettavaa matriisia eikä korjaa vanhoja raportteja jälkikäteen. Se kertoo, mitä
vanhan suunnitelman portteja ei enää pidä ehdottaa uusiksi kokeiksi ja mitkä
aluekohtaiset puutteet ovat edelleen auki. Rinnakkainen työvirta F vastaa
erillisestä minitestien suunnittelijasta; tätä taulukkoa ei saa antaa runnerille
ajomanifestina.

## Näytön luokat ja tarkistetut lähteet

[sources.json](sources.json) yksilöi tarkistetut GitHub-lähteet ja
[readiness_delta.csv](readiness_delta.csv) sisältää täsmälleen neljä aluekohtaista
delta-riviä. NATIONAL ei ole viides testialue. CSV:n `False` on kirjaimellinen
ei-ajoa-merkintä, ei käyttäjälle annettava valtuutuskenttä.

- Pinnaus ja dokumentin SHA256 yksilöivät luetun koodin tai dokumentin tavut.
  Ne eivät todista CSC-syötteen aitoutta tai alkuperäistä valmistushistoriaa.
- PR #22:n, #7:n ja #76:n todelliset CSC-tulokset ovat **käyttäjän raportoimia**
  GitHubiin tallennettuja konsoli-/Slurm-havaintoja. Tämän työn ympäristö ei
  lukenut Roihun tiedostoja tai riippumattomasti hankittuja Slurm-lokeja.
- Tarkistetuissa lähteissä ei ollut riippumattomasti allekirjoitettua
  CSC-kuluttaja-/tuottajatodistetta. Tämä rajattu toteamus ei väitä, ettei muuta
  aineistoa voisi olla käyttäjän hallussa. `SOURCE_AUTHENTICATION=NOT_ASSESSED`.
- Issue #81:n hyväksyttyjä kampanjoita käytetään niiden ilmoitetussa
  ohjelmistotestien laajuudessa. Hyväksytty syntestitulos ei ole aluekohtainen
  syöteidentiteetti, hydrologinen hyväksyntä tai kansallinen valmius.

Lähde-ID:t S1 ja S2 ovat vain kaksi pientä, tarkasta GitHub-commitista
`4518285f0c74c01f12c96d6d831515846260d1a4` luettua metadata-CSV:tä. Rastereita,
CSC-tiedostoja tai uusia rasteriarvoja ei luettu. Niiden Windows-polut ovat
aineistoluettelon ilmoituksia, eivät vahvistettuja CSC-polkuja.

## Aluekohtainen muutos alkuperäiseen suunnitelmaan

| Alue | Muuttunut tai uudelleen vahvistettu näyttö | Edelleen estävä tekijä | Tämän työvirran uusi Roihu-minitesti |
| --- | --- | --- | --- |
| NATURAL `E0560000_N7690000` | S1/S2 ilmoittavat aineistot ja valintainventaariossa 0 rakennetta. Tarkistetuissa lähteissä ei uutta NATURAL-alueen todellista ajo-/syöteidentiteettinäyttöä. | Todellisten syötteiden identiteetti ja rajattu tieteellinen koesuunnitelma puuttuvat. | Ei; dokumentaatiomuutos ei tarvitse CSC-ajoa. |
| LOW `E200000_N6900000` | PR #22:n 2026-10-21 havainto: kaikki 14 vastaanottajaa LAND, 14 kelvollista Whitebox-pointeria, 56 palautettua arvoa ja 0 jatkojäljityksen askelta. Alkuperäisen matriisin vastaanottajat eivät enää ole vain lukemattomia ennusteita. | S1/S2: `area_id=E200000_N6900000`, mutta `canonical_tile_id=E0200000_N6900000`. Historiallinen tuottajalinja ja lopullinen D8/kertymä puuttuvat. | Ei PR #22:n uusintalukua. Uudet erilliset ohjelmistotarkistukset kuuluvat niiden omille työvirroille. |
| MODERATE `E0510000_N7620000` | PR #7 ilmoittaa työn 2369720 päättyneen `COMPLETED`, exit0:0, commit `a3c42be…`; 49/49 OBSERVED, joista 45 paikallisen alemman solun parihavaintoa ja 4 käyntirajaan sensuroitua hakua. Menneen ajon tekninen käynnistys onnistui. | 02D.4–02D.5:n tieteellinen kysymys, komponentittomat rantakynnykset ja epätäydellinen historiallinen provenienssi säilyvät. Menneen ajon allokaatio ei ole uuden ajon resurssitodiste. | Ei 49 järven koettimen uusintaa eikä raskasta täyttöä. |
| HIGH `TEST_SULKU_11` | S2:n HIGH-rivin `dem` ja `dem_qa` ovat edelleen tyhjät. S1/S2 ilmoittavat 11 inventoitua rakennetta. | Todellisen HIGH-DEM:n ja muiden syötteiden identiteetti puuttuu; CI-fixture ei yksin ratkaise tätä. Rakenteeton baseline ei mallinna sulkujen/patojen toimintaa. | Ei; syötepuutetta ei voi ratkaista synteettisellä PASS-tuloksella. |

LOW:n jo havaitut solut eivät todista toimivia ojia tai outlet-pisteitä.
20+32 jaettua vastaanottajaa kohti ilmoitettua lähdereittiä eivät ole validoitu
virtauskertymä. LAND_WATERin konsolissa näkyvät luvut eivät ole alkuperäisiä
rasteriraakabittejä. S5:n 256 keskuksen / 236 kelvollisen LAND-keskuksen otos ja
119 kvantittunutta lähes tasaista askelta eivät anna tarvittavien korjausten
prosenttia tai koko LOW:n hydrologista virheosuutta. Työvirta C käsittelee tämän
näytön nimittäjät ja epävarmuudet tarkemmin; D ei laske sitä uudelleen.

MODERATE:n 45 havaintoa eivät ole 45 järven hyväksyttyä purkureittiä: koetin
löytää alemman naapurin suhteessa käytyyn paikalliseen soluun, ei välttämättä
lähtöjärven korkeus- tai rantakynnystasoon. Neljä sensuroitua järveä
203477, 203714, 203857 ja 205128 eivät ole todistettuja suljettuja painanteita.
Raportoitu käyntiraja2000 säilyy tiedon rajana. Tätä ei yhdistetä samaan
hyväksymispäätelmään kuin erillistä STORAGE-/D8-auditointia.

## Minitestit ja tuleva aluepilotti ovat eri portteja

Tämän dokumentaatiodeltan **uusia ajettavia testejä on nolla**. Se ei pyydä
Roihu-resursseja, R/terra/GDAL-versiotestiä tai puuttuvan syötteen korvaavaa
syntestikierrosta. F:n myöhemmässä minitestimanifestissa D on nimenomaisesti
`EXCLUDED_DOCUMENTATION_ONLY`, ei epäselvä optional-testi. Muiden työvirtojen
uudet testit valitaan vasta niiden tarkkojen commitien ja tulosten katselmoinnin
jälkeen; niitä ei oleteta valmiiksi tässä dokumentissa.

Älä lisää tulevaan erään uudelleen hyväksyttyjä v2:n58R+125Python-testejä,
S2F75-, v1:n7-, G5A97-, LOW PR34:n87- tai 02G.3:n739-tarkistuskampanjoita.
Myös PR #22:n jo valmistunut 14 vastaanottajan rasteriluku, MODERATE:n49 järven
koetin sekä LOW:n otos- ja CSV-kvantittumishavainnot säilytetään aiempana
näyttönä. Niiden uusinta vaatii uuden relevantin muutoksen tai erillisen,
perustellun tutkimuskysymyksen — ei tämän taulukon julkaisemista.

Ennen mitään erillistä **aluepilottia** tarvitaan vähintään:

1. Täsmällinen alue-ID:n ja ruudukon sopimus. LOW:n kaksi ID-merkkijonoa
   sovitetaan todennetulla päätöksellä; niitä ei oikaista hiljaisesti. HIGH:n
   puuttuva DEM yksilöidään. Jokaiselle alueelle tarvitaan todellinen kattavuus,
   EPSG:3067,2m resoluutio ja pinnautuneet syöteidentiteetit.
2. Tuottaja–kuluttajalinjan ja syötteen nykyisen identiteetin ero. Tulevan
   kontrolloidun ajon mekanismi ei autentikoi vanhaa 02F-ajokertaa eikä vanhan
   pointerin valmistusta. Historiallinen STOP pysyy.
3. Tieteellinen, rajattu hypoteesi ja hyväksyntä-/STOP-säännöt. Lopullisen
   WATER_CONNECTED-D8:n ja kertymän puutetta ei peitetä paikallisen DAG:n
   lukumäärällä. Tuntematon ulkopuolinen tuonti pysyy UNKNOWN, STEP_LIMIT
   sensuroituna eikä rasteriraja muutu rannikko-/meripisteeksi.
4. Tuore tieto CSC-yhteydestä ja nimetystä allokaatiosta. Historiallinen
   `CSC_LOGIN_BLOCKED` ei ole todiste tämänhetkisestä esteestä, mutta vanha
   onnistunut työ ei myöskään varmista tulevaa yhteyttä tai muistivarausta.
5. Katselmoitu muistikiintiö, aika, prosessi-/tulostusrajat, yksityinen
   työ-/raporttitila ja alkuperäisten tiedostojen muuttumattomuus.
   Aluepilottien muisti/aika ovat tässä **NOT_ESTIMATED**. Uusien adapterien
   yhdistettyjä vaatimuksia ei arvata.
6. Käyttäjän erillinen hyväksyntä juuri kyseiselle manifestille ja Slurm-kiintiölle.
   `execution_enabled=False` säilyy tässä delta-aineistossa. Ulkopuolisen
   riippumattoman todistajan/trust-rootin puutetta ei voi kuitata itse ilmoitetulla
   hyväksyntäkentällä.

## Resurssien uusi tärkeä havainto

PR #76:n kuvauksen kohta *Roihu v2 attempt — environment STOP (2026-10-24)*
kirjaa tunnetun käynnistysongelman: 256MiB `RLIMIT_AS` **ennen CSC:n
kontti-wrapperia** pysäytti Go-ajoympäristön virtuaalimuistivarauksen
(`failed to reserve page summary memory`). R_EXIT=2, R_OUTPUT_BYTES=0;
sekä R- että Python-testit olivat silloin NOT_RUN, eivät koodin FAIL.

Sama kuvaus kirjaa myöhemmän muuttumattoman v2-commitin onnistumisen
työssä2516979, Slurmin fyysisellä `--mem=256M`-varauksella ja erillisissä
peräkkäisissä R/Python-konttivaiheissa. Tämä hyväksyy vain kyseisen v2-sarjan
58+125 testin runtime-laajuuden. Se **ei** osoita, että tulevan adapterin,
terra/GDAL:n tai yhdistetyn uuden erän 256MiB olisi riittävä. Älä toista
tunnettua wrapperin RLIMIT_AS-rajoitusta; myöhempi erä tarvitsee oman
fyysisen allokaation ja perustellun liikkumavaran katselmoinnin. D ei määritä
uutta Slurm-kiintiötä eikä anna suoritettavaa CSC-komentoa.

## Tämän deltan tarkistus ja pysähdysraja

Uusia runtime-/hydrologiatestejä ei toteutettu eikä ajettu: dokumentaatiotehtävä.
Vanhoja kampanjoita ei uusittu. Uusien kolmen tiedoston staattiset tarkistukset
kattavat neljän alueen ja lähdeviitteiden täsmällisyyden, lukitus-/ei-ajoa-tilat,
pinnattujen metadata-CSV:iden LOW/HIGH-havainnot sekä muutosten allowlistan.
Ne eivät ole CSC- tai hydrologisia PASS-tuloksia. `git diff --check` tarkistaa
dokumenttidiffin. Näiden tarkistusten tulos ja lopullinen commit raportoidaan
työvirran toimituskuitissa.

Luonnollinen STOP: **aluepilotin syötteet, tieteelliset päätökset, tuore allokaatio
ja käyttäjälupa puuttuvat**. Vain työvirtojen aidosti uudet synteettiset
ohjelmistotarkistukset voivat edetä F:n valmisteltavaan erään; D ei avaa näitä
portteja. Ei uusia CSC-lukuja, Slurm-ajoja, workflow-käynnistyksiä, lähdeaineiston
muutoksia tai mergeä.

```text
NATIONAL=LOCKED
MODERATE=REVIEW_REQUIRED
hydrological_validation=NOT_ASSESSED
channel_interpretation=NOT_ASSESSED
routing_authorized=false
outlet_selection=UNASSIGNED
HISTORIC_02F_EFFECTIVE_D8=NOT_ASSESSED
```
