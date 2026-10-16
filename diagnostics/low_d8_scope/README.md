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

## 2. Koko LOW-rasterin kattava nollasolujen inventointi — EI VIELÄ AJETTU

scan_entire_low_d8.R lukee 64 rivin lohkoissa jo olemassa olevat D8- ja RANTA10-vesiluokkarasterit, yhden rivin naapurihaalolla. Se laskee kaikki sisäiset ei-vesisolu-D8=0-solut, järven viereiset sisäiset nollat, ja järvestä suoraan nollaan tulevat D8-osoittimet. Se ei vielä kartoita kaikki D8-NA-arvoja, syklejä, domain exittejä eikä koko verkon reittijakaumaa.

**Ajo kielletty Roihun login-solmulla.** Ohjelma pysähtyy, ellei SLURM_JOB_ID ole asetettu oikeassa laskentatyössä. R/terra-toteutusta ei vielä ole ajettu todellisella CSC-R-ympäristöllä. Laskentatyön resurssit ja hyväksyntä sovitaan ennen Slurm-käynnistystä; älä kierrä laskentasolmusuojia. Ohjelma ei kirjoita rastereita, ja tulostaa vain aggregaattiluvut.

Kutsurajapinta hyväksytyssä laskentatyössä:

    Rscript --vanilla diagnostics/low_d8_scope/scan_entire_low_d8.R BASELINE_DIR SOURCE_DIR

## 3. Tieteellinen vaihtoehtoarvio

[SCIENTIFIC_OPTIONS.md](SCIENTIFIC_OPTIONS.md) vertailee nykyisen D8:n säilyttämistä, järven käsittelyä omana verkkosolmuna ja riippumatonta purkuevidenssiä, tasakorkeuskäsittelyä sekä RANTA10–MML-raja- ja STORAGE-herkkyystarkasteluja. **Mikään niistä ei valitse uutta purkupistettä tai tee D8-korjausta.**

NATIONAL LOCKED; MODERATE REVIEW_REQUIRED. SYKEn tunnetut lähteiköt tutkitaan erikseen issue #9:ssä **myös silloin kun D8 != 0**; maa-ainesta tai turvepaksuutta ei lisätä malliin.
