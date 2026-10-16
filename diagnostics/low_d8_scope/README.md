# LOW D8 laajuus ja rantavyöhykkeen reititysvaihtoehdot

Read-only tutkimusdiagnostiikka; liittyy LOW D8:n [issue #10](https://github.com/annasuuronen/MaaltaMerelle/issues/10) sekä aiempaan [PR #11](https://github.com/annasuuronen/MaaltaMerelle/pull/11). Tuotanto-R-koodia tai rastereita ei muokata.

## 1. Kevyt raporttivertailu Roihun kirjautumissolmulla

Suorita tässä hakemistossa tai anna tiedostolle absoluuttinen polku:

    python3 -I -B diagnostics/low_d8_scope/scope_existing_02c.py /scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000/02_baseline

Ohjelma lukee vain olemassa olevat kolme CSV:tä: 02C_zero_pointer_cells.csv, 02C_shore_component_classification.csv ja 02F_water_connected_route_evidence.csv. Se näyttää 02C:n vesistöjen viereisten D8=0-maasolujen määrän, komponenttien luokitusmäärät ja seitsemän tunnetun 02F-päätesolun komponenttiosumat. Se vertaa myös 101 reitin / 41 nollareitin / seitsemän terminaalin havaintoon. Ei kirjoita dataa, ei muokkaa rastereita. **02C:n tulos ei ole koko LOW-rasterin lukumäärä.**

Paikalliset Python 3 stdlib -regressiotestit on ajettu onnistuneesti (4/4) komennolla:

    python3 -m unittest discover -v -s diagnostics/low_d8_scope -p 'test_*.py'

## 1b. LOW 02C: järvestä D8=0-maasoluun tuleva osoitin (Roihu PASS)

`incoming_02c_lake_d8.R`, `test_incoming_02c_lake_d8.R` ja
`run_incoming_02c_lake_d8.R` ovat **vain lukevia**. Jälkimmäinen hakee 02C:n
valmiista vesinaapuritaulukosta järvi-, joki- ja jokiviivanaapurien D8-osoittimet
pienin rajatuin rasteri-ikkunoin. Ajo ei lue koko rasteria eikä muuta D8:aa.
Aja alkuperäisen lukitun CSC-LOW:n tiedoilla, kun olet tämän PR-version checkoutissa:

    D=diagnostics/low_d8_scope
    B=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000/02_baseline
    Rscript --vanilla "$D/test_incoming_02c_lake_d8.R" && Rscript --vanilla "$D/run_incoming_02c_lake_d8.R" "$B"

Todellisen Roihu-testin PASS (16.10.2026): 643 vesistöä sivuavaa 02C-nollasolua;
**535 erilliseen nollasoluun** tulee **1 273** järvi-D8-osoitinta. 02C:n
`SAFE_LAKE_CONNECTOR`-luokassa näitä soluja on **534/640** ja järviosoitinreunoja
**1 270**. `INTERIOR_REVIEW`: 1 solu ja 3 reunaa; `EDGE_CASE`: 0 järvestä
tulevaa osumaa. Kaikki 7 aiempaa 02F-päätettä ja 10 järviosoitinta toistuivat.
Rasterin käyttö **1 745 soluarvoa 846 suppeasta ikkunasta**; ei laajaa skannausta.

Tulkinta: nämä ovat todellisia paikallisia **järvi-D8 → maasolu D8=0**
-katkoskohtia, eivät 535 eri järveä, valuma-aluetta tai koko LOW-rasterin kaikki
katkokset. `SAFE_LAKE_CONNECTOR` ei osoita toimivaa virtausjatkumoa.
Kaikkien 535 solun todellinen järvikohtainen jakauma tai mahdollisten
korjausvaihtoehtojen hyväksyntä on erillinen tieteellinen jatkotehtävä.

## 1c. LOW 02C: lähdejärvet, joihin liittyy järvestä D8=0-soluun tulevia osoittimia

Laajennettu `incoming_02c_lake_d8.R` tukee valinnaista `detail=TRUE`-tulosta:
todellisten järvestä nollasoluun tulevien osoitinreunojen lähdejärvitunnukset
(`lake_objectid`), rasterin järvisolut ja vastaanottavat maasolut. Vanha
`detail=FALSE`-dataframe-rajapinta ja kaikki aiemmat 02C-laskurit säilyvät.

`run_incoming_02c_lake_d8.R` raportoi lisäksi **erillisten lähdejärvien**
määrän, globaaleina yksilöllisten vastaanottavien nollasolujen määrän,
osoitinreunojen määrän ja **20 eniten erillisiä nollasoluja saavaa järveä**.
Samalla nollasolulla voi olla osoitinreunoja kahdesta eri järvestä: järvittäisten
nollasolujen summa ei silloin ole globaalisti yksilöllisten solujen lukumäärä,
ja päällekkäisten solujen määrä näytetään erikseen.

Roihussa paketti voidaan purkaa omaksi hakemistokseen ja ajaa yhdellä
komentorivillä (ei tuotantohaaran checkoutia):

    unzip -oq "$HOME/MaaltaMerelle_LOW_02C_jarvikohtainen_D8_20261016.zip" -d "$HOME"
    D="$HOME/low_d8_lakes_20261016/diagnostics/low_d8_scope"
    B="/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000/02_baseline"
    Rscript --vanilla "$D/test_incoming_02c_lake_d8.R" && Rscript --vanilla "$D/run_incoming_02c_lake_d8.R" "$B"

Tässä uudessa ajossa odotetaan aiempien LOW-tulosten 535 yksilöllistä
nollasolua ja 1 273 järvestä tulevaa osoitinta; seitsemän 02F-päätesolun
välittömät lähdejärvitunnukset 3181, 1892, 1894 varmistetaan. **Järvien
kokonaislukumäärää ei arvata etukäteen.** Uudet synteettiset R-testit ja
todellisen aineiston järvikohtainen ajo odottavat Roihun tuloksia.
Edellisen 02C-aggregaatin tekninen PASS ei yksin todista uusia
järvikohtaisia laskureita oikeiksi.

## 1c. Lähdejärvittäin ryhmitetty katkeava D8 (Roihu PASS)

Laajennettu `incoming_02c_lake_d8.R` sekä `run_incoming_02c_lake_d8.R`
laskevat järvitunnuskohtaiset **erilliset D8=0-maasolut**, järvestä tulevat
**osoitinreunat** ja mahdolliset useasta järvestä vastaanottavat maasolut.
Ne käyttävät osion 1b **täsmälleen samaa rajattua lukua**; tämä ei ole uusi
koko rasterin käsittely.

Todellisen LOW Roihu-testin PASS (16.10.2026; synteettiset ryhmittely-,
päällekkäisyys-, summatarkistus- ja virhesyötetestit PASS):

- **22 lähdejärveä**; **535 eri maasolua**, joihin tulee D8-osoitin
  RANTA10-järvestä; **1 273 järvi-D8-osoitinreunaa**.
- Järvikohtaisten nollasolujen summa 535; **0** nollasolua, joihin tulisi
  osoittimia kahdesta eri järvestä.
- Järvitunnus `3181`: **317 solua / 785 reunaa** (noin 59,3 % ja 61,7 %
  otoksen kokonaismääristä). Järvi `1847`: **88 / 197**.
  Yhdessä **405/535 = 75,7 % soluista** ja **982/1 273 = 77,1 % reunoista**.
- Seuraavat `1898` (**26 / 55**) ja `1832` (**15 / 32**);
  alkuperäiset 02F-lähdejärvet `1892` (**3 / 8**),
  `1894` (**10 / 19**) sekä `3181` (**317 / 785**).
- Järviä, joilla on 1 / 2–4 / 5–9 / vähintään 10 tällaista maasolua:
  **1 / 9 / 6 / 6**.
- Näissä tuloksissa ei ole tehty järven kokoon, rantaviivan pituuteen,
  maastotyyppiin tai järven todelliseen purkupisteeseen perustuvaa
  normalisointia. **Pelkkä määrällinen keskittyminen ei todista järvien
  3181 tai 1847 olevan suhteellisesti hydrologisesti huonompia.**

**Tieteellinen status pysyy REVIEW_REQUIRED.** Tuloksella ei hyväksytä eikä
muuteta purkuyhteyttä, D8:aa tai DEM:iä. 22 järveä on **02C-otoksen
osoitinreunoissa esiintyvien järvien määrä**, ei koko LOW:n kaikkien
mahdollisesti ongelmallisten järvien määrä. Mahdollinen jatkotehtävä on
rantaviivan pituudella tai järven reunan solumäärällä normalisoitu vertailu
siten, että tarkistetaan geometria sekä erilaisten lähdeaineistojen rajaukset.

## 1d. Lähdejärvien rantaviivan pituuteen suhteutettu vertailu (ODOTTAA ROIHIU-TESTIÄ)

[README_shoreline.md](README_shoreline.md) sisältää erillisen read-only
geometriavertailun lähdejärville 3181, 1847 sekä muille 20 02C:stä
vahvistetulle lähdejärvelle. Scriptit:

- `lake_shoreline_rates.R` — vektorirantaviivan laskenta rajattuna LOW:n ruutuun;
  ruuturajan kanssa yhtyvät keinotekoiset viivasegmentit vähennetään.
- `test_lake_shoreline_rates.R` — synteettinen metri/km-, liittymä-,
  virhesyöte- ja sf-geometriatesti, jos sf on asennettu.
- `run_lake_shoreline_rates.R` — käyttää saman 02C:n 22 järven
  validoidun D8-laskennan, mutta lisää RANTA10:n `lakes`-GPKG-geometrian
  pinta-alasta riippumattoman rantaviivapituuden (km) sekä suhdeluvut.

Raportoitavat suhdeluvut ovat **02C-rantavyöhykeotoksen D8-katkeamissolut /
RANTA10-vektorirantakilometri** ja vastaavat osoittimet / km. Ne **eivät**
ole mallin virheprosentteja, eivätkä oikaise 02C:n otosrajausta.
Vain raportointia. Koodin rakennetarkistus valmis; tämän uuden geometrisen
R-ajon PASS odottaa vielä Roihun todellisia tuloksia. **Ei Slurm-ajoa.**

## 1d. Riippumaton nimittäjä: kaikki järven D8 → maasolu -osoittimet

**Tätä koko LOW:n laskentasolmuvaihetta EI OLE AJETTU.** Aiemmissa 02C- ja
rantaviivatesteissä tunnistettiin 535 välitöntä järvi-D8 → maasolu D8=0
-katkoskohtaa, 1 273 osoitinta, 22 lähdejärveä. Niiden osuutta **kaikista**
järvestä maalle osoittavista D8-reunoista ei voi laskea 02C:n
`02C_zero_pointer_water_neighbors.csv`-tiedostosta: se on otos, joka on
poimittu **nollasolujen kautta**, joten sen käyttö nimittäjänä aiheuttaisi
valikoitumisharhan.

`lake_to_land_d8_core.R` ja `test_lake_to_land_d8.R` toteuttavat
pienen riippumattoman base-R-kernelin ja synteettiset regressiotestit
(lohkorajan yli osoittava D8, saman maasolun useampi järviosoittimen tulo,
toisen järven vastaanotin, ulos tileltä, D8=NA, D8>0 ja puuttuvan
yhden rivin haloikkunan suljettu käsittely). Synteettinen testi:

    Rscript --vanilla diagnostics/low_d8_scope/test_lake_to_land_d8.R

`scan_entire_low_d8.R` käyttää **samaa tulevaa 64 rivin lohkoskannausta**
sekä alkuperäistä `d8_pointer_land_water_FLT8S.tif`,
`ranta10_water_class.tif`- ja `ranta10_lake_id.tif`-rasteria
molempiin tehtäviin: koko LOW:n nollasolujen inventointiin ja kaikkien
järvi-D8 → maa-osoittimien laskentaan. Ei toista raskasta skannausta.
Järville raportoidaan (1) kaikki järvi→maa-osoittimet, (2) välittömästi
D8=0-vastaanottajaan johtavat osoittimet, (3) positiiviseen D8-osoittimeen
johtavat osoittimet, (4) D8-NA-vastaanottajat, (5) erilliset zero-kohdesolut
sekä (6) välitön nollapääteosuus (2)/(1). Nimittäjässä ovat vain
**ruudun sisäiset**, kartoitetusta järvestä **maa-vesiluokkaan (NA)** johtavat
kelvolliset Whitebox D8 -osoittimet. Ei esimerkiksi veteen tai ruudun
ulkopuolelle johtavia osoittimia. Jos nimittäjä on 0, osuus jää puuttuvaksi
eikä muutu 0:ksi.

`scan_entire_low_d8.R` vaatii `SLURM_JOB_ID`-ympäristömuuttujan;
raskasta ajoa **ei** saa suorittaa Roihun kirjautumissolmulla.
Ennen laskentasolmuajoa käyttäjän tulee hyväksyä resurssit ja laskentatyö.
Raportti vertaa aiemman 22 järven 1 273 välitöntä nollaan johtavaa
osoitinreunaa / 535 erillistä nollavastaanottajaa; ristiriita
pysäyttää ajon tieteelliseen REVIEW_REQUIRED-tarkasteluun. Ensimmäisiä
nimittäjätuloksia ei ole vielä olemassa.

**Tärkeä tulkinta:** vastaanottavan maasolun D8≠0 ei takaa
katkeamatonta jatkoreittiä. Näin mitattu osuus on **välitön D8-nollaan
päättymisosuus**, ei koko virtausverkon toimivuusprosentti.

## 2. Koko LOW-rasterin kattava nollasolujen inventointi — EI VIELÄ AJETTU

scan_entire_low_d8.R lukee 64 rivin lohkoissa jo olemassa olevat D8-, RANTA10-vesiluokka- ja RANTA10-järvitunnusrasterit, yhden rivin naapurihaalolla. Se laskee kaikki sisäiset ei-vesisolu-D8=0-solut, järven viereiset sisäiset nollat ja järvestä suoraan nollaan tulevat D8-osoittimet sekä samassa lukukierroksessa täydellisen järvi-D8 → maasolu -nimittäjän. Se ei vielä kartoita kaikki D8-NA-arvoja, syklejä, domain exittejä eikä koko verkon reittijakaumaa.

**Ajo kielletty Roihun login-solmulla.** Ohjelma pysähtyy, ellei SLURM_JOB_ID ole asetettu oikeassa laskentatyössä. R/terra-toteutusta ei vielä ole ajettu todellisella CSC-R-ympäristöllä. Laskentatyön resurssit ja hyväksyntä sovitaan ennen Slurm-käynnistystä; älä kierrä laskentasolmusuojia. Ohjelma ei kirjoita rastereita, ja tulostaa vain aggregaattiluvut.

Kutsurajapinta hyväksytyssä laskentatyössä:

    Rscript --vanilla diagnostics/low_d8_scope/scan_entire_low_d8.R BASELINE_DIR SOURCE_DIR

## 3. Tieteellinen vaihtoehtoarvio

[SCIENTIFIC_OPTIONS.md](SCIENTIFIC_OPTIONS.md) vertailee nykyisen D8:n säilyttämistä, järven käsittelyä omana verkkosolmuna ja riippumatonta purkuevidenssiä, tasakorkeuskäsittelyä sekä RANTA10–MML-raja- ja STORAGE-herkkyystarkasteluja. **Mikään niistä ei valitse uutta purkupistettä tai tee D8-korjausta.**

NATIONAL LOCKED; MODERATE REVIEW_REQUIRED. SYKEn tunnetut lähteiköt tutkitaan erikseen issue #9:ssä **myös silloin kun D8 != 0**; maa-ainesta tai turvepaksuutta ei lisätä malliin.
