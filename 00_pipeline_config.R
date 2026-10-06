# ============================================================
# 00_pipeline_config.R
#
# Hydrology pipeline v2
#
# Kehitysjärjestys:
#   LOCAL_TEST
#      ->
#   CSC_TEST
#      ->
#   NATIONAL
#
# NATIONAL on tarkoituksella lukittu siihen asti,
# että koko pipeline läpäisee paikalliset ja CSC-testit.
# ============================================================


# ------------------------------------------------------------
# 1. AJOTILA
# ------------------------------------------------------------

HYDRO_MODE <- "LOCAL_TEST"

allowed_modes <- c(
  "LOCAL_TEST",
  "CSC_TEST",
  "NATIONAL"
)

stopifnot(
  HYDRO_MODE %in% allowed_modes
)


# ------------------------------------------------------------
# 2. PIPELINE
# ------------------------------------------------------------

PIPELINE_VERSION <- "2.0-dev"

TEST_ID <- "TEST_SULKU_11"

CRS_EPSG <- 3067

CELL_SIZE_M <- 2

HALO_M <- 1000

STREAM_THRESHOLD_HA <- 4

CELL_AREA_M2 <- CELL_SIZE_M^2

STREAM_THRESHOLD_CELLS <-
  STREAM_THRESHOLD_HA *
  10000 /
  CELL_AREA_M2

POINTER_SCHEME <- "whitebox"

OVERWRITE <- FALSE


# ------------------------------------------------------------
# 3. TESTIALUEEN REFERENSSI
#
# Rasterin todellinen grid-aligned extent.
# ------------------------------------------------------------

TEST_EXTENT <- c(
  xmin = 407030,
  xmax = 419030,
  ymin = 7070072,
  ymax = 7082072
)

TEST_NCOL <- 6000L
TEST_NROW <- 6000L


# ------------------------------------------------------------
# 4. PAIKALLINEN TESTI
# ------------------------------------------------------------

if (HYDRO_MODE == "LOCAL_TEST") {

  PIPELINE_ROOT <-
    "D:/pienvedet/hydrology_pipeline_v2"

  SOURCE_TEST_ROOT <-
    "D:/pienvedet/hydro_test/TEST_SULKU_11"

  STRUCTURES_ROOT <-
    "D:/pienvedet/hydrology_structures"

  RUN_ROOT <- file.path(
    PIPELINE_ROOT,
    "runs",
    TEST_ID
  )

  DEM_FILE <- file.path(
    SOURCE_TEST_ROOT,
    "dem_12km_rumpukorjattu.tif"
  )

  RANTA10_GPKG <- file.path(
    SOURCE_TEST_ROOT,
    "RANTA10_TEST_SULKU_11.gpkg"
  )

  STRUCTURES_GPKG <- file.path(
  STRUCTURES_ROOT,
  "processed",
  "HYDRO_STRUCTURES_LOCAL_TEST_SULKU_11_12km.gpkg"
  )
}


# ------------------------------------------------------------
# 5. CSC TEST
#
# Tätä käytetään vasta kun LOCAL_TEST on valmis.
# ------------------------------------------------------------

if (HYDRO_MODE == "CSC_TEST") {

  PIPELINE_ROOT <-
    "/scratch/project_2004707/pienvedet/hydrology_pipeline_v2"

  SOURCE_TEST_ROOT <-
    "/scratch/project_2004707/pienvedet/hydro_test/TEST_SULKU_11"

  STRUCTURES_ROOT <-
    "/scratch/project_2004707/pienvedet/hydrology_structures"

  RUN_ROOT <- file.path(
    PIPELINE_ROOT,
    "runs",
    TEST_ID
  )

  DEM_FILE <- file.path(
    SOURCE_TEST_ROOT,
    "dem_12km_rumpukorjattu.tif"
  )

  RANTA10_GPKG <- file.path(
    SOURCE_TEST_ROOT,
    "RANTA10_TEST_SULKU_11.gpkg"
  )

  STRUCTURES_GPKG <- file.path(
    STRUCTURES_ROOT,
    "HYDRO_STRUCTURES_LOCAL_TEST_SULKU_11_12km.gpkg"
  )
}


# ------------------------------------------------------------
# 6. NATIONAL
#
# Ei vielä sallita ajoa.
# ------------------------------------------------------------

if (HYDRO_MODE == "NATIONAL") {

  stop(
    paste0(
      "\nNATIONAL RUN IS LOCKED.\n",
      "Validate LOCAL_TEST and CSC_TEST first.\n"
    )
  )
}


# ------------------------------------------------------------
# 7. RUN-KANSIOT
# ------------------------------------------------------------

DIR_01 <- file.path(
  RUN_ROOT,
  "01_inputs"
)

DIR_02 <- file.path(
  RUN_ROOT,
  "02_baseline"
)

DIR_03 <- file.path(
  RUN_ROOT,
  "03_structures"
)

DIR_04 <- file.path(
  RUN_ROOT,
  "04_final_routing"
)

DIR_05 <- file.path(
  RUN_ROOT,
  "05_flow_accumulation"
)

DIR_06 <- file.path(
  RUN_ROOT,
  "06_final"
)

for (d in c(
  RUN_ROOT,
  DIR_01,
  DIR_02,
  DIR_03,
  DIR_04,
  DIR_05,
  DIR_06
)) {

  dir.create(
    d,
    recursive = TRUE,
    showWarnings = FALSE
  )
}


# ------------------------------------------------------------
# 8. TESTIALUEEN ODOTETUT REFERENSSIT
# ------------------------------------------------------------

EXPECTED_TEST <- list(

  lakes = 108L,

  river_areas = 8L,

  river_lines = 81L,

  physical_structures = 11L,

  hydraulic_sites = 9L,

  confirms_current = 3L,

  controls_existing = 4L,

  adds_outlet_candidate = 2L,

  unresolved_flow_split = 2L
)


# ------------------------------------------------------------
# 9. TURVALLISUUS
# ------------------------------------------------------------

stopifnot(
  CELL_SIZE_M == 2,
  POINTER_SCHEME == "whitebox",
  STREAM_THRESHOLD_HA == 4
)