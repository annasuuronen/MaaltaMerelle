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

config_file <- file.path(PROJECT_ROOT, "R", "00_pipeline_config.R")

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
