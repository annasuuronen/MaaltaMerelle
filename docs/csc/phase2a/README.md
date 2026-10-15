# Vaihe 2A: offline-sopimus ja paikallinen allowlist-tarkistin

Lähtöcommit: `ab9f61fbc445e72509716b93020884f535058c93`.
Haara: `codex/csc-report-allowlist-phase-2a`. Worktree:
`/workspace/MaaltaMerelle-phase-2a`. Alkuperäinen checkout ja aiemmat
02D.4-muutokset eivät kuulu muutokseen.

Toteutussuunnitelma ja sen toteutusjärjestys:

1. Säilytä toimitetut lähteet ja muodosta kymmenelle ehdokkaalle vain
   `NOT_CHECKED`-alkuinventaario.
2. Määritä toisistaan erilliset ehdokas-, inventaario-, allowlist- ja
   pyyntösopimukset. Älä tee ehdokkaista hyväksyttyä listaa.
3. Tarkista riippumaton hyväksyntäsidonta ennen paikallisen raporttipolun
   koskettamista. Erota metadatan inventointi tavujen tarkistuksesta.
4. Testaa synteettiset hylkäykset sekä vaiheen 1 regressiot ja tyhjä testiajo.
5. Toimita diff ja tulokset paikallista katselmointia varten.

## Lähteet ja havaintojen rajat

- `PLAN.supplied.md` on käyttäjän toimittaman suunnitelman muuttamaton kopio.
- `candidates.csv` on käyttäjän toimittaman kymmenen ehdokkaan CSV:n
  sisällöltään muuttamaton kopio; CRLF-rivinvaihdot on normalisoitu LF-muotoon.
  `EXPECTED_UNVERIFIED`, `NOT_CHECKED`, tyhjät koko- ja
  SHA256-kentät sekä `transfer_approved=NO` säilyvät.
- `inventory.not-checked.json` on deterministinen, **havaintoja sisältämätön**
  alkuinventaario. Jokainen koko, mitattu tiiviste, havaintoaika ja lähdeviite
  on `null`. Se ei ole hyväksytty allowlist.
- Historialliset lähtölähteet ovat
  [EVIDENCE.md](../2026-10-14/EVIDENCE.md),
  [artifacts.tsv](../2026-10-14/artifacts.tsv) ja
  [AUTOMATION.md](../AUTOMATION.md). Seitsemän CSV:n täsmällistä polkua on
  artifacts.tsv:ssä; viimeiset kolme v2-yhteenvetoa kuvataan EVIDENCE.md:n
  v2-tulosyhteenvedoissa. Tämä on tekstilähteiden vastaavuus, ei CSC-inventointi.

CSC:n tiedostoja, kokoa, tiivisteitä, job-ID:itä tai Slurm-tilaa ei ole
tarkistettu. Synteettiset testiarvot eivät ole CSC-näyttöä. Historiallinen
hydrologiakoodin commit `4bbf22bb39181c8a4c27ebc3e2769766043115b8`,
tämän toteutuksen lähtöcommit ja hyväksyttävän paketin tiiviste ovat eri
asioita. Lähdecommit on myöhemmin vahvistettava raporttien alkuperästä.

## Sopimukset

Tarkka rakenne: `automation/csc/phase2a/contracts.schema.json`.
Jokaisessa sopimuksessa on tyyppitunniste, versio `2a.1`, lukittu juuritunniste
ja muuttumaton turvallisuuskonteksti. Tuntemattomat kentät hylätään.

| Sopimus | Sisältö ja merkitys |
| --- | --- |
| `candidates` | Tarkat odotetut suhteelliset polut ja käyttötarkoitukset. Ei havaintoja tai lupia. |
| `inventory` | Ehdokkaiden tiivistesidonta ja tiedostokohtaiset havainnot. Ei lupia. |
| `allowlist` | Tarkka tiedostojoukko, tiedostokohtainen kokoraja, odotettu koko ja SHA256 tai eksplisiittinen `null`, mahdollinen erikseen tunnettu job-ID, operaation ja kontekstin sidonnat sekä voimassaoloaika. Pelkkä dokumentti ei ole hyväksyntä. |
| `request` | Täsmälleen hyväksyttyä joukkoa ja kontekstia vastaava pyyntö sekä allowlistin tiiviste. Ei hyväksyntäkenttää. |

Tilat eivät korvaa toisiaan:

| Tila | Merkitys |
| --- | --- |
| `NOT_CHECKED` | Ei havaintoa; ei kokoa, mitattua tiivistettä, havaintoaikaa tai havaintoviitettä. |
| `MISSING` | Tarkistettavaan juureen päästiin, mutta täsmällinen tiedosto tai sen alihakemisto puuttui. |
| `UNREADABLE` | Paikallinen tiedostokohtainen tarkistus kohtasi oikeusvirheen. |
| `AVAILABLE` | Paikallinen tarkistus havaitsi säännöllisen, rajatun tiedoston; koko on mitattu. Tiiviste saa edelleen olla `null`, jos vain metadata tarkistettiin. |
| `OUT_OF_SCOPE` | Erikseen perusteltu rajaus; ei puuttumisväite tai mitattu tiiviste. |

Kaikki havainnot tarvitsevat ajan ja havaintoviitteen. Symlink, erikoistiedosto,
liian suuri tiedosto tai epäselvä juurihakemisto keskeyttää tarkistuksen.
Juurivirhe ei tuota kymmentä keksittyä `MISSING`-riviä. Rajat ovat enintään
5 MiB/tiedosto ja 25 MiB/kokonaisuus. CSV-/JSON-kontrollidokumentin raja on
1 MiB. JSONin kaksoisavaimet, kelluvat luvut ja liian monimutkainen rakenne
hylätään; skeemalla ei ole verkkoviitteitä.

## Riippumaton hyväksyntä ja paikallinen tarkistus

Komentorivi tarkistaa **vain kontrollidokumentin rakenteen** ja palauttaa
aina `authorization=NOT_GRANTED`. Se ei lataa hyväksyntöjä, avaa ehdokkaiden
raportteja eikä kirjoita raportteja tai siirrä tiedostoja.

Kirjaston `check_request` tarkistaa policy-sidonnat ja `check_local` tekee
hyväksytyn paikallisen tarkistuksen. Tässä vaiheessa jälkimmäistä käytetään
vain testien tilapäisiin synteettisiin tiedostoihin. Luotetun isäntäohjelman
pitää antaa erillinen `TrustStore`: pyyntötunnisteen sitominen koko
hyväksytyn allowlistin tiivisteeseen ja paikalliseen peilijuureen sekä
riippumattomasti tunnetut job-ID:t. Oletusvarasto on tyhjä. Varastolle ei ole
manifesti-, JSON-, CSV-, ympäristömuuttuja- tai komentorivilatainta. Testit
asettavat **synteettiset** pin-sidonnat suoraan muistissa. Paketin mukana
tulevaa tiedostoa tai itse ilmoitettua viitettä ei pidä koskaan käyttää
luotettuna hyväksyntälähteenä.

`approved=true` ja `approval_record_ref` hylätään tuntemattomina kenttinä.
Myöskään oikea tiiviste ei yksin anna lupaa. Hyväksyntä sitoo operaation,
repositorioidentiteetin, haaran, lähdecommitin, paketin tiivisteen,
pyyntötunnisteen, CSC-projektin ja juuren, ehdokkaat, inventaarion,
tarkan tiedostolistan, tulospolun, kokorajat ja voimassaolon. Muutos
vaatii uuden riippumattoman pin-sidonnan. Käyttöyritys kuluttaa hyväksynnän
muistissa myös epäonnistuessaan; tarkistuksen esikatselu ei kuluta sitä.

- `INVENTORY_LOCAL_REPORTS` tarkistaa vain metadatan. Se ei avaa raporttien
  sisältöä. Tuntematon odotettu koko/tiiviste säilyy `null`-arvona.
- `VERIFY_LOCAL_REPORTS` vaatii täsmällisen hyväksytyn koon ja SHA256:n sekä
  niitä vastaavan `AVAILABLE`-inventaarion. Se tarkistaa hyväksytyt paikalliset
  UTF-8-tekstitavut rajatusti; se ei jäsennä QA:ta, job-ID-tiedostoa tai Slurmia
  eikä palauta sisältöä. Rasterin tiedostopäätteet ja TIFF/BigTIFF-signatuurit
  hylätään. Tiedostojen sisältämiä komentoja tai linkkejä ei suoriteta.
- Siirto, CSC-luku, Slurm-kysely tai laskenta ei ole sallittu operaatio.
  Siirtotoimintoa ei ole toteutettu.

Polkujen jokainen komponentti avataan hakemistodeskriptorin suhteen
`O_NOFOLLOW`-lipulla, myös paikallisen juuren esivanhemmat. Lopputiedosto
tarkistetaan `O_PATH`-deskriptorilla ennen mahdollista sisältölukua.
Säännöllinen tiedostotyyppi, inode, koko, tiiviste sekä aikaleimojen pysyvyys
tarkistetaan samasta sisältödeskriptorista. Polkuja ei globata. Tämä
toteutus käyttää Linuxin deskriptorirajapintoja.

MODERATE:n 52 järveä säilyvät `REVIEW_REQUIRED`-tilassa ja syy
`POSITIVE_SHORE_THRESHOLD_NO_OBSERVED_RAISE` säilyy. NATIONAL on `LOCKED`.
Scheduler-tila on `UNKNOWN`, tekninen QA `NOT_EVALUATED` ja tieteellinen
hyväksyntä `NOT_GRANTED`. `AVAILABLE` tai tiivisteen täsmääminen ei muuta niitä.
Vaiheen 1 skeemat, tarkistin ja paikallinen bundle-tarkistus säilyvät
ennallaan; niitä ei saa käyttää vaiheen 2 keruu- tai siirtovaltuutuksena.

## Kevyet paikalliset komennot

Riippuvuudet ovat samat kuin vaiheen 1 `requirements-preflight.lock`-lukossa.
Tämän työtilan erillinen Python 3.12 -venv on `/workspace/csc-phase2a-venv`.
Repositorion riippuvuuslukkoa tai workflowita ei muutettu.

```sh
cd /workspace/MaaltaMerelle-phase-2a
PYTHONDONTWRITEBYTECODE=1 /workspace/csc-phase2a-venv/bin/python automation/csc/phase2a/check.py candidate-csv docs/csc/phase2a/candidates.csv
PYTHONDONTWRITEBYTECODE=1 /workspace/csc-phase2a-venv/bin/python automation/csc/phase2a/check.py inventory docs/csc/phase2a/inventory.not-checked.json
PYTHONDONTWRITEBYTECODE=1 /workspace/csc-phase2a-venv/bin/python automation/csc/tests/run_tests.py
PYTHONDONTWRITEBYTECODE=1 /workspace/csc-phase2a-venv/bin/python automation/csc/tests/run_tests.py --pattern 'no_tests_phase2a_*.py'
```

Viimeisen komennon **pitää epäonnistua paluukoodilla 2**. Täysi testiajo
sisältää myös tämän odotetun epäonnistumisen regressiotestin. Synteettinen
`UNREADABLE` testataan injektoidulla `PermissionError`-virheellä, jotta testi
ei riipu testikäyttäjän oikeuksista. Testit käyttävät vain pieniä paikallisia
tiedostoja; eivät R:ää, hydrologiaa tai CSC:tä.

## Avoimet riskit ja vaiheen 2B portit

Oikeaa hyväksyttyä allowlistaa ei ole toimitettu eikä luotu tässä työssä.
Luotetun hyväksyntävaraston ylläpito, hyväksyjän identiteetin todennus,
paketin todellisten tavujen mittaaminen ja sidonta hyväksyttyyn koodiin,
pysyvä/lukittu kertakäyttökirjanpito sekä monen prosessin toistonsuoja
ovat tulevan integraation edellytyksiä. Muistissa oleva `TrustStore` ei
takaa näitä eikä ole tuotantovaltuutuspalvelu.

Tarkistin ei todista CSV:ssä väitetyn havainnon aitoutta, job-ID:n alkuperää,
Slurm-tilaa, QA-lukujen totuutta tai hydrologista hyväksyttävyyttä. Null job-ID
tarkoittaa, ettei pyyntö esitä job-sidontaa; annettu ID vaatii erillisen
luotetun tunnettuuden. Dynaamiset lokit eivät ole kymmenen ehdokkaan listassa,
eikä niiden nimiä ratkaista. Kovien linkkien tai bind-mountien alkuperää
ei todenneta; paikallisen peilijuuren on oltava luotettu ja rajattu.

Ennen CSC-käyttöä tarvitaan erillinen katselmointi, todellisten täsmällisten
polkujen ja komentojen esittely sekä käyttäjän erillinen read-only-hyväksyntä.
Siirto vaatii oman hyväksyntänsä, CSC:n salliman menetelmän ja raporttien
salassa pidettävien sisältöjen tarkistuksen. CSC-adapteria, salaisuuksia,
SSH:ta, FirecRESTiä, Slurmia tai siirtorajapintaa ei lisätä tähän vaiheeseen.
