# Vaihtoehdot ja päätösmuistio

Päätös koskee [issuen #29](https://github.com/annasuuronen/MaaltaMerelle/issues/29)
jatkosuuntaa. Tämä tiedosto ei muuta algoritmia tai hyväksy uutta ajoa.
V/E/P/M/B/Q ja lisämuuttujat on määritelty
[kustannusmallissa](complexity_and_invariants.md). Nykykoodin A/B-lähteet,
SHA:t ja rivialueet ovat [lähdetaulukossa](README.md#sources).

## Toteutusvaihtoehdot

Alla ovat menetelmien ehdolliset kustannukset, eivät mitatut tavumäärät.
Jokaisen vaihtoehdon on säilytettävä (a) havaitun prefiksin ja (b) täydellisen
DAG:n summan eri merkitys. Esiin listatut formaatit/kirjastot eivät ole
asennettuja riippuvuuksia tai jo toteutettuja muutoksia.

| Vaihtoehto | Oikeellisuusolettama ja pahimman tapauksen tila | Resurssi-/I/O-riski | Tiilirajat, auditointi ja tietohäviö |
| --- | --- | --- | --- |
| Täydet lähdetunnuslistat | Täsmällinen jäsenyys ja deduplikointi: O(M), lisäksi P/Q/ledgerit. Ei tarvitse olettaa lähdejoukkoja erillisiksi | Ketjun M on neliöllinen, nykyiset kasvavat R-listat voivat käsitellä samoja jäseniä toistuvasti | Lähde/edge/run/budget-identiteetit säilyvät. Ei ratkaise tuntematonta tuontia; täydet historiat eivät ole skaalautuva viestiformaatti |
| Bittijoukot / tiiviit ID-jaksot | Globaalisti yksikäsitteinen ja palautettava ID-kartta. Tiheä bittimatriisi vaatii O(V²) bittiä, eli O(V²/w) konetyöyksikköä; w on sanan bittileveys. Kiinteässä ID-järjestyksessä sirpaleisten jaksovektoreiden pahin tapaus on O(M). Täydellisen funktionaalisen DAG-metsän erikoistapaus kuvataan alla | Unionien ja ID-muunnosten työ jää; pakkaussuhdetta ei ole mitattu. Kirjaston tavuesitys ja riippuvuudet vaativat erillisen valinnan | Joukkounioni on idempotentti, jos ID-nimiavaruus on yhteinen. Oletetut jatkuvat välit, likimääräiset jäsenyydet tai pelkät hashit eivät kelpaa täsmälliseksi jäsenyystodisteeksi ([C9](counterexamples.md#c9)) |
| Kiinteän täydellisen DAG:n pelkät lukumäärät | Yksi lähtevä reuna, yksi lähdepanos/maasolu, ei sykliä, ei sensuroitua jäsenyystavoitetta. O(V+E) tallennettu graafi/tila ja topologinen laskenta indeksoidussa esityksessä | Tarvitsee topologisen validoinnin ja numeerisen tarkkuusrajan. Jäsenyystulosta ei synny; samasta luvusta ei voi rekonstruoida lähde-ID:itä | Tuontisummat saa yhdistää vain osoitetusti erillisistä lähdealueista, kerran per riippuvuusversio. Kuittaus ei todista tätä. Ei korvaa (a):ta STEP_LIMIT-verkossa |
| Lohkoittainen/topologinen streaming | Täysi riippuvuusjärjestys ja valmistumisen ehdot tunnetaan. RAM O(F+lohko), missä aktiivisen rintaman F pahin tapaus on O(V); säilytettävä graafi vähintään O(V+E) | Maantieteellinen rivi-/tiilijärjestys ei ole D8:n topologinen järjestys. Lajittelu, odotusjonot ja reunojen uudelleenluku voivat kasvattaa I/O:ta | Puuttuva naapuri ei sulje rintamaa. Tiilien naapuruus voi kiertää, vaikka solugraafi on DAG ([C7](counterexamples.md#c7)). Lähdejäsenyyttä ylläpidettäessä M ei katoa |
| Levypohjainen kertymä | Sama tarkka tulossopimus kuin RAM-versiossa. Numeeriselle graafille levy O(V+E); kaikkien jäsenyyksien/historioiden säilytys edelleen O(M+P+Q) sekä sopimus-/ledgerkuorma | Levy ei itsessään todista rajattua RAM:ia: indeksit, cache, jonot ja snapshotit voivat kasvaa. Ulkoinen lajittelu/hajasaanti, levyn täyttyminen ja palautuminen on mitattava erikseen | Idempotentti pysyvä outbox/inbox ja transaktiot puuttuvat nykyisestä prototyypistä ([B1] 25–28; [D2] 176–180). Lokin poistaminen ennen riippuvuuden todistettua sulkeutumista voi hävittää näyttöä |
| Hybridi: tunnetut numeeriset paikallissummat + erilliset auditoitavat lähdejäljet | Numeerinen haara vain (b):n ehdot täyttävälle osalle. (a):n prefiksit pysyvät omalla sopimuksellaan. RAM/levy O(V+E) **plus** säilytetyn auditoinnin P_a/M_a/Q_a; koko auditoinnin säilyttämisessä vanhat rajat palaavat | Rajapintojen ja kattavuuden pitää estää kahden tulosmerkityksen sekoittaminen. Auditoinnin valinta ei saa hiljaa poistaa poikkeamia tai muuttua hydrologiseksi validoinniksi | Molemmat haarat sidotaan samoihin globaaleihin ID:ihin, input-versioihin ja omistajuuteen. Ratkaisematon tuonti, kuittaamattomat siirrot ja havaintopuutteet säilyvät; hajautettu aggregointisopimus vaatii oman myöhemmän päätöksen |

Nykyinen koodi käyttää täysiä listoja ja jälkiä ([A1] 65–108; [B1] 25–28,
42–79), ei valmiiksi tiiviitä bittijoukkoja tai topologista lukumääräydintä.
Pelkkä nykyisten listojen siirto levylle tai ruudukon kokorajan nostaminen
ei poista M/Q-kustannusta. Pahimman tapauksen lähdejäsenyystulostetta ei voi
materiaalisoida O(V)-kokoiseksi taulukoksi. Tämä ei ole väite, että kaikki
jäsenyys olisi mahdotonta esittää häviöttömästi epäsuoran graafin avulla.

**Tiiviin jaksokuvauksen tärkeä erikoistapaus:** täysin tunnettu yksilähtöinen
DAG muodostaa virtaussuunnalle käännettynä juurellisen metsän, kun ensivesi
katkaisee reitin. Syvyyssuuntainen läpikäyntijärjestys voi esittää kunkin
solun koko yläpuolisen alipuun yhtenä indeksivälinä. Indeksi ja palautettava
globaali ID-kartta voivat siten olla O(V+E), vaikka jäsenien **luetteloitu**
tulos on O(M). Tämä ei ole nykykoodin kiinteiden globaalien ID-listojen
jo toteutettu pakkaus eikä tarkoita, että sensuroidut joukot olisivat
alipuita: C2:n {a,b} ja {b,c} limittyvät ilman sisäkkäisyyttä. Katkaisuihin
sidottu numeerinen DAG-laskenta on myös ehdollinen mahdollisuus, jonka
erillinen todistusvaatimus on [kustannusmallissa](complexity_and_invariants.md).
Näitä indeksi-/katkaisulaajennuksia ei valita nyt toiseksi toteutukseksi.

## Valinta: hybridi, mutta seuraavaksi vain yksi laskentahaara

**GO suunnittelupäätöksenä:** erota täydellisen paikallisen DAG:n numeerinen
laskenta havaitun lähdejäsenyyden auditoinnista. Seuraava ehdotettu pieni
muutos on **erillinen synteettinen paikallisen DAG:n lukumääräydin**, joka
ei kutsu tai korvaa `g02_accumulate`-/`g2r_*`-toteutuksia, laajenna niiden
lukurajoja tai muuta niiden kenttien merkitystä. Auditoiva haara jää nykyiseksi.
Tässä ei ehdoteta toista uutta pakkaus-, viestitys- tai levyjärjestelmää.

Valinta on perusteltu [kustannusmallin kertalaskentatodistuksella](complexity_and_invariants.md#kertalaskennan-todistus-ja-rajat):
täydellisen yksilähtöisen DAG:n vanhempien lähdejoukot ovat erilliset.
Numeerinen ydin voi välttää kaikkien jäsenyyksien materiaalistamisen tässä
rajatussa tulostavoitteessa. Todistusta ei siirretä sensuroituihin jälkiin.
Hybridi kokonaisuudessaan ei vielä ole toteutettu tai tuotantovalmis.

### Ehdotetun yhden muutoksen tarkka sopimus

Syöte on pieni, muuttumaton synteettinen solugraafi, ei havaittujen jälkien
kanonisten reunojen unioni. Se sisältää globaalit solutunnukset, 2 m/EPSG:3067-
metatiedot, yksilölliset ydinsoluomistajat, kaikki määritellyt paikalliset
maasolu-lähteet ja niiden havaitut kelvolliset seuraajat. Ensivesisolu on
terminaali, jonka omaa pointeria ei seurata. Alkuvaiheen hyväksytty scope
on kokonaan tunnettu paikallinen DAG, jossa jokainen paikallinen lähde
päättyy tunnettuun ensimmäiseen vesisoluun.

Tuottajan on erikseen ilmoitettava ja tarkistajan varmistettava
`COMPLETE_DECLARED_LOCAL_DAG`-sopimus. Puuttuva soluhavainto, NoData,
ristiriitainen pointeri/luokka, puuttuva kohde tai omistaja, sykli tai aktiivinen
STEP_LIMIT-sensurointi estää tämän haaran täydellisen tuloksen. Ydintä ei saa
kutsua jäljitystulosten adapterina eikä käyttää jatkamaan niiden lähteitä.
Pelkkä muuttujan `complete=true` arvo ei korvaa rakenteellisia tarkistuksia
tai syötteen erillistä täydellisyysnäyttöä.

`external_import=UNKNOWN` **sallitaan paikallisen luvun laskennassa**, koska
ulkopuoliset lähteet eivät kuulu ilmoitettuun paikalliseen lähdejoukkoon.
Se ei salli koko valuma-alueen lukua. Ehdotetut tulosmerkitykset ovat:

| Tieto | Lupaus |
| --- | --- |
| Paikallinen numeerinen määrä ja 4 × määrä m² | Täsmälleen ilmoitettujen, täysin havaittujen paikallisten lähteiden osuus |
| Ensivesikontaktin paikallinen lähdemäärä | Vain maasolu-panokset; ei uutta vesiyksikköä eikä järven purkupisteen valintaa |
| `membership_mode=NOT_MATERIALIZED` | ID-jäsenyyslistaa ei ole tuotettu eikä sen olemassaoloa väitetä |
| Kattavuus ja `external_import` | Paikallisen graafin täydellisyys ja ulkopuolisen tuonnin tuntemattomuus eri kentissä |
| `total_upstream_*` | `NA`, kun ulkoinen tuonti tai koko yläpuolinen alue ei ole varmennettu |
| Provenienssi ja tulostavoite | Erottaa (b):n graafisumman (a):n havaituista prefikseistä; tarkka graafiversio ja omistajuus |

Nimet ovat **ehdotettu tulossopimus**, eivät nykyisten prototyyppien uusia
jo toteutettuja kenttiä. Piilotettua oletusta ulkopuolisesta nollatuonnista
tai hydrologisesta hyväksynnästä ei sallita.

### Hyväksyntä- ja epäonnistumiskriteerit seuraavalle toteutukselle

1. Yksi lähdepanos per yksilöllinen maasolu, ei halo-/vesipanosta; globaalin
   ID-kartan pitää olla yksikäsitteinen ja palautettava. Sama reuna ei esiinny
   kahdesti, eikä yhdellä maasolulla ole kahta seuraajaa. Kohdesolu vastaa
   havaittua Whitebox-D8-pointeria samalla ilmoitetulla ruudukolla.
2. Riippumaton topologinen validointi havaitsee syklin/käsittelemättömät solut.
   Ydin ei korjaa sykliä poistamalla reunaa tai asettamalla virtausta nollaksi.
   Puuttuva tai sensuroitu scope pysäyttää täyden tuloksen; alkuperäinen näyttö
   ja syykoodi säilyvät auditointihaarassa.
3. Täydellisessä scopessa solukohtaiset luvut, pinta-alat ja ensimmäisten
   vesikontaktien luvut vastaavat riippumattoman eksplisiittisen ID-orakkelin
   lähdejoukkojen kokoja. Odotuksia ei lasketa uudella topologisella ytimellä,
   sen apuindeksillä tai sen tuloksista muodostetuilla syötteillä.
4. Rivijärjestyksen tai saman yksilöidyn havainnon toimitusjärjestyksen muutos
   ei muuta semanttista tulosta. Ristiriitainen tai duplikaattinen graafisyöte
   hylätään; sitä ei hiljaa lasketa uudelleen. Ydin ei lisää uutta viestipalvelua.
5. Rajatun täydellisen DAG:n ensimmäisiin vesiin päätyvien lähdemäärien summa
   on V. Tätä ei tarkisteta kaikkien solmujen A-arvojen summasta. Ehto on vain
   rakenteellisen todistuksen ja ID-orakkelin lisätarkistus, ei globaali PASS.
6. Numeerinen esitys ja kertolasku 4 × A ovat tarkkoja valitulla V-rajalla;
   ylivuotoa/epätarkkuutta ei sallita. R:n integer-ylivuotoa ei saa peittää.
   Mahdollinen double-pohjainen kokonaisluku edellyttää eksplisiittistä
   tarkkuusrajaa myös pinta-alalle, ei pelkkää A ≤ V -jälkitarkistusta.
7. [C2](counterexamples.md#c2):n sensuroidun jälkiunionin tarjoaminen
   täydellisen paikallissumman syötteeksi hylätään. (a):n ja (b):n luvut voivat
   tarkoituksella erota; vanhaa testiä ei muuteta samaksi tulostavoitteeksi.
   Tuntemattoman ulkoisen tuonnin muuttuminen numeeriseksi kokonaistulokseksi
   on virhe. Myös neljän tieteellisen lukituksen muutos on virhe.

Jos jokin ehto ei ole todistettavissa tai orakkelivertailu poikkeaa, seuraava
toteutus pysähtyy. Älä paikkaa summaa keinotekoisella kertymällä. Tähän
katselmointiin ei liitetä uuden ytimen PASS-tulosta.

### Rajattu seuraava synteettinen koe, ei tässä ajettava kampanja

Enimmäisaloituskoko on **27 ruudukkopaikkaa ja 11 maasolu-lähdettä**, sama
kokoluokka ja pääfixture kuin [B2] 3–23 ja [B3] 74–90. Lisäksi vain tätä
pienemmät käsin määritellyt ketju-/yhtymäesimerkit ja negatiiviset syötekokeet.
Odotukset saadaan olemassa olevan riippumattoman `r_reference`-menetelmän
eksplisiittisistä lähdejoukoista tai käsin luetelluista joukoista, ei nykyisen
kertymäfunktion kutsusta. Kattavuusvirheet ja C1–C6:n riskit tarkistetaan
uuden ytimen sopimuksen hyväksyntä-/hylkäysehtoina.
Viestiprotokollaa ei toteuteta uudelleen: C6:n osalta uusi graafiydin
hylkää duplikaattireunan. PR #28:n viestitestisarjaa ei toisteta tätä varten.

Koon lähtöperuste on aiempi 27 paikan sarjan 1,9807 s / 130,898 MiB
ryhmämittaus ([README](README.md#measurements)), ei uuden algoritmin
ennustettu suorituskyky. Se oikeuttaa varovaisen **aloitusrajan**, ei muisti-
tai aikagarantiota. Tuleva koe rajataan enintään 120 sekuntiin, 1 536 MiB:n
lapsikohtaiseen osoiteavaruuteen ja 1 792 MiB:n näytteistettyyn ryhmä-RSS:ään
(samankaltaiset valvontarajat kuin [D2] 160–162), alle 2 GiB:n tavoitteen
turvamarginaalilla. RSS-näytteistys ei yksin ole jatkuva ryhmämuistin kova katto.
Ylitys/uhka, puuttuva RESULT tai nolla testiä on epäonnistuminen.
1 000 tai 10 000 solun koetta ei tässä ehdoteta seuraavaksi.

## Asiat, joita tämä päätös ei ratkaise

Täyden hybridin auditointipolitiikkaa, jäsenyysten pakkausta, positiivisia
ulkoisia tuonteja, tiilien aggregoitujen panosten erillisyyttä, solutason
rajariippuvuuksia ja hajautettua pysyvyyttä ei ole todistettu. Erityisesti
tiilen A kokonaiskertymää ei voi vain lisätä tiileen B ja myöhemmin takaisin
A:han; geometrinen tiilinaapuruus ei anna topologista laskentajärjestystä.
Näihin ei aloiteta toista toteutusta tämän päätöksen sivutuotteena.

Todellisen LOW-aineiston seuraava erillinen portti on edelleen PR #22:n
14 vastaanottajaa / 56 arvoa, ei tämän ytimen rasteriajo. Hydrologista
hyväksyntää tai todellista uomaa ei päätellä numeerisen kokeen onnistumisesta.
Lukitukset: `hydrological_validation=NOT_ASSESSED`,
`channel_interpretation=NOT_ASSESSED`, `MODERATE=REVIEW_REQUIRED`,
`NATIONAL=LOCKED`.
