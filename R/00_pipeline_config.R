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

# Resolve paths from the script location, not the caller's working directory.
PROJECT_ROOT <- local({
  override <- Sys.getenv("HYDRO_PROJECT_ROOT", unset = "")
  if (nzchar(override)) {
    root <- normalizePath(override, winslash = "/", mustWork = TRUE)
  } else {
    source_files <- Filter(nzchar, lapply(sys.frames(), function(frame) {
      if (is.null(frame$ofile)) "" else as.character(frame$ofile)
    }))
    script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
    script_file <- if (length(source_files)) {
      tail(source_files, 1L)[[1L]]
    } else if (length(script_arg)) {
      sub("^--file=", "", script_arg[1L])
    } else {
      stop("Cannot locate the script. Use Rscript, source(), or HYDRO_PROJECT_ROOT.")
    }
    root <- dirname(dirname(normalizePath(script_file, winslash = "/", mustWork = TRUE)))
  }
  if (!file.exists(file.path(root, "R", "00_pipeline_config.R"))) {
    stop("HYDRO_PROJECT_ROOT / script location does not identify the pipeline repository.")
  }
  root
})

HYDRO_MODE <- Sys.getenv("HYDRO_MODE", unset = "LOCAL_TEST")

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

# Relative overrides are resolved against PROJECT_ROOT in all modes.
hydro_path <- function(variable, default) {
  path <- Sys.getenv(variable, unset = default)
  if (!nzchar(path)) stop(paste(variable, "must not be empty."))
  absolute <- grepl("^([A-Za-z]:[/\\\\]|[/\\\\])", path)
  if (!absolute) path <- file.path(PROJECT_ROOT, path)
  normalizePath(path, winslash = "/", mustWork = FALSE)
}

if (HYDRO_MODE == "LOCAL_TEST") {
  PIPELINE_ROOT <- hydro_path("HYDRO_PIPELINE_ROOT", PROJECT_ROOT)
  SOURCE_TEST_ROOT <- hydro_path(
    "HYDRO_SOURCE_TEST_ROOT", file.path("data", TEST_ID)
  )
  STRUCTURES_ROOT <- hydro_path(
    "HYDRO_STRUCTURES_ROOT", SOURCE_TEST_ROOT
  )
  STRUCTURES_GPKG <- file.path(
    # Preserve the existing processed/ layout for explicit structures overrides.
    if (nzchar(Sys.getenv("HYDRO_STRUCTURES_ROOT", unset = ""))) {
      file.path(STRUCTURES_ROOT, "processed")
    } else {
      SOURCE_TEST_ROOT
    },
    "HYDRO_STRUCTURES_LOCAL_TEST_SULKU_11_12km.gpkg"
  )
}


# ------------------------------------------------------------
# 5. CSC TEST
#
# Existing CSC layout remains the default; all roots can be overridden.
# ------------------------------------------------------------

if (HYDRO_MODE == "CSC_TEST") {
  CSC_ROOT <- hydro_path("HYDRO_CSC_ROOT", "/scratch/project_2004707/pienvedet")
  PIPELINE_ROOT <- hydro_path(
    "HYDRO_PIPELINE_ROOT", file.path(CSC_ROOT, "hydrology_pipeline_v2")
  )
  SOURCE_TEST_ROOT <- hydro_path(
    "HYDRO_SOURCE_TEST_ROOT", file.path(CSC_ROOT, "hydro_test", TEST_ID)
  )
  STRUCTURES_ROOT <- hydro_path(
    "HYDRO_STRUCTURES_ROOT", file.path(CSC_ROOT, "hydrology_structures")
  )
  STRUCTURES_GPKG <- file.path(
    STRUCTURES_ROOT,
    "HYDRO_STRUCTURES_LOCAL_TEST_SULKU_11_12km.gpkg"
  )
}

if (HYDRO_MODE %in% c("LOCAL_TEST", "CSC_TEST")) {
  RUN_ROOT <- hydro_path("HYDRO_RUN_ROOT", file.path(PIPELINE_ROOT, "runs", TEST_ID))
  DEM_FILE <- file.path(SOURCE_TEST_ROOT, "dem_12km_rumpukorjattu.tif")
  RANTA10_GPKG <- file.path(SOURCE_TEST_ROOT, "RANTA10_TEST_SULKU_11.gpkg")
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
