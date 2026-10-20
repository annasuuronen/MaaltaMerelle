# MaaltaMerelle: maa-alueiden virtausverkon, ojitusten ja pienvesien tutkimussuunnitelma

Laadittu 19.10.2026, päivitetty 20.10.2026 käyttäjän hyväksymän ojitus- ja
pienvesipainotuksen sekä DEM-lähdekorjauksen mukaisesti.
**Suunnitelma tieteelliseen katselmointiin.**
Tämä dokumentti ei osoita alla ehdotettujen menetelmien toteutusta tai
hyväksyntää. Päivitys muuttaa vain tätä tiedostoa suunnitteluhaarassa,
jonka lähtöcommit on
`baseline-no-structures`-haaran `7050b582edab3195669529f366b4f5a2915488c6`.
LOW:n ja MODERATE:n kehityshaaroja ei yhdistetä tähän muutokseen.

**MODERATE=REVIEW_REQUIRED; NATIONAL=LOCKED.** Nykyinen 02D.5-laatuportti,
TEST_SULKU_11-odotukset, 2 m ruudukko, EPSG:3067, Whitebox-D8-koodaus ja
4 ha uomakynnys säilyvät. Tämä suunnitelma ei valtuuta seuraavan tehtävän
ohjelmointia, rasterimuutoksia tai uusia CSC-ajoja.

## 1. Tavoite ja tutkimuksen kohde

Tutkimuksen viisi keskeistä tavoitetta ovat:

1. Mahdollisimman tarkka ja jäljitettävä 2 m solukohtainen virtausverkko maa-alueilla.
2. Ojien, rumpuyhteyksien ja muiden kuivatusreittien tunnistaminen ja jatkuvuuden arviointi.
3. Virtauskertymän, ojien yhtymien ja uomaverkon muodostumisen tutkiminen.
4. Mahdollisten RANTA10:stä puuttuvien pienvesien tunnistaminen näyttöön sidottuina ehdokkaina.
5. Reittien luotettava kytkeminen tunnettuihin RANTA10-vesistöihin ja muualla kehitettyihin vesistömalleihin.

Tutkimuskohteena on erityisesti **ennen tunnettua RANTA10-vesikontaktia
kulkeva ojitus- ja pintavirtausverkko**. Kontakti ei ole ainoa kiinnostava
tulos eikä koko verkon kattava validointikriteeri. RANTA10:n tunnettuja
kohteita käytetään vertailuaineistona ja mallien välisinä liittyminä.
Jokaiselle mallin lähtöjoukkoon kuuluvalle maasolulle pitää pystyä esittämään:

- lähtösolun yksikäsitteinen tunniste ja sijainti;
- käytetyn pinnan ja D8:n määräämä soluketju, myös sen epävarmat kohdat;
- reitin ojitus-/uomaehdokkaat, yhtymät ja niiden näytön alkuperä;
- ensimmäinen vastaanottava vesisolu, sen luokka,
  koordinaatit ja tunnistettu vesistökohde;
- yläpuolinen kertymä sekä jatkumisen ja taseen tarkistukset;
- nimenomainen selvittämätön päätepiste, jos vastaanottajaa ei voida osoittaa.

Ensimmäisen tunnetun RANTA10-vesistökontaktin jälkeen järven tai joen
sisäinen jatkoreititys kuuluu erilliseen kytkentään olemassa olevaan
vesistöverkkoon. Maalta tulevan
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

### 2.4 DEM:n lähtötilanne ja pintojen käsittelyhistoria

**Käyttäjän vahvistama DEM-lähdekorjaus:** MaaltaMerellen syöte-DEM muodostuu
vain kahdesta aineistosta:

1. MML:n alkuperäinen Korkeusmalli 2 m (KM2), hankittu Paitulista.
2. SYKEn julkaistu uomakorjaus- ja rumpujen kaiverrusaineisto [S11].

MaaltaMerellessä tähän DEM:iin ei ole yhdistetty kolmansia erillisiä oja-,
rumpu- tai salaoja-aineistoja. Aiempi kuvaus erillisistä salaojapoltoista
korvataan tällä täsmennyksellä. SYKE-tuotteen nimestä ei päätellä sen
sisältävän erillisiä salaojaverkkoja tai tiettyjä sisäisiä lähtöaineistoja.
Julkaisulinkki on käyttäjän toimittama; alkuperäisen aineistokuvauksen
sisältöä ei voitu lukea tässä tarkistuksessa.

Syötettä käsitellään edelleen hydrologisesti muokattuna DEM:nä, ei
muuttamattomana MML:n KM2:na. Konfiguraatio lukee valmiin
`dem_12km_rumpukorjattu.tif`-tiedoston [S1C]. Tarkistetuista lähteistä ei
löytynyt näiden kahden aineiston yhdistämistä toteuttavaa menetelmää,
tarkkoja aineistoversioita tai paikallisia parametreja. Käyttäjän vahvistama
lähdepari, dokumentoitu valmistusmenetelmä ja numeerisesti varmennettu
muutos ovat eri näyttöä. RANTA10:n myöhempi käyttö maskeihin ja
järvikorkeuksiin kuuluu jäljempänä erotettuihin laskentavaiheisiin.

| Pinta | Koodista tai lähdekuvauksesta tiedetty | Mahdollinen vaikutus kuivatusyhteyteen |
| --- | --- | --- |
| MML:n alkuperäinen KM2 Paitulista | MML on tuottaja, Paituli jakelukanava. Käytetty versio, ruudut ja vertailukopio pitää yksilöidä. | Vertailuperusta SYKEn korjausaineiston soveltamiselle, ei sama asia kuin nykyinen syöte. |
| Hydrologisesti muokattu DEM | Käyttäjän vahvistamat lähteet ovat MML:n KM2 ja SYKEn korjausaineisto [S11]; paikallinen yhdistämismenetelmä on vahvistamatta. | Korjausten sijainti, korkeudet ja soveltamistapa pitää sitoa käytettyyn SYKE-versioon; kolmansia paikallisia aineistoja ei oleteta. |
| LAND_RAW | `ifel(is.na(lake_id), dem, NA)` [S1R]. | Järvi-ID-solut poistetaan; niihin osuva polttojälki voi poistua reititysesityksestä. Muu pinta periytyy muokatusta DEM:stä. |
| LAND_FILL | `FillDepressions(LAND_RAW, fix_flats=TRUE)` [S1R]. | Täyttö voi korottaa poltettua uraa ja tasanteiden käsittely muuttaa paikallista kaltevuutta. Jatkuva poltettu yhteys ei välttämättä muutu; säilyminen pitää osoittaa. |
| LAND_WATER | `cover(land_fill, lake_z)` [S1R]; järvikorkeudet sidotaan RANTA10-kohteisiin [S9]. | Säilyttää kelvollisen LAND_FILLin ja täydentää puuttuvia soluja järvikorkeuksilla. Ei palauta järvialueen alkuperäistä polttotopografiaa. |
| STORAGE | Erillinen `FillDepressions(LAND_WATER, fix_flats=FALSE)` [S1R]. | Voi korottaa lisää soluja ilman pyydettyä tasannegradienttia. Ei ole LAND_WATERin tai alkuperäisen maaston hydrologinen vastine. |

Nykyinen Whitebox-D8 tuotetaan **LAND_WATERista, ei STORAGEsta** [S1R].
STORAGEssa havaittu muutos ei yksin osoita nykyisen D8-suunnan muuttuneen.
Polton ja myöhemmän käsittelyn vaikutukset erotetaan ketjussa
alkuperäinen DEM → muokattu DEM → LAND_RAW → LAND_FILL → LAND_WATER → D8;
STORAGE säilytetään erillisenä diagnostisena haarana.

Myös tallennustarkkuus ja vanhojen välitulosten käyttö huomioidaan:
LAND_RAW kirjoitetaan koodissa `FLT4S`-muodossa tiedostonimen `FLT8S`-päätteestä
huolimatta, ja `OVERWRITE=FALSE` sallii olemassa olevien tiedostojen käytön.
Tämä on koodihavainto, ei tässä todettu CSC:n reittivirhe. Nykyinen koodi
ei yksin todista olemassa olevan rasterin historiallista syntytapaa.
`01_input_manifest.csv` sisältää polkuja ja asetuksia, mutta ei polttoreseptiä,
alkuperäisen DEM:n yksilöintiä, koodi-SHA:ta tai rasteritiivisteitä [S9].
Ilman ennen–jälkeen-aineistoja ja valmistustietoja polton vaikutusta ei
voida varmasti erottaa muista syötteen muutoksista.

### 2.5 Ensikontaktiprototyypin erillinen tila

Draft PR #16:n `first_water_contact()` on erillisessä haarassa,
commitissa `24b81af244c867d7a3f7c36594589acc8d9c01f9` [S10]. Se käyttää
LOW:n jäljitysydintä ja erottaa ensimmäisen vesikontaktin, vastaanottajan
tunnistamisen ja `hydrological_validation=NOT_ASSESSED`-tilan.
Paikallinen synteettinen tarkistus on dokumentoitu, mutta ensimmäistä
todelliseen LOW:n 02B-raporttiin ja alkuperäisiin rasterisoluihin perustuvaa
vertailua ei ole tässä varmennettu. Prototyyppiä ei yhdistetä tähän haaraan
eikä muuteta tällä dokumentaatiopäivityksellä.

## 3. Ojitus- ja pienvesitavoitteen vaikutus 02D–02G:n painotukseen

| Vaihe | Säilyvä tehtävä | Painotus uudessa tutkimusrajauksessa |
| --- | --- | --- |
| 02D | Rantakynnykset, korotuskomponentit ja spill/escape-evidenssi | Järvestä poistumisen epävarmuus erotetaan maalta ensimmäiseen veteen saapumisen epävarmuudesta. Kaikki löydökset ja 02D.5-portti säilyvät. |
| 02E | Kaikkien kelvollisten rinnakkaisehdokkaiden säilyttäminen | Vesistöverkon jatkokytkennän evidenssiä; ehdokkaan puuttuminen ei sulje pois maalta saapuvaa kontaktia. Ei outlet-valintaa. |
| 02F | Ehdokasvastaanottajien D8-päätepisteet | Nykyisiä terminaaliluokkia ja jäljityksen periaatteita voidaan uusiokäyttää. Kattavuus pitää laajentaa erikseen hyväksyttävänä tutkimuksena maasoluihin. |
| 02G / myöhempi vaihe | Tarkistetuissa puissa ei toteutusta | Solukohtainen vastaanotinkartta, kertymä ja tiiligraafi ovat suunniteltavia toimituksia. Niitä ei nimetä valmiiksi 02G-menetelmäksi. |

Ojaverkon tutkimukseen tarvitaan myöhemmin suunniteltava solureunojen tai
segmenttien havaintotuote ennen RANTA10-kontaktia: lähde- ja kohdesolut,
pinnan ja pointerin identiteetti, yhtymät, katkokset, kertymän luotettavuus
sekä lähdeaineistoihin sidotut oja- ja pienvesihavainnot. Nykyiset
02B/02F-raportit tai ensikontaktiprototyyppi eivät yksin tuota tätä verkkoa.
Pienvesiehdokkaan löytäminen ei automaattisesti muuta nykyistä vesimaskia
eikä prototyypin pysähtymissääntöä.

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

Dokumentoidulle ojalle tai rumpuyhteydelle tutkitaan, seuraako D8 kuvattua
yhteyttä, jatkuuko reitti rakenteen kohdalla ja päätyykö se alempaan uomaan
tai tunnettuun vesistöön. Katkos paikannetaan käsittelyvaiheeseen: poltto,
järvimaskaus, täyttö, tasanteen käsittely tai järvikorkeuden yhdistäminen.
Samansuuntaisuus polttolinjan kanssa on sisäistä johdonmukaisuutta,
ei riippumaton todiste todellisesta uomasta.

Vedenjakajan ylityksessä erotetaan virheellinen pintareitti dokumentoidusta
ojan, rummun tai maanalaisen yhteyden vaikutuksesta. Alkuperäisen ja
muokatun pinnan vedenjakajat voivat erota perustellusti. Kumpaakaan ei
käytetä automaattisena totuutena ilman yhteyden riippumatonta näyttöä.

**Näyttö:** nykyisten rajattujen D8-ytimien ja testien uusiokäyttö,
pienten tunnettujen topologioiden tarkistukset sekä perustellut todelliset
vertailukohteet. Ratkaistuksi merkityn reunan pitää johtaa täsmälleen
dekoodattuun naapuriin, ja jokainen poikkeama säilytetään. Uusi koko
LOW-/MODERATE-skannaus edellyttää muuttunutta tutkimuskysymystä ja erillistä lupaa.

### B — Maa–vesi-rajapinta, ensimmäinen vastaanottaja ja pienvesiehdokkaat

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

Ojaverkon ja pienvesien suunnitellussa tulossopimuksessa erotetaan kohteen
lähdeluokka, laskennallinen reittihavainto ja riippumaton vahvistus. Nämä
ovat eri ulottuvuuksia: esimerkiksi tunnettu oja voi olla myös RANTA10-uoma.

| Raportoitava luokka | Näyttövaatimus ja epävarmuus |
| --- | --- |
| Tunnettu RANTA10-vesistö | Versio ja lähdekohde sidottu; kontakti ei yksin vahvista rantaa tai virtaussuuntaa. |
| Tunnettu tai ennakkokäsittelyssä kuvattu oja | Erota maastossa tai rekisterissä todettu kohde polttosyötteen kuvauksesta. Säilytä kohdetunnus, alkuperä ja todistusaste. |
| Laskennallinen uomaehdokas | D8:n, kertymän tai maastonmuodon peruste ja lähdepinta kirjataan. Suuri kertymä tai polttolinja ei yksin osoita uomaa tai vettä. |
| Mahdollinen RANTA10:stä puuttuva pienvesi | Puuttuminen tarkistetusta RANTA10-versiosta sekä polttoaineistosta riippumaton uoma- tai vesihavainto. Luonnollisuus, kohdelaji, veden pysyvyys ja virtaussuunta voivat jäädä avoimiksi. |
| Ratkaisematon virtausyhteys | Nolla, NoData, tasanne, sykli, hakuraja, epäselvä siirto tai ristiriitainen näyttö säilytetään syineen ja vaikutusalueineen. |

Ehdokkaat muodostetaan myöhemmin varmennetun maaverkon segmenteistä ja
niiden näytöstä; nykyinen prototyyppi ei tee tätä luokittelua. Pelkkä
RANTA10:n ulkopuolisuus ei osoita uuden vesistön löytymistä. Nollapointeri
tai painanne voi liittyä myös todelliseen kosteikkoon tai kausittaiseen
pienveteen; niitä ei korjata automaattisesti eikä kaikkia ojia luokitella
pienvesiksi. Ehdokkaan hyväksyntä tunnetuksi kohteeksi on erillinen päätös.

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

Ojien yhtymissä tarkistetaan eri yläpuolisten lähdejoukkojen yhdistyminen,
kertymän kasvu ja saman lähteen kertalaskenta. D8:n laskennallinen yhtymä
ei yksin osoita todellista uomien yhtymäkohtaa. Jos vain paikallinen osa
verkosta tai ulkopuolinen tuonti tunnetaan, kokonaiskertymää ei väitetä
tarkaksi; katkosten yläpuolinen vaikutusala säilyy tarvittaessa tuntemattomana.

**Näyttö:** kokonaislukuisen solutaseen täsmällinen yhtälö, paikalliset
kertymärekursiot ja riippumaton pienen verkon rekonstruktio. Yhteenlaskettua
solupinta-alaa ei kutsuta virtaamaksi: virtaama tai kuormitus vaatii lisäksi
ajallisen valunta-/kuormitusmallin, yksiköt ja niiden epävarmuudet.

Nykyinen **4 ha = 40 000 m² = 10 000 kahden metrin solua** säilyy
uomaverkon lähtökynnyksenä. Se on myöhemmän uomaesityksen/eroosioskenaarion
valinta, ei ensimmäisen vesistökontaktin suodatin. Myös sitä pienempien
yläpuolisten alueiden vesikontaktit ja katkokset pitää säilyttää.
4 ha ei ole pienveden olemassaolon tai riippumattoman vahvistuksen raja,
eikä sen alittaminen ole pienvesiehdokkaan poistoperuste.

Yllä oleva kertymä- ja tasemääritelmä koskee pintamaagraafia. Jos salaojien
maanalaisia yhteyksiä tutkitaan myöhemmin, ne kuvataan erikseen lähde-,
liittymä- ja purkupisteineen. Nykyiseen DEM:iin ei ole yhdistetty erillistä
salaoja-aineistoa, eikä SYKE-tuotteen salaojasisältöä ole tässä vahvistettu.
Mahdollinen maanalaisen yhteyden laskennallinen esitys ei ole havaittu pintauoma.
Pinta- ja salaojareitin yhdistäminen edellyttäisi erikseen hyväksyttyä
siirto-/jakautumissopimusta: samaa vettä ei lasketa molempiin. Pelkkä
topologinen yhteys ei osoita putken kapasiteettia, painekorkeuksia tai
tapahtumakohtaista virtausta. Tällaista maanalaista mallia ei toteuteta tässä.

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

Ojien ja pienvesien vertailua varten selvitetään dokumentoitujen
maastohavaintojen, rumpujen pohjakorkeusmittausten, ojitus-/salaojasuunnitelmien
ja toteumakarttojen, ortokuvien sekä erillisten uoma- ja laserkeilaushavaintojen
saatavuus. Poltossa käytetty aineisto voi todentaa syötteen tarkoituksen,
mutta ei samalla toimia riippumattomana validointina. Myös eri julkaisuissa
esiintyvien aineistojen yhteinen alkuperä ja havainnointiajankohta tarkistetaan.
Vertailun pitää erottaa uoman olemassaolo, sijainti, virtaussuunta ja veden
esiintyminen eri vuodenaikoina. Aineistojen saatavuutta tai tätä vertailua
ei ole tässä varmennettu. Nämä ovat mahdollisia vertailulähteitä, eivät
nykyiseen DEM:iin yhdistettyjä kolmansia aineistoja. SYKEn korjausaineiston
käyttö sekä DEM:n valmistamiseen että vertailuun ei muodosta kahta
riippumatonta todistetta.

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
| Kuivatusyhteys | Polttokohteen sijainti, käsittelyvaiheiden muutokset, rummun jatko, yhtymä ja vedenjakajan ylitys | Polttosyötteen toistuminen erotetaan riippumattomasti todetusta yhteydestä. Pintareitti ja maanalainen siirto erotellaan. |
| Pienvesiehdokas | Lähdeluokka, jatkuvuus, kertymän peruste, RANTA10-version kattavuus ja riippumaton havainto | Ehdokas ei muutu tunnetuksi pienvedeksi pelkän kynnysarvon, polton tai RANTA10:n puuttuvan osuman perusteella. |
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

Riskipriorisointi tehdään solureunalle tai yhteydelle ja sen vaikutukselle,
ei vain onnistuneiden kontaktien lukumäärälle. Erityisesti tarkastetaan
kuivatusyhteyden katkeaminen, väärä vastaanottaja, perustelematon vedenjakajan
ylitys ja pinta-/salaojareittien kaksoislaskenta. Tuntematon kertymä tai
RANTA10-kontaktin puuttuminen ei osoita vähäistä riskiä. Myös pienen
valuma-alueen pienvesiehdokas ja ristiriitainen näyttö säilytetään auditoitavina.

## 6. Rakenteet ja muut tunnetut vaikutukset

Padot, rummut, kanavat, tiet ja muut rakenteet kirjataan erilliseen
validoinnin vaikutusinventaarioon lähde- ja ajankohtatietoineen. Tarkastelu
koskee myös niiden hydrologista vaikutusaluetta tiilineliön ulkopuolella.
Tuntematon rakennevaikutus ei muutu luonnontilaisuuden todisteeksi.

Baselineen ei lisätä rakenteiden perusteella uusia reititysohituksia.
Käyttäjän vahvistama lähdeketju on MML:n KM2 Paitulista ja SYKEn
uomakorjaus-/rumpukaiverrusaineisto [S11], ilman kolmansia MaaltaMerellessä
yhdistettyjä oja-, rumpu- tai salaoja-aineistoja. Tämä kirjataan syötedatan
käsittelyhistoriaan: rakenteita käyttämätön ajokoodi ei osoita syötedatan
olevan rakenteista riippumatonta. SYKE-tuotteen sisäinen valmistus ja sen
paikallinen soveltamistapa säilyvät vahvistamattomina, kunnes lähdenäyttö
löytyy. Erillisiä salaojaverkkoja ei oleteta tuotteen sisällöksi. Tunnelin/rummun
todellinen yhteys voi jäädä pintamallin ulkopuolelle. Tällainen poikkeama säilytetään mallirajauksena tai
epävarmuutena, ei automaattisena pointerikorjauksena.

Kahden DEM-lähteen ja niiden soveltamisen provenienssivaatimukset ovat:

- MML:n alkuperäisen KM2:n, käytetyn SYKE-tuotteen ja käsitellyn DEM:n lähdeviitteet,
  versiot/ajankohdat, ruudukot, NoData ja korkeusjärjestelmät;
- SYKEn julkaisun resurssi-/ruututunnukset sekä mahdolliset sen mukana
  dokumentoidut kohdetunnukset, sijainnit, korkeus- ja suuntatiedot;
- SYKE-tuotteen dokumentoitu valmistus ja siitä erikseen MaaltaMerellen
  yhdistämis-/soveltamissääntö, ohjelmisto/koodiversio, kohdistus ja NoData-käsittely;
  kaiverrussyvyyttä, leveyttä tai kaltevuusmenetelmää ei päätellä tuotteen nimestä;
- käytettävissä oleva ennen–jälkeen-näyttö: muutosraportti tai tallennettu
  erotus/polttomaski sekä niiden sidonta samoihin lähtötiedostoihin;
- myöhempien pintojen ja D8:n ajokohtaiset lähteet, parametrit,
  ohjelmisto-/binääriversiot, exit-tilat ja olemassa olevat tarkistussummat.

Vaatimus ei tarkoita, että nämä tiedot olisivat jo saatavilla. Pelkkä
tiedostonimi, nykyinen SHA256 tai nykyisen checkoutin HEAD ei todista
historiallista valmistustapaa. Puuttuva tieto merkitään puuttuvaksi;
esimerkiksi `flat_increment`-arvoa tai polttosyvyyttä ei arvata. Eri
ruudukkojen ennen–jälkeen-vertailu edellyttäisi kohdistuksen ja mahdollisen
uudelleennäytteistyksen vaikutusten erottamista poltosta.

Mahdollinen myöhempi rakennekerros on erillinen hyväksyttävä menetelmä,
jota verrataan muuttumattomaan baselineen vaikutusalueineen ja taseineen.

## 7. Avoimet tutkimuskysymykset

- Löytyykö LOW:sta yksi SYKEn korjausaineistoon sidottu yksilöity
  oja–rumpuyhteys, miten sen korjaus on yhdistetty MML:n KM2:een ja mikä
  myöhempi vaihe säilyttää tai muuttaa sitä?
- Mitkä RANTA10:n ulkopuoliset reitit ovat dokumentoituja ojia, mitkä vain
  laskennallisia uomaehdokkaita ja millä riippumattomalla näytöllä niistä
  voidaan erottaa mahdollisia puuttuvia pienvesiä?
- Jos salaojia tutkitaan erikseen myöhemmin, miten pintavalunta ja
  maanalaiset siirrot erotetaan niin, että yhtymät, vedenjakajien tulkinta
  ja lähteiden kertalaskenta säilyvät oikein?
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

### 1. Yhden dokumentoidun LOW:n oja–rumpuyhteyden provenienssiauditointi

**Ensimmäinen seuraava tutkimustehtävä.** Auditointi aloitetaan GitHubin ja
olemassa olevien dokumenttien lähdeselvityksellä. Kohdekohtaista jäljitystä
CSC-raporteista ei väitetä tämän perusteella valmistuneeksi. Tarkastelu
rajataan yhteen SYKEn korjausaineistoon sidottuun dokumentoituun oja–rumpuyhteyteen LOW-alueella
`E200000_N6900000`. Käytetään vain olemassa olevia lähdekuvauksia,
esikäsittelymuistioita, kohdeviitteitä, manifesteja ja pieniä raportteja.
Ei uusia CSC-töitä, rasterilukuja, rasterien sisältötiivisteiden laskentaa,
polttoja, täyttöjä tai koko alueen inventaarioita.

Tarkistus etenee seuraavasti:

1. Varmistetaan raporttien todellinen saatavuus ja aineistosidonta. LOW:n
   dokumentoitu tulosjuuri on
   `/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000/02_baseline/`.
   `../01_inputs/01_input_manifest.csv` ja `../01_inputs/01_input_QA.csv`
   ovat tähän juureen suhteutettuja rinnakkaisen vaihehakemiston
   raporttiehdokkaita; lähdepolut eivät osoita
   tiedostojen olemassaoloa. Tästä Codex-ympäristöstä CSC:n `/scratch` ei ollut
   luettavissa. Se ei osoita tiedostojen puuttuvan Roihulta.
2. Selvitetään SYKEn korjausaineiston olemassa olevasta kuvauksesta tai
   käyttödokumentaatiosta yksi yksilöity yhteys. Kohdetunnusta ei oleteta
   olevan: myös aineistoversioon ja resurssi-/ruututunnukseen sidottu
   dokumentoitu sijainti voi yksilöidä tarkastelukohdan. Ojan ja rummun
   välisen yhteyden pitää silti perustua lähdenäyttöön. Valintaperuste,
   lähdetiedosto, versio ja saatavilla oleva tarkistussumma kirjataan.
   Mielivaltaista D8-reittiä, nollasolua tai suurta kertymää ei nimetä ojaksi
   tai rummuksi.
3. Jäljitetään MML:n alkuperäisen KM2:n (Paitulista), käytetyn SYKE-tuotteen
   ja käsitellyn DEM:n identiteetit sekä näiden kahden lähteen paikallinen
   yhdistämis-/soveltamismenetelmä. Tuotteen mahdolliset geometrialähteet
   selvitetään alkuperäisestä aineistokuvauksesta; kolmansia MaaltaMerellessä
   yhdistettyjä aineistoja ei oleteta. Selvitetään, onko jo
   olemassa kohteeseen sidottu ennen–jälkeen-raportti, polttomaski tai muu
   vertailunäyttö. Rasterin tai maskin sisältöä ei lueta tällä rajauksella;
   pelkkä tiedostoviite ei osoita muutoksen suuruutta tai oikeellisuutta.
4. Sidotaan saatavilla olevat ajotiedot ja vertailuraportit LAND_RAW-,
   LAND_FILL-, LAND_WATER-, STORAGE- ja D8-vaiheisiin. Esimerkiksi
   `02A_storage_regression_QA.csv` ja aiemman storage-provenienssiauditoinnin
   `comparisons.csv` ovat olemassaololtaan tarkistettavia raporttiehdokkaita.
   Koko pinnan summat tai regressiovastaavuus eivät todista juuri valitun
   kuivatusyhteyden säilymistä. Raportoimaton kohdekohtainen muutos jää tuntemattomaksi.
5. Toimitetaan yksi jäljitettävyystaulu: kohde/sijainti ja valintaperuste,
   SYKE-lähdeviite ja dokumentoitu menetelmä, MML:n KM2, lähteiden paikallinen
   yhdistäminen, käsitelty DEM, ennen–jälkeen-näyttö, myöhemmät pinnat/ajot sekä kunkin
   tiedon lähde ja puuttuvat alkuperäisaineistot. Käyttäjän ilmoitus,
   dokumentoitu valmistus ja numeerinen vertailuhavainto erotetaan toisistaan.

**Jos yksilöityä dokumentoitua kohdetta ei löydy, raportti sanoo nimenomaisesti
"Yksilöityä dokumentoitua LOW:n oja–rumpuyhteyttä ei löytynyt tarkistetuista
lähteistä" ja nimeää tarkistetut lähteet sekä puuttuvan näytön.** Tämä ei
osoita ojien tai rumpujen puuttuvan maastosta. Puuttuva polttoresepti tai
ennen–jälkeen-vertailu raportoidaan erikseen myös silloin, kun kohde löytyy.
Auditointi ei hyväksy yhteyttä hydrologisesti. Mahdollinen seuraava
kohdekohtainen rasterivertailu määritellään vasta tämän näytön perusteella
ja hyväksytään erikseen.

### 2. Rajattu ojaverkon ja RANTA10-liittymän menetelmävalidointi

Provenienssiauditoinnin jälkeen suunnitellaan erikseen hyväksyttävä rajattu
jatkuvuuskoe dokumentoidulle kuivatusyhteydelle. Määritellään edellä kuvattu
solureunojen/segmenttien tulossopimus, pintojen muutoksen ja riippumattoman
uomanäytön erottelu sekä katkosten ja yhtymien tarkistukset. Tätä menetelmää
ei nimetä toteutetuksi.

Liittymän rinnakkaisena tutkimuslinjana säilytetään B-vaiheen tulossopimus ja
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

Toimitus: lähteisiin sidottu kattavuus- ja epävarmuustaulukko, vastaanottajan
tunnistesopimus ja perusteltu pienin seuraava mittaus. Olemassa olevat
CSV:t voivat jättää yläpuolisen maa-alan ja ensikontaktin tuntemattomiksi;
niiden ei väitetä sisältävän koko maagraafia. Ei uusia rasterilukuja tai
D8-korjauksia tämän raporttitehtävän perusteella.

PR #16:n ensikontaktiprototyyppi ja sen pienet synteettiset regressiot
säilytetään erillisinä (§2.5). Mahdollinen LOW:n
`02B_land_to_first_water_entries.csv`-tarkistus valitsee deterministisesti
enintään kaksi todellista reunaa kustakin esiintyvästä vesiluokasta,
yhteensä enintään kuusi. Puuttuvia luokkia ei keksitä. Tämä on liittymän
regressio, ei ojaverkon kattava validointi. CSV:n sisäinen geometria,
alkuperäisten rasterisolujen vastaavuus ja riippumaton hydrologinen
oikeellisuus ovat eri näyttöä. `read_cell`-syötteitä ei rakenneta CSV:n
odotetuista tuloksista itsenäiseksi rasteritestiksi. Uudet rasteriluvut
vaativat erillisen hyväksynnän; valmiita raskaita laskentoja ei uusita.

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
dokumentin tarkistamiseen. PR #7:ää, #12:ta tai #16:ta ei muuteta tai yhdistetä.
Dokumentaatiokorjaus ja GitHubin lähdeselvitys eivät sisällä CSC:n
kohdekohtaista auditointia, ohjelmointia tai uusia rasterilukuja.

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
- [S9: syötemanifesti ja järvikorkeuksien muodostus][S9], baseline-commit
  `7050b582edab3195669529f366b4f5a2915488c6`.
- [S10: erillinen ensikontaktiprototyyppi ja dokumentoidut synteettiset tarkistukset][S10],
  commit `24b81af244c867d7a3f7c36594589acc8d9c01f9`, draft PR #16.
- [S11: SYKEn uomakorjaus- ja rumpujen kaiverrusaineiston julkaisulinkki][S11],
  käyttäjän vahvistama toinen DEM-lähde. Aineistokuvauksen sisältöä,
  käytettyä versiota tai paikallista soveltamista ei ole tässä varmennettu.

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
[S9]: https://github.com/annasuuronen/MaaltaMerelle/blob/7050b582edab3195669529f366b4f5a2915488c6/R/01_prepare_hydrology_inputs.R
[S10]: https://github.com/annasuuronen/MaaltaMerelle/blob/24b81af244c867d7a3f7c36594589acc8d9c01f9/diagnostics/land_first_water/README.md
[S11]: https://ckan.ymparisto.fi/dataset/uomakorjaus-rumpujen-kaiverrus-korkeusmalli-2m
