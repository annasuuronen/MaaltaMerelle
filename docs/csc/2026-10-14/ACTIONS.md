# Dokumentointi- ja arkistointicommitin Actions-tarkastus

Tarkistuskanta: `baseline-no-structures` ennen arkistointia,
`4bbf22bb39181c8a4c27ebc3e2769766043115b8` (15.10.2026).
Kaikki 15 workflow-tiedostoa tarkistettiin. Tässä muutoksessa lisätään vain
`docs/csc/2026-10-14/**`-tiedostoja; `R/`, `tests/`, workflowt ja `main`
säilyvät muuttumattomina. Uusia workflow-käynnistyksiä ei pyydetä.

## Push-triggerit

Kaikki 14 push-workflowta vaativat sekä haaran `baseline-no-structures` että
jonkin alla olevista poluista. Yksikään ei sisällä `docs/**`-polkua.
Kaikki nämä workflowt tukevat myös erillistä `workflow_dispatch`-käynnistystä,
jota tässä ei käytetä. Taulukon ”oma tiedosto” tarkoittaa polkua
`.github/workflows/<taulukossa mainittu tiedosto>`.

| Workflow | Push-polut |
| --- | --- |
| `audit-02d8-schema.yml` | Oma tiedosto. |
| `audit-natural-evidence.yml` | Oma tiedosto. |
| `audit-partial-gradient.yml` | Oma tiedosto. |
| `audit-validation-fixtures.yml` | Oma tiedosto. |
| `audit-workflow-safety.yml` | Oma tiedosto. |
| `verify-low-coastline.yml` | Oma tiedosto. |
| `audit-r-source-graph.yml` | Oma tiedosto; `R/**`. |
| `audit-r-syntax.yml` | Oma tiedosto; `R/**`; `tests/**`. |
| `test-natural-reference.yml` | Oma tiedosto; `R/**`; `tests/**`. |
| `test-sulku-11.yml` | Oma tiedosto; `R/**`; `tests/**`. |
| `continue-validation-gradient.yml` | Oma tiedosto; `.github/workflows/test-natural-reference.yml`; `R/**`; `tests/**`. |
| `test-low-transfer.yml` | Oma tiedosto; `R/02_build_baseline_hydrology.R`; `R/02A_whitebox_fill_retry.R`; `R/02E_water_connected_candidates.R`; `R/02F_water_connected_route_diagnostics.R`; `tests/whitebox_fill_retry.R`; `tests/water_connected_candidates.R`; `tests/water_connected_route_diagnostics.R`. |
| `test-moderate-transfer.yml` | Oma tiedosto; edellisen rivin koodi-/testipolut; lisäksi `R/02D7K2_non_target_raised_link_resolution.R` ja `tests/low_02d7k2_regression.R`. |
| `test-portability-matrix.yml` | Oma tiedosto; `tests/portability.R`; `R/00_pipeline_config.R`; `R/02_build_baseline_hydrology.R`. |

Lähteet ovat muuttumattomassa [workflow-hakemistossa](../../../.github/workflows/).

## Ajojen jatkoketjut

Viidestoista workflow, `retry-hydrology-infra.yml`, kuuntelee vain neljän
hydrologiaworkflown (`LOW`, `MODERATE`, `NATURAL`, `TEST_SULKU_11`)
`workflow_run: completed` -tapahtumia haarassa `baseline-no-structures`.
Sen job-ehdossa vaaditaan epäonnistuminen, ja se voi uusia tunnistetun
runner-keskeytyksen. Se ei ole arkistointipushin triggeri. Jo aikaisemmin
käynnistetty muu ajo voi silti päättyessään aktivoida tämän kuuntelijan.

`continue-validation-gradient.yml` voi dispatchata LOW- ja MODERATE-ajot
onnistuneen NATURAL-ajon jälkeen. Sen oma push-polkurajaus ei täyty
arkistoinnista, joten tämä muutos ei aloita jatkoketjua.
`pull_request`, `schedule`, `repository_dispatch`- tai `workflow_call`-
triggereitä ei näissä tiedostoissa ole.

## Johtopäätös ja tarkistuksen rajat

Näiden triggerien perusteella vain arkistohakemistoon rajattu push ei käynnistä
Actions-ajoja eikä raskaita hydrologialaskentoja. Tämä on workflow-lähteiden
perusteella tehty arvio, ei väite CSC-testien tai uuden commitin CI:n PASSista.

Ennen committia tarkistetaan kopioiden tavuyhtäläisyys ja SHA256:t, Bashin
syntaksi sekä upotettujen R-/Slurm-lohkojen jäsentyminen suorittamatta niitä.
Stage-alueen on sisällettävä vain arkistopolun tiedostot. Rastereita tai
muualta peräisin olevia tuloksia ei lisätä. Arkistoidut skriptit tarkistettiin
myös näkyvien tunnusten/salaisuuksien varalta; niissä on CSC-projektipolkuja
ja odotettuja tiivisteitä, ei julkaistavia tunnistautumistietoja.

GitHubin Actions-websivu oli luettavissa, ja sen repositoriotunnisteeksi
vahvistettiin `1407101587`. `gh api` -kyselyn verkkoproxy palautti 403 Forbidden;
se ei ole Actions-ajon tulos eikä osoita Git-pushin oikeuksia.
Commitin lähetyksen jälkeinen havaittu Actions-tilanne raportoidaan erikseen
commit-SHA:n yhteydessä. Tässä dokumentissa ei esitetä tulevaa CI-tulosta
valmiiksi havaittuna.
