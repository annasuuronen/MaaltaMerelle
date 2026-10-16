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

**Koko rasterin nollasolut**: scan_entire_low_d8.R lukee D8:n ja RANTA10-vesiluokan 64 rivin lohkoina laskentasolmulla. Se laskee ei-vesisolujen sisäiset D8-nollat, järven vieressä olevat nollat sekä järven D8-osoittimien vastaanottavat nollat. Se ei havaitse kaikkia D8-syklejä, NA-päätteitä tai muita reittiongelmia. Skanneri on vasta valmisteltu, ei ajettu tai R-tulkilla validoitu. Suoritus vaatii erillisen laskenta-ajon hyväksynnän. Ei koko rasterin käsittelyä login-solmulla.

Lähteikkövalidointi säilyy issue #9:ssä D8-arvosta riippumatta, eikä maa-ainesta tai turpeen paksuutta lisätä malliin.
