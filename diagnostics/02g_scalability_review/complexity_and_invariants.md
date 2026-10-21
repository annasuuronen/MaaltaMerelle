# Kustannusmalli ja tuloksen oikeellisuusehdot

Toteutusviitteiden SHA:t ja tiedostolinkit: [lähdetaulukko](README.md#sources).
Alla oleva kustannusmalli on koodin rakenteesta johdettu, **ei uusi mittaus**.
Nykyiset 1 000/121 ruudukkopaikan rajat säilyvät; asymptoottinen tarkastelu
kuvaa menetelmän kasvutekijöitä eikä lupaa rajojen poistamiseen.

## Muuttujat

| Merkintä | Määritelmä |
| --- | --- |
| V | Saatavilla olevien ydinten yksilölliset kelvolliset maasolut; jokainen on yksi lähde |
| E | Näiden solujen erilliset havaitut lähtevät ruudukon sisäiset D8-reunat; E ≤ V. Reittirivien määrä ei ole E |
| P | Lähdepolkujen solukäyntien yhteispituus, mukaan lukien lähtö/terminaali ja mahdollinen sulkeva uudelleenkäynti |
| M | Tallennetut yksilölliset (vastaanotettu maa- tai ensivesisolu, lähde)-jäsenyydet; M ≤ P. Vesijäsenyyksiä yhteensä enintään V |
| B | Erilliset lähdekohtaiset rajasiirtymäviestit, ei vain geometriset saumat. Merkitään erillisiä saumareunoja b:llä; b ≤ E ja B ≤ P − V |
| Q | Kaikkien B viestin sisältämien polkuprefiksien yhteispituus; koodivektorit lisäävät saman suuruusluokan. Sama historia voi esiintyä monessa viestissä |
| K, l_s | Lähteen globaali askelraja ja sen toteutuneen polun pituus; P = Σ l_s ≤ V(K+1), Q ≤ B(K+1) |
| N, H, T | Koko ilmoitetun ruudukon paikat, aktoreiden havaintorivit halo-kopioineen yhteensä ja tiilien määrä. N ei yleensä ole V |
| D, Q_attempt | Tunnuksen pituus sekä kaikkien toimitusyritysten, myös uusintojen, tarkastettujen historioiden yhteispituus |

Merkkijonojen kopiointi/serialisointi lisää D-riippuvuuden; alla olevat
oliomäärät käyttävät yhtä tunnusviitettä yksikkönä. B:n erottaminen b:stä on
välttämätöntä: 27 paikan esimerkissä kaksi saumareunaa kuljettaa 4+8=12
lähdekohtaista siirtoa ([A5] 4–43; [B3] 194–209). Tämä ei tarkoita 12 uutta lähdettä.

## Todellinen säilytettävä rakenne

**02G / PR #25.** `g02_observe` rakentaa N-paikkaisen lukuindeksin ja yhden
reitin jokaiselle maasolulle ([A1] 32–45). `trace_land_d8_route` säilyttää
havainto-, polku- ja siirtymätaulukot ([R1] 48–113), suuruusluokka P.
`g02_accumulate` kasvattaa lähdelistoja solukohtaisesti, vesilistoja erikseen
ja lisäksi lähdeledgerin sekä lähdekohtaiset siirtymärivit ([A1] 65–108).
Looginen säilytettävä tila on O(N + V + P + M), jo ennen tiilikirjanpitoa.
Tiiliversio lisää halo-/ydinhavainnot H, koko ruudukon omistajuuden N,
saumareunat b sekä B siirtojäsenyyttä ([A2] 11–23, 30–89).
Se kokoaa ytimet keskitetysti; sen kuitit ovat johdettuja ([A2] 46–51, 64–77).

**02G.2 / PR #28.** `g2r_actor` säilyttää omat ydin-/halohavainnot,
`source_sets`-, `water_sets`-, inbox-, outbox-, confirmations- ja terminals-listat
([B1] 17–28). Terminaaleissa on täydellinen lähteen polku; jokaiseen
lähetysviestiin tulee koko siihenastinen polku ja koodit ([B1] 42–52).
Yksilölliset jäsenyydet vievät edelleen O(M) ja erilliset viestiprefiksit O(Q).
Terminaalipolut lisäävät enintään O(P), ledgerit O(V+B), havaintorivit O(H).
Tämä on polkujen/lähteiden protokolla, ei vain O(V+E)-kokoinen lukumäärägraafi.

Lisäksi **jokainen viesti ja kuitti sisältää `contract`-olion**, jossa on koko
ruudukon `owners`-vektori N tunnuksineen ja `layout` T tiilelle
([B1] 14–15, 44–47, 138–141; [A2] 11–23). Samassa R-prosessissa yhteisiä
olioita voidaan jakaa. Erillisissä prosesseissa tai erikseen serialisoiduissa
viesteissä samaa jakamista ei voi olettaa: sopimuskopiot voivat lisätä
O((T+B)(N+T)) yksikön tallennus-/siirtokuorman. Historiat Q eivät kata tätä.
Kyse on mahdollisesta materiaalisoidusta kuormasta, ei todistetusta saman
R-prosessin RSS-kertoimesta.

R:n listat, vektorien otsakkeet, data.frame-rivit, nimet, merkkijonoviitteet,
allokointivara ja copy-on-modify-väliaikaiset kopiot lisäävät kustannusta.
Internoidut merkkijonot voivat jakaa merkkisisältöä, mutta M viitettä tai Q
polkuindeksiä eivät katoa. `object.size` yhdestä tulosoliosta ei mittaa näitä
kaikkia eikä prosessiryhmää. Kiinteää tavua/lähde-arviota ei ole mitattu.

## Aikavaativuuden konkreettiset kasvutekijät

Jo ideaalinen indeksoitu, amortisoidusti kasvava toteutus joutuu tuottamaan
säilytettävät P-, M-, B- ja Q-tiedot. Nykykoodi sisältää lisäksi seuraavat
ei-lineaariset operaatiot. Nämä ovat rakenteellisia kustannustermejä, eivät
tarkka konekohtainen kokonaisajan yhtälö.

| Kohta | Koodiperusteinen kustannus / riski |
| --- | --- |
| Per-source-jäljitys | Kasvavan `seen`-historian jäsenyystarkistus ja vektorien `c()`-kasvatus voivat käyttää Σ l_s² työtä ([R2] 77–81; [R1] 50–53; [B1] 60, 75) |
| Lähdelistan kasvatus | Solussa v lopullinen listapituus m_v: peräkkäiset `c()` / `union()` käsittelevät kasvavia listoja, pahimmillaan Σ_v m_v² viitetyötä; nimetyt listahaut eivät ole luvattu O(1)-indeksi ([A1] 82, 92; [B1] 65, 68) |
| Reittien arvotarkistus | `match(..., cells$cell_uid)` tehdään jokaiselle lähteelle; kohteen skannaus/uusi hakurakenne voi lisätä VN-työtä ([A1] 76–81) |
| Kanonisten reunojen QA | **Jokaiselle E reunalle muodostetaan N ruudukkopaikan UID-vektori uudelleen**: EN-mittakaavan tunnustyö ([A1] 111–120) |
| Rekurrenssin QA | Jokainen V solun tarkistus suodattaa koko reunataulukon ja tarkistaa lähdejäsenyyksiä; ei topologinen yksi läpikäynti, vaan VE- ja hakurakenteista riippuva lisätyö ([A1] 153–157) |
| Vanha tiiliryhmittely | Jokainen b saumareuna suodattaa lähdekohtaisia rajasiirtymärivejä uudelleen: bB-työtermi ([A2] 55–70) |
| Viestin validointi | Polku käydään läpi; havaintohaku kohdistuu aktorin H_t riveihin. Lisäksi aiempi inbox käydään läpi jokaiselle viestille ja saman lähteen prefiksejä verrataan ([B1] 112–125). Mahdollisia termejä ovat Σ q_m H_t, Σ B_t² ja saman lähteen historiavertailut, karkeasti enintään B²K tällä osuudella |
| Uusinnat | `g2r_receive` validoi **ennen** inboxin replay-haaraa ([B1] 129–135). Tilapäivitys on idempotentti, mutta aika ei ole O(1) per uusinta: Q_attempt voi kasvaa ilman uusia lähdejäsenyyksiä |
| Lopullinen koonti | Viestien/kuittien täysi vertailu ja nimetyt haut, lähdekohtainen `match`, ratkaisemattoman lähteen koko outbox-suodatus ja jäsenjoukkojen lajittelu ([B1] 170–215). Mukana voi olla V²-, VB-, B²- sekä Σ m_v log m_v -työtä |

Vakiokokoisella K:lla M ja P voivat olla O(VK), mutta se ei tee yllä olevista
nimetyistä hauista, QA-silmukoista tai sopimusten siirrosta O(V):tä.
Q_attempt ei rajoitu B:hen, ellei toimitusyrityksiä erikseen rajata.
Nykyisen testiharnessin toimitusraja on testin turvaraja, ei verkkopalvelu.

## I/O ja tilan pysyvyys

Nämä Base R -funktiot eivät lue rasteria tai toteuta verkkosiirtoa. Arkistoitu
erillisprosessitesti lukee/kirjoittaa RDS:n, jossa on vastaanottajan tila ja
yksi viesti ([B3] 92–104; [B4] 4–11). Se ei mittaa viestipalvelun I/O:ta.
Jos nykyiset viestit serialisoidaan erikseen, historiat vaativat O(Q) ja
toistuvat koko sopimukset voivat vaatia O(B(N+T)) siirtoyksikköä. Kuittien
sopimukset lisäävät saman kertaluokan. Täydet aktoritilasnapshotit jokaisen
viestin jälkeen voivat kirjoittaa kertyneet M/P/Q/ledgerit monta kertaa;
I/O ei silloin ole vain lopullisen tuloksen koko. Uusinnat lisäävät I/O:ta,
vaikka tilan deduplikointi onnistuu. Tavumääriä tai levy-I/O-nopeutta ei tässä mitata.

## Verkon muodon merkitys

| Muoto | Johtopäätös (matemaattinen, ei uusi koe) |
| --- | --- |
| Ketju, K riittää koko pituuteen | V maasolua ja lopuksi vesi: M_land = V(V+1)/2, M_water = V, P = M_land+V. Kaikki jäsenet materiaalisoiva taulukko vaatii neliöllisen tallennustilan. Kasvavien listojen työtä voi olla Θ(V³) |
| Suppilo / pitkä yhteinen runko | U yläpuolista lähdettä ja t havaittua yhteistä runkosolua tuottavat jo Ut jäsenyyttä, vaikka yhteisiä reunatyyppejä on vain t:n verran. Yhtyminen ei poista lähdeidentiteettien kustannusta |
| Useat tulouomat | Haarat ovat useita **tulevia** reittejä; D8 ei jakaudu kahteen lähtevään reunaan. Kustannus riippuu Σ l_s:stä ja yhteisestä rungosta, ei pelkästä tulouomien määrästä. Suora solun sisääntuloaste on enintään kahdeksan |
| Sykli | Uudelleenkäynti pysäyttää lähteen, mutta monet lähteet voivat ensin kiertää pitkän osan syklistä. Havaitut jäsenet eivät ratkaise äärellistä A:ta; syklisolujen A jää NA:ksi ([A1] 85–87, 125–133; [B1] 60, 192, 215) |
| Puuttuva tiili | Päätepiste, pending-viestit ja tuntematon tuonti säilyvät. Puuttuvien lähteiden lukumäärää ei tunneta; ledgerit eivät vapaudu vain siksi, että työ pysähtyi ([B1] 193–203, 239–246) |
| STEP_LIMIT | P ≤ V(K+1), mutta havainto kattaa vain lähdekohtaiset prefiksit. Pieni P ei osoita koko reitin jatkuvuutta eikä lupaa käyttää muiden lähteiden jatkoja ([A1] 47–54; [B1] 72–75) |

Usean rajan ylityksissä sama prefiksi toistuu: yhdellä lähteellä, jonka polku
ylittää rajan toistuvasti, Σ prefiksipituudet voi olla Θ(l_s²). Koko verkossa
Q voi siten olla paljon P:tä suurempi. Esimerkiksi vierekkäisten ydinten
välinen siksak voi olla solutasolla DAG, vaikka tiilien suunnattu naapuruus
kiertää; ks. [C7](counterexamples.md#c7).

## Neljä eri tulostavoitetta

| Tavoite | Merkitys | Voiko pelkkä O(V+E)-topologinen summa korvata sen? |
| --- | --- | --- |
| (a) Havaitut paikalliset lähdejäsenyydet ja niiden määrät | S_obs(v) = lähteet, joiden oma havaittu polku sisältää v:n. Kertymä voi olla sensuroitu | **Ei pelkällä rekurrenssilla 1+Σ.** Reunojen unioni jatkaisi STEP_LIMIT-lähteitä. Kaikkien jäsenien materialisointi tarvitsee Ω(M) tallennustilaa ja niiden luetteleminen Ω(M) työtä/I/O:ta; epäsuora indeksi on eri tulostavoite |
| (b) Täysin havaitun paikallisen DAG:n numeeriset summat | Kaikki määritellyt paikalliset lähteet, jokaisen käytetyn reunan havainto ja täydelliset paikalliset päätepisteet tunnetaan | **Kyllä**, kun yksilöllinen omistajuus, lähtevä aste ≤ 1, DAG, sopiva numeerinen esitys ja O(1)-indeksoitu graafi on varmistettu. Ei tuota jäsenyyslistoja |
| (c) Tiilirajan ylittävä mahdollinen kertymä | Vahvistetut paikalliset panokset ja mahdollinen vielä saapuva panos erikseen | Vain tunnettu **paikallinen** osa ehdollisesti. Saamattomat/epävarmat tuonnit ja kuittaamattomat tapahtumat eivät muutu nollaksi. Pelkkä vastaanottokuitti ei sulje riippuvuuksia |
| (d) Todellinen koko valuma-alueen kertymä | Kaikki yläpuolinen alue ja kelvolliset yhteydet tunnetaan | Ei nykyisestä näytöstä. Ulkoisen tuonnin tai aineiston puuttuessa `NA/UNKNOWN`; laskentatavan vaihto ei korjaa havaintojen puutetta |

(b):n lineaarisuus koskee graafialgoritmia; raakaruudukon N-paikkainen
lukeminen, ID-indeksin rakentaminen, auditointijäljet ja mahdollinen lajittelu
on laskettava erikseen. Se ei ole koko nykyisen R-putken aikavaatimus.
Nykyiset kokonaistuloskentät jättävät tuonnin tuntemattomaksi ([A1] 132, 145;
[B1] 216–246). Tätä eroa ei saa hävittää uuden kentän nimeämisellä.

Tarkennus (a):n **numeeriselle** osalle: lineaarinen laskenta ei ole
periaatteessa mahdotonta, mutta se vaatii enemmän kuin reunojen unionin.
Jos yhteinen graafi on varmennettu DAG ja jokaisesta lähteestä tunnetaan
täsmällinen havaittu päätepiste oikeine jäsenyys-/vesisemantiikkoineen,
lähdekohtaiset katkaisut voidaan laskea erillisiksi tapahtumiksi. Merkitään
maasolu v:ssä päättyvien lähteiden määrää C(v):llä. Ehdollinen kuljetus olisi
maasolulle `A_obs(v)=1+Σ F(parent)`, `F(v)=A_obs(v)−C(v)`: päättyviä lähteitä
ei siirretä eteenpäin. Ensivesi saa vain Σ F(parent), ilman omaa lähdeyksikköä.
Päätepisteen pitää todella kuulua kyseisen lähteen yksikäsitteiseen
polkuun; pelkkä vapaasti ilmoitettu C(v) ei riitä. [C2](counterexamples.md#c2):ssa
C(b)=1 ja C(c)=1 antavat w:lle oikein yhden lähteen.

Tämä on matemaattinen mahdollisuus, **ei nykyinen toteutus eikä tämän päätöksen
seuraava toteutettava muutos**. Se tarvitsee uuden todistuksen havaituille
prefikseille, päätepisteiden provenienssille, NoData-/puuttuvan omistajan
rajoille ja vesikontaktille. Syklit eivät täytä DAG-oletusta. Nykyinen
terminaali-UID voi viitata myös NoData- tai puuttuvaan kohteeseen ([B1] 193–203),
joten se ei sellaisenaan ole katkaisusolun jäsenyystodiste. Tulos ei myöskään
anna materiaalisoituja lähdejäsenyyksiä O(V+E)-ajassa. Valittu ensimmäinen
lukumääräydin rajautuu siksi (b):hen.

## Kertalaskennan todistus ja rajat

Täydellisessä DAG:ssa kukin maasolu aloittaa yhdellä panoksella. Jos kahdella
v:n suoralla vanhemmalla olisi sama lähde, sen yksikäsitteisen lähtevän polun
pitäisi haarautua tai palata sykliin päästäkseen molempiin ennen v:tä.
Molemmat on suljettu pois. Vanhempien lähdejoukot ovat siis erilliset, ja
topologisessa järjestyksessä `A(v)=1+Σ A(parent)` on induktiolla oikea.
Vesi saa saapuvat panokset mutta ei uutta omaa maasolu-yksikköä eikä jatka
ensikontaktilaskentaa uloslähtevällä pointerillaan.

Todistus **ei koske** lähdekohtaisesti sensuroitujen jälkien unionia,
toistettuja reunarivejä, päällekkäisiä omistajia tai summia, joiden
yläpuoliset lähdealueet voivat limittyä. Kuittaus todistaa vain oman
vastaanottotapahtuman. Nykyinen erillinen vastaanotto tarkistaa paikallisen
ydin-/halon, ei kaikkea vierasta historiaa ([B1] 115–119).

Lähteiden päätepistejako `V = ensivesi + ratkaisemattomat` on tarpeellinen
kirjanpitoehto, ei globaali PASS. Kaikkien solmujen A-arvojen summaa ei verrata
V:hen: sama lähde kuuluu tarkoituksella monen alapuolisen solun paikalliseen
kertymään. Lukumäärätase yksin voi myös peittää yhden lähteen katoamisen ja
toisen tuplauksen ([C8](counterexamples.md#c8)). Pieni riippumaton ID-orakkeli,
rakenteelliset ehdot ja epävarmuudet tarvitaan rinnalle.

Yksi lähde = 4 m²; 4 ha = 10 000 solun kynnysmetatieto. Kumpikaan ei ole
virtaama eikä osoitus todellisesta ojasta/uomasta. Kaikki neljä tieteellistä
tilalukitusta säilyvät [README:n](README.md) mukaisina.
