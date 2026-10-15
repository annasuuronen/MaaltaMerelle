# Arkistointimuutoksen paikallinen tarkistus 15.10.2026

Tämä raportti koskee arkiston eheyttä ja dokumentointia, ei CSC-hydrologian
hyväksyntää. Lähtö-HEAD on `4bbf22bb39181c8a4c27ebc3e2769766043115b8`.

| Tarkistus | Tulos | Rajaus |
| --- | --- | --- |
| Kahdeksan arkistokopion vertailu alkuperäisiin liitteisiin | 8/8 tavu tavulta samat. | Ei rivinvaihto-, polku- tai sisältömuutoksia. |
| `sha256sum -c SHA256SUMS` | 8/8 täsmää. | `scripts.tsv`:n koot ja tiivisteet tarkistettu samoista tavuista. |
| `bash -n` alkuperäisille skripteille | 8/8 jäsentyy. | Mitään `check`, `submit` tai `status` -haaraa ei suoritettu. |
| `bash -n` erilleen poimituille Slurm-heredoc-lohkoille | 8/8 jäsentyy. | Ei Slurm-lähetyksiä eikä ajosuoritusta. |
| R:n `parse(file=...)` upotetuille R-lohkoille/lausekkeille | 8/8 jäsentyy. | R-koodia ei evaluoitu, rastereita ei luettu eikä laskettu. |
| Markdownin paikalliset linkkikohteet | Kohteet löytyvät. | Lähdekoodiriviviitteet tarkoittavat lähtöcommittia. |
| Workflow-triggerit | Dokumenttipolku ei täytä yhdenkään push-workflown polkurajausta. | Erilliset vanhat/manual-ajot eivät ole tämän commitin validointia. |
| Alkuperäisten skriptien sisältötarkastus | CSC-polut ja odotetut tiivisteet dokumentoitu; näkyviä salaisuuksia ei löytynyt. | Arkistointi ei muuta tai aja skriptejä. |

Commitin stage-tarkistuksessa edellytetään lisäksi, että kaikki lisäykset ovat
`docs/csc/2026-10-14/`-hakemistossa, Gitin stageen tallennetut skriptit vastaavat
liitteiden alkuperäisiä tavuja ja `R/`, `tests/` sekä `.github/workflows/` ovat
muuttumattomia. Suuria rastereita ei lisätä. GitHub-pushin ja sen jälkeisen
Actions-havainnon tulos raportoidaan arkistocommitin SHA:n yhteydessä.

Hydrologisia ajoja ei tässä työssä käynnistetty. CSC PASS -tuloksia ei vielä
vahvisteta; seuraavassa vaiheessa luetaan olemassa olevat Roihun lokit ja
QA-raportit [EVIDENCE.md](EVIDENCE.md)-luettelon mukaisesti.
