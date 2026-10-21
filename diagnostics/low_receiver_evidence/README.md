# LOW PR #22 – havaintoaineiston arkistointi ja yksi offline-testikerta

**Tila: ohjelmisto-/havaintosopimuksen katselmointi; ei hydrologista hyväksyntää.**

Erillinen tutkimushaara PR #22:n commitista effab29aa4d44ecc897efc0c91c96f3bfc1b4db6.
Ei tuotantokoodin, aikaisempien PR:ien eikä hydrologisten rasterien muutoksia.

## Vuoden 2026-10-21 Roihu-tulosteen täsmällinen merkitys

Käyttäjän toimittama terminaalituloste: CODE_VERSION_VERIFICATION=LOCAL_GIT_CLEAN,
GEOMETRY_CHECK=PASS, 16 poistumisreunaa, 14 yksilöllistä vastaanottajasolua,
neljä terra-extract-kutsua / 56 palautettua arvoa, DOWNSTREAM_STEPS=0.

observed_receivers_20261021.csv on tästä **käsin kirjattu näyttö**, ei
riippumattomasti allekirjoitettu CSC-tulos. LAND_WATER-arvot ovat
**vain konsolissa näkyvällä desimaalitarkkuudella**; älä esitä niitä
raakana tarkkana aineistona tai luonnollisen kaltevuuden todisteena.
Historiallinen D8-rasteriprovenienssi on UNKNOWN/INCOMPLETE.

Havaintotulos: 14/14 kelvollista LAND-solua ja kelvollista Whitebox-D8-pointeria,
0 RANTA10-vesisolua ja 0 NoDataa. Yhteisten vastaanottajien (3000,2994)
ja (3006,3002) raportoidut lähdereittimäärät ovat 20 ja 32. Luku 121
on raportoitujen reittimäärien yhteensä, **ei** laskettu virtauskertymä.

Havaittu (3000,2994) osoittaa N(128) kohti jo havaittua (2999,2994):ää;
tämän NW(64) osoittaa näytejoukon **ulkopuolelle** (2998,2993). Kyseessä
on yksiaskelinen geometrinen päätelmä, ei uusi reittijäljitys.
LAND_WATER-lukemien noin 0,221 m absoluuttista merkitystä tai erittäin
pientä vaihtelua ei tulkita ennen korkeuslähteen ja yksikön riippumatonta
selvitystä.

## Yhdellä Roihu-kerralla ajettava testijoukko

- Uudet Python-havaintotestit: 19 testiryhmää, joiden sisällä on erillisiä
  positiivisia ja negatiivisia solukohtaisia testejä. Lukitsevat 16 lähderivin,
  14 vastaanottajarivin, D8-offsetit, cell-ID:t, 121 reittimäärän sekä
  kahden jaetun vastaanottajan havainnot. Testaavat rivijärjestyksen muutokset,
  duplikaatit, puuttuvat rivit ja virheelliset pointerit/soluarvot.
- Olemassa olevat PR #22:n 21 synteettistä R-testiä: tilapäiset pienet
  GeoTIFF/VRT/CLI-fixturet, ei todellista LOW-rasterilukua.
- Yksi one_shot_roihu.sh: siivoamaton checkout tai väärä git-origin/haara,
  muuttunut PR22:n lähtö-CSV, puuttuva terra tai aikakatkaisu => STOP.
  Pythonin aikaraja 45 s ja R:n 180 s. Ei Slurmia, Whiteboxia eikä
  mitään tuotantorasterien lukuja. Testit eivät kirjoita repositorioon.

Kun haara on erikseen tarkistettu ja haettu Roihulle omaksi puhtaaksi
Git-checkoutiksi, esimerkiksi:
~~~bash
module load r-env/461
bash "$HOME/MaaltaMerelle_PR22_evidence/diagnostics/low_receiver_evidence/one_shot_roihu.sh"
~~~
Tuo polku **ei ole vielä Roihulla** ilman erillistä kloonausta.
Kaikki testitulokset pitää tarkistaa; mitään CSC-ajon PASS-tulosta ei väitetä
ennen todellista ajoa. Älä aja aiempia suuria regressiokampanjoita uudelleen
tai sekoita PR #32:n 02G.3:n numeerista prototyyppiä tähän tulokseen.

Avoinna: tuotantorasterien riippumaton provenienssi, korkeuspinnan merkityksen
tarkastus ja seuraavan **erikseen hyväksyttävän** D8-jatkokokeen rajaus.
Aiempi lupa koski vain jo suoritettua 56 rasteriarvon lukua.

hydrological_validation=NOT_ASSESSED
channel_interpretation=NOT_ASSESSED
MODERATE=REVIEW_REQUIRED
NATIONAL=LOCKED
