# Näytön alkuperä ja hyväksyntäportit

**Tämä dokumentti erottaa historiallisen testinäytön, uuden kampanjan valmistelun ja oikean hydrologisen hyväksynnän.** Tuotannon käyttäjälupaa ei voi antaa tähän GitHub-haaraan kirjoittamalla.

## Lähteet, tunnettu näyttö ja avoimet kysymykset

| Lähde | Pysyvä viite | Tulkinta |
| --- | --- | --- |
| Rakenteeton vertailu | baseline-no-structures @ 7050b582edab3195669529f366b4f5a2915488c6 | Ei hydraulisten rakenteiden reititystä eikä kansallista hyväksyntää |
| CSC-automaation PR #3–6 | commitit 6d75c9a6, a952ef13, 734669e8, 1edc9aa2 | Jo yhdistetyt **offline**-esivarmistukset, ei automaattista CSC-suoritusoikeutta |
| Validointialueiden aineisto | ci-testdata-validation-gradient @ 4518285f0c74c01f12c96d6d831515846260d1a4 | NATURAL/LOW/MODERATE/HIGH ja rakenteiden 0/1/3/11 valintaluku; HIGH:n DEM on manifestissa tyhjä |
| TEST_SULKU_11 CI-syötteet | ci-testdata-test-sulku-11 @ 85efe0ecb1bdc09040851bfd391e78f770501058 | Testifixturet eivät todenna HIGH:n todellista CSC-DEM:ää |
| LOW #11–17 | PR #11 b46ca05e, #12 cd9612aa, #15 053df7c3, #16 24b81af2, #17 753ac0d5 | Rantapäätteet, 2 m ensimmäinen vesi, maasolujen D8, ei järven läpi reititystä |
| LOW #18 | PR #18 08ef53bd | Erillinen rajattu todellisen aineiston 02B-ankkuroitu ikkuna, ei yhdistetty #19-ketjuun |
| LOW #19–21 | PR #19 63cfcb67, #20 ffcdfe93, #21 40509d50 | 121 maasolulähdettä, 105 paikallista LAND→LAND-reunaa, 18 yhtymää ja 16 suoraa ikkunapoistumista |
| LOW #22 | PR #22 effab29aa4d44ecc897efc0c91c96f3bfc1b4db6 | Lukittu 14 vastaanottajan/56 palautetun rasteriarvon lukija, jonka paikalliset ohjelmistotestit on raportoitu; **14 todellista vastaanottajaa ei vielä havaittu** |
| LOW #23–24 | PR #23 01485c08, #24 f626ba465d8c044acb0ad981da18667fbfa98df6 | Synteettinen mittakaava-/pitkän D8-reitin ohjelmistonäyttö, ei koko alueen kerääntymä |
| LOW 02G #25 | 08a7b17f856aa266cd989a3c9c2bb9734e623900 | Raportoitu paikallinen synteettinen 02G-kertymän lähdejoukko-/tiili-PASS; 10k lisäkoe NOT_RUN_RESOURCE_GATE |
| MODERATE #7 | a3c42be333468e25c731faa3fd63f9687ed83978 | 02D.4–02D.5 tutkimus kesken; Roihun kirjautumissolmun SSH-este issue #14 |
| 02E #8 | 5312b4cf5512c97ddc801598ee4d34e3ae7ad1a5 | QA:n rivijärjestyksen indeksivirheen korjaus; aiempi CSC-integraatiotesti jäi virheeseen |

Yksikään matriisin EXISTING_EVIDENCE-rivi ei oikeuta tulkitsemaan syntestien PASS-tulosta toimivaksi outletiksi, koko valuma-alueen kertymäksi tai varmistetuksi uomaksi. LOW:n 02G-vaiheen **tuntematon ulkopuolinen tuonti pysyy tuntemattomana**, sykli ei saa keinotekoista äärellistä kertymää, STEP_LIMIT ei muutu hyväksytyksi ulosmenoksi ja 4 ha pysyy metatietona, kunnes erillinen tieteellinen päätös muuttaa käyttöä.

## Ajoporttien järjestys

1. **Offline-kartoitus:** lähdetunnisteet, neljän alueen täsmällinen vertailu ja vanhat raportit. Ilman tunnistettuja lähteitä -> STOP.
2. **CSC-yhteyden riippumaton vahvistus:** SSH-yhteys ja tarpeellinen palvelun toimintakyky. Issue #14:n historiallisen esteen poistumista ei saa arvata.
3. **Todellisten syötteiden ja resurssien todentaminen:** täsmällinen rasteripolku, SHA256, koko, CRS, 2 m solu, rasterilaajuus, Whitebox D8 -semantiikka sekä voimassa oleva työallokaatio ja käytettävä muisti. HIGH:n DEM-identiteetti tuntematon; LOW:n area-ID / canonical-ID -ero on ratkaistava avoimesti.
4. **Erillinen tutkimus- ja käyttäjähyväksyntä:** oikea koe-ID, lähdecommit, tietue-/soluraja, varattu aika, ulostulo ja stop-säännöt. Matriisissa ei ole approval-granted-kenttää, jonka muuttaminen käynnistäisi työn.
5. **Ainoastaan valtuutettu rajattu read-only-ajo:** ei uuden 11×11-ikkunan kokoamista, ei rajareitin jatkamista, ei automaattisia vaihtoehtoisten kohteiden lisälukuja, ei koko rasterin ajoa.
6. **Erillinen uusi raportti:** uniikki todellinen run-ID, alkuperäisen commitin SHA, todellisten syötteiden tiivisteet, käytetty varaus, virhelokit ja tekninen PASS/FAIL/NOT_RUN/STOP sekä tästä erillinen tieteellinen tulkinta. Ei ylikirjoiteta aiempaa FAIL:ia tai epävarmaa tilaa.
7. **Tieteellinen päätös:** hyväksytään vain erikseen arvioitu tulos; MODERATE=REVIEW_REQUIRED, NATIONAL=LOCKED ja 02G:n hydrological_validation=NOT_ASSESSED säilyvät siihen asti.

## Offline-generaattorin turvallisuus

Python-työkalu ei lue ulkopuolisia tiedostoja CSV:n lisäksi eikä tee etäoperaatioita. Plan sisältää aina execution_enabled=false, csc_connection_verified=false, input_identity_verified=false, resource_allocation_verified=false, user_approval_granted=false ja jokaiselle riville execution_state=NOT_RUN. Arvot muodostetaan ohjelmallisesti, ei käyttäjän täyttämästä CSV:n PASS/approval-kentästä.

Ei Slurm job array -toteutusta, toteuttavaa runscriptiä, FirecREST-yhteyttä eikä automaattista hyväksyntäportin avaamista. Ne kuuluvat mahdolliseen erilliseen käyttäjän hyväksymään myöhempään vaiheeseen.
