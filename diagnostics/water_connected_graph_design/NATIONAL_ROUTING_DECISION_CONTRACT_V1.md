# Valtakunnallinen WATER_CONNECTED-D8: päätössääntöjen suunnitelma v1

**Tila:** DESIGN_ONLY / REVIEW_REQUIRED. Ei tuotantoreititystä, muutoksia korkeusmalliin, D8:aan, STORAGEen, RANTA10-maskeihin, SYKE-purkupisteisiin eikä hyväksyttyihin järvipurkuihin. Tämä dokumentti on pinottu G3:n jälkeen; kansalliset ajot ovat edelleen lukittuja.

## A. Ongelma ja rajaus

MaaltaMerelle tarvitsee 2 metrin ruudukossa maalta merelle johtavan yhtenäisen virtausverkon. Nykyinen 02C tunnistaa rantavyöhykkeen D8-nollapointerikomponentteja; 02D kirjaa spill-/reunavaihtoehtoja; 02E valitsee vain tarkasteltavia ehdokasryhmiä; 02F jäljittää ehdokkaiden nykyisen LAND_WATER-D8:n **vain ensimmäiseen päättymistilaan**. Se ei vielä ratkaise järven aktiivista purkua tai rakenna WATER_CONNECTED-D8:aa.

LOW ei ole tilastollisesti edustava otos Suomesta. Sen tehtävä on tuottaa **regressiotapauksia ja suunnittelun vastaesimerkkejä**. Kansallinen toimivuus on arvioitava riippumattomalla, maantieteellisesti kerrostetulla testiaineistolla.

## B. Keskeinen periaate: evidenssi ei ole hyväksyntä

Pidä neljä erillistä käsitettä:
1. **Lähdehavainto:** suoraan olemassa olevista aineistoista laskettu sijainti, luokka, solun osoitin tai attribuutti.
2. **Yhteensopivuus:** esimerkiksi 02C-rasterinaapuri vastaa RANTA10-vektorin 2m solujalanjälkeä; SYKEn valuma-alue-ID on sama.
3. **Reittihypoteesi:** täsmällisesti yksilöity ehdokas `origin_lake → receiver_lake/river`, jonka väliaskelten suunta, korkeusrajoitteet ja topologia on arvioitava.
4. **Hyväksytty hydrologinen yhteys:** vasta tulevassa hyväksyntämenettelyssä, joka edellyttää päätössääntöjen, riippumattoman näytön ja julkaisukriteerien täyttymistä. **Tässä suunnitelmassa tällaisia yhteyksiä ei tuoteta.**

Merkitse kaikille havainnoille `source_role = INPUT | AUXILIARY | INDEPENDENT_REFERENCE`. Jos sama SYKE-/RANTA10-lähde vaikuttaa ehdokkaan muodostamiseen, sen vastaavuus ei ole riippumaton validointi.

## C. Päätöstilan ehdotus

| Tila | Merkitys | Saako muodostaa tuotanto-D8-reitin? |
|---|---|---|
| OBSERVED | Geometria / 02C–02F-inventaario saatavilla | Ei |
| CANDIDATE | Lähde-, vastaanottaja- ja osittainen topologinen hypoteesi | Ei |
| REVIEW_REQUIRED | Monitulkintainen vesiluokka, puuttuva väliaskel, epävarma virtaussuunta, lähderistiriita | Ei |
| REJECTED | Täsmällinen ja dokumentoitu mahdottomuus, ei vain puuttuva lähdekohde | Ei |
| VALIDATED | Tuleva hyväksyntäportti: riippumaton näyttö ja graafin invarianssit täyttyvät | Vasta erikseen avattavassa tuotantovaiheessa |
| NOT_ASSESSED | Kyseistä näyttöä ei ole vielä tuotettu | Ei |

**Älä sekoita** testiajon `PASS`-tilaa hydrologiseen `VALIDATED`-tilaan. `SAFE_LAKE_CONNECTOR` on 02C-algoritmin *vesinaapuriluokitus*, ei hyväksytty järvipurkuyhteys. Komponentitön tai nollaan päättyvä yhteys jää havainnoksi, ei täytetyksi painanteeksi.

## D. Ehdokkaan vähimmäistietomalli

Rivi yhdelle **yksilölliselle reittiehdokkaalle**, ei jokaiselle rinnakkaiselle rannansivulle:
- `region_id`, `grid_id`, EPSG:3067, solukoko ja ruudun todelliset `xmin/xmax/ymin/ymax`; syöteruudun ja reunahalojen tunnisteet.
- `origin_lake_id`, `receiver_type` (`LAKE | RIVER_AREA | RIVER_LINE | UNKNOWN`), `receiver_id` tai `NA`; suunnattu hypoteesi erillään havainnosta.
- `source_cell`, `receiver_cell`, `terminal_cell`, `component_id`, nykyinen `02F_route_status`, `steps`, `origin_receiver_key`.
- RANTA10-solukeskiön ja solujalanjäljen geometriatiedot, lähellä olevien jokiviivojen yksilölliset `fid/objectid`-tunnisteet sekä SYKEn valuma-alue-/purkupiste-ID:t vain lähderoolinsa mukaisina.
- `evidence_version`, manifestin SHA-256 tai vastaava provenienssi, algoritmiversio, `reason_codes`, `decision_state`, `independent_validation_state` sekä tarkastelupäivä.
- Jos täysi D8-soluketju ei ole käytettävissä, merkitse `route_geometry=SUMMARY_ONLY`. Älä generoisi ketjua yhteenvedon perusteella.

Aggregoi ehdokkaat vähintään avaimella `(origin_lake, receiver_cell)` ja jäljitä lisäksi todellinen `terminal_cell`; eri lähtösolut, jotka yhtyvät samaan komponenttiin, **eivät ole riippumattomia hydrologisia todistuskappaleita**. Rajojen yli kulkevat ehdokkaat tarvitsevat johdonmukaisen identiteetin viereisten ruutujen kesken.

## E. Poikkeamatyypit ja turvalliset säännöt

| Tyyppi | Tunnistus | Sallittu automaattinen tulos |
|---|---|---|
| E1: LAND-D8_ZERO lähellä vettä | D8=0 sisäsolussa; nykyinen 02C-tunniste ja lähellä vesinaapuri | Havainto + syykoodi `ZERO_NEAR_WATER`; ei reitin lisäämistä |
| E2: MONILUOKKAINEN vesinaapuri | 02C `MIXED` (esim. LAKE + RIVER_LINE_ONLY) | `REVIEW_REQUIRED:MULTI_WATER_CLASS` |
| E3: mahdollinen järvestä toiseen | 02F:n lähtöjärvi ja läheinen vieras järvi, mutta terminaali on LAND-D8_ZERO | `CANDIDATE:UNRESOLVED_LAKE_LINK`, ei `REACHES_OTHER_LAKE` |
| E4: rasteri/vektori-rajapinta | Solujalanjälki leikkaa vesivektoria, vaikka keskipiste ei osu | `OBSERVED:BOUNDARY_PIXEL`, ei rasterin tai maskin korjausta |
| E5: puuttuva kartoitettu jokiviiva | Järvien väliltä ei löydy RANTA10-viivaketjua asetetulla toleranssilla | `NOT_ASSESSED:MAPPED_LINE_GAP`; ei automaattista hylkäystä |
| E6: purkupiste lähellä rantaa | SYKE-piste osuu järvipolygonin rajaan tai sisään | `AUXILIARY_MATCH`; ei purkuaukon hyväksyntää |
| E7: ruutureunan katkeaminen | Reitti poistuu tarkasteluruudusta tai halosta | `REVIEW_REQUIRED:TILE_BOUNDARY`, jatkokohteen identiteetin tarkistus |
| E8: sisäjärven palautus / silmukka | 02F `RETURNS_TO_ORIGIN_LAKE` tai `D8_CYCLE` | Havaintoluokka, ei automaattista korjausta |

**STOP-portit** ennen ehdokkaan korottamista tulevassa vaiheessa: ei riittävää provenienssia; epäselvä solun CRS/ruudukko; tasojen identiteettiristiriita; puuttuva täydellinen väliaskelten kulku; aktivoitavan reitin D8-jatkuvuus tai korkeusrajoitteet ratkaisematta; ristiriita riippumattoman referenssin kanssa; tuntematon rengas-/sykliriski tai ruuturajaliitos.

## F. LOW:sta otettavat lukitut regressiohavainnot

1. **Järvet 1894 ja 1892:** korkeusattribuutit 0,44m vs 0,37m (ero 0,07m ei yksin todista virtaussuuntaa). Vektoripolygonien väli 38,12m. RANTA10-jokiviiva fid29/objectid129081 koskettaa järveä1894, jää 22,78m järvestä1892, eikä 0–10m toleranssilla löydy viivaketjua molempien rantojen välille. **Kuusi** eri 02F-lähtöä, askeleita 21–24, päättyy samaan sisäiseen LAND-D8_ZERO-soluun 23211319 / komponentti274 lähellä järveä1892. Odotettu turvallinen päätös: `CANDIDATE+REVIEW_REQUIRED`; `hydrological_validation=NOT_ASSESSED`.
2. **Järvi3181, komponentti235:** neljä järvi3181-vesinaapuria + yksi class3/RIVER_LINE_ONLY-naapuri, `MIXED/INTERIOR_REVIEW`, vaikka hyvin lähellä oleva komponentti236 on `SAFE_LAKE_CONNECTOR`. Sama lähin RANTA10-jokiviiva fid8/objectid57590. Odotettu päätös: `MULTI_WATER_CLASS` ja alkuperäisen 02C-luokituksen säilyttäminen.
3. **RANTA10-solujalanjäljet:** 18/18 alkuperäisistä naapurisoluista leikkaa odotettua 2m lähdegeometriaa; vain **kuusi 18:sta** solukeskuksesta osuu odotettuun geometriaan (**6/17** järvisolun keskusta ja **0/1** jokiviivasolun keskusta). Keskiöosumattomuus ei tarkoita rasterivirhettä. Solukeskusten laskenta käyttää oikeaa 6000×6000 LOW-rajausta, ei oletusarvoista TEST_SULKU_11-ruutua.
4. **SYKE-purkupiste7025519:** noin 0,04m vektorirantaviivasta (XY pyöristetty 0,1m), sama valuma-aluetunniste kuin neljällä järvi3181-komponentilla. Odotettu luokitus `AUXILIARY_MATCH`, ei `VALIDATED_OUTLET`.
5. **02F-tasot:** 101 yksilöllistä lähtöjärvi+vastaanottajasolu-reittiyhteenvetoa; niistä 41 päättyy D8_ZERO_INTERIOR-tilaan vain seitsemään erilliseen 02C-soluun. Odotettu laskenta: ei 41 riippumatonta virhettä tai 41 hyväksyttyä korjauskohdetta.

**Huomio:** LOW:n korkeusarvot, lake ID:t, solut ja vesinaapurit ovat yhden ruudun havaintoja. Näiden perusteella EI aseteta koko maata koskevia kovia etäisyys-, pinta-ala-, korkeusero- tai toleranssirajoja.

## G. Synteettiset ja kansallisesti riippumattomat testit

**Synteettinen yksikkötestipaketti ilman CSC-laskentaa (seuraava toteutus):**
- Järvet 38m erillään, jokiviiva päättyy ennen vastaanottavaa järveä: ei hyväksyntää.
- Kaksi erilaista vesityyppiä samassa rantakomponentissa: `REVIEW_REQUIRED`.
- Järvipolygonin nurkkaa vain hipaiseva 2m rasterisolu: rasterin ja keskipisteen ero tunnistetaan ilman muutosta.
- 6 lähtöä → yksi nollaterminaali: yhteensulautuminen, identiteetit ja riippumattomuus oikein.
- SYKE-piste 0m rannasta mutta väärä purkusuunta: vain apuaineistovastaavuus.
- Componentless-case / puuttuva vastaanottaja: havainto, ei täytetty painanne.
- Syklinen reitti, ulos ruudusta katkeava reitti ja viereisten tilejen päällekkäiset reunasolut: ei vahingossa `VALIDATED`-tilaa.
- Lähdeaineistojen laittomat muutokset, puuttuvat kentät ja vanhentunut manifesti: STOP.

**Maantieteellinen koesuunnitelma ennen NATIONAL-lukon arviointia:** kerrostetut, LOW:sta erilliset alueet, joissa rannikko, matalat järvien väliset korkeuserot, sisämaan pienet lammet, turvemaat, uomaverkko, vähäiset/puuttuvat RANTA10-jokiviivat, kallio-/rinnealueet, ruuturajat, tiheä vesistökontakti, rumpukorjaukset ja korkeusmallin virheet. Huomioi ennakkoon kunkin luokan otosyksikkö, riippumaton referenssi ja epävarmuus. Raportoi vähintään **tapauksittainen oikeellisuus, väärän hyväksynnän osuus, arvioimatta jääneiden osuus, graafin jatkuvuus, syklit ja suorituskyky**, erikseen ennen yhteenlaskettua kansallista arviota. Ei valtakunnallista onnistumisprosenttia yhdestä LOW-ruudusta.

## H. Toteutuksen vaiheistus

**S0 – nyt:** dokumentoi terminologia, portit, poikkeamat, LOW-regressiot, ja rakentamisen/validoinnin erottelu. Tässä vaiheessa ei ole lupaa muuttaa hydrologisia syötteitä.

**S1 – suunniteltu GitHub/Codex:** puhtaasti funktionaalinen, synteettisillä pienillä verkoilla testattu luokitin: `observations → evidence/reason_codes/decision_state`. Ei rasterikirjoitusta, automaattista D8-patchia eikä osittaista vahvistusta; `VALIDATED` ei ole mahdollinen ilman tulevaa erillistä hyväksyntäporttia. Luokittele myös alkuperäisen 02F-yhteenvedon kattamattomat täydet soluketjut `NOT_ASSESSED`.

**S2 – suunniteltu rajattu CSC:** sparse/read-only reittiketjutarkistus vain ennalta valituille epäselville ehdokkaille, laskenta vain jo olemassa olevista rastereista, erikseen rajatuissa ajoissa. Kirjaa myös resurssikustannus, dataprovenienssi, reunahalot ja tiedostojen lukuikkunat.

**S3 – myöhemmin riippumaton validointi:** eri maantieteelliset alueet ja tieteellisesti riittävät ulkopuoliset vertailut. Mallin läpäisy edellyttää, että väärien hyväksyntöjen riskitaso ja tuntemattomien osuus sovitaan ennen testausta.

**S4 – erillinen päätös:** vasta kun S1–S3:n tulokset on arvioitu, voidaan keskustella WATER_CONNECTED-D8:n toteutuksesta ja kansallisen lukon avaamisen ehdoista. Tämän dokumentin perusteella **ei avata** `NATIONAL`- tai `MODERATE`-tilaa.

## I. Avoimet tieteelliset päätökset

Ennen tuotantomenetelmää on vielä määriteltävä:
- Onko automaattinen purkuyhteyden vahvistus ylipäänsä sallittu ilman riippumatonta referenssiä, ja mille rajatulle tapaustyypille?
- Miten määritellään korkeuseron mittausepävarmuus ja aineistojen korkeustasojen yhtenevyys (7cm LOW-esimerkki ei riitä kynnykseksi)?
- Millä perusteella RANTA10-jokiviivan puuttuminen tulkitaan tietopuutteeksi eikä yhteyden puuttumiseksi?
- Mikä on keskenään riippumattomien testitapausten yksikkö (esim. vesistökontaktikomponentti, järvipari, kokonainen osavaluma-alue)?
- Millainen virheellinen positiivinen yhteys on menetelmälle hyväksyttävissä ja millainen edellyttää kovaa STOPia?
- Miten todistetaan koko verkon yhdistyminen mereen, ruutujen rajasiirtymät ja ettei D8-syklejä tai keinotekoisia nollapointereita jää tuotantoon?

**Tieteelliset lukot:** `NATIONAL=LOCKED`, `MODERATE=REVIEW_REQUIRED`, `hydrological_validation=NOT_ASSESSED`, `channel_interpretation=NOT_ASSESSED`. PR pysyy luonnoksena.