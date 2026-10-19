# MaaltaMerelle – hydrologisen menetelmän kokonaiskuva 19.10.2026

**Tutkimuksen jatkuvuusmuistio, ei uusi analyysitulos eikä tuotannon hyväksyntä.** Tämä erillinen dokumentti yhdistää MaaltaMerelle-projektissa aiemmin toimitetut siirtomuistiot / Roihun tulostarkastelut ja 19.10.2026 GitHubista tarkistetut kehityshaarat. Aiempi keskustelu- ja siirtomuistioaineisto ei ole uusi riippumaton rasterimittaus. CSC:n aktiivisia työvaraustiloja tai laskentasolmun tiedostoja ei tarkistettu tässä GitHub-katselmoinnissa.

**Pakolliset tieteelliset lukot: MODERATE=REVIEW_REQUIRED; NATIONAL=LOCKED.** Myös LOW:n avoimet reitit vaativat tutkimuksellisen katselmoinnin. Mitään luonnollista outletia, uutta D8-suuntaa tai 02D.5-portin ohitusta ei hyväksytä tällä dokumentilla.

## Tutkimuksen yhteinen tarkoitus

Rakennetaan RANTA10:n ja 2 m DEM:n perusteella jäljitettävä pintavesireittien hydrologinen lähtöketju: järvien rantakynnysten ja virtausyhteyksien evidenssi, lopullinen myöhemmin hyväksyttävä D8, virtauskertymä, tiilirajojen ylittävät siirrot ja solukohtainen sekä globaali jatkuvuus- ja massatase-QA. Ihmisen tekemät rakenteet eivät ohjaa baseline-reititystä; mahdollinen vaikutustieto on ensin vain erillistä osittelua/QA:ta. SYKEn lähteikkövalidointi on oma [issue #9](https://github.com/annasuuronen/MaaltaMerelle/issues/9), eikä sitä rajata vain D8=0-tapauksiin. 02G:n alkuperäiset prototyypit ja geometriatestit eivät siirtomuistion mukaan olleet tuotantoon integroituja tai todellisessa R-ympäristössä hyväksyttyjä: tarkista ne erikseen, älä siirrä vanhaa suunnitelmatilaa automaattisesti nykyiseksi PASSiksi.

Käyttörajoitettujen VMI-/routatutkimusten raaka-arvoja, arkaluonteisia lokitietoja tai CSC-tunnuksia ei saa tuoda julkiseen GitHubiin. MaaltaMerelle ja EIFFEL ovat erilliset projektit.

## GitHubin ajantasaiset tutkimushaarat (tarkistettu 19.10.2026)

| Linja | GitHub-lähde ja tarkistettu HEAD | Tila |
| --- | --- | --- |
| LOW D8 -tutkimus | [Draft PR #12](https://github.com/annasuuronen/MaaltaMerelle/pull/12), `codex/low-d8-scope-options`, `cd9612aa1cb4dd39bc6b33d825302202b28ef09e`, base `baseline-no-structures` | Avoin; ei yhdistetty, ei lopullista outletia |
| MODERATE 02D.4–02D.5 | [Draft PR #7](https://github.com/annasuuronen/MaaltaMerelle/pull/7), `codex/moderate-02d4-diagnosis`, `2130eb8919c6aa8e7ff6c55c2d22580eb17e37a2` | Avoin; vain erillistä diagnostista koodia ja dokumentointia |
| LOW 02F:n rannan päätepisteiden diagnoosi | [PR #11](https://github.com/annasuuronen/MaaltaMerelle/pull/11), [issue #10](https://github.com/annasuuronen/MaaltaMerelle/issues/10) | Omat erilliset diagnostiset rajat |
| MODERATE 02D.5:n näyttöportti | [Issue #13](https://github.com/annasuuronen/MaaltaMerelle/issues/13) | Synteettisesti testattu luokittelija, ei hydrologinen ratkaisu |
| CSC kirjautumisympäristö | [Issue #14](https://github.com/annasuuronen/MaaltaMerelle/issues/14) | Käyttäjä ilmoitti 19.10. että yhteys toimii jälleen; tämän ajankohdan onnistunutta Login node shell -testitulostetta ei vielä ole dokumentoitu |
| `main` ja baseline | `main` `1146a81de97974f2275f1084c8be7b620aa1535d`; `baseline-no-structures` `7050b582edab3195669529f366b4f5a2915488c6` | Ei muutoksia tähän tutkimusmuistioon perustuen |

Uusin varmistettu MODERATE-CI: [run 38998807929](https://github.com/annasuuronen/MaaltaMerelle/actions/runs/38998807929), kaikki kuusi vaadittua työn päätöstilaa `success`; [CSC preflight 38998793711](https://github.com/annasuuronen/MaaltaMerelle/actions/runs/38998793711) `success`. Ne testaavat GitHubissa syntetisoitua koodia; eivät todenna Roihun 49 järven uutta ajoa. Downstream workflow -määritelmän oma commit ei ole sama kuin PR:n lähdecommit.

## LOW — oikealla Roihu-aineistolla raportoitu tutkimuslinja

LOW E200000_N6900000:n aiemmassa, valmistuneessa **read-only Slurm-työssä 2345102** (raportoitu `COMPLETED`, `ExitCode 0:0`) inventoitiin koko alueen D8-nollat. Ei-vesialueen D8=0-soluja oli **1 481**; niistä sisäisiä **719**, sisäisiä järven viereisiä **641**. Järvestä välittömästi D8=0-maasoluun osoittavia reunoja **1 273**, erillisiä vastaanottajia **535** ja kaikkia järvestä maalle osoittavia reunoja **2 998**. Osuus 1 273/2 998 eli **42,46 %** koskee vain **välittömiä** nollavastaanottajia, ei koko alavirran reittien epäonnistumista. Älä toista tätä koko alueen Slurm-työtä.

Järvi **1847**: aiemmat todelliset rajatut raportit osoittavat **198** järvi→maa-D8-reunaa, joista **197** päättyy heti D8=0-maasoluun ja viimeinen yhden maa-askeleen jälkeen; **88** erillistä nollavastaanottajaa. MML 2025 -järvipolygonin ja RANTA10:n paikalliset rajaukset eroavat: 1847:n 88/88 D8=0-maavastaanottajan keskipistettä sijoittuu MML:n järvipolygoniin, mutta eivät RANTA10:n järvipolygoniin. RANTA10:n alkuperäinen `touches=TRUE`-rasterointisääntö vastasi paikallista rasteria täsmällisesti; tämä ei ole automaattinen rasterointivirhe eikä MML:n luonnollisen purkukohdan todistus.

**Kohdennettu 02D.6-vs-D8 -ero, tärkein seuraava LOW-testi:**
- STORAGE-pinnan 02D.6:n komponentti **241** (`LOWER_ESCAPE`) löysi yhden alemman NW-reunan: `source_cell=11158308` → `receiver_cell=11152307`, STORAGE-pudotus noin **0,01015 m**; `gate_level_m≈12.175`.
- Saman lähdesolun **nykyinen LAND_WATER-D8 = 8 (S)**; NW vaatisi Whitebox-koodin 64. Lähteen suoraan eteläinen naapuri on `11164308`; NW-vastaanottajan oma D8 on **32 (W)**. Raportoitu 3×3-naapuruston korkeusvertailu tukee etelään osoittavaa alkuperäistä D8:aa paikallisen jyrkimmän laskun perusteella. STORAGEssa eteläisen/itäisen naapurin taso muuttuu, joten nämä ovat **eri pinnan** reitityskysymyksiä.
- Uusi tieto, jota ei vielä ole validoitu: **kaksi erillistä, lyhyttä read-only D8-jäljitystä saman nykyisen LAND_WATER-pointerin mukaan**, alkaen (A) `11164308` ja (B) `11152307`; pidä luetut solut, lopputila ja askeleet erillään. Ei D8:n 8→64-muutosta, ei pinnan muokkausta, ei outlet-hyväksyntää.
- PR #12:n `diagnostics/low_d8_scope/lake_1847_focus_core.R` sisältää jo käytetyn, enintään 256 askeleen yleisen `l1847_trace`-funktion. **Arvioi tämän uusiokäyttö ennen uuden algoritmin kirjoittamista**. Aiempi `run_lake_1847_focus.R` testaa 198/197/88-tapausta, mutta se ei itsessään todista näiden kahden uuden aloitussolun koko jäljitystä.

Koko LOW:n 02F-evidenssin 101 ehdokasvastaanottajareittiä jakautui 41 `D8_ZERO_INTERIOR`, 34 `REACHES_RIVER_AREA`, 5 `REACHES_RIVER_LINE` ja 21 `RETURNS_TO_ORIGIN_LAKE`. Nämä 41 päättyivät seitsemään erilliseen sisäiseen D8-nollasoluun; **ei** 41 itsenäistä koko järviverkon virhettä. 02E:n `outlet_selection` pysyy `UNASSIGNED`.

Lisälähde: [LOW:n tutkimuskoodit ja tieteelliset rajat](https://github.com/annasuuronen/MaaltaMerelle/tree/codex/low-d8-scope-options/diagnostics/low_d8_scope).

## MODERATE — oikean Roihun read-only -tutkimustulos ja jäljellä oleva syy

16.10.2026 ajettu MODERATE:n rajattu D8-/spill- ja geometriadiagnostiikka, RStudio `2354869` (raportissa R 4.6.1, terra 1.9.34), suoritti **molemmat** havaintoskriptit onnistuneesti. Tämä oli **vain havaintojen tekninen PASS**, ei uusittu Whitebox `FillDepressions` eikä vesireitityksen hyväksyntä. [Roihun tutkimusraportti](https://github.com/annasuuronen/MaaltaMerelle/blob/codex/moderate-02d4-diagnosis/docs/moderate_roihu_readonly_review_20261016.md).

- Yhteenvetorivejä **158**. **52** järvellä positiivinen `spill_raise_m` (rantakynnys) mutta **0** toteutunutta yli toleranssin olevaa `STORAGE-LAND_WATER`-korotettua järvisolua tai `n_depression_components`-komponenttia. Muilla 106 järvellä ei raportoitu korotuskomponenttia.
- 52 kohdejärvellä **29 290** järvisolua ja **14 192** rasterin sisäistä ulkorantanaapuruusparia. Kolme ulkorajalla: ID:t **203439, 203443, 203444**; **49** muuta ovat sisäisiä.
- Ei havaittuja välittömiä *rasterin sisäisiä* NoData-rantanaapureita. Lähdejärven min–max ei ylittänyt `1e-7 m` toleranssia. Kaukana sijaitsevan NoDatan tai koko algoritmin käyttäytyminen ei tästä ratkea.
- **162** alimman kynnyksen spill-rantareunaa; D8:ssa **159** paluuta lähtöjärveen ja **3** `TERMINAL_0` järvellä 204104, solussa 12373731. Yksikään ei sellaisenaan todista luonnollista outletia.
- Oikea V2-tuotanto pysähtyi vaiheessa 02D.5 vaatimukseen `all(spill_lakes$n_depression_components >= 1)`, joka ei täyty. Erillisessä vanhassa fixture-versiossa nähtyä 49/1-predikaattia **ei** saa käyttää oikean ajon ehdon korvikkeena.
- Alkuperäisen 02A STORAGE -pinnan Whitebox-komento-/binääri-/exit-/välimuistiprovenienssi on avoin. Erillinen `FillDepressions`-uusintayritys aikakatkaistiin (exit 124) ilman uutta vertailupintaa; **ei** uusi onnistunut täyttö.

Erillinen 02D.5-raporttiluokittelija ja 49 sisäjärven pieni ikkunakoetin ovat GitHubissa **synteettisesti** testattuina. Koko 49 järven todellista ikkunakoetta ei ole suoritettu: RStudio-kontissa aiemmin puuttuivat todennettava Slurm-muistiraja ja `scontrol`. Näitä puutteita ei saa korjata luottamalla pelkkään ympäristömuuttujaan. Uusi `scripts/roihu_existing_job_memory_check.sh` tekee ensin vain elävän varauksen/muistin tarkistuksen login-hostin `srun`-askeleen kautta. `MEMORY_PREFLIGHT_COMPLETE` **ei** ole hydrologinen tulos.

## Jatkojärjestys yhteyden toimiessa

**Yhteinen portti 0 (ei laskentavarausta):** vahvista itse, että CSC:n **Roihu-CPU → Tools → Login node shell** avaa kirjautumissolmun shell-kehotteen ja että `srun`/`scontrol` ovat saatavilla; ilmoitettu yhteyden palautuminen ei vielä ole tämän katselmoinnin mitattu todiste. Jos SSH edelleen hylätään, pysähdy ja jatka olemassa olevaa CSC-tukikeskustelua. Älä aja raskasta R-lukua kirjautumissolmulla.

**MODERATE portti 1:** vasta toimivan login-shellin jälkeen tee yksi tarkoitukseen sopivan lyhyt RStudio-varaus ja ota sen **uusi** `RUNNING`-job-ID. Käytä PR #7:n kiinnitettyä commit-versiota ja vain hostin varaus-/muistiesitarkistusta, ei vanhaa RStudio-kontissa estynyttä koko tutkimusajoa. Estyminen on `BLOCKED`, ei lupa ohittaa näyttöä.

**MODERATE portti 2 (erillinen hyväksyntä):** vahvista host-R/terra, olemassa olevat 02A-lokit ja ikkunakoettimen riippuvuudet. Vasta sitten rajattu **49 sisäjärven** read-only-koe samoilla korkeintaan 250 000 solua/ikkuna, 4 000 000 solua yhteensä ja 2 000 käyntiä/järvi -rajoilla. Ei uutta koko 36 miljoonan solun Whitebox täyttöä.

**LOW seuraava tieteellinen koe, erillään MODERATE:n Slurm-turvaportista:** valmistele kahden aloitussolun `11164308` (S) ja `11152307` (NW) askelrajoitettu, olemassa olevia rastereita vain lukeva D8-jäljitys. Erota lähtöpinta, nykyinen osoitin, D8-ketjun päätepiste ja mahdollinen luonnollinen purkutulkinta. Käytä PR #12:n testattua reittiydintä soveltuvin osin. Älä toista 2345102:n koko rasteriauditointia.

**Vasta näiden tulosten tieteellisen tarkistuksen jälkeen:** arvioi 02G:n erilliset R/terra-geometriatestit, luonnollinen purkuevidenssi, myöhemmin D8-/accumulation-/tile-transfer-/massatasetutkimus. Keskeneräisiä, ei-commitoituja 02G-siirtopaketteja ei väitetä nykyisen repohaaran osaksi.

## Työskentelyperiaatteet

- **Älä muokkaa vanhoja tiedostoja ilman osoitettua tarvetta.** Uusi itsenäinen testi-/katselmointiraportti omana tiedostonaan; ei olemassa olevien R-lähteiden tai CSV-tulosten päällekirjoitusta.
- Käytä ensin alkuperäisiä CSV-lokeja ja jo testattua rajattua koodia. Jokaisella uudella Roihu-ajolla on eri tutkittava hypoteesi ja selvät työbudjetit.
- Älä siirrä suuria tai käyttörajoitettuja rastereita julkiseen GitHubiin. Vain tarkistettu koodin/testin metatieto, rajattu turvallinen raportti ja viitteet.
- PR #7 ja PR #12 pysyvät erillisinä **draft**-tutkimuslinjoina; ei mergeä eikä tuotantoreitityksen muutosta.
- Projektin sisäinen tutkimuslupa ei ole sama kuin `MODERATE`-/`LOW`-/`NATIONAL`-hydrologinen hyväksyntä.

**Tila 19.10.2026:** yhteys on käyttäjän mukaan palautunut; uutta CSC:n laskentatulosta ei ole tässä dokumentissa väitetty. Seuraava näkyvä tulos on portin 0 login-shellin varmennus, sitten erillisesti rajattu tieteellinen testi.
