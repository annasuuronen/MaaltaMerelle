# MaaltaMerelle — CSC-vaihe 2A: turvallinen suunnittelu

Päiväys: 15.10.2026. Lähtöhaaran `baseline-no-structures` yhdistämiscommit: `ab9f61fbc445e72509716b93020884f535058c93`.

## Perusta ja rajaus

Tämä on **suunnitteluluettelo**, ei käyttäjän hyväksymä luku- tai siirtoallowlist. Ehdokaspolut on poimittu GitHubin `docs/csc/2026-10-14/EVIDENCE.md`- ja `artifacts.tsv`-dokumenteista. GitHub-arkisto **ei vahvista** CSC-tiedostojen nykyistä olemassaoloa, kokoa tai mitattua SHA256-tiivistettä. Luettelon olemassaolotila on `NOT_CHECKED`; mitään merkintää ei saa hiljaisesti korottaa `AVAILABLE`-tilaan.

Rajoitettu CSC-juuri (kontekstitieto, ei pääsyoikeus):

`/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02`

Vain kymmenen täsmällistä suhteellista polkua tiedostossa `MaaltaMerelle_vaihe2A_raporttiehdokkaat.csv`. Nimettyjä dynaamisia `qa_<jobid>.log`-, `audit_<jobid>.log`- tai muita logeja **ei** ratkaista globilla: niiden todellinen job-ID, polku ja tarkoitus on tarkistettava erikseen. Tässä vaiheessa ei lueta, siirretä tai pakata tiedostoja Roihusta.

## Toteutettava vaihe 2A (vain paikallinen koodi ja synteettiset testit)

1. Laadi riippumattomaan, katselmoitavaan lähteeseen perustuva ehdokasluettelo ja erottele se varsinaisesta *hyväksytystä* tiedostokohtaisesta allowlistasta. Manifesti ei saa itse hyväksyä omia polkujaan.
2. Määrittele eksplisiittinen fail-closed-sääntö: ilman riippumattomasti hyväksyttyä listaa mahdollinen myöhempi keruu/siirto on estetty. Kirjaa hyväksyntään rajattu toimenpide, juurihakemisto, tarkat polut, odotettu koko/tiiviste tai selvästi merkitty vielä selvittämätön tieto, voimassaolo sekä yksilöivä pyyntötunniste. Toteuta vasta pyyntöä seuraava paikallinen tarkistin — ei CSC-käyttöä.
3. Erottele tiedoston statuksen tilat `NOT_CHECKED`, `AVAILABLE`, `MISSING`, `UNREADABLE` ja `OUT_OF_SCOPE`; vain oikea, hyväksytty paikallinen tarkistus voi muodostaa uusia havaintoja.
4. Valmistele synteettisin tiedostoin regressiotestit väärälle polulle, symlink-kierrolle, kaksoisavaimille, tuntemattomalle job-ID:lle, tiedostokokorajalle, ristiriitaiselle SHA256:lle, puuttuvalle hyväksynnälle ja rikotulle commit-sidonnalle. Älä väitä simuloituja tapauksia CSC-näytöksi.
5. Säilytä vaiheen 1 sopimus, tekninen QA ja tieteellinen hyväksyntä toisistaan erillisinä. MODERATE:n 52 järveä pysyvät `REVIEW_REQUIRED`; NATIONAL ei aukea.
6. Testaa vain paikallisesti. Ei Slurmia, raskaita rastereita, SSH:ta, FirecRESTiä, GitHub-pushia tai PR:ää ilman seuraavaa hyväksyntää.

## Alustava pilotin sisältö

| Aineistoryhmä | Raportteja | Miksi tarkistetaan ensin |
| --- | ---: | --- |
| D8-arvovertailu | 2 | job-ID:n ja QA-CSV:n olemassaolo sekä teknisen D8-tuloksen laajuus |
| MODERATE 02D.4 -auditointi | 3 | järvikohtaiset poikkeamat ja 52 `spill_raised`-tapauksen tulkinta |
| MODERATE v2 | 5 | D8-muunnoksen ja komponentti-/spill-evidenssin tarkistaminen |

Nämä ovat **odotettuja** raportteja, eivät todennettuja tuloksia. Joitain v2:n raportteja ei ehkä syntynyt, jos ajo katkesi ennen kyseistä vaihetta. `MISSING` pitää todentaa; jos juurta ei voi tarkastaa, käytetään `NOT_CHECKED`.

## Pakolliset portit ennen vaihetta 2B

- Käyttäjälle esitetään kaikki tarkat polut, koot, rajaukset ja suoritettavat komennot.
- Käyttäjä hyväksyy **erikseen** vain määritellyn, CSC:n käytäntöjen salliman read-only-inventoinnin; mahdollinen tiedostosiirto tarvitsee oman erillisen hyväksyntänsä.
- Ei salaisuuksia ChatGPT:lle, GitHubiin, Codexille eikä Actionsiin.
- Ei uusia CSC-töitä tai automatisoituja uusintoja. Suuria rastereita, sisältötiivisteiden laskentaa niistä tai rajatonta hakemistoetsintää ei tehdä.
- Pienraporttien alustava enimmäiskoko on 5 MiB/tiedosto ja 25 MiB/paketti; nämä ovat enimmäisrajat, eivät siirtovaltuutuksia.
- Tiedostot pidetään ensisijaisesti CSC:ssä. Ennen ulos siirtämistä tarkistetaan myös mahdolliset tunnukset, henkilötiedot ja muut salassa pidettävät rivit.

## Tiedon lähde

GitHub: `annasuuronen/MaaltaMerelle`, `docs/csc/2026-10-14/EVIDENCE.md`, `docs/csc/2026-10-14/artifacts.tsv` ja `docs/csc/AUTOMATION.md`. V2-raporttien lähdecommit, mikäli ne kuuluvat lokissa kuvattuihin historiallisiin ajoihin, on tarkistettava erikseen (historiallinen `4bbf22bb...`, ei automaation nykyinen HEAD). Kuvitteellisia job-ID- tai SHA256-arvoja ei käytetä.
