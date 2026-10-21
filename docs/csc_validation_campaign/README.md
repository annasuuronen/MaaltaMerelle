# MaaltaMerelle: neljän alueen CSC-testikampanjan valmistelu

**Tila: OFFLINE-SUUNNITELMA. EI CSC-AJOLUPA.** Tämä hakemisto toteuttaa [issue #26](https://github.com/annasuuronen/MaaltaMerelle/issues/26): neljän validointialueen kokeiden inventaario, rajaukset ja fail-closed-ajoihin valmistautuminen. Tämä ei yhdistä LOW-tutkimusketjua, muuta hydrologista tuotantokoodia eikä käynnistä CSC- tai Slurm-työtä.

## Neljä todellista validointialuetta

| Rooli | Aluetunnus | Yksilöllisiä rakenteita 12 km:n valintainventaariossa | Käyttö |
| --- | --- | ---: | --- |
| NATURAL | E0560000_N7690000 | 0 | Luonnontilaisen vertailualueen tarkistus |
| LOW | E200000_N6900000 | 1 | Ensimmäinen vesikontakti, D8 ja 02G:n metodinen tutkimus |
| MODERATE | E0510000_N7620000 | 3 | Painanteet, rantakynnykset ja 02E-QA |
| HIGH | TEST_SULKU_11 | 11 | Rakenteettoman mallin rajoitusten tunnistaminen rakenteisessa ympäristössä |

Alkuperäinen valinta ja aineistoluettelo: [validation_gradient_selection.csv](https://github.com/annasuuronen/MaaltaMerelle/blob/ci-testdata-validation-gradient/ci/VALIDATION_GRADIENT/validation_gradient_selection.csv) ja [validation_gradient_manifest.csv](https://github.com/annasuuronen/MaaltaMerelle/blob/ci-testdata-validation-gradient/ci/VALIDATION_GRADIENT/validation_gradient_manifest.csv), aineistohaaran commit 4518285f0c74c01f12c96d6d831515846260d1a4.

- **HIGH = TEST_SULKU_11, ei viides alue.** HIGH:n DEM- ja DEM_QA-kentät ovat validointimanifestissa tyhjiä. Erillinen CI-testirasteri ei vielä todista oikeaa CSC-DEM:n identiteettiä.
- LOW:n valintataulukon canonical_tile_id on E0200000_N6900000, mutta area_id on E200000_N6900000. Älä oikaise eroa hiljaisesti: vahvista ennen CSC:n todellista syöteajoa.
- **NATIONAL ei ole testialue**, vaan tila LOCKED.
- Baseline-versio ei mallinna patojen, sulkujen eikä muiden hydraulisten rakenteiden vaikutusta. HIGH:lla ei saa tulkita niitä hyväksytyiksi läpivirtauksiksi.

## Offline-testimatriisi

[test_matrix.csv](test_matrix.csv) sisältää yhdeksän riviä neljälle alueelle. Joka rivillä on kokeen ID ja alue, hypoteesi, commit-viite, aikaisemman näytön **luokka**, syöteidentiteetin ehto, lukuraja, resurssiarvion tila, riippuvuudet, vastuurooli, onnistumis-/keskeytysehdot ja hyväksyntäportti.

Suunnitelman jokaisen rivin hyväksyntä = USER_APPROVAL_REQUIRED, uuden kokeen tekninen tila = NOT_RUN ja tieteellinen tila = NOT_ASSESSED. Erillinen REPORTED_LOCAL_PASS -luokka voi kuvata aiempaa synteettistä testiraporttia, **ei** CSC:n todellista hyväksyttyä ajoa.

## Turvallinen ehdotettu järjestys

1. Tarkista inventaario, syötecommitit, 12 km:n aineistojen identiteetti ja mahdolliset aukot **vain offline**. Älä toista jo hyväksyttyjä testejä.
2. Selvitä Roihun kirjautumissolmun SSH-este (issue #14). Vasta sen poistuttua, todellisen syöteidentiteetin ja erillisen käyttäjähyväksynnän jälkeen LOW:n rajattu PR #22 -koe: **14 lukittua vastaanottajasolua × neljä rasteria = 56 palautettua arvoa**. Ei reitin jatkamista eikä lisäikkunalukua.
3. MODERATE: tarkista todellinen hostin muisti-/allokaatiotodiste erillään 02D.4:n hydrologisesta diagnoosista. Pidä MODERATE=REVIEW_REQUIRED.
4. NATURAL: vahvista ensin todelliset rasterit ja suunnittele vasta sitten erillinen paikallinen ensimmäisen vesikontaktin koe.
5. HIGH: vahvista puuttuva DEM-viite ja rakenteeton vertailukoe erillisenä, ilman rakenteiden mallinnusoletuksia.
6. Kaiken uuden 02G-kertymän, hajautetun tiilikäsittelyn tai 4 ha:n uomaverkon todelliset kokeet ovat **tämän PR:n ulkopuolella** ja tarvitsevat omat hyväksynnät.

## Standardikirjastolla toimiva, paikallinen tarkistin

Komennot suoritetaan projektin juuresta:

    python3 docs/csc_validation_campaign/offline_plan.py validate
    python3 -m unittest discover -s docs/csc_validation_campaign -p 'test_offline_plan.py' -v

Uusi pelkkä dry-run-suunnitelma:

    mkdir -p /tmp/maalta-merelle-campaign-plan
    python3 docs/csc_validation_campaign/offline_plan.py plan --out /tmp/maalta-merelle-campaign-plan

Työkalu ei ota verkkoyhteyttä eikä suorita Slurm-komentoja. Se vahvistaa neljä täsmällistä aluetta, ID:t, commit-muodon, UNKNOWN/NOT_ESTIMATED-rajaukset, kiinteän 56-arvon LOW-portin ja tilat. Se kirjoittaa deterministisen plan.json + plan.sha256 -parin olemassa olevaan tuloshakemistoon **vain kerran**; aiempaa suunnitelmaa ei saa ylikirjoittaa. Dry-run-ID **ei ole** CSC-ajon ID.

Tämä skripti **ei** varmista rasteritavuja, varsinaista syöte-SHA:ta, hostin muistia eikä käyttäjähyväksyntää. JSON:ssa niiden tilat ja execution_enabled pysyvät false. Esimerkkikomennon tarkoitus on ainoastaan näyttää, että suunnitelma on ristiriidaton eikä voi muuttaa vanhaa FAIL/NOT_RUN-merkintää PASS:ksi.

## Rajat

Ei muutoksia R/-hakemistoon, muihin testeihin, GitHub Actions -työnkulkuihin, DEM:iin, D8:aan, STORAGEen, RANTA10-maskeihin, järvien ulosmenopisteisiin tai olemassa oleviin tuloksiin. Ei ssh-, srun-, sbatch-, FirecREST- tai automaattisia työkomentoja. Ei PR:n yhdistämistä. Ei vanhojen kampanjoiden uusinta-ajoja.

hydrological_validation=NOT_ASSESSED

channel_interpretation=NOT_ASSESSED

MODERATE=REVIEW_REQUIRED

NATIONAL=LOCKED

Lisää lähteitä ja hyväksyntäportteja: [provenance_and_gates.md](provenance_and_gates.md).
