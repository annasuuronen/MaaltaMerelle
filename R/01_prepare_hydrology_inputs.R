# ============================================================
# 01_prepare_hydrology_inputs.R
#
# Hydrology pipeline v2
#
# Tehtävä:
#   - tarkista DEM
#   - tarkista RANTA10
#   - tarkista järvien korkeudet
#   - tarkista jo tehdyt RANTA10-rasterit
#   - tarkista rakenteiden lähtöaineisto
#   - tee canonical input manifest
#
# EI:
#   - Whitebox-ajoa
#   - D8-laskentaa
#   - flow accumulationia
#   - routing-muutoksia
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
  library(sf)
})


# ------------------------------------------------------------
# 2. LÄHTÖTIEDOSTOT
# ------------------------------------------------------------

f_lake_id <- file.path(
  SOURCE_TEST_ROOT,
  "ranta10_lake_id.tif"
)

f_river_area <- file.path(
  SOURCE_TEST_ROOT,
  "ranta10_river_area_mask.tif"
)

f_river_line <- file.path(
  SOURCE_TEST_ROOT,
  "ranta10_river_line_mask.tif"
)

f_water_class <- file.path(
  SOURCE_TEST_ROOT,
  "ranta10_water_class.tif"
)

f_water_mask <- file.path(
  SOURCE_TEST_ROOT,
  "ranta10_water_mask.tif"
)

required_files <- c(
  DEM_FILE,
  RANTA10_GPKG,
  STRUCTURES_GPKG,
  f_lake_id,
  f_river_area,
  f_river_line,
  f_water_class,
  f_water_mask
)

missing_files <- required_files[
  !file.exists(required_files)
]

if (length(missing_files) > 0) {

  stop(
    paste(
      "Missing required input file(s):",
      paste(
        missing_files,
        collapse = "\n"
      ),
      sep = "\n"
    )
  )
}


# ------------------------------------------------------------
# 3. DEM
# ------------------------------------------------------------

dem <- rast(
  DEM_FILE
)

dem_epsg <- suppressWarnings(
  crs(
    dem,
    proj = TRUE
  )
)

dem_res <- res(dem)

dem_ext <- ext(dem)

stopifnot(
  ncol(dem) == TEST_NCOL,
  nrow(dem) == TEST_NROW,
  abs(dem_res[1] - CELL_SIZE_M) < 1e-9,
  abs(dem_res[2] - CELL_SIZE_M) < 1e-9
)

extent_ok <-
  abs(xmin(dem_ext) - TEST_EXTENT["xmin"]) < 1e-6 &&
  abs(xmax(dem_ext) - TEST_EXTENT["xmax"]) < 1e-6 &&
  abs(ymin(dem_ext) - TEST_EXTENT["ymin"]) < 1e-6 &&
  abs(ymax(dem_ext) - TEST_EXTENT["ymax"]) < 1e-6

stopifnot(
  extent_ok
)


# ------------------------------------------------------------
# 4. RANTA10 VEKTORIT
# ------------------------------------------------------------

ranta_layers <- st_layers(
  RANTA10_GPKG
)$name

needed_layers <- c(
  "lakes",
  "river_areas",
  "river_lines"
)

stopifnot(
  all(
    needed_layers %in%
      ranta_layers
  )
)

lakes <- st_read(
  RANTA10_GPKG,
  layer = "lakes",
  quiet = TRUE
)

river_areas <- st_read(
  RANTA10_GPKG,
  layer = "river_areas",
  quiet = TRUE
)

river_lines <- st_read(
  RANTA10_GPKG,
  layer = "river_lines",
  quiet = TRUE
)

stopifnot(
  st_crs(lakes)$epsg == CRS_EPSG,
  st_crs(river_areas)$epsg == CRS_EPSG,
  st_crs(river_lines)$epsg == CRS_EPSG
)


# ------------------------------------------------------------
# 5. RANTA10 REGRESSION
# ------------------------------------------------------------

stopifnot(
  nrow(lakes) ==
    EXPECTED_TEST$lakes,

  nrow(river_areas) ==
    EXPECTED_TEST$river_areas,

  nrow(river_lines) ==
    EXPECTED_TEST$river_lines
)


# ------------------------------------------------------------
# 6. JÄRVIEN KORKEUDET
# ------------------------------------------------------------

height_field <- names(lakes)[
  tolower(names(lakes)) ==
    "korkeus_m"
]

stopifnot(
  length(height_field) == 1
)

lake_z <- suppressWarnings(
  as.numeric(
    lakes[[height_field]]
  )
)

n_lake_z_ok <- sum(
  is.finite(lake_z)
)

n_lake_z_missing <- sum(
  !is.finite(lake_z)
)

if (n_lake_z_missing > 0) {

  stop(
    paste0(
      "RANTA10 lake elevations missing: ",
      n_lake_z_missing,
      " / ",
      nrow(lakes)
    )
  )
}


# ------------------------------------------------------------
# 7. RASTEREIDEN GEOMETRIA
# ------------------------------------------------------------

raster_files <- c(
  f_lake_id,
  f_river_area,
  f_river_line,
  f_water_class,
  f_water_mask
)

geometry_ok <- logical(
  length(raster_files)
)

for (i in seq_along(raster_files)) {

  r <- rast(
    raster_files[i]
  )

  geometry_ok[i] <-
    compareGeom(
      dem,
      r,
      stopOnError = FALSE
    )
}

stopifnot(
  all(geometry_ok)
)


# ------------------------------------------------------------
# 8. LAKE-ID RASTER QA
# ------------------------------------------------------------

lake_id <- rast(
  f_lake_id
)

lake_freq <- freq(
  lake_id
)

lake_ids <- lake_freq[
  is.finite(lake_freq$value) &
    lake_freq$value > 0,
  "value"
]

n_lake_ids <- length(
  unique(
    lake_ids
  )
)

stopifnot(
  n_lake_ids ==
    EXPECTED_TEST$lakes
)


# ------------------------------------------------------------
# 9. JÄRVEN KORKEUSRASTERI
#
# Canonical raster geometry tulee ranta10_lake_id.tif:stä.
#
# ranta10_lake_id.tif:n arvot = RANTA10 objectid.
#
# Emme rasteroi polygonigeometriaa uudelleen, koska se
# aiheuttaa reunasolujen eroja.
# ------------------------------------------------------------

f_lake_z <- file.path(
  DIR_01,
  "ranta10_lake_elevation_m.tif"
)

# objectid -> korkeus_m
lake_objectid <- suppressWarnings(
  as.numeric(
    lakes$objectid
  )
)

lake_height <- suppressWarnings(
  as.numeric(
    lakes[[height_field]]
  )
)

stopifnot(
  length(lake_objectid) == nrow(lakes),
  length(unique(lake_objectid)) == nrow(lakes),
  all(is.finite(lake_objectid)),
  all(is.finite(lake_height))
)

# Kaikkien rasterin ID-arvojen pitää löytyä vektorista.
raster_ids <- freq(
  lake_id
)

raster_ids <- unique(
  raster_ids$value[
    is.finite(raster_ids$value)
  ]
)

missing_objectid <- setdiff(
  raster_ids,
  lake_objectid
)

stopifnot(
  length(missing_objectid) == 0
)

if (
  !file.exists(f_lake_z) ||
  OVERWRITE
) {

  lake_z_raster <- subst(
    lake_id,
    from = lake_objectid,
    to = lake_height,
    others = NA
  )

  writeRaster(
    lake_z_raster,
    f_lake_z,
    overwrite = TRUE,
    datatype = "FLT4S",
    gdal = c(
      "COMPRESS=DEFLATE",
      "BIGTIFF=YES"
    )
  )

} else {

  lake_z_raster <- rast(
    f_lake_z
  )
}

stopifnot(
  compareGeom(
    dem,
    lake_z_raster,
    stopOnError = FALSE
  )
)

# Canonical mask QA:
# jokaisella lake-ID-solulla täytyy olla korkeus.
lake_mask <- !is.na(
  lake_id
)

height_mask <- !is.na(
  lake_z_raster
)

missing_height_cells <- global(
  lake_mask & !height_mask,
  "sum",
  na.rm = TRUE
)[1, 1]

extra_height_cells <- global(
  !lake_mask & height_mask,
  "sum",
  na.rm = TRUE
)[1, 1]

stopifnot(
  missing_height_cells == 0,
  extra_height_cells == 0
)

# ------------------------------------------------------------
# 10. RAKENNEAINEISTO
#
# Tässä vain varmistetaan että paketti löytyy.
# Varsinainen standardointi/deduplikointi tehdään 03:ssa.
# ------------------------------------------------------------

structure_layers <- st_layers(
  STRUCTURES_GPKG
)$name

stopifnot(
  length(structure_layers) > 0
)


# ------------------------------------------------------------
# 11. INPUT MANIFEST
# ------------------------------------------------------------

manifest <- data.frame(

  key = c(
    "pipeline_version",
    "run_mode",
    "test_id",
    "pointer_scheme",
    "cell_size_m",
    "stream_threshold_ha",

    "dem",
    "ranta10_gpkg",

    "lake_id_raster",
    "river_area_raster",
    "river_line_raster",
    "water_class_raster",
    "water_mask_raster",
    "lake_elevation_raster",

    "structures_gpkg"
  ),

  value = c(
    PIPELINE_VERSION,
    HYDRO_MODE,
    TEST_ID,
    POINTER_SCHEME,
    as.character(CELL_SIZE_M),
    as.character(STREAM_THRESHOLD_HA),

    normalizePath(
      DEM_FILE,
      winslash = "/"
    ),

    normalizePath(
      RANTA10_GPKG,
      winslash = "/"
    ),

    normalizePath(
      f_lake_id,
      winslash = "/"
    ),

    normalizePath(
      f_river_area,
      winslash = "/"
    ),

    normalizePath(
      f_river_line,
      winslash = "/"
    ),

    normalizePath(
      f_water_class,
      winslash = "/"
    ),

    normalizePath(
      f_water_mask,
      winslash = "/"
    ),

    normalizePath(
      f_lake_z,
      winslash = "/"
    ),

    normalizePath(
      STRUCTURES_GPKG,
      winslash = "/"
    )
  ),

  stringsAsFactors = FALSE
)

f_manifest <- file.path(
  DIR_01,
  "01_input_manifest.csv"
)

write.csv(
  manifest,
  f_manifest,
  row.names = FALSE
)


# ------------------------------------------------------------
# 12. QA
# ------------------------------------------------------------

qa <- data.frame(

  item = c(
    "dem_cols",
    "dem_rows",
    "dem_res_x",
    "dem_res_y",

    "xmin",
    "xmax",
    "ymin",
    "ymax",

    "ranta10_lakes",
    "ranta10_river_areas",
    "ranta10_river_lines",

    "lake_heights_valid",
    "lake_heights_missing",

    "lake_ids_raster",

    "structure_layers"
  ),

  value = c(
    ncol(dem),
    nrow(dem),
    dem_res[1],
    dem_res[2],

    xmin(dem_ext),
    xmax(dem_ext),
    ymin(dem_ext),
    ymax(dem_ext),

    nrow(lakes),
    nrow(river_areas),
    nrow(river_lines),

    n_lake_z_ok,
    n_lake_z_missing,

    n_lake_ids,

    length(structure_layers)
  )
)

f_qa <- file.path(
  DIR_01,
  "01_input_QA.csv"
)

write.csv(
  qa,
  f_qa,
  row.names = FALSE
)


# ------------------------------------------------------------
# 13. TIIVIS KONSOLITULOSTE
# ------------------------------------------------------------

cat("\014")

cat("=== 01 PREP INPUTS PASS ===\n")

cat(sprintf(
  "Mode              : %s\n",
  HYDRO_MODE
))

cat(sprintf(
  "DEM               : %d x %d | %.0f m\n",
  ncol(dem),
  nrow(dem),
  dem_res[1]
))

cat(sprintf(
  "RANTA10 L/A/line  : %d / %d / %d\n",
  nrow(lakes),
  nrow(river_areas),
  nrow(river_lines)
))

cat(sprintf(
  "Lake heights      : %d / %d valid\n",
  n_lake_z_ok,
  nrow(lakes)
))

cat(sprintf(
  "Lake raster IDs   : %d\n",
  n_lake_ids
))

cat(sprintf(
  "Structure package : %d layers\n",
  length(structure_layers)
))

cat(sprintf(
  "Manifest          : %s\n",
  basename(f_manifest)
))

cat("===========================\n")
