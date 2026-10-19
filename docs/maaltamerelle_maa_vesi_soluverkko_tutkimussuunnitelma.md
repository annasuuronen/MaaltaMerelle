# MaaltaMerelle: maa–vesi-soluverkon tutkimussuunnitelma

19.10.2026. **Suunnitelma tieteelliseen katselmointiin.** Tämä dokumentti ei
osoita alla ehdotettujen menetelmien toteutusta tai hyväksyntää. Muutos lisää
vain tämän tiedoston erilliseen suunnitteluhaaraan, jonka lähtöcommit on
`baseline-no-structures`-haaran `7050b582edab3195669529f366b4f5a2915488c6`.
LOW:n ja MODERATE:n kehityshaaroja ei yhdistetä tähän muutokseen.

**MODERATE=REVIEW_REQUIRED; NATIONAL=LOCKED.** Nykyinen 02D.5-laatuportti,
TEST_SULKU_11-odotukset, 2 m ruudukko, EPSG:3067, Whitebox-D8-koodaus ja
4 ha uomakynnys säilyvät. Tämä suunnitelma ei valtuuta seuraavan tehtävän
ohjelmointia, rasterimuutoksia tai uusia CSC-ajoja.

## 1. Tavoite ja tutkimuksen kohde

Rakennetaan mahdollisimman tarkka **maa-alueiden solukohtainen pintavalunnan
virtausverkko ensimmäiseen määriteltyyn vesistökontaktiin asti**. Jokaiselle
mallin lähtöjoukkoon kuuluvalle maasolulle pitää pystyä esittämään:

- lähtösolun yksikäsitteinen tunniste ja sijainti;
- käytetyn pinnan ja D8:n määräämä soluketju, myös sen epävarmat kohdat;
- ensimmäinen vastaanottava vesisolu, sen luokka,
  koordinaatit ja tunnistettu vesistökohde;
- yläpuolinen kertymä sekä jatkumisen ja taseen tarkistukset;
- nimenomainen selvittämätön päätepiste, jos vastaanottajaa ei voida osoittaa.

Ensimmäisen vesistökontaktin jälkeen järven tai joen sisäinen jatkoreititys
kuuluu erilliseen kytkentään olemassa olevaan vesistöverkkoon. Maalta tulevan
veden vastaanottaja ja vesistöstä myöhemmin poistuvan veden purkupiste ovat
eri tutkimuskysymyksiä. Uutta hydrodynaamista järvi- tai jokimallia ei tarvita
tämän tavoitteen toteuttamiseksi.

Kahden metrin solu on mallin erotuskyky, ei lupaus korkeuden tai virtaussuunnan
absoluuttisesta oikeellisuudesta. D8 on yhden seuraajan mallioletus: se ei
yksin kuvaa tasanteen hajautunutta virtausta, pohjavettä tai rakenteen läpi
kulkevaa yhteyttä. Näiden rajoitusten pitää näkyä tulosten tulkinnassa.

## 2. Tarkistettu kehitystila ja näytön alkuperä

Lähdekoodi ja GitHub-tehtävät tarkistettiin tätä suunnitelmaa varten.
CSC-rastereita tai työn 2369720 raporttipakettia ei luettu tässä ympäristössä.
Erota toisistaan tarkistettu koodiominaisuus, dokumentoitu aiempi ajohavainto,
käyttäjän toimittama uusi ajotulos ja tuleva menetelmä.

| Kokonaisuus | Tarkistettu lähde | Nykyinen näyttö ja raja |
| --- | --- | --- |
| Baseline | `7050b582edab3195669529f366b4f5a2915488c6` [S1] | 02D.8-evidenssi, 02E-ehdokkaat ja 02F-reittidiagnostiikka ovat koodissa. Lopullinen koko maan solukohtainen verkko ei ole valmis. |
| MODERATE, draft PR #7 | `a3c42be333468e25c731faa3fd63f9687ed83978` [S2] | Erillistä luokittelua ja rajattua tutkimusta; tuotannon 02D.5-ongelma ei ole ratkaistu. |
| LOW, draft PR #12 | `cd9612aa1cb4dd39bc6b33d825302202b28ef09e` [S3] | Todellisiin Roihu-havaintoihin sidottua diagnostiikkaa ja vaihtoehtoarvioita; ei hyväksyttyä D8-korjausta tai outlet-valintaa. |
| LOW:n päätepisteet | Issue #10 ja PR #11:n tutkimuslinja [S4] | Seitsemän tunnettua nollapäätesolua, joita ei saa tulkita koko verkon virheiden täydelliseksi inventaarioksi. |
| SYKEn lähteiköt | Avoin issue #9 [S5] | Validointiaineiston käyttösuunnitelma; aineiston hankintaa tai vertailun valmistumista ei osoiteta tällä dokumentilla. |
| MODERATE:n näyttöportti | Avoin issue #13 [S6] | Erillinen tekninen valmiusluokittelija on PR #7:ssä. Tekninen johdonmukaisuus ei ole hydrologinen hyväksyntä. |
| 02G, kertymä ja tiiligraafi | Tarkistetut baseline-, PR #7- ja PR #12-puut | Näistä puista ei löytynyt 02G-toteutusta tai sen testejä. Siirtomuistion mainitsemia erillisiä prototyyppejä ei väitetä integroiduiksi tai hyväksytyiksi. |

### 2.1 Nykyisten 02B–02F-vaiheiden kattavuus

02B tallentaa **suorat vierekkäiset maa→vesi-D8-liittymät**. Se ei vielä
anna jokaiselle yläpuoliselle maasolulle lopullista vastaanottajaa. 02C:n
nollapointeritaulukko on vesistönaapuruuden ehdokasjoukko, ei kaikkien
nollapointerien inventaario.

02E säilyttää hyväksyttävään evidenssiluokkaan päässeiden spill-ryhmien
rinnakkaiset rantareunat; `outlet_selection=UNASSIGNED`. Ehdokasmaskit eivät
ole lopullinen reitityspinta. 02F alkaa näiden ehdokkaiden vastaanottajista,
ei kaikista maasoluista. Se seuraa olemassa olevaa LAND_WATER-D8:aa ensimmäiseen
vesikontaktiin tai selvään päättymisluokkaan asti. Se ei jatka vesistön läpi.
Reitin avain sisältää vastaanottajan ja lähtöjärven; CSV:n järvikenttä on
`origin_lake_objectid`.

Tästä seuraa olennainen kattavuusraja: 02E/02F:n tyhjä ehdokasjoukko voi
läpäistä teknisen luokittelu-QA:n, mutta ei osoita järven purkuyhteyden
puuttumista eikä maalta järveen tulevien yhteyksien puuttumista. Nykyisiä
diagnooseja ei nimetä jälkikäteen kaikkien maasolujen vastaanotinkartaksi.

### 2.2 LOW:n säilytettävä tutkimusnäyttö

PR #12:n tutkimusraporttien ja issue #10:n mukaan:

- 101 erillistä 02F-vastaanottaja/lähtöjärvi-reittiä: 41
  `D8_ZERO_INTERIOR`, 34 `REACHES_RIVER_AREA`, 5 `REACHES_RIVER_LINE`
  ja 21 `RETURNS_TO_ORIGIN_LAKE`. Ehdokasreunoja on 229. Nämä ovat eri nimittäjiä.
- 41 nollaan päättyvää reittiä yhtyy seitsemään erilliseen päätesoluun.
  Niiden yläpuolista maa-aluetta tai kaikkien maasolujen ensikontakteja
  ei päätellä näistä reittimääristä.
- Dokumentoitu Slurm-työ 2345102 (`COMPLETED`, exit 0:0) inventoi LOW:n:
  1 481 ei-vesialueen D8-nollasolua, 719 sisäistä ja 641 sisäistä
  järvenviereistä nollasolua. Järvi→maa-reunoista 1 273/2 998 johti
  välittömästi nollaan, 535 eri vastaanottajaan. 42,46 % on tämän
  **välittömän reunajoukon** osuus, ei verkon tai maa-alan virheprosentti.
- Järven 1847 kaikki 88 tarkasteltua nollavastaanottajaa sijoittuivat
  MML 2025:n järvipolygonin sisään mutta RANTA10:n ulkopuolelle.
  Paikallinen RANTA10-rasterointi vastasi `touches=TRUE`-sääntöä.
  Kontrollijärvellä 1898 vastaava MML-osuma oli 0/26. Tämä erottaa
  lähdegeometrian eron rasterointisäännön virheestä; kumpaakaan rantaa
  ei julisteta tämän perusteella oikeaksi.
- Järvellä 1847 oli 20 02E-spill-ryhmää, mutta ei mukaan otettuja
  ehdokasreunoja tai 02F-reittejä. Kontrollilla 1898 oli yksi mukaan
  otettu ryhmä, viisi reunaa ja kolme jokialueelle päättyvää reittiä.
  Molemmilla outlet-valinta säilyi `UNASSIGNED`.

PR #12:n README sisältää myös aikaisempia odottaa-ajoa-osioita. Tässä
tilakuvassa jo toteutettu työ erotetaan niistä saman commitin myöhempien
`SCIENTIFIC_OPTIONS.md`- ja `README_MML_gap.md`-ajokirjausten perusteella.
Jo tehtyä LOW-skannausta tai geometriavertailua ei tilata uudelleen.

### 2.3 MODERATE:n vanha ja uusi näyttö

Aiempi dokumentoitu aineisto [S2, S7]: 158 järveä; 52 positiivisen
rantakynnyksen järveä ilman havaittuja STORAGE-korotussoluja ja
korotuskomponentteja. Alimpien rantakynnysten 162 reunasta 159 D8-reittiä
palasi lähtöjärveen ja kolme päättyi nollapointeriin järvellä 204104.
02D.5 pysähtyi ehtoon `all(spill_lakes$n_depression_components >= 1)`.
Positiivinen `spill_raise_m` mittaa rantakynnystä, ei toteutunutta korotusta.

**Uusi käyttäjän toimittama todellinen CSC-tulos:** Slurm 2369720,
commit `a3c42be333468e25c731faa3fd63f9687ed83978`, `COMPLETED`, exit 0:0,
kesto 3 min 50 s, R 4.6.1 ja terra 1.9.34. Kaikki 49 sisäjärveä saivat
teknisen `OBSERVED`-tilan. Raportoitiin 45
`LOWER_NEIGHBOUR_WITNESS_IN_ISOLATED_SEARCH`-tulosta ja neljä
`CENSORED_LOCAL_SEARCH`-järveä: **203477, 203714, 203857 ja 205128**.
Näillä neljällä `visited_cells=2000`, `visit_cap_reached=TRUE` ja
`search_touched_window_edge=FALSE`; alempaa naapuria ei havaittu.

Raportti on käyttäjän mukaan `fill_probe_45dd5l3l`. Sen yksittäisiä CSV-rivejä,
arkistotiivistettä tai komponenttikohtaista 45/4-jakaumaa ei varmennettu tässä.
Koetin vertaa naapuria käsiteltyyn soluun, ei järvitasoon, eikä seuraa D8:aa.
Sen järvi-ID-maskiosat eivät ole STORAGE-korotuskomponentteja. Neljä
rajautumista eivät osoita suljettuja painanteita. `HISTORICAL_PROVENANCE=INCOMPLETE`
ja `HYDROLOGICAL_APPROVAL=false` säilyvät. Alkuperäisen Whitebox-täytön
komento-, binääri-, exit- ja välimuistisidonta jää avoimeksi; aiempi
aikakatkaistu täyttöyritys ei ole onnistunut replikaatio.

Jatkuvuusmuistion `docs/maaltamerelle_tutkimustilanne_20261019.md` [S7]
aiempi tieto vielä ajamattomasta 49 järven kokeesta on tätä uutta
käyttäjän ajonäyttöä vanhempi. Muistio säilytetään historiallisena.

## 3. Maa–vesi-tavoitteen vaikutus 02D–02G:n painotukseen

| Vaihe | Säilyvä tehtävä | Painotus uudessa tutkimusrajauksessa |
| --- | --- | --- |
| 02D | Rantakynnykset, korotuskomponentit ja spill/escape-evidenssi | Järvestä poistumisen epävarmuus erotetaan maalta ensimmäiseen veteen saapumisen epävarmuudesta. Kaikki löydökset ja 02D.5-portti säilyvät. |
| 02E | Kaikkien kelvollisten rinnakkaisehdokkaiden säilyttäminen | Vesistöverkon jatkokytkennän evidenssiä; ehdokkaan puuttuminen ei sulje pois maalta saapuvaa kontaktia. Ei outlet-valintaa. |
| 02F | Ehdokasvastaanottajien D8-päätepisteet | Nykyisiä terminaaliluokkia ja jäljityksen periaatteita voidaan uusiokäyttää. Kattavuus pitää laajentaa erikseen hyväksyttävänä tutkimuksena maasoluihin. |
| 02G / myöhempi vaihe | Tarkistetuissa puissa ei toteutusta | Solukohtainen vastaanotinkartta, kertymä ja tiiligraafi ovat suunniteltavia toimituksia. Niitä ei nimetä valmiiksi 02G-menetelmäksi. |

Ensikontaktin havaintograafissa vesi käsitellään päätepisteenä. Kun
**maasolujen seuraajat ja vesimaski pysyvät samoina**, pelkkä vesisolujen
uloslähtevien pointerien muutos ei saa muuttaa maasolujen ensimmäistä
vesikontaktia. Tämä on suunniteltu regressioinvariantti.

Riippumattomuus ei koske syötepinnan valmistelua: LAND_WATER yhdistää
täytettyä maapintaa ja järvikorkeuksia, ja nykyinen D8 lasketaan siitä.
Rantamaski, järvikorkeus, LAND_FILL ja niiden provenienssi voivat vaikuttaa
maan reititykseen. LOW:n vääräksi epäilty maa/vesiraja tai ennen kontaktia
oleva maapainanne on suoraan tämän hankkeen tavoitteen kannalta olennainen.

MODERATE:n järven sisäinen purkuepävarmuus ei yksin todista, että maalta
oikeaan järveen päättyvä reitti olisi väärä. Se estää silti kyseisen
jatkokytkennän hyväksynnän. **Nykyinen tuotantoketju jää MODERATE:ssa
02D.5-portille.** Erillinen ensikontaktin tutkimus ei anna lupaa ajaa
tuotantoketjua portin ohi tai nimetä koko baselinea hyväksytyksi.

## 4. Menetelmävaiheet ja näyttöportit

Riippuvuudet: A:n ruudukko- ja pointerisopimus sekä B:n vesikohdemäärittely
tarvitaan solukohtaiseen ensikontaktiin. C käyttää niiden yhteistä graafia.
D:n tunniste- ja reunasopimus suunnitellaan varhain ja sen toiminta
todennetaan C:n kanssa ennen alueiden yhdistämistä. E käyttää B:n
vastaanottajia ja C–D:n varmennettua kertymää. F kulkee kaikkien vaiheiden
rinnalla; lopullista hydrologista hyväksyntää ei siirretä pelkän CI:n varaan.

### A — Maa-alueiden solukohtainen reititys

Kiinnitetään DEM:n versio, korkeusjärjestelmä, ruudukon origo, resoluutio,
NoData, maa/vesimaski, pinnan käsittelyhistoria ja D8-rasterin identiteetti.
Varmennetaan Whitebox-koodin purku oikeaksi 8-naapurisiirtymäksi sekä
ortogonaalisen ja diagonaalisen etäisyyden käsittely. Paikallista
jyrkimmän laskun tarkistusta arvioidaan juuri pointerin lähdepinnalla,
ei toisella täyttöpinnalla.

Painanteet, tasanteet, nollat, virheelliset pointerit, syklit ja
vedenjakajan epävarmat suunnat saavat erilliset syyt. Kelvoton tai epävarma
suunta ei muutu keksityksi D8-reunaksi. Korkeusmallin epävarmuuden kanssa
yhteensopiva lähes tasainen tapaus ei ole sama kuin ohjelmointivirhe.

**Näyttö:** nykyisten rajattujen D8-ytimien ja testien uusiokäyttö,
pienten tunnettujen topologioiden tarkistukset sekä perustellut todelliset
vertailukohteet. Ratkaistuksi merkityn reunan pitää johtaa täsmälleen
dekoodattuun naapuriin, ja jokainen poikkeama säilytetään. Uusi koko
LOW-/MODERATE-skannaus edellyttää muuttunutta tutkimuskysymystä ja erillistä lupaa.

### B — Maa–vesi-rajapinta ja ensimmäinen vastaanottaja

Määritellään lähdeaineistoon sidottu vesiluokitus: järvi, jokialue,
uomaviiva ja mahdollinen erikseen hyväksyttävä muu vesikohde. Tarkistetaan
vektorin ja rasterin rajaus, rasterointisääntö, ajankohta ja päällekkäiset
kohteet. Olemassa olevaa maskia ei vaihdeta automaattisesti MML-geometriaan.

Suunniteltu solukohtainen tulossopimus sisältää lähtösolun globaalin ID:n,
viimeisen maasolun ja ensimmäisen vesisolun ID:t, rivin/sarakkeen,
EPSG:3067-keskipisteet, vesiluokan, vesistökohteen tunnuksen ja lähteen,
reittitilan sekä epävarmuuden perusteen. Solureuna ja vektorirannan leikkaus
ovat eri sijaintitietoja; niitä ei korvata toisillaan huomaamatta.

Nykyinen järvi-ID ja pelkkä jokialue-/uomaviivamaskin luokkakoodi eivät ole
sama tunnistesopimus. Jos joelle ei ole varmennettua yksilöllistä
lähdekohdetunnusta, kontakti voidaan havaita mutta vastaanottajan ID jää
eksplisiittisesti tuntemattomaksi. Tunnusta tai lähimpään uomaan napsautusta
ei keksitä. Usean kohteen päällekkäisyys säilytetään selvitettävänä tapauksena.

**Näyttö:** 02B:n vierekkäiset liittymät vertailuksi, 02F:n päättymissääntöjen
uusiokäyttö ja LOW:n rajavertailut. Kukin lähdesolu saa yhden ensimmäisen
kontaktin tai yhden selvittämättömän terminaalin. Veteen saapumisen jälkeen
ei vaadita järven sisäistä D8-jatkoa tässä havaintotuotteessa.
Vesiulosmenojen muuttumattomuusinvariantti testataan erikseen.

### C — Virtauskertymä ja jatkuvuus

Sovitaan yksikkö, lähtösolun sisällyttäminen kertymään ja pinta-alan laskenta.
Suunnitellussa vertailusopimuksessa jokainen kelvollinen maasolu tuottaa
yhden yksikön, joka vastaa 2 m ruudukossa 4 m²:ä. Syklittömässä maagraafissa:

```text
A(v) = 1 + summa A(u), kun u:n maaseuraaja on v
vesikontaktin vastaanottama määrä = sinne saapuvien maakertymien summa
```

Vesisolujen omaa pinta-alaa ei lisätä maa-alueiden tuloon. Kukin lähdesolu
kirjataan kerran vesikontaktiin, selvittämättömään terminaaliin tai
varmennettuun ulkoiseen vientiin. Paikallisessa tiilitaseessa lisätään
varmennetut tuonnit. Syklien ja muiden ratkaisemattomien terminaalien
yläpuolinen lähdejoukko jää näkyviin; sitä ei hävitetä eikä sille lasketa
ääretöntä tai keinotekoista läpivirtausta.

**Näyttö:** kokonaislukuisen solutaseen täsmällinen yhtälö, paikalliset
kertymärekursiot ja riippumaton pienen verkon rekonstruktio. Yhteenlaskettua
solupinta-alaa ei kutsuta virtaamaksi: virtaama tai kuormitus vaatii lisäksi
ajallisen valunta-/kuormitusmallin, yksiköt ja niiden epävarmuudet.

Nykyinen **4 ha = 40 000 m² = 10 000 kahden metrin solua** säilyy
uomaverkon lähtökynnyksenä. Se on myöhemmän uomaesityksen/eroosioskenaarion
valinta, ei ensimmäisen vesistökontaktin suodatin. Myös sitä pienempien
yläpuolisten alueiden vesikontaktit ja katkokset pitää säilyttää.

### D — Tiilirajojen ylittävät yhteydet

Erotetaan laskennan halo ja tuloksesta vastaava ydin. Globaalin solutunnuksen
on perustuttava yhteiseen ruudukkoon ja yksikäsitteiseen omistajuuteen,
ei eri tiilien samanarvoisiin paikallisiin solunumeroihin. Tiilirajalla
kirjataan todellinen lähde–kohdesolureuna ja kohdetiili.

**Näyttö:** vastaanoton ja lähetyksen vastaavuus, yhtenevä ruudukko,
ytimien kertalaskenta ja kertymän säilyminen yhdistettäessä. Sisäiset
tiilisiirrot kumoutuvat globaalista taseesta kerran; halon päällekkäistä
maa-alaa ei lasketa uutena lähteenä. Pienellä vertailulla monitiilinen
ratkaisu vastaa saman alueen yhtenäistä graafia.

Puuttuva naapuritiili on keskeneräinen siirto, ei luonnollinen outlet.
Myös koko tutkimusalueen ulkorajan tila ja ulkoa tuleva kertymä pitää
määritellä: pelkkä rasterin reuna ei osoita fyysistä purkupaikkaa.

### E — Kytkentä olemassa oleviin vesistömalleihin

Luovutusrajapintaan tarvitaan vastaanottavan mallin kohde-ID/versio,
lähdevesistötunnuksen vastaavuus, kontaktisolun sijainti, yläpuolinen
maa-ala, aineisto- ja menetelmäprovenienssi sekä kaikki laatu- ja
epävarmuustilat. Ajallista virtaamaa/kuormitusta luovutettaessa tarvitaan
lisäksi suure, yksikkö, aikaväli ja lähtömalli.

Saman vesistökohteen useat maakontaktit säilytetään solutasolla ja voidaan
summata kohdetasolle lähteet kerran laskien. Järvien välistä jatkoa ei
johdeta niiden sisäisestä D8:sta ilman hyväksyttyä vesistöverkkokytkentää.
Tässä suunnitelmassa ei valita tiettyä ulkoista mallia valmiiksi kytkennäksi.

**Näyttö:** vastaanottajatunnusten todellinen vastaavuus, yksikkö- ja
aikasopimus, aggregoinnin tase sekä epäselvien vastaavuuksien säilyminen.
Määrittämättömät outletit pysyvät määrittämättöminä. Tämä rajapinta ei
ohita 02D.5:n turvaporttia.

### F — Todellisiin aineistoihin perustuva validointi

Valitaan vertailut nykyisen [validointigradientin][S8] pohjalta:
luonnontilaiseksi perustellut, tunnetusti muokatut ja vaikutukseltaan
tuntemattomat kohteet erikseen. TEST_SULKU_11 säilyy hyväksytyn
regressiokäyttäytymisen ja muokatun ympäristön rasitustestinä.
Yhden alueen hyvä tulos ei todista siirrettävyyttä koko Suomeen.

Riippumaton vertailu voi käyttää ajallisesti ja sijainnillisesti
dokumentoituja uomia, rantoja, vedenjakajia, maastohavaintoja ja
valuma-alueita. MML:n ja RANTA10:n rajavertailu on lähteiden vertailu,
ei automaattinen totuusluokitus. Samaa lähdedataa käyttävää vertailukohdetta
ei lasketa riippumattomaksi todisteeksi.

Issue #9:n SYKE-aineisto sisältää metatiedon mukaan lähteikköjen
**50 m lähialueen puskuripolygoneja**, ei 2 m tarkkoja lähdepisteitä.
Vertailu tehdään D8-arvosta riippumatta, myös D8≠0-kohteille. Osuma kuvaa
tunnettua lähteisyyttä; puuttuva osuma on `NO_KNOWN_SPRING_IN_DATA`.
MML-pohjaisten lähteiden päällekkäisyydet ja aineiston epätäydellisyys
kirjataan. Aineisto ei yksin varmista vastaanottajaa, luonnollista outletia
tai pohjaveden virtausta. Sen käyttöönotto on suunniteltu, ei tässä toteutettu.

## 5. Solukohtainen QA, verkostovaikutus ja hyväksymisen perusteet

| Laatutaso | Mitattava suure | Automaattinen tarkistus / riippumaton näyttö |
| --- | --- | --- |
| DEM ja sijainti | Versio, korkeusjärjestelmä, ruudukon vastaavuus, NoData, muokkaushistoria, rajaerot | Metadata ja kohdistus voidaan tarkistaa; korkeuden ja oikean rannan luotettavuus vaatii vertailua. |
| Paikallinen D8 | Kelvottomat koodit, väärä naapurisiirtymä, nollat, tasanteet, korkeusepävarmuuden kannalta epäselvät suunnat | Koodaus ja geometria tarkasti; fysikaalinen suunta tarvitsee maastollisen perustelun. |
| Reitin topologia | Syklit, katkokset, askelrajoitukset, NoData ja ratkaistujen lähteiden kattavuus | Lähdesolut ositetaan kattavasti ja ilman päällekkäisyyttä. Askelraja ei todista yhteyden puuttumista. |
| Ensimmäinen vesikontakti | Kontaktisolun sijainti, vesiluokka, ID:n saatavuus, päällekkäisyydet, vastaanottajan vaihtuminen | Soluketju ja tunnisteviitteet tarkasti; oikea vastaanottaja vaatii vertailua. |
| Kertymä | Paikallisen rekursion jäännös, vastaanotettu ja selvittämätön maa-ala, tuonti/vienti | Valitun kokonaislukusopimuksen tase on täsmällinen. Tasetulos ei yksin todista oikeaa reittiä. |
| Tiilirajat | Puuttuvat/väärät siirrot, kaksoislaskettu ydin/halo, katkokselle päätyvä maa-ala | Solu-ID:t, siirtokirjanpito ja vertailugraafi tarkasti. Ulkorajan hydrologinen merkitys erikseen. |
| Epävarmuus | Syyluokka, näytön alkuperä ja ikä, ratkaisematon vaikutusalue, aineistoriippuvuus | Tuntematon säilyy tuntemattomana; perustelemattomia luottamustodennäköisyyksiä ei tuoteta. |

Ohjelmallinen hyväksymisehto voidaan johtaa määritelmästä: ratkaistussa
reittigraafissa ei ole kelvottomia seuraajia tai sykliä, lähteet eivät
katoa tai monistu ja tase täsmää. **Koko todellisen aineiston ratkeamiselle
tai sijaintivirheelle ei aseteta tässä mielivaltaista prosentti- tai
metrirajaa.** Ne sovitaan aineistojen virhekuvausten, riippumattoman näytteen
ja käyttötarkoituksen perusteella ennen hydrologista hyväksyntää.

Raportoi aina erikseen solut, osoitinreunat, erilliset reitit,
vesistökohteet ja yläpuolinen maa-ala sekä niiden tutkimusjoukon nimittäjä.
Pelkkä poikkeamien kappalemäärä tai kaikkien rasterisolujen onnistumisprosentti
voi peittää yhden suuren valuma-alueen väärään vastaanottajaan ohjaavan virheen.

**Priorisointijärjestys on vaikutukseen perustuva:** ensin väärä vastaanottaja
tai vedenjakajan ylitys, laajan maa-alueen katkos, virheellinen vesiliittymä,
tiilirajakatkos ja tasehäiriö. Jokaisesta erotetaan mahdollisuuksien mukaan
yksilölliset yläpuoliset lähdesolut, niiden pinta-ala, vastaanottaja ja
vaikutuksen epävarmuus. Saman katkoksen päällekkäisiä yläpuolisia alueita ei
summata useaan kertaan. Jos kelvollista kertymää ei vielä ole, vaikutusala
merkitään tuntemattomaksi; sitä ei korvata ehdokasreittien määrällä.

## 6. Rakenteet ja muut tunnetut vaikutukset

Padot, rummut, kanavat, tiet ja muut rakenteet kirjataan erilliseen
validoinnin vaikutusinventaarioon lähde- ja ajankohtatietoineen. Tarkastelu
koskee myös niiden hydrologista vaikutusaluetta tiilineliön ulkopuolella.
Tuntematon rakennevaikutus ei muutu luonnontilaisuuden todisteeksi.

Baselineen ei lisätä rakenteiden perusteella uusia reititysohituksia.
Syötteen mahdollinen aikaisempi rumpukorjaus tai muu korkeusmallin muokkaus
pitää silti kirjata: rakenteita käyttämätön ajokoodi ei osoita syötedatan
olevan rakenteista riippumatonta. Tunnelin/rummun todellinen yhteys voi jäädä
pintamallin ulkopuolelle. Tällainen poikkeama säilytetään mallirajauksena tai
epävarmuutena, ei automaattisena pointerikorjauksena.

Mahdollinen myöhempi rakennekerros on erillinen hyväksyttävä menetelmä,
jota verrataan muuttumattomaan baselineen vaikutusalueineen ja taseineen.

## 7. Avoimet tutkimuskysymykset

- Mitkä LOW:n tunnetut nollat ja rajaerot muuttavat maalta saapuvan veden
  **ensimmäistä** kontaktia, ja mitkä koskevat vasta järvestä poistumista?
  Nykyiset järvilähtöiset 02F-reitit eivät anna koko maajoukon vastausta.
- Miksi 1847:n 20 spill-ryhmästä yksikään ei pääse 02E-ehdokkaaksi, ja mitä
  tämä kertoo juuri jatkokytkennän evidenssistä? Puuttuva ehdokas ei osoita
  puuttuvaa maa→järvi-kontaktia.
- Ovatko MODERATE:n 45 paikallisen todistajaparin korkeudet järvitason tai
  rantakynnyksen alapuolella, ja mitä neljän haun budjetti kului tutkimaan?
  Arvioidaan ensisijaisesti valmiista CSV:istä; ei uutta täyttöä tai
  hakurajan kasvattamista ilman erillistä tutkimuskysymystä.
- Kuinka paljon hyväksyttyihin syöte-epävarmuuksiin liittyvä ero muuttaa
  vedenjakajaa, vastaanottajaa ja yläpuolista maa-alaa? Tätä ei vielä tunneta.
- Mistä saadaan jokialueiden ja uomaviivojen kestävät kohdetunnukset ja
  niiden vastaavuus myöhemmin valittavaan vesistömalliin?
- Miten sisään tuleva ulkoinen kertymä, tiilirajat ja ratkaisemattomat
  terminaalit kirjataan niin, ettei lähteitä häviä tai lasketa kahdesti?
- Mitä alkuperäisen Whitebox-ajon komento-/binääri-/cache-todisteista on
  todella säilynyt? Nykyisen syötteen tiiviste ei korvaa syntyhistoriaa.

## 8. Seuraavat kolme tehtävää tärkeysjärjestyksessä

### 1. Maa–vesi-ensikontaktin näyttösopimus ja LOW:n raporttipohjainen rajaus

**Suositus ensimmäiseksi toteutettavaksi tehtäväksi erillisen hyväksynnän
jälkeen.** Määritellään yllä olevan B-vaiheen tulossopimus ja luetaan
valmiit LOW:n 02B/02C/02D.8/02E/02F-pienraportit. Seitsemän tunnetun
päätesolun ja 1847/1898-vertailun avulla erotetaan ennen kontaktia ja sen
jälkeen olevat katkokset sekä raporttien todellinen kattavuus. Tarkastetaan
1847:n 20 ryhmän `evidence_status`, `evidence_class`,
`has_external_evidence` ja mukaan ottamisen perusteet.

Tarvittavia olemassa olevia raportteja ovat esimerkiksi
`02B_land_to_first_water_entries.csv`, `02C_zero_pointer_cells.csv`,
`02C_shore_component_classification.csv`, `02D8_final_spill_evidence.csv`,
`02E_water_connected_candidate_evidence.csv`,
`02E_water_connected_candidate_spill_edges.csv` ja
`02F_water_connected_route_evidence.csv` ja lähdemanifesti.
Todelliset ajokohtaiset tiedostonimet ja olemassaolo tarkistetaan
ajomanifestista; tuntemattomia ei korvata keksityillä tiedostoilla.
LOW:n dokumentoitu tulosjuuri on
`/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000/02_baseline/`.

Toimitus: lähteisiin sidottu kattavuus- ja epävarmuustaulukko, vastaanottajan
tunnistesopimus ja perusteltu pienin seuraava mittaus. Olemassa olevat
CSV:t voivat jättää yläpuolisen maa-alan ja ensikontaktin tuntemattomiksi;
niiden ei väitetä sisältävän koko maagraafia. Ei uusia rasterilukuja tai
D8-korjauksia tämän raporttitehtävän perusteella.

### 2. Rajattu maasolujen ensikontaktigraafin menetelmävalidointi

Erikseen hyväksyttävä pieni tutkimustoteutus hyödyntää olemassa olevia
D8- ja päätepisteytimiä sekä nykyisiä testikäytäntöjä. Pienissä tunnetuissa
verkoissa todennetaan maa→järvi/jokialue/uomaviiva, nolla, NoData, tasanne,
sykli, puuttuva vastaanottaja-ID ja vesiosuuden ulosmenojen invariantti.
Tämän jälkeen valitaan vain uutta kysymystä vastaava rajattu todellinen
vertailu. Kokonaista onnistunutta LOW-skannausta ei uusita varmuuden vuoksi.

Toimitus: todennettu ensikontaktimenetelmän kattavuus, eksplisiittiset
epävarmuudet ja muuttumattomien syötteiden osoitus. Tuotannon lopullista
D8:aa tai 02D.5-porttia ei muuteta tällä tutkimustoteutuksella.

### 3. Kertymän ja tiilirajojen yhteinen jatkuvuuskoe

Vasta selkeän maa-/vesisolusopimuksen jälkeen suunnitellaan ja erikseen
hyväksytään C–D-vaiheiden pieni yhdistetty koe. Se vertaa yhtenäistä ja
tiilijaettua graafia, selvittämättömiä terminaaleja sekä yläpuolisen
maa-alan paikallista ja globaalia tasetta. 4 ha esityskynnys ei saa muuttaa
kontakti- tai tasetuloksia. Toimitus ei ole kansallinen ajo.

MODERATE:n 49 järven valmiiden CSV:iden tulkinta ja alkuperäisen täytön
provenienssiselvitys säilyvät PR #7:n omana rinnakkaisena tutkimuslinjana.
Niitä tarvitaan järvien jatkokytkennän arviointiin ja syöte-epävarmuuden
rajaamiseen; 45 todistajaa ei muuteta hyväksytyiksi outleteiksi eikä
neljää rajautumista hävitetä tästä uudesta painotuksesta huolimatta.

## 9. Tämän dokumentointimuutoksen rajat ja tarkistus

Muutos sisältää vain tämän suunnitteludokumentin. R-, Python-, Slurm-,
testi- ja workflow-tiedostot, CSC-arkistot ja historialliset tutkimusraportit
säilyvät. Tarkistus kohdistuu lähdeviitteisiin, toteutuksen ja suunnitelman
erotteluun, dokumentointidiffiin ja Actions-triggerien rajauksiin.
Raskaita tai jo onnistuneita hydrologisia testejä ei tarvita tämän
dokumentin tarkistamiseen. PR #7:ää tai PR #12:ta ei yhdistetä.

Kaikki seuraavan tehtävän ohjelmointi ja mahdolliset CSC-mittaukset
odottavat erillistä hyväksyntää. **MODERATE=REVIEW_REQUIRED; NATIONAL=LOCKED.**

## Lähteet

- [S1: baseline README][S1], [02-pääskripti][S1R], [02E][S1E], [02F][S1F]
  ja [konfiguraatio][S1C], kaikki commitissa `7050b582edab3195669529f366b4f5a2915488c6`.
- [S2: MODERATE draft PR #7][S2] ja [koettimen täsmällinen ehto][S2P],
  tarkistettu head `a3c42be333468e25c731faa3fd63f9687ed83978`.
- [S3: LOW draft PR #12][S3], [tieteellinen vaihtoehtoarvio][S3O] ja
  [MML/02E/02F-tutkimusraportti][S3M], tarkistettu head
  `cd9612aa1cb4dd39bc6b33d825302202b28ef09e`.
- [S4: issue #10, seitsemän LOW-päätesolua][S4].
- [S5: issue #9, SYKEn lähteikkövalidointi][S5].
- [S6: issue #13, MODERATE:n näyttöportti][S6].
- [S7: aiempi tutkimustilannemuistio][S7] ja [16.10. MODERATE-raportti][S7R]
  PR #7:n tarkistetussa commitissa. Uusi työ 2369720 on tämän toimeksiannon
  yhteydessä käyttäjän raportoima; raakaa raporttipakettia ei ole luettu tässä.
- [S8: baseline-validointigradientti][S8].

[S1]: https://github.com/annasuuronen/MaaltaMerelle/blob/7050b582edab3195669529f366b4f5a2915488c6/README.md
[S1R]: https://github.com/annasuuronen/MaaltaMerelle/blob/7050b582edab3195669529f366b4f5a2915488c6/R/02_build_baseline_hydrology.R
[S1E]: https://github.com/annasuuronen/MaaltaMerelle/blob/7050b582edab3195669529f366b4f5a2915488c6/R/02E_water_connected_candidates.R
[S1F]: https://github.com/annasuuronen/MaaltaMerelle/blob/7050b582edab3195669529f366b4f5a2915488c6/R/02F_water_connected_route_diagnostics.R
[S1C]: https://github.com/annasuuronen/MaaltaMerelle/blob/7050b582edab3195669529f366b4f5a2915488c6/R/00_pipeline_config.R
[S2]: https://github.com/annasuuronen/MaaltaMerelle/pull/7
[S2P]: https://github.com/annasuuronen/MaaltaMerelle/blob/a3c42be333468e25c731faa3fd63f9687ed83978/scripts/lib/probe_fill_hypotheses.R#L98
[S3]: https://github.com/annasuuronen/MaaltaMerelle/pull/12
[S3O]: https://github.com/annasuuronen/MaaltaMerelle/blob/cd9612aa1cb4dd39bc6b33d825302202b28ef09e/diagnostics/low_d8_scope/SCIENTIFIC_OPTIONS.md
[S3M]: https://github.com/annasuuronen/MaaltaMerelle/blob/cd9612aa1cb4dd39bc6b33d825302202b28ef09e/diagnostics/low_d8_scope/README_MML_gap.md
[S4]: https://github.com/annasuuronen/MaaltaMerelle/issues/10
[S5]: https://github.com/annasuuronen/MaaltaMerelle/issues/9
[S6]: https://github.com/annasuuronen/MaaltaMerelle/issues/13
[S7]: https://github.com/annasuuronen/MaaltaMerelle/blob/a3c42be333468e25c731faa3fd63f9687ed83978/docs/maaltamerelle_tutkimustilanne_20261019.md
[S7R]: https://github.com/annasuuronen/MaaltaMerelle/blob/a3c42be333468e25c731faa3fd63f9687ed83978/docs/moderate_roihu_readonly_review_20261016.md
[S8]: https://github.com/annasuuronen/MaaltaMerelle/blob/7050b582edab3195669529f366b4f5a2915488c6/docs/validation_gradient.md
