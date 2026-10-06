# ============================================================
# 02_build_baseline_hydrology.R
#
# Hydrology pipeline v2
#
# VERSION: 0.6-dev
#
# TÄMÄ KEHITYSVERSIO SISÄLTÄÄ:
#   02A LAND + WATER STORAGE
#   02B LAND -> FIRST RANTA10 WATER
#   02C ZERO-POINTER / SHORE TARGET CLASSIFICATION
#   02D LAKE SPILL / DEPRESSION / LEVEL-FLAT DIAGNOSTICS
#
# EI VIELÄ SISÄLLÄ:
#   - lopullista outlet-valintaa kaikille järville
#   - WATER_CONNECTED-routing-pintaa
#   - lopullista D8-pointeria
#   - lopullista flow accumulationia
#
# Tavoite: pitää tähän asti validoitu baseline-metodi yhdessä
# ajettavassa skriptissä ilman TEST_SULKU_11:een kovakoodattuja
# lukumääriä.
# ============================================================


# ------------------------------------------------------------
# 0. CONFIG
# ------------------------------------------------------------

config_file <-
  "D:/pienvedet/hydrology_pipeline_v2/R/00_pipeline_config.R"

stopifnot(
  file.exists(config_file)
)

source(config_file)


# ------------------------------------------------------------
# 1. PAKETIT
# ------------------------------------------------------------

suppressPackageStartupMessages({
  library(terra)
  library(whitebox)
})


# ------------------------------------------------------------
# 2. INPUTS
# ------------------------------------------------------------

f_lake_id <- file.path(
  SOURCE_TEST_ROOT,
  "ranta10_lake_id.tif"
)

f_lake_z <- file.path(
  DIR_01,
  "ranta10_lake_elevation_m.tif"
)

stopifnot(
  file.exists(DEM_FILE),
  file.exists(f_lake_id),
  file.exists(f_lake_z)
)

dem <- rast(DEM_FILE)

lake_id <- rast(
  f_lake_id
)

lake_z <- rast(
  f_lake_z
)

stopifnot(
  compareGeom(
    dem,
    lake_id,
    stopOnError = FALSE
  ),

  compareGeom(
    dem,
    lake_z,
    stopOnError = FALSE
  )
)


# ------------------------------------------------------------
# 3. OUTPUTS
