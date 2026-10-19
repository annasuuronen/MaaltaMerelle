# MODERATE 02D.4: rantakynnys ei ole rasterikorotus

Päiväys: 16.10.2026. Tarkastettu lähdecommit:
`7050b582edab3195669529f366b4f5a2915488c6`, `baseline-no-structures`.
Tämä muutos lisää vain diagnoosin ja pienet synteettiset regressiotestit.
Tuotannon laskentaa, tuloksia, luokittelua tai rastereita ei muuteta.

**Johtopäätös:** `spill_raised=TRUE` ilmaisee nykykoodissa positiivisen
äärellisen rantakynnyksen suhteessa lähtöpinnan järvitasoon. Se ei mittaa
Whiteboxin tekemää korotusta. Siksi 52 positiivisen kynnyksen ja nollan
korotussolun yhdistelmä ei yksin todista rasterien erotuslaskennan virhettä.
Sen tulkitseminen 52 toteutuneeksi järven korotukseksi on luokittelutulkinnan
virhe. **Kaikkien 52 järven täyttymättä jäämisen fysikaalista tai
laskennallista syytä ei voi ratkaista toimitetuista yhteenvetoluvuista.**
Reuna-/NoData-geometria ja Whiteboxin erikoistapaukset ovat aidosti erillisiä
vaihtoehtoja, jotka pienet kokeet erottavat.

MODERATE:n 52 järveä säilyvät `REVIEW_REQUIRED`-tilassa, syyllä
`POSITIVE_SHORE_THRESHOLD_NO_OBSERVED_RAISE`. NATIONAL pysyy `LOCKED`.
Tekninen QA ei ole tieteellinen hyväksyntä. Tuotantokorjausta tai yhdistämistä
ei ehdoteta ennen tieteellistä katselmointia.

## Näyttö ja sen rajat

Käyttäjän toimittamat todellisten CSC-auditointien tulokset:

| Havainto | Ilmoitettu tulos |
| --- | ---: |
| Järviä | 158 |
| Positiivinen `spill_raise_m` | 52 |
| `raised_cells_all` / `lowered_cells_all` | 0 / 0 |
| `surface_na_mask_mismatches` | 0 |
| `spill_raised_lakes_with_zero_raised_cells` | 52 |
| D8-vertailun soluja | 36 000 000 |
| D8-arvoeroja / virheellisiä suuntakoodeja | 0 / 0 |

Näitä käytetään käyttäjän toimittamana ajonäyttönä. Alkuperäisiä CSV-tiedostoja,
lokeja tai CSC-rastereita ei luettu eikä niiden tiivisteitä tai Slurm-tilaa
varmennettu tässä tehtävässä. Historiallista EVIDENCE.md:tä ei kirjoiteta
jälkikäteen uudelleen.

Arkistoidun auditointiskriptin korotus-/laskulaskurit käyttävät rajaa `1e-7 m`.
Pelkkä kahden laskurin nolla todistaa korkeintaan toleranssin sisäisen eron;
täsmällinen arvoidenttisyys edellyttää lisäksi minimi-/maksimieron nollaa tai
muuta arvovertailua. NA-maskien nollaero ei tarkoita, ettei yhteisessä maskissa
olisi NoData-soluja. Tässä diagnoosissa huomioidaan myös käyttäjän vahvempi
ilmoitus pintojen identtisyydestä, mutta sitä ei johdeta pelkistä laskureista.

D8-arvojen ja suuntakoodien yhtäläisyys ei todista pinnan täyttämisen
onnistumista, järven oikeaa purkautumista tai koko reitin hydrologista
oikeellisuutta. Samankaltaiset pinnat voivat antaa saman pointerin; kaksi
eri pintaa voi myös antaa saman pointerin. D8-QA ja pinnan korotus-QA ovat eri
kysymyksiä. Ei valita uusia purkupisteitä eikä D8-suuntia tämän perusteella.

## Lähdekoodin laskentaketju

Viitteet koskevat yllä mainittua lähtöcommittia, jonka tuotantotiedostot
säilyvät tässä muutoksessa ennallaan.

1. [02A: LAND RAW ja LAND FILL](../R/02_build_baseline_hydrology.R#L167):
   järvien `lake_id`-solut poistetaan maa-DEM:stä NA:ksi. Maapinta täytetään
   `fix_flats=TRUE`-asetuksella. Tämä voi muuttaa rantanaapurien korkeuksia
   jo ennen STORAGE-vaihetta; vertailukohta ei ole alkuperäinen fyysinen DEM.
2. [02A: LAND + LAKE](../R/02_build_baseline_hydrology.R#L267):
   `W = cover(land_fill, lake_z)`. Kanoninen `lake_z` tuotetaan
   [01-vaiheessa](../R/01_prepare_hydrology_inputs.R#L342) ID:n korkeusattribuutista.
   `cover` suosii kuitenkin äärellistä ensimmäistä argumenttia. Jos LAND FILL
   olisi muuttanut järven NA-maskiinsa äärellisiä soluja tai välimuisti olisi
   eri ajosta, tulos ei välttämättä olisi ID-kohtaisesti vakio. Tämä on
   tarkistettava oletus, ei tässä todettu virhe.
3. [02A: WATER STORAGE](../R/02_build_baseline_hydrology.R#L305):
   `S = FillDepressions(W, fix_flats=FALSE)`. Olemassa olevat tiedostot
   ohitetaan `OVERWRITE=FALSE`-tilassa; nimi ja geometria eivät todista
   saman ajokerran provenienssia. V2-resume-skripti kopioi olemassa olevat
   02A-pinnat omaan tuloshakemistoonsa. Se ei siten itsessään todenna uutta
   STORAGE-täyttöä.
4. [02D.1](../R/02_build_baseline_hydrology.R#L2586): luetellaan järvisolujen
   kahdeksan naapurisuunnan sisäiset rasterinaapurit ja poistetaan saman
   järvi-ID:n sisäiset parit. Solulle rasterin ulkopuolella ei synny paria.
   `storage_raise_m = S(source) - W(source)` on toteutunut **lähdesolun** muutos.
   `max_storage_raise_m` on rantaparien lähdesolujen maksimi, ei automaattisesti
   kaikkien järvisolujen maksimi. Osittainen sisäsolukorotus voi jäädä siltä
   huomaamatta; 02D.4 tarkistaa kaikki ID:n järvisolut.
5. [02D.2](../R/02_build_baseline_hydrology.R#L3296): alin rantaparin STORAGE-taso
   valitaan **vain äärellisistä** pareista. NoData-naapuri ei osallistu
   minimiin. Järven vertailutaso on lähtöpinnan `lake_z_m`-arvojen mediaani
   kaikista rantapareista. Muuttujan nimi `lake_z_unique` ei tarkoita
   `unique()`-suodatusta: sama lähdesolu voi esiintyä usean rantaparin kautta.
   Epätasaisella järvipinnalla kyseessä on reunaparien lukumäärällä painottuva
   mediaani, ei varmennettu yhteinen vedenkorkeus.
6. [02D.2A](../R/02_build_baseline_hydrology.R#L4027): `storage_raised` ja
   `spill_raised` lasketaan eri suureista, molemmat kynnyksellä `1e-7 m`.
   `spill_tol_m=1e-6 m` puolestaan ryhmittelee matalia rantareunoja; se ei ole
   rasterikorotuksen kynnys.
7. [02D.4](../R/02_build_baseline_hydrology.R#L4828): komponentit muodostetaan
   ehdosta `S-W > 1e-7 m`, kahdeksan naapurin yhteydellä. Kun kaikki erot ovat
   nollia, korotuskomponenttien ja korotettujen järvisolujen puuttuminen on
   laskennallisesti oikea tulos. Myös komponenttirasterilla on tiedostoon
   perustuva välimuisti; riippumaton pintojen erotusauditointi on siksi arvokas.
   Luokka [`SPILL_RAISED_NO_COMPONENT`](../R/02_build_baseline_hydrology.R#L5045)
   yhdistää positiivisen rantakynnyksen ja puuttuvan korotuskomponentin. Se ei
   ole todistus kadonneesta komponentista tai toteutuneesta korotuksesta.

Muodollisesti, järvelle i ja sen äärellisille ulkorantapareille E_i:

```text
L_i = median(W(source))                   # rantaparien lähtötaso
T_i = min_E_i max(S(source), S(receiver))  # alin paikallinen äärellinen kynnys
spill_raise_m(i) = T_i - L_i
storage_raise_m(source) = S(source) - W(source)
raised_component_mask(x) = [S(x) - W(x) > 1e-7]
```

Esimerkki: lähtöpinnan tasainen järvi on 10 m ja kaikki äärelliset
rantanaapurit ovat 12 m. Sekä muuttumattomalla pinnalla (järvi edelleen 10 m)
että oikein 12 metriin täytetyllä pinnalla `spill_raise_m=2 m`. Todellinen
järvisolun `storage_raise_m` on vastaavasti 0 m tai 2 m. Sama rantakynnys
ei siis yksilöi toteutunutta täyttöä.

## Whitebox ja `fix_flats=FALSE`

Tarkistettu julkinen WhiteboxTools v2.4.0 -lähde:
[`fill_depressions.rs`, commit 28ed01f…](https://github.com/jblindsay/whitebox-tools/blob/28ed01f506f2024cfb52db85348b887f2ded4e5d/whitebox-tools-app/src/tools/hydro_analysis/fill_depressions.rs).
Tämä ei ole varmennus CSC:ssä suoritetusta binääristä tai sen versiotulosteesta.

Täyttö ja tasanteen keinotekoinen gradientti ovat eri osat. V2.4.0:ssa
`outlet_found` käynnistää painanteen korotuksen rivien 483–502 lohkossa
riippumatta `fix_flats`-asetuksesta. `fix_flats=FALSE` asettaa
`small_num=0` ja ohittaa myöhemmän gradientin rakentamisen (rivi 530).
Se **ei** tarkoita `FillDepressions`-täytön poiskytkemistä.
R-whitebox 2.4.3 jättää `--fix_flats`-lipun pois arvolla FALSE.
Tuotannon STORAGE-kutsu ei anna `max_depth`-rajaa; tarkistetun lähteen oletus
on ääretön. Käyttöliittymän perusteella ei siis ole syytä päätellä
tarkoituksellista syvyysrajoitusta.

Algoritmi etsii aluksi sisäsoluista pit-ehdokkaita. NoData-naapuri estää
solun valinnan pit-ehdokkaaksi (rivit 328–340); ulkoreunan soluja ei
tarkastella samoina sisäsoluina. Alueen kasvatus etsii alempaa vielä
käsittelemätöntä naapuria ja korottaa vain, jos ulostulo löytyy.
Näillä yksityiskohdilla on merkitystä NoData- ja reunaerikoistapauksissa.
NoDataa ei pidä ilman erillistä hydrologista päätöstä käsitellä fyysisenä
purkautumisreittinä. Tasannekorjauksen kytkeminen TRUE:ksi voisi peittää
ongelman keinotekoisilla korkeuseroilla; sitä ei tehdä tässä.

## Pienet regressiot ja toistettava vertailu

`tests/spill_storage_semantics.R` suorittaa vain tuotantotiedostosta
poimittuja puhtaita laskentalohkoja: rantainventaarion, alimpien reunojen
ryhmityksen, erotusmaskin, komponentit ja luokittelun. Se ei suorita koko
pipelinea, lataa oikeita syötteitä tai muuta 108 järven referenssitestejä.
Synteettinen seitsemän rivin rasteri ei ole TEST_SULKU_11-referenssi.

Yhdeksän perustarkistusta erottavat mm. positiivisen kynnyksen todellisesta
korotuksesta, koko järven komponentin rantamaksimista, alle toleranssin
muutoksen nollasta sekä tasaisen järven epätasaisesta vertailutasosta.
Lisäksi testataan tuotannon kaksi todellista FillDepressions-kutsuasetusta.
Valinnaiset neljä Whitebox-koetta käyttävät 7×7-rastereita ja yhtä säiettä.
Whiteboxin tuottaman komentorivin prosessipaluukoodi säilytetään ja
tulospinnan arvot tarkistetaan, ei vain tiedoston olemassaoloa.

Tässä työtilassa käytetty binääri ladattiin vain repositorion
`ci-testdata-validation-gradient/ci/whitebox/whitebox_tools`-fixturestä,
ilman rasteriaineistoja. SHA256 tarkistettiin **ennen suorittamista**
arkistoskriptien odotusarvoa vastaan:
`96bb47a9d1f0fe8a3cb46df524242c990eab9bc2ae1930e540e09328331172e4`.
Versiotuloste: WhiteboxTools 2.4.0. Binääriä tai uusia rastereita ei lisätä Gitiin.

| Synteettinen tapaus | `spill_raise_m` | Korotetut järvisolut | Merkitys |
| --- | ---: | ---: | --- |
| 3×3-järvi tasolla 10, reuna 12, ulkopuolella alempi 8 m | 2 m | 9 | FALSE täyttää tavallisen suljetun painanteen. |
| Yhden solun järvi rasterin ulkoreunalla, äärelliset naapurit 12 m | 2 m | 0 | Rajattu domain voi tuottaa kynnyksen ilman korotusta. |
| Yhden solun järvi NoData-naapurin vieressä, muut naapurit 12 m | 2 m | 0 | NoData voi estää pit-ehdokkaan, vaikka äärellinen minimi on positiivinen. |
| 3×3-järvi 10 m, kaikki muu domain tasan 12 m | 2 m | 0 | Tässä versiossa toistettu täyttöalgoritmin rajoite: alempaa ulkopuolista naapuria ei löydy. |

Viimeinen tapaus ei ole yleisesti perusteltu hydrologinen syy jättää suljettua
allasta täyttämättä. Reuna-arvot 12 m antavat tavanomaisessa reunoille
purkautuvassa minimax-täyttömallissa täyttötasoksi 12 m. Whiteboxin palauttama
10 m osoittaa synteettisen algoritmisen erikoistapauksen, ei että se olisi
MODERATE:n 52 tapauksen todellinen syy. Samoin yksittäinen NoData-koe ei
oikeuta väitettä, että kaikki NoDataan koskevat järvet jäisivät täyttymättä.

Komennot repositorion juuresta:

```sh
source /workspace/hydro-env/activate.sh
Rscript tests/spill_storage_semantics.R
HYDRO_TEST_WHITEBOX_EXE=/workspace/cloud-tools/whitebox_tools-moderate-diagnosis Rscript tests/spill_storage_semantics.R
```

Ilman binääripolkua yhdeksän perustarkistusta suoritetaan ja neljä
integraatiotapausta merkitään eksplisiittisesti ohitetuiksi. Binääripolun
kanssa odotetaan 13 läpäistyä tarkistusta ja prosessin paluukoodia 0.
Paikallinen ympäristö: R 4.2.2, terra 1.7.29 ja whitebox-R 2.4.3.
Terra ilmoittaa olevansa rakennettu R 4.2.3:lla; yllä olevat toiminnalliset
testit läpäisivät tässä ympäristössä. Uusia raskaita ajoja ei tarvita testiin.

## Diagnoosi ja vähimmät seuraavat tarkistukset

**Vahvistettu kooditasolla:** suureet ovat eri asioita ja 02D.4:n nolla
korotuskomponenttia on pintojen identtisyydellä odotettu tulos. Tämän perusteella
ei pidä korjata erotusmaskia tai luoda komponentteja rantakynnyksestä.
`spill_raised`-nimen ja komponenttipohjaisen tulkinnan yhdistäminen on
harhaanjohtavaa. Se on tulevan erikseen katselmoitavan luokittelumuutoksen
peruste, ei todiste siitä, että STORAGE-täyttö onnistui oikein.

**Avoin 52 järven syy:** seuraavat vaihtoehdot eivät erotu yhteenvetoluvuista:

1. Reunaan ulottuva, katkennut tai NoDataan rajoittuva järvimaski; ulkoinen
   reitti puuttuu äärellisten rantaparien minimitarkastelusta. Myös saman ID:n
   erilliset komponentit ja täytön naapuruusoletukset on erotettava.
2. Pit-ehdokkaan tai alemman ulostulon löytymiseen liittyvä Whitebox-rajoite.
   Sen mahdollisuus on osoitettu pienillä kokeilla, mutta ei 52 järvelle.
3. Väärä tai eri ajosta kopioitu/välimuistissa säilytetty STORAGE-pinta,
   eri binääri tai syötemaski; geometria ja samannimisyys eivät sulje tätä pois.
   Retry-apuri tarkistaa ei-tyhjän tiedoston, ei täytön fysikaalista oikeellisuutta.
4. Epätasainen lähtöpinnan järvitaso, `cover`-etuoikeus, ID-/korkeusmaskien
   ero tai alle toleranssin muutokset. Nämä vaativat omat havaintonsa eivätkä
   selitä vahvistettua tarkkaa nollaeroa automaattisesti.

Nopein jatko on pyytää ensin **jo olemassa olevat** pienet raportit ja
niiden provenienssi, erikseen hyväksytyn tiedostokohtaisen menettelyn kautta:

- Yhdistä `lake_audit.csv`, `02D_spill_group_diagnostic.csv` ja
  `02D_lake_depression_component_summary.csv` ID:llä; varmista 52:n tarkka
  ID-joukko, kynnysarvot, toleranssit ja auditoitujen solujen määrät.
- Lue jo tehdyn `moderate_fill_recheck_20261014`-kokeen `summary.csv`,
  `lake_summary.csv` ja olemassa oleva loki **jos ne ovat saatavilla**.
  Tuore vs vanha -vertailu voi erottaa vanhan välimuistin toistuvasta
  algoritmikäyttäytymisestä ilman uutta täyttöajoa. Näiden tiedostojen
  olemassaoloa tai tulosta ei oleteta.
- Tarkista olemassa olevasta ajolokista todellinen komento, binäärin
  versio/tiiviste, exit ja pinnan syöte-/tulosidentiteetti. Varmista
  `min_storage_minus_routing_m=max_storage_minus_routing_m=0`, jos väitetään
  tarkkaa arvoidenttisyyttä.
- Olemassa olevista rantaryhmäraporteista saa `touches_raster_edge`-tiedon,
  mutta vain valituille alimmille äärellisille ryhmille. Se ei kata kaikkia
  järvisoluja eikä NoData-yhteyksiä. Jos kattava pieni topologiaraportti
  puuttuu, seuraavaksi tarvitaan erikseen hyväksytty rajattu lukutarkistus
  52 järven kaikkiin osiin: ulkoreuna, äärellinen/NoData-ranta, lähtöpinnan
  min/max ja vakioisuus, geometria, ID-maskit ja paikallinen ulostuloyhteys.
  Uutta 36 miljoonan solun täyttöä ei pidä tilata ensimmäiseksi.

Jos järvi on varmasti sisäinen, yhtenäinen ja tasainen, sillä ei ole
NoData-yhteyttä ja sitä ympäröi kaikissa kahdeksassa suunnassa korkeampi
äärellinen ranta, tavallisen reunoille purkautuvan täyttömallin pitäisi
korottaa sitä. Nollakorotus tällaisessa tapauksessa on tutkittava
laskenta-/provenienssipoikkeama, ei kuitattavissa pelkällä terminologialla.
Kun taas reunageometria selittää tarkistettavan tapauksen, positiivinen
äärellinen kynnys voi olla luettelon ominaisuus ilman todellista täyttöä.
Ennen näitä erottavia havaintoja kumpaakaan selitystä ei yleistetä 52 järveen.
