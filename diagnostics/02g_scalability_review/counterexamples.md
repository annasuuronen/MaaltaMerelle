# Pienet vastaesimerkit ja todistettavuuden rajat

Nämä ovat **käsin johdettuja ajatuskokeita**, eivät tässä työssä ajettuja
testejä tai väitteitä nykykoodin uusista virheistä. Ne erottavat korvaavalle
menetelmälle vaarallisen oletuksen nykyisestä auditoidusta käyttäytymisestä.
`a,b,c` ovat erillisiä maasolu-lähteitä, `w` tunnettu ensivesisolu.
Kaikki nimet tarkoittavat globaaleja solutunnuksia, eivät kopioitavia halo-ID:itä.
Toteutusviitteiden SHA:t: [lähdetaulukko](README.md#sources).

<a id="c1"></a>
## C1: yhtymässä tuplalaskenta

Verkko `a → c ← b`, `c → w`. Kukin kolmesta maasolusta tuottaa yhden yksikön.
Oikea S(c) = {a,b,c}, A(c)=3 ja paikallinen lähdeala 12 m².
Jos kahden reitin listat {a,c} ja {b,c} summataan pituuksina, saadaan 2+2=4:
c lasketaan kahdesti. Myös saman c:n kopiointi kahdesta halosta lähteeksi on
virhe. ID-unioni ja yksilöllinen ydinomistajuus estävät tämän. DAG-summa
`1+A(a)+A(b)=3` on oikea, koska **vanhempien yläpuoliset** joukot ovat erilliset.
Esimerkki on D8-geometrisesti mahdollinen: a=(1,1), b=(1,3), c=(2,2), w=(3,2).
Nykyinen suoja: [A1] 61–82, 104, 146–148; [B1] 23–28, 65–68, 182–186, 212–236.

<a id="c2"></a>
## C2: askelrajaan pysähtyneen lähteen luvaton jatkaminen

Ketju `a → b → c → w`, kaikille sama globaali K=1:

| Lähde | Oma havaittu polku | Tila |
| --- | --- | --- |
| a | a,b | STEP_LIMIT |
| b | b,c | STEP_LIMIT |
| c | c,w | FIRST_WATER_CONTACT |

Havaittu S_obs(c)={b,c} ja S_obs(w)={c}; a ei ole havaittu kummassakaan.
Kanonisten reunojen unioni sisältää silti koko ketjun. Sen täydellinen
DAG-summa antaisi c:lle 3 ja w:lle 3, eli lainaisi b:n/c:n alapuolisia
havaintoja a:lle ja c:n havaintoa b:lle. Se on **eri tulostavoite**, ei (a):n
optimointi. Vain erikseen kokonaan havaittu scope voisi oikeuttaa (b):n luvun.
Jos lähteille sallittaisiin eri budjetit, sama ongelma korostuisi; yhteinen
budjettikaan ei poista sitä. Rajalla budjettia ei saa aloittaa uudelleen.
Nykyinen suoja: [A1] 47–54, 80–82, 123–129; [B1] 72–75;
arkistoitu konkreettinen 4 lähettäjäjäsenen / 2 ylittäjän tarkistus [B3] 83–87.

<a id="c3"></a>
## C3: sykli ei ole äärellinen valuma-aluekertymä

`a → b → a`. Rekurrenssit A(a)=1+A(b) ja A(b)=1+A(a) johtavat
A(a)=2+A(a): äärellistä ratkaisua ei ole. Havaittu joukko {a,b} kummassakin
solussa on auditoitava reittihavainto, ei ratkaistu A=2. Rajaviestit voivat
silti saada molemmat teknisen kuitin; se ei tee syklistä purkuyhteyttä.
Nykyinen suoja: [A1] 85–87, 125–133; [B1] 60, 192, 215;
aiempi rajasyklin koe [B3] 154–157. Uusi DAG-ydin hylkää syklin eikä poista reunaa.

<a id="c4"></a>
## C4: puuttuva naapuritiili

A omistaa a:n; a:n pointeri osoittaa B:n soluun b, mutta B:n ydin puuttuu.
A:n halo voi sisältää b:stä havainnon. Se ei anna B:n lähdeinventaaria,
omistajan suorittamaa vastaanottoa tai b:n jatkoa. Oikea lähdetase koskee vain
saatavilla olevan A:n lähteitä; siirto jää ratkaisemattomaksi. b:tä ei luoda
uudeksi lähteeksi, ulostuloksi tai nollatuonniksi. Puuttuvaa kuittia ei
muodosteta vastaanottajasolun koordinaatin perusteella.
Nykyinen suoja: [A2] 64–77, 87–89; erillinen vastaanotto [B1] 170–203, 243–246;
aiempi 7 saatavilla olevan lähteen / 4 ratkaisemattoman koe [B3] 129–134.

<a id="c5"></a>
## C5: tuntematon ulkoinen tuonti

Paikallinen verkko on `a → w`. Ulkopuolelta voi olla `x → a`, mutta x:n
aineistoa ei ole. Paikallinen laskettu osuus on 1 solu = 4 m². Todellinen
kokonaismäärä voisi olla 1, 2 tai paljon enemmän; ei ole näyttöä sen
valitsemiseen. `local=1, external=UNKNOWN, total=NA` säilyttää tiedon.
`total=local` asettaisi tuntemattoman tuonnin perusteetta nollaksi.
Nykyinen suoja: [A1] 58–60, 132, 145; [B1] 216–229, 246.
`KNOWN_ZERO_SYNTHETIC` on vanhan 02G:n erillinen testisopimus, ei realismin osoitus.

<a id="c6"></a>
## C6: saman viestin uudelleenlähetys

b:n oma lähdepanos on yksi. Lähde s saapuu viestillä m rajalta a→b.
Kahden toimitusyrityksen jälkeen S(b)={b,s}, ei {b,s,s}. Naivi `A(b)+=1`
jokaisesta toimituksesta antaisi 3. Sama looginen viesti tuottaa saman kuitin
ja saman tilan; muuttunut sisältö samalla ID:llä pysäyttää vastaanoton.
Kadonnut kuitti ei tee lähteestä uutta. Pelkkä samankaltainen numero tai
vastaanottajan olemassaolo ei korvaa viesti-/run-identiteettiä ja inbox-näyttöä.
Nykyinen suoja: [B1] 93–159, 170–179; aiemmat uusinta-/palautumistestit
[B3] 29–47, 106–152. Validointi tehdään ennen replay-palautusta: idempotenssi
ei tarkoita vakioaikaista uusintaa eikä kryptografista todennusta.

<a id="c7"></a>
## C7: tiilien riippuvuussykli ilman solujen sykliä

A omistaa sarakkeen 1 ja B sarakkeen 2. Solut
`a1=(1,1) → b1=(1,2) → a2=(2,1) → w=(3,1)` muodostavat DAG:n
(Whitebox-suunnat E=2, SW=16, S=8). Tiilien naapuruus on kuitenkin A→B→A.
Jos koko tiili supistetaan yhdeksi solmuksi, saadaan näennäinen sykli.
A:n yhtenäinen lopullinen summa ei voi olla sekä B:n edellytys että sen
tulos ilman solmukohtaista riippuvuuden erottelua. Tarvitaan solutason tai
todistetusti erillisten rajakomponenttien riippuvuudet, ei geografisen
tiilijärjestyksen oletusta. Tämä on tulevan streaming-/tiilisuunnittelun riski;
nykyinen lähdetoken kulkee yksittäisiä soluja ([B1] 55–80).

<a id="c8"></a>
## C8: numerotase voi peittää kadonneen lähteen

Paikallisia lähteitä ovat a ja b. Virheellinen päätepistetoteutus kirjaa a:n
kahdesti ja kadottaa b:n. Numeerinen lähtötase 2 ja loppusumma 2 täsmäävät,
mutta jäsenyydet eivät. Pelkkä taseluku tai A≤V-raja ei siis todista
kertalaskentaa. Tarvitaan DAG:n rakennetodistus sekä pienessä kokeessa
riippumaton lähde-ID-orakkeli. Nykyiset testit tarkistavat sekä joukot että
määrät ([A3] 59–82; [B3] 49–70), eivät pelkkää vihreää summaa.

<a id="c9"></a>
## C9: pakkaus ei saa täydentää puuttuvaa jäsenyyttä

Tarkka lähdejoukko on {1,3}. Sen korvaaminen yhdellä välillä [1,3] lisäisi
lähteen 2. Kaksi erillistä väliä [1,1] ja [3,3] tai täsmällinen bittijoukko
säilyttää tiedon, mutta sirpaleiset joukot voivat vaatia O(M) merkintää.
Pakattu esitys tarvitsee myös globaalin ID-kartan: kahden tiilen paikallinen
numero 1 ei itsessään tarkoita samaa lähdettä. Tämä on vaihtoehtoisen
esityksen vaatimus, ei nykykoodiin lisätty pakkausmenetelmä.
Esimerkki koskee kiinteää tunnusjärjestystä. Täydellisen funktionaalisen
DAG-metsän lähteet voi järjestää erilliseen alipuuindeksiin, jolloin täysi
yläpuolinen jäsenyys voidaan kuvata tiiviisti; indeksin oletukset eivät päde
automaattisesti sensuroituihin joukkoihin. Ks. [vaihtoehdot](alternatives_decision.md).

## Pinta-ala, kynnys ja tieteellinen tulkinta

Kolme lähdeyksikköä tarkoittaa 12 m² havaittua maapinta-alaa, ei virtaamaa.
9 999 solun reittiä/ensikontaktia ei poisteta 4 ha:n kynnysmetatiedolla.
10 000 solun kertymä voi olla täysin laskennallinen rinteiden yhtyminen eikä
todellinen uoma. Vesikontakti ei ratkaise järven uloslähtevää reittiä.
Riippumaton oja-/uomahavainto, sen kohdetunnus, aineistoversio ja todistusaste
tarvitaan erikseen; synteettinen PASS tai kuitti ei korvaa niitä.
Nykyiset erottelut: [A1] 136–145, 167–169; [B1] 224–249; [D1] 155–163.

`hydrological_validation=NOT_ASSESSED`
`channel_interpretation=NOT_ASSESSED`
`MODERATE=REVIEW_REQUIRED`
`NATIONAL=LOCKED`
