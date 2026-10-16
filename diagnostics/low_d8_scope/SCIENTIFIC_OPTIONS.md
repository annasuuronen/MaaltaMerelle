# LOW — rantavyöhykkeen D8-jatkuvuuden tieteelliset vaihtoehdot

Tämä on vain tieteellinen arvio. Ei muutoksia D8:aan, DEM:iin, WATER_STORAGEen tai outletteihin. NATIONAL LOCKED; MODERATE REVIEW_REQUIRED.

## Todellinen LOW E200000_N6900000

Alkuperäinen hydrologinen koodi: 4bbf22bb39181c8a4c27ebc3e2769766043115b8. Käyttäjän Roihu-tuloksessa 02F:ssä 101 eri receiver/origin-reittiä, joista 41 D8_ZERO_INTERIOR (loput 34 REACHES_RIVER_AREA, 5 REACHES_RIVER_LINE ja 21 RETURNS_TO_ORIGIN_LAKE). 229 ehdokasreunaa eivät ole 229 eri reittiä.

Nämä 41 reittiä päättyvät vain 7 nollasoluun: 10007129, 10031127, 15389414, 15401414, 23211319, 23355315, 23373314. 7/7 saa järvisolusta suoran D8:n (yhteensä 10 osoitinta), 17/17 järvinaapuria on maskattu LAND_RAW/LAND_FILL -pinnoissa, keskisolut ovat DEM=LAND_RAW=LAND_FILL=LAND_WATER, ja 6/7 nousee erillisessä WATER_STORAGE-täytössä. Lähin RANTA10-järvisolu on aina keskussolua korkeampi, 2.00–2.83m päässä. Solu 23373314 sisältää tasakorkuisen länsinaapurin 23373313, jonka D8 jatkaa alemmas soluun 23373312. Nämä havainnot toistettiin PR #11:n synteettisissä ja todellisissa Roihu-testeissä.

Koodin kulku: järvet maskattu LAND_RAW:ssa; LAND_FILL fix_flats=TRUE; LAND_WATER palauttaa lake_z:n; Whitebox D8 lasketaan LAND_WATER:sta; WATER_STORAGE:n erillinen FillDepressions fix_flats=FALSE. Maskireunan ja järvestä alempaan maasoluun johtavan D8-katkoksen mekanismi on vahvasti tuettu. Whiteboxin täsmällinen NoData-reunakäyttäytyminen on yhä erikseen vahvistamatta.

MML 2025:n maastoluokista neljä keskisolua on niittyä, kaksi muuta avointa aluetta ja yksi järvipolygonia; RANTA10 water_class=NA kaikissa seitsemässä. Ei suo/soistuma-polygoneja 100m etäisyydellä näistä seitsemästä. Tämä ei ole koko LOW:n yleistetty maankäyttötulos.

## Vaihtoehtojen arviointi

| Vaihtoehto | Tulkinta | Hyväksyntään tarvittava näyttö |
|---|---|---|
| A. Säilytetään D8 ja raportoidaan katkokset | Nykyinen vertailutaso, ei yhtenäinen vesistöverkko | PR #11:n QA |
| B. Järvi erillisenä vesistöverkon solmuna, purku riippumattomasta näyttöketjusta | **Ensisijainen tutkimusvaihtoehto**; järven sisäistä D8:aa ei käytetä ainoana purkupisteen perustana | RANTA10 ja 02E-rantakynnys / spill-ehdokkaat, riippumaton reittievidenssi ja tieteellinen arvio |
| C. Tasakorkeuksien käsittely erikseen | Mahdollinen paikallinen jatko solulle 23373314, ei yleinen ratkaisu | Tarkan flat-topologian ja vaikutusten QA |
| D. MML–RANTA10-järvirajaerojen arviointi | Mahdollinen rajaus-/ajallinen ongelma etenkin 23211319 | Riippumaton geometria- ja aineistoversiotarkistus |
| E. STORAGE-pinnan vaihtoehtoinen D8 herkkyystestinä | Täyttöpinnan tasanteet voivat synnyttää uuden reititysongelman | Erillinen turvallinen testikopio ja riippumaton purku-/suuntavalidointi |

Älä osoita D8:aa automaattisesti lähimpään järveen, kun järvi on korkeammalla, äläkä käsittele 02C:n SAFE_LAKE_CONNECTOR-luokkaa automaattisena outlet-päätöksenä.

## Laajuus

**02F**: vain 101 ehdokasperustaista reittiä, joista 41 nollaan ja 7 ainutlaatuista terminaalia.

**02C**: valmiit 02C_zero_pointer_cells.csv ja 02C_shore_component_classification.csv koskevat vain vesistöjen vieressä olevia ei-vesisoluja ja niiden nollakomponentteja. Pythonin scope_existing_02c.py vertailee 02C- ja 02F-raportit vain lukien, ei väitä koko LOW:n kattavuutta.

**Koko rasterin nollasolut — CSC Roihu PASS 16.10.2026:** hyväksytty kertaluonteinen
Slurm-työ `2345102` (`COMPLETED 0:0`, 15 s) kävi 64 rivin lohkoissa läpi
lukitun LOW:n. Ei-vesialueen D8=0-soluja **1 481**, näistä sisäisiä
**719** ja sisäisiä järven vieressä **641**. Järvestä D8=0-soluun tulevia
osoitinreunoja **1 273**, joiden erillisiä vastaanottajia **535**.
Kaikkia järvestä maalle osoittavia Whitebox-D8-reunoja **2 998**
(22 järveltä), joten välitön nollapääteosuus **42,46 %**.
Aiempi 02C-suppea QA ja koko LOW-skannaus täsmäävät samoihin
1 273 reunaan / 535 vastaanottajaan. Koko alueen reittien tai
syklien täydellistä seurantaa tämä ei tee.

**RANTA10–MML 2025 ja rasterointi — CSC Roihu PASS 16.10.2026:**
tarkastelujärvet 1847 ja 1898. Alkuperäinen RANTA10-järvi-ID-rasteri
vastaa molemmissa paikallisissa ikkunoissa **täsmälleen**
`touches=TRUE`-vektorirasterointia: 1847 **24 344/24 344**
ja 1898 **2 059/2 059** järvisolua, kummassakin nolla
kahdensuuntaista poikkeamaa. Alkuperäinen `00A_validation_fixture_QA.csv`
raportoi `rasterization_touches=TRUE`. Lähdesolukeskukset RANTA10:n
vektorijärven ulkopuolella eivät siis yksin osoita rasterointivirhettä.
Sen sijaan järven 1847 **88/88** erillistä D8=0-maavastaanottajaa
sijaitsee MML 2025 `jarvi`-polygonissa mutta yksikään niiden
rasterisoluruuduista ei kosketa RANTA10:n järvipolygonia.
Kontrollijärvellä 1898 MML:n sisään sijoittuu **0/26** nollasoluista.
RANTA10/MML-aluerajojen todellinen IoU on 1847:llä **0.852107**
ja 1898:lla **0.560888**; geometriat ovat paikallisesti
päällekkäisiä, mutta vastaavuutta tai oikeaa outletia ei voi
osoittaa pelkällä IoU:lla. Lisätiedot:
`README_1847.md`, `README_MML_1847_1898.md`,
`README_touch_replay.md`.

**MML-erotusalueen 1847/1898 02E/02F -QA — CSC Roihu PASS 16.10.2026:**
korjattu v2-tutkimusajuri vahvistettiin sekä synteettisillä testeillä että
todellisilla 02E/02F-CSV:illä. Järven **1847** kaikki 88 erillistä
D8=0-vastaanottajaa ovat `MML 2025 jarvi \\ RANTA10 lakes` -erotusalueella
(**8 358.843 m²**) ja muodostavat **21** erillistä 8-naapuruusryhmää;
kuudessa suurimmassa on **67/88** solua. Kontrollijärvellä **1898** on
**0/26** nollasolua MML-yksinomaisella vesialueella
(**99.095 m²**) ja **25** naapuruusryhmää.

1847:n **20** 02E-spill-ryhmästä **0** on mukana rinnakkaisehdokkaana
ja **0** on review-lipullisia; 02E:n mukaan otettuja spill-reunoja ja
02F:n ehdokasvastaanottajareittejä on **0**. Kontrollijärvellä 1898
12 02E-ryhmästä **1** on mukana (5 spill-reunaa); 02F:ssä
**3** erillistä reittiä saa luokan `REACHES_RIVER_AREA`.
Molemmissa `outlet_selection=UNASSIGNED`. Tämä ei osoita
1847:n luonnollisen purkuyhteyden puuttumista tai hyväksy
1898:n purkupistettä. Aiempi v1 pysähtyi uuden tutkimusajurin
virheelliseen 02F-sarakkeen nimioletukseen; v2 korjasi sen
`origin_lake_objectid`-kentäksi, ja oikean aineiston PASS vahvistettiin.
Ks. `README_MML_gap.md`.

**Seuraava rajattu tutkimus:** tutki 1847:n MML:n ja RANTA10:n
*geometrinen erotus juuri D8=0-vastaanottajien kohdalla* ja
tarkista mahdollinen riippumaton luonnollisen purkuyhteyden
todiste ennen hydrologisen reititysratkaisun suunnittelua.
Johtopäätös on rajausepäsuhdan paikallinen ristivarmistus,
ei automaattinen maskin vaihto, ei MML:n määrääminen oikeaksi
rannaksi eikä uusi outlet. `SCIENTIFIC_STATUS: REVIEW_REQUIRED`.

Lähteikkövalidointi säilyy issue #9:ssä D8-arvosta riippumatta, eikä maa-ainesta tai turpeen paksuutta lisätä malliin.
