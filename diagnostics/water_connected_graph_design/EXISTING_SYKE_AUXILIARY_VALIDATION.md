# Olemassa olevien SYKE-apuaineistojen käyttö LOW- ja valtakunnallisessa validoinnissa

**Status:** DRAFT – tieteellinen validointisopimus, ei uusi laskenta eikä hyväksytty reititys. Tämä täsmentää `docs/validation_gradient.md`-suunnitelmaa ja PR #38/#39:n WATER_CONNECTED-evidenssityötä. **Ei aineistojen hankintaa, uudelleenmuodostamista eikä muuttamista.**

## 1. Käyttäjän vahvistama nykyinen aineistokokonaisuus

| Aineisto | Nykyinen käyttö | Tässä työssä sallittu näyttö | Mitä siitä ei saa päätellä |
|---|---|---|---|
| MML:n 2 m korkeusmalli + SYKEn uoma-/rumpukorjaus | Yhdistetty nykyiseksi `dem_12km_rumpukorjattu.tif`-syöte-DEM:ksi | Syötteen provenienssi, menetelmän geometriayhteensopivuus ja toteutusregressiot | Ei riippumaton testi DEM:n oikeellisuudesta. Alkuperäistä erillistä korjausrasteria ei oleteta olevan Roihulla. |
| SYKEn valtakunnalliset purkupisteet | Jo käytettävissä projektin apuaineistona; tarkoitus auttaa purkureitin tulkintaa | Olemassa olevan pisteen ja purkureittiehdokkaan **vastaavuus / ristiriita**, kun tunnisteet, geometria ja käytön historia on tarkistettu | Pelkkä pisteen läheisyys ei osoita toimivaa virtausreittiä eikä oikeuta kirjoittamaan uutta tuotantopurkupistettä. |
| SYKEn valtakunnallinen valuma-aluejako | Jo käytettävissä projektin apuaineistona | Valuma-alue- ja vastaanottajaverkon **topologiavertailu**, rajojen laadun ja mallin yhteensopivuuden analyysi | Ei automaattisesti riippumaton mittaus 2 m reitityksestä; lähtöaineistoissa voi olla yhteistä alkuperää. |
| RANTA10-järvet, jokialueet, jokiviivat ja rasteroidut maskit | Vesistöluokan ja `lake_objectid`-identiteetin syöte | Lähdeskeeman, vesistöidentiteetin ja rantakontaktigeometrian sisäinen QA | Sama lähtöaineisto ei voi yksin toimia riippumattomana validointitotuutena. |

**Pysyvät säännöt:** alkuperäisiin DEM-, D8-, STORAGE-, RANTA10-maskien, valtakunnallisen valuma-aluejaon ja purkupisteaineiston tiedostoihin ei tehdä muutoksia. `NATIONAL=LOCKED`; `MODERATE=REVIEW_REQUIRED`; `hydrological_validation=NOT_ASSESSED`; `channel_interpretation=NOT_ASSESSED`. Nykyinen `outlet_selection=UNASSIGNED` jää ennalleen. Lopullinen WATER_CONNECTED-D8 ja flow accumulation ovat vielä rakentamatta.

## 2. Evidenssin kaksi roolia on pidettävä erillään

1. **Apu-/muodostustieto**: purkupistettä, valuma-aluetta tai RANTA10-tietoa on katsottu ehdokkaiden suodattamiseen, suunnan päättelyyn, algoritmin korjaamiseen tai käsin tehtyyn valintaan. Sen kanssa yhtenevä tulos on `AUXILIARY_CONCORDANCE`, **ei** riippumattoman hydrologisen validoinnin PASS.
2. **Vertailutieto, jota ei ole käytetty menetelmän muodostamiseen**: voidaan raportoida `HELD_OUT_COMPARISON` vain, jos pisteiden/alueiden valinta, versio, geometria, kytkentä ja tarkastelun riippumattomuus on etukäteen dokumentoitu. Saman lähdejärjestelmän ja DEM-juuren riippuvuus merkitään erikseen. `HELD_OUT_COMPARISON` ei vieläkään tarkoita havaittua maastototuutta.

Jos yksittäisen SYKE-pisteen käyttöhistoriaa ei tiedetä, sille annetaan `REFERENCE_USE_UNKNOWN`, ei keinotekoista holdout-statusta. Vertaillut kohteet voivat olla tunnettuja referenssejä, mutta **totuusluokka** pysyy `NOT_ASSESSED`, ellei siihen ole erillistä näyttöä. Järven, valuma-alueen ja lähdepurun suhde täytyy dokumentoida; pisteiden lukumäärää ei rinnasteta itsenäisten alueiden määrään.

## 3. Oikean aineiston löytyminen ennen uutta liittymätarkistusta (G0)

Repo vahvistaa 2 m `DEM_FILE`-syötteen ja RANTA10:n lukutavan `R/00_pipeline_config.R`- ja `R/01_prepare_hydrology_inputs.R`-tiedostoista. **Käyttäjän Roihun terminaalista 22.10.2026 toimittama rajoitettu tiedostonimilista vahvistaa olemassa olevien SYKE-Shapefilejen sijainnin**. Alla ovat todetut tiedostopolut; muita alueita ei haettu eikä tiedostoja avattu:

- Hakemisto: `/scratch/project_2004707/pienvedet/open_data/SYKE_VALUMAALUEJAKO_LATEST/`.
- Purkupisteet: `Valumaaluejako_purkupiste.shp` (+ `.shx`, `.dbf`, `.prj`, `.cpg` ja sivutiedostot).
- Valuma-aluejaon tasot: `Valumaaluejako_taso1.shp` … `Valumaaluejako_taso5.shp` (+ vastaavat sivutiedostot).
- Hakemistossa on myös `valumaalueet_latest.zip`; älä pura ZIPiä tai muodosta uudelleen näitä jo valmiita aineistoja.

**G0: sijainti ja tiedostoperheet löytyivät; G0-metadatan tarkastus yhä NOT_RUN.** Shapefilejen sisäisiä kenttiä, koordinaatistoa, feature-lukumääriä, voimassaolo-/julkaisupäivää tai LOW:n todellista pistepeittoa **ei** ole tässä vielä tarkistettu. Hakemiston `LATEST`-nimi ei yksin vahvista aineistoversion ajankohtaisuutta. Älä oleta rakennekenttiä tai hae korvaavia aineistoja.

Seuraava Codex/GitHub-valmistelu:
- Tarkista ensin nykyiset projektimanifestit/konfiguraatiot ja mahdolliset tiedostolistaukset **read-only**; älä käynnistä tiedostojärjestelmän rajoittamatonta rekursiivista hakua.
- Kun jo olemassa olevien alkuperäisten tiedostojen tarkat polut löytyvät, laadi **vain metatiedot** raportoiva, rajattu ja auditoitava CSV/GPKG/SHP-inventaario (nimi, koko, CRS, layer, geom-tyyppi, kentät, identiteetti ja alkuperäisen aineiston versio jos saatavilla). Älä kirjoita, siirrä, täydentäviä rasterointeja tee tai laske massiivisten aineistojen SHA256-tiivisteitä. Älä paljasta suojattua sisältöä.
- Luo kuuden kentän provenienssisopimus per piste-/alueaineisto: `source_path_or_id`, `source_version`, `used_in_build_or_candidate_review`, `reference_role`, `shared_lineage` ja `verification_state`. Jokainen puuttuva arvo on `UNKNOWN`, ei hyväksyntä.

**G0-osa 1 (tiedostonimet ja sijainti) on käyttäjän Roihu-tulosteen perusteella suoritettu; G0-osa 2 (alkuperäisten lähdemetatietojen tarkastus) on NOT_RUN.**

## 4. LOW:n olemassa oleva 02C/02D/02E/02F-evidenssi (G1)

Käyttäjän 22.10.2026 Roihun konsolista toimittamat, vanhoihin CSV-tiedostoihin perustuvat tulokset:

- `02F_water_connected_route_evidence.csv`: 101 yksilöllistä lähtöjärvi–vastaanottajasolureittiä; 41 `D8_ZERO_INTERIOR`, 21 `RETURNS_TO_ORIGIN_LAKE`, 34 `REACHES_RIVER_AREA`, 5 `REACHES_RIVER_LINE`. Näistä mikään ei ole vahvistettu reitti mereen.
- 41 nollaan päättyvää reittiä → **7** erillistä 02C:n nollapointersolua/komponenttia; alustava 02C-kohdejärvi on 33 reitillä **sama** kuin lähtöjärvi, 6 reitillä **eri**, 2 reitillä `INTERIOR_REVIEW/MIXED` eikä kohdetta ole.
- **Komponentti 274 / päätesolu 23211319:** 8 lähtöjärven 1892 reittiä palaa kohdejärveen 1892; 6 lähtöjärven 1894 reittiä käyttää samaa päätesolua, jonka alustava kohdejärvi on 1892. Jälkimmäiset ovat **1894→1892-yhteysehdokkaita**, eivät hyväksytty järvien välinen virtaus.
- **Komponentti 235 / päätesolu 15389414:** kaksi järven 3181 reittiä, `INTERIOR_REVIEW`, `MIXED`, kohdejärvi NA. Ei saa täydentää automaattisesti.
- **Järvi 1940:** 21 alkuperäiseen järveen palaavaa yksilöllistä reittiä 11 eri vesipäätesoluun. Palaaminen ei todista ulkoisen purun puuttumista.

Käyttäjän ilmoittamat alkuperäisten CSV:iden SHA256-tiivisteet: `02F_water_connected_route_evidence.csv` `402fdbf16cb41eaa6a3ad2180cc4d3af8534e32cff299d73eacec8dc5c187db5`; `02C_zero_pointer_cells.csv` `e72d231c2a3d1fed7cc26009921e8945747015772184f00b798be4aa2eb433bd`; `02C_shore_component_classification.csv` `fe84dd4b0d633ac87b802b23272c9ee3aaa580721c55130dede9fa3c99f71886`. Käyttäjän ilmoittamaa historiallista aineistoprovenienssia ei ole riippumattomasti tarkistettu.

## 5. Purkupisteiden nykyisen apuaineiston hyödyntäminen (G2, vasta G0:n jälkeen)

Tee pienellä, etukäteen lukitulla joukolla **read-only** vastaavuustaulukko:

| Kenttä | Merkitys |
|---|---|
| `origin_lake_objectid`, `spill_group_id`, `source_cell`, `receiver_cell` | Alkuperäisen 02D–02F-ehdokkaan identiteetti; rinnakkaisia ehdokkaita ei poisteta |
| `terminal_cell`, `route_status`, `component_id`, `target_lake_objectid` | Nykyinen havaintoreitti ja alustava 02C-kohde |
| `syke_outlet_point_id`, `syke_catchment_id` | Olemassa olevien apuaineistojen todelliset alkuperäiset tunnisteet; tuntematon sallitaan |
| `match_type`, `distance_m`, `geometry_relation`, `crs_check` | Ennaltamääritelty geometrinen vastaavuus ja epäselvyyden syy |
| `reference_role`, `shared_lineage`, `reference_version` | Estää sisäisen apuaineistovastaavuuden merkitsemisen riippumattomaksi testiksi |
| `outlet_selection`, `hydrological_validation`, `review_reason` | `UNASSIGNED`, `NOT_ASSESSED` ja eksplisiittinen epävarmuus säilyvät |

Tarkista koordinaattijärjestelmät ja lähdejärven/vastaanottajavesistön identiteetit ennen etäisyysvertailua; sallitut puskurit, pisteiden yksikäsitteisyys ja 4-/8-naapuruus on päätettävä ennakolta. Lähellä oleva piste on **todisteen osa**, ei yksin hyväksymispäätös. Jos usea ehdokas osuu samaan purkupisteeseen tai ehdokas kulkee toisen järven kautta, säilytä kaikki vaihtoehdot ja ristiriidat. Älä korjaa alkuperäistä purkupisteaineistoa.

Ensimmäiset neljä tieteellistä katselmoitavaa tapausta: komponentti 274 (1894/1892), komponentti 235 (3181), järven 1940 palautuvat reitit ja järven 1847 erillinen NW/STORAGE-tapaus, jolle ei ole nykyisessä 02E:ssä yhtään jatkoon otettua purkautumisehdokasryhmää.

## 6. Koko Suomen menettelyn testaus (G3–G5)

1. **G3 / LOW:** testaa 02C/02F-yhteyksien oikea luokittelu, aidosti erilliset komponentit, sisäiset paluut, ristiriitaiset SYKE-apupisteet ja tiedon puuttuminen. Tee nimenomainen ero `AUXILIARY_CONCORDANCE` vs. riippumaton mittaus. Mikään vertailu ei muuta tuotantorasteria.
2. **G4 / alueellinen holdout:** käytä jo olemassa olevia purkupisteitä ja valuma-aluejakoa mutta erottele käyttämättömät vertailualueet ennakkoon **valuma-alueittain**; arvioi niiden viiteaineistoriippuvuus, tarkkuus ja kattavuus. Lisää vain erikseen todettuja riippumattomia maasto-/virtaushavaintoja, jos aidosti riippumatonta näyttöä tarvitaan. Ennalta lukitut alueet: alavat/jyrkät maastot, suo-/ojitusympäristöt, runsasjärviset alueet, rannikot, rakenteelliset ylitykset ja ruuturajat.
3. **G5 / valtakunnallinen verkko:** vasta hyväksytyn WATER_CONNECTED-D8:n ja virtauskertymän jälkeen testaa rajojen yli jatkuvuus, mahdolliset syklit, vesistöidentiteetit, yksi-/monipurku-evidenssi, massatasapaino, puuttuvat ulkoiset virtaamat, lukujen nimittäjät ja alueittaiset epävarmuusvälit. Vertailua ei saa raportoida loppuunsa validoiduksi ennen topologista ja riippumatonta hydrologista hyväksyntää.

Raportin vähimmäistilat: `PASS`, `FAIL`, `REVIEW_REQUIRED`, `NOT_RUN`, `NOT_ASSESSED`; niiden merkitys sidotaan aina yksilöityyn testiin. Ei kansallisia virheprosentteja yhdestä LOW-ruudusta; 02F:n 101 reittiä eivät ole toisistaan riippumattomia satunnaisotantayksiköitä.

## 7. Muutosraja ja välitön työjono

Tämän dokumentin tarkoitus on korjata viiteaineistojen roolit **jo toteutetun työn pohjalta**. Seuraava turvallinen Codex-työ on G0:n repo-/manifestitarkastus ja sen jälkeen erikseen, vasta todella löytyville olemassa oleville SYKE-aineistotiedostoille rajattu metadata-audit. Ei GitHubiin aineistoja, ei vektorien/rasterien uudelleenmuodostusta, ei uutta DEM:iä, D8:aa, accumulationia, hyväksyttyjä purkupisteitä eikä CSC-ajoja.

**G0:** suunniteltu, ei suoritettu. **G1:** käyttäjän olemassa olevista CSV:istä toimittama inventaario valmis, hydrologisesti NOT_ASSESSED. **G2–G5:** NOT_RUN.
