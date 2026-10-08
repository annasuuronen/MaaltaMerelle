# ============================================================
# 02_build_baseline_hydrology.R
#
# Hydrology pipeline v2
#
# VERSION: 0.1
#
# TÄSSÄ VAIHEESSA:
#   02A LAND + WATER STORAGE
#
# Ei vielä:
#   - lake outlet selection
#   - WATER_CONNECTED
#   - final D8
#   - flow accumulation
#
# Kun 02A reproduisoi referenssin, tätä samaa skriptiä
# jatketaan vaiheilla 02B ... 02J.
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
# ------------------------------------------------------------

f_land_raw <- file.path(
  DIR_02,
  "land_dem_raw_FLT8S.tif"
)

f_land_fill <- file.path(
  DIR_02,
  "land_dem_filled_FLT8S.tif"
)

f_land_water <- file.path(
  DIR_02,
  "routing_surface_land_water_FLT8S.tif"
)

f_storage <- file.path(
  DIR_02,
  "routing_surface_water_storage_FLT8S.tif"
)


# ------------------------------------------------------------
# 4. WRITE FLOAT64 / WBT-COMPATIBLE
# ------------------------------------------------------------

write_f64 <- function(
  x,
  filename
) {

  writeRaster(
    x,
    filename,
    overwrite = TRUE,
    datatype = "FLT8S",
    gdal = c(
      "COMPRESS=DEFLATE",
      "BIGTIFF=YES"
    )
  )
}


# ------------------------------------------------------------
# 5. LAND DEM RAW
#
# Järvet poistetaan maareitityksestä.
#
# Jokialueita / jokiviivoja EI poisteta tässä:
# ne eivät ole tasaisia järvipintoja.
# ------------------------------------------------------------

if (
  !file.exists(f_land_raw) ||
  OVERWRITE
) {

  cat(
    "Building land_dem_raw...\n"
  )

  land_raw <- ifel(
    is.na(lake_id),
    dem,
    NA
  )

  writeRaster(
  land_raw,
  f_land_raw,
  overwrite = TRUE,
  datatype = "FLT4S",
  gdal = c(
    "COMPRESS=DEFLATE",
    "BIGTIFF=YES"
  )
)

  rm(
    land_raw
  )

  gc()
}

land_raw <- rast(
  f_land_raw
)


# ------------------------------------------------------------
# 6. LAND FILL
#
# FillDepressions on routing-only.
#
# Tämä EI muuta fyysistä rumpukorjattua DEM:iä.
# ------------------------------------------------------------

if (
  !file.exists(f_land_fill) ||
  OVERWRITE
) {

  cat(
    "Running land FillDepressions...\n"
  )

  whitebox::wbt_fill_depressions(
    dem = f_land_raw,
    output = f_land_fill,
    fix_flats = TRUE,
    verbose_mode = TRUE
  )
}

stopifnot(
  file.exists(f_land_fill)
)

land_fill <- rast(
  f_land_fill
)


# ------------------------------------------------------------
# 7. GEOMETRY QA
# ------------------------------------------------------------

stopifnot(
  compareGeom(
    dem,
    land_fill,
    stopOnError = FALSE
  )
)


# ------------------------------------------------------------
# 8. LAND + RANTA10 LAKE LEVEL
#
# land_fill on land
# lake_z on lake cells
# ------------------------------------------------------------

if (
  !file.exists(f_land_water) ||
  OVERWRITE
) {

  cat(
    "Building land + lake routing surface...\n"
  )

  land_water <- cover(
    land_fill,
    lake_z
  )

  write_f64(
    land_water,
    f_land_water
  )

  rm(
    land_water
  )

  gc()
}

land_water <- rast(
  f_land_water
)


# ------------------------------------------------------------
# 9. WATER STORAGE
#
# TÄRKEÄ:
# fix_flats = FALSE
#
# Tästä pinnasta saadaan todellinen spill/storage-taso.
# Tässä vaiheessa ei tehdä vielä keinotekoista
# routing-gradienttia järvien sisälle.
# ------------------------------------------------------------

if (
  !file.exists(f_storage) ||
  OVERWRITE
) {

  cat(
    "Running WATER_STORAGE FillDepressions...\n"
  )

  whitebox::wbt_fill_depressions(
    dem = f_land_water,
    output = f_storage,
    fix_flats = FALSE,
    verbose_mode = TRUE
  )
}

stopifnot(
  file.exists(f_storage)
)

storage <- rast(
  f_storage
)


# ------------------------------------------------------------
# 10. BASIC QA
# ------------------------------------------------------------

stopifnot(
  compareGeom(
    dem,
    storage,
    stopOnError = FALSE
  )
)

n_dem <- ncell(
  dem
)

lake_cells <- global(
  !is.na(lake_id),
  "sum",
  na.rm = TRUE
)[1, 1]

land_cells <- n_dem -
  lake_cells


# ------------------------------------------------------------
# 11. REGRESSION AGAINST EXISTING TEST_SULKU_11
#
# Verrataan vain jos referenssit löytyvät.
# ------------------------------------------------------------

reference_dir <- SOURCE_TEST_ROOT

references <- c(
  land_raw =
    "land_dem_raw_BASELINE.tif",

  land_fill =
    "land_dem_filled_BASELINE.tif",

  land_water =
    "routing_surface_land_water_BASELINE.tif",

  storage =
    "routing_surface_water_storage_BASELINE.tif"
)

new_files <- c(
  land_raw = f_land_raw,
  land_fill = f_land_fill,
  land_water = f_land_water,
  storage = f_storage
)


compare_rasters <- function(
  new_file,
  ref_file,
  tolerance = 1e-7
) {

  if (!file.exists(ref_file)) {

    return(
      data.frame(
        geometry_ok = NA,
        na_mismatch = NA,
        max_abs_diff = NA,
        changed_cells = NA,
        pass = NA
      )
    )
  }

  a <- rast(
    new_file
  )

  b <- rast(
    ref_file
  )

  geometry_ok <- compareGeom(
    a,
    b,
    stopOnError = FALSE
  )

  if (!geometry_ok) {

    return(
      data.frame(
        geometry_ok = FALSE,
        na_mismatch = NA,
        max_abs_diff = NA,
        changed_cells = NA,
        pass = FALSE
      )
    )
  }

  na_diff <- xor(
    is.na(a),
    is.na(b)
  )

  n_na_diff <- global(
    na_diff,
    "sum",
    na.rm = TRUE
  )[1, 1]

  d <- abs(
    a - b
  )

  max_diff <- global(
    d,
    "max",
    na.rm = TRUE
  )[1, 1]

  changed <- global(
    d > tolerance,
    "sum",
    na.rm = TRUE
  )[1, 1]

  pass <-
    n_na_diff == 0 &&
    is.finite(max_diff) &&
    max_diff <= tolerance

  data.frame(
    geometry_ok = geometry_ok,
    na_mismatch = n_na_diff,
    max_abs_diff = max_diff,
    changed_cells = changed,
    pass = pass
  )
}


reg <- list()

for (nm in names(references)) {

  reg[[nm]] <- compare_rasters(
    new_files[[nm]],
    file.path(
      reference_dir,
      references[[nm]]
    )
  )

  reg[[nm]]$surface <- nm
}

reg <- do.call(
  rbind,
  reg
)

row.names(reg) <- NULL

reg <- reg[
  ,
  c(
    "surface",
    "geometry_ok",
    "na_mismatch",
    "max_abs_diff",
    "changed_cells",
    "pass"
  )
]


# ------------------------------------------------------------
# 12. SAVE QA
# ------------------------------------------------------------

f_reg <- file.path(
  DIR_02,
  "02A_storage_regression_QA.csv"
)

write.csv(
  reg,
  f_reg,
  row.names = FALSE
)


# ------------------------------------------------------------
# 13. RESULT
# ------------------------------------------------------------

known_tests <- !is.na(
  reg$pass
)

all_pass <-
  any(known_tests) &&
  all(
    reg$pass[known_tests]
  )

cat("\014")

cat(
  "=== 02A LAND + STORAGE ===\n"
)

cat(sprintf(
  "DEM cells          : %.0f\n",
  n_dem
))

cat(sprintf(
  "Lake cells         : %.0f\n",
  lake_cells
))

cat(sprintf(
  "Land cells         : %.0f\n",
  land_cells
))

cat("\nRegression:\n")

for (i in seq_len(nrow(reg))) {

  cat(sprintf(
    "%-12s  pass=%-5s  NA-diff=%s  max-diff=%s  changed=%s\n",
    reg$surface[i],
    ifelse(
      is.na(reg$pass[i]),
      "N/A",
      as.character(reg$pass[i])
    ),
    ifelse(
      is.na(reg$na_mismatch[i]),
      "NA",
      format(
        reg$na_mismatch[i],
        scientific = FALSE
      )
    ),
    ifelse(
      is.na(reg$max_abs_diff[i]),
      "NA",
      format(
        reg$max_abs_diff[i],
        scientific = TRUE,
        digits = 4
      )
    ),
    ifelse(
      is.na(reg$changed_cells[i]),
      "NA",
      format(
        reg$changed_cells[i],
        scientific = FALSE
      )
    )
  ))
}

cat(sprintf(
  "\n02A RESULT         : %s\n",
  ifelse(
    all_pass,
    "PASS",
    "CHECK DIFFERENCES"
  )
))

cat(sprintf(
  "QA file            : %s\n",
  basename(f_reg)
))

cat(
  "===========================\n"
)

# ============================================================
# 02B - LAND -> FIRST RANTA10 WATER
#
# VERSION: 0.2
#
# Tarkoitus:
#
#   LAND --D8--> first RANTA10 water cell
#
# water_class:
#   1 = LAKE
#   2 = RIVER_AREA
#   3 = RIVER_LINE_ONLY
#
# TÄRKEÄÄ:
# - ei nearest-neighbour-snappausta
# - jokialue / jokiviiva EI ole routing-terminal
# - järvet käsitellään myöhemmin erikseen
# - tässä vain tunnistetaan todellinen D8-vastaanottaja
# ============================================================


# ------------------------------------------------------------
# 14. INPUT / OUTPUT FILES
# ------------------------------------------------------------

f_water_class <- file.path(
  SOURCE_TEST_ROOT,
  "ranta10_water_class.tif"
)

stopifnot(
  file.exists(f_water_class)
)

f_ptr_land_water <- file.path(
  DIR_02,
  "d8_pointer_land_water_FLT8S.tif"
)

f_entry_mask <- file.path(
  DIR_02,
  "actual_land_to_water_entry.tif"
)

f_entry_class <- file.path(
  DIR_02,
  "actual_entry_water_class.tif"
)

f_entry_lake <- file.path(
  DIR_02,
  "actual_entry_lake_objectid.tif"
)

f_entry_csv <- file.path(
  DIR_02,
  "02B_land_to_first_water_entries.csv"
)

f_qa_02b <- file.path(
  DIR_02,
  "02B_land_to_first_water_QA.csv"
)


# ------------------------------------------------------------
# 15. D8 POINTER: LAND + LAKE SURFACE
#
# Whitebox pointer scheme:
#
#   64 128  1
#   32  x   2
#   16  8   4
#
# ------------------------------------------------------------

if (
  !file.exists(f_ptr_land_water) ||
  OVERWRITE
) {

  cat(
    "\n02B: building land-water D8 pointer...\n"
  )

  f_tmp_ptr <- file.path(
    DIR_02,
    "_TMP_d8_pointer_land_water.tif"
  )

  if (file.exists(f_tmp_ptr)) {
    file.remove(f_tmp_ptr)
  }

  whitebox::wbt_d8_pointer(
    dem = f_land_water,
    output = f_tmp_ptr,
    esri_pntr = FALSE,
    verbose_mode = TRUE
  )

  stopifnot(
    file.exists(f_tmp_ptr)
  )

  tmp_ptr <- rast(
    f_tmp_ptr
  )

  writeRaster(
    tmp_ptr,
    f_ptr_land_water,
    overwrite = TRUE,
    datatype = "FLT8S",
    gdal = c(
      "COMPRESS=DEFLATE",
      "BIGTIFF=YES"
    )
  )

  rm(tmp_ptr)
  gc()

  file.remove(
    f_tmp_ptr
  )
}


# ------------------------------------------------------------
# 16. READ RASTERS
# ------------------------------------------------------------

ptr_land_water <- rast(
  f_ptr_land_water
)

water_class <- rast(
  f_water_class
)

lake_id <- rast(
  f_lake_id
)

stopifnot(
  compareGeom(
    ptr_land_water,
    water_class,
    stopOnError = FALSE
  ),
  compareGeom(
    ptr_land_water,
    lake_id,
    stopOnError = FALSE
  )
)


# ------------------------------------------------------------
# 17. HELPER
# ------------------------------------------------------------

cell_values <- function(
  r,
  cells
) {

  if (length(cells) == 0) {
    return(numeric(0))
  }

  z <- r[cells]

  if (
    is.data.frame(z) ||
    is.matrix(z)
  ) {
    z <- z[, 1]
  }

  as.numeric(z)
}


# ------------------------------------------------------------
# 18. ALL RANTA10 WATER CELLS
# ------------------------------------------------------------

water_tab <- as.data.frame(
  water_class,
  cells = TRUE,
  na.rm = TRUE
)

stopifnot(
  nrow(water_tab) > 0
)

water_cells <- water_tab$cell


# ------------------------------------------------------------
# 19. TRUE LAND CELLS ADJACENT TO WATER
#
# Maa =
# ei LAKE
# ei RIVER_AREA
# ei RIVER_LINE_ONLY
# ------------------------------------------------------------

adj <- terra::adjacent(
  water_class,
  cells = water_cells,
  directions = 8,
  pairs = TRUE,
  include = FALSE
)

candidate_cells <- unique(
  adj[, 2]
)

candidate_cells <- candidate_cells[
  candidate_cells >= 1 &
    candidate_cells <= ncell(water_class)
]

candidate_class <- cell_values(
  water_class,
  candidate_cells
)

candidate_cells <- candidate_cells[
  !is.finite(candidate_class)
]

rm(
  adj,
  candidate_class
)

gc()


# ------------------------------------------------------------
# 20. POINTER VALUES ON TRUE LAND
# ------------------------------------------------------------

p_all <- cell_values(
  ptr_land_water,
  candidate_cells
)

valid_pointer_codes <- c(
  1,
  2,
  4,
  8,
  16,
  32,
  64,
  128
)

valid <- is.finite(p_all) &
  p_all %in% valid_pointer_codes

source_cell <- candidate_cells[
  valid
]

p <- as.integer(
  p_all[valid]
)


# ------------------------------------------------------------
# 21. POINTER -> RECEIVER CELL
# ------------------------------------------------------------

rc <- rowColFromCell(
  ptr_land_water,
  source_cell
)

dr <- c(
  "1"   = -1,
  "2"   =  0,
  "4"   =  1,
  "8"   =  1,
  "16"  =  1,
  "32"  =  0,
  "64"  = -1,
  "128" = -1
)

dc <- c(
  "1"   =  1,
  "2"   =  1,
  "4"   =  1,
  "8"   =  0,
  "16"  = -1,
  "32"  = -1,
  "64"  = -1,
  "128" =  0
)

receiver_row <- rc[, 1] +
  unname(
    dr[
      as.character(p)
    ]
  )

receiver_col <- rc[, 2] +
  unname(
    dc[
      as.character(p)
    ]
  )

inside <- receiver_row >= 1 &
  receiver_row <= nrow(ptr_land_water) &
  receiver_col >= 1 &
  receiver_col <= ncol(ptr_land_water)

source_cell <- source_cell[
  inside
]

p <- p[
  inside
]

receiver_row <- receiver_row[
  inside
]

receiver_col <- receiver_col[
  inside
]

receiver_cell <- cellFromRowCol(
  ptr_land_water,
  receiver_row,
  receiver_col
)


# ------------------------------------------------------------
# 22. FIRST WATER RECEIVER
# ------------------------------------------------------------

receiver_class <- cell_values(
  water_class,
  receiver_cell
)

is_first_water <- is.finite(
  receiver_class
)

entry_cell <- source_cell[
  is_first_water
]

entry_pointer <- p[
  is_first_water
]

entry_receiver <- receiver_cell[
  is_first_water
]

entry_class <- as.integer(
  receiver_class[
    is_first_water
  ]
)

stopifnot(
  all(
    entry_class %in% c(
      1L,
      2L,
      3L
    )
  )
)


# ------------------------------------------------------------
# 23. LAKE OBJECTID ONLY FOR LAKE RECEIVERS
# ------------------------------------------------------------

entry_lake_objectid <- rep(
  NA_integer_,
  length(entry_cell)
)

is_lake_entry <- entry_class == 1L

if (any(is_lake_entry)) {

  tmp <- cell_values(
    lake_id,
    entry_receiver[
      is_lake_entry
    ]
  )

  stopifnot(
    all(
      is.finite(tmp)
    )
  )

  entry_lake_objectid[
    is_lake_entry
  ] <- as.integer(tmp)
}


# ------------------------------------------------------------
# 24. ENTRY TYPE
# ------------------------------------------------------------

entry_type <- rep(
  NA_character_,
  length(entry_class)
)

entry_type[
  entry_class == 1
] <- "LAKE"

entry_type[
  entry_class == 2
] <- "RIVER_AREA"

entry_type[
  entry_class == 3
] <- "RIVER_LINE"


# ------------------------------------------------------------
# 25. ENTRY TABLE
# ------------------------------------------------------------

xy_source <- xyFromCell(
  ptr_land_water,
  entry_cell
)

xy_receiver <- xyFromCell(
  ptr_land_water,
  entry_receiver
)

entries <- data.frame(
  source_cell = entry_cell,
  source_x = xy_source[, 1],
  source_y = xy_source[, 2],

  d8_code = entry_pointer,

  receiver_cell = entry_receiver,
  receiver_x = xy_receiver[, 1],
  receiver_y = xy_receiver[, 2],

  water_class = entry_class,
  water_type = entry_type,

  lake_objectid = entry_lake_objectid,

  stringsAsFactors = FALSE
)

entries <- entries[
  order(
    entries$water_class,
    entries$receiver_cell,
    entries$source_cell
  ),
  ,
  drop = FALSE
]

row.names(entries) <- NULL

write.csv(
  entries,
  f_entry_csv,
  row.names = FALSE
)


# ------------------------------------------------------------
# 26. SPARSE ENTRY RASTERS
# ------------------------------------------------------------

entry_points <- vect(
  data.frame(
    x = entries$source_x,
    y = entries$source_y,

    entry = 1L,

    water_class =
      entries$water_class,

    lake_objectid =
      entries$lake_objectid
  ),

  geom = c(
    "x",
    "y"
  ),

  crs = crs(
    ptr_land_water
  )
)


# Binary entry raster

entry_mask <- rasterize(
  entry_points,
  ptr_land_water,
  field = "entry",
  background = NA
)

writeRaster(
  entry_mask,
  f_entry_mask,
  overwrite = TRUE,
  datatype = "INT1U",
  NAflag = 255,
  gdal = c(
    "COMPRESS=DEFLATE",
    "BIGTIFF=YES"
  )
)


# Receiver water class

entry_class_raster <- rasterize(
  entry_points,
  ptr_land_water,
  field = "water_class",
  background = NA
)

writeRaster(
  entry_class_raster,
  f_entry_class,
  overwrite = TRUE,
  datatype = "INT1U",
  NAflag = 255,
  gdal = c(
    "COMPRESS=DEFLATE",
    "BIGTIFF=YES"
  )
)


# Lake ID only where receiver = lake

lake_points <- entry_points[
  entries$water_class == 1,
]

entry_lake_raster <- rasterize(
  lake_points,
  ptr_land_water,
  field = "lake_objectid",
  background = NA
)

writeRaster(
  entry_lake_raster,
  f_entry_lake,
  overwrite = TRUE,
  datatype = "INT4S",
  gdal = c(
    "COMPRESS=DEFLATE",
    "BIGTIFF=YES"
  )
)


# ------------------------------------------------------------
# 27. QA
# ------------------------------------------------------------

n_candidate <- length(
  candidate_cells
)

n_valid_pointer <- sum(
  valid
)

n_entries <- nrow(
  entries
)

n_lake <- sum(
  entries$water_class == 1
)

n_area <- sum(
  entries$water_class == 2
)

n_line <- sum(
  entries$water_class == 3
)

n_target_lakes <- length(
  unique(
    entries$lake_objectid[
      is.finite(
        entries$lake_objectid
      )
    ]
  )
)

n_lakes_total <- length(
  unique(
    cell_values(
      lake_id,
      water_cells[
        cell_values(
          water_class,
          water_cells
        ) == 1
      ]
    )
  )
)

zero_candidate <- sum(
  p_all == 0,
  na.rm = TRUE
)

na_candidate <- sum(
  !is.finite(p_all)
)

invalid_candidate <- sum(
  is.finite(p_all) &
    !p_all %in%
      c(
        0,
        valid_pointer_codes
      )
)


qa_02b <- data.frame(

  item = c(
    "true_land_adjacent_to_water",
    "adjacent_land_valid_pointer",
    "direct_land_to_first_water",
    "first_water_lake",
    "first_water_river_area",
    "first_water_river_line",
    "target_lakes",
    "total_lakes",
    "adjacent_land_pointer_zero",
    "adjacent_land_pointer_na",
    "adjacent_land_pointer_invalid"
  ),

  value = c(
    n_candidate,
    n_valid_pointer,
    n_entries,
    n_lake,
    n_area,
    n_line,
    n_target_lakes,
    n_lakes_total,
    zero_candidate,
    na_candidate,
    invalid_candidate
  )
)

write.csv(
  qa_02b,
  f_qa_02b,
  row.names = FALSE
)


# ------------------------------------------------------------
# 28. PRINT
# ------------------------------------------------------------

cat("\n")
cat("=== 02B LAND -> FIRST WATER ===\n")

cat(sprintf(
  "True land adjacent to water : %d\n",
  n_candidate
))

cat(sprintf(
  "Valid D8 pointers           : %d\n",
  n_valid_pointer
))

cat(sprintf(
  "Direct first-water entries  : %d\n",
  n_entries
))

cat(sprintf(
  "  -> LAKE                   : %d\n",
  n_lake
))

cat(sprintf(
  "  -> RIVER_AREA             : %d\n",
  n_area
))

cat(sprintf(
  "  -> RIVER_LINE             : %d\n",
  n_line
))

cat(sprintf(
  "Target lakes / all lakes    : %d / %d\n",
  n_target_lakes,
  n_lakes_total
))

cat(sprintf(
  "Adjacent pointer zero       : %d\n",
  zero_candidate
))

cat(sprintf(
  "Adjacent pointer NA         : %d\n",
  na_candidate
))

cat(sprintf(
  "Adjacent pointer invalid    : %d\n",
  invalid_candidate
))

cat(sprintf(
  "Entry CSV                   : %s\n",
  basename(f_entry_csv)
))

cat("=================================\n")

# ============================================================
# 02C - ZERO POINTER / FLAT SHORE COMPONENT QA
#
# Tavoite:
# - ryhmittele LAND-solut, joiden pointer = 0
# - selvitä mitä RANTA10-vesiluokkia kukin komponentti koskee
# - selvitä järvien objectid:t
# - tarkista korkeussuhde veteen
#
# EI MUUTETA ROUTINGIA VIELÄ.
# ============================================================


# ------------------------------------------------------------
# 29. ZERO POINTER CELLS
# ------------------------------------------------------------

zero_cells <- candidate_cells[
  is.finite(p_all) &
    p_all == 0
]

stopifnot(
  length(zero_cells) ==
    zero_candidate
)

n_zero <- length(
  zero_cells
)


# ------------------------------------------------------------
# 30. CONNECT ZERO CELLS INTO 8-NEIGHBOUR COMPONENTS
# ------------------------------------------------------------

zp <- terra::adjacent(
  ptr_land_water,
  cells = zero_cells,
  directions = 8,
  pairs = TRUE,
  include = FALSE
)

keep <- zp[, 2] %in% zero_cells

zp <- zp[
  keep,
  ,
  drop = FALSE
]

n0 <- length(
  zero_cells
)

adj_list <- vector(
  "list",
  n0
)

if (nrow(zp) > 0) {

  ii <- match(
    zp[, 1],
    zero_cells
  )

  jj <- match(
    zp[, 2],
    zero_cells
  )

  for (k in seq_len(nrow(zp))) {

    i <- ii[k]
    j <- jj[k]

    adj_list[[i]] <- c(
      adj_list[[i]],
      j
    )

    adj_list[[j]] <- c(
      adj_list[[j]],
      i
    )
  }
}


component <- integer(
  n0
)

component_id <- 0L

for (start in seq_len(n0)) {

  if (component[start] != 0L) {
    next
  }

  component_id <- component_id + 1L

  queue <- start
  component[start] <- component_id

  qpos <- 1L

  while (qpos <= length(queue)) {

    i <- queue[qpos]

    nb <- unique(
      adj_list[[i]]
    )

    if (length(nb) > 0) {

      new <- nb[
        component[nb] == 0L
      ]

      if (length(new) > 0) {

        component[new] <- component_id

        queue <- c(
          queue,
          new
        )
      }
    }

    qpos <- qpos + 1L
  }
}

stopifnot(
  all(component > 0)
)


# ------------------------------------------------------------
# 31. ADJACENT WATER CELLS
# ------------------------------------------------------------

wp <- terra::adjacent(
  water_class,
  cells = zero_cells,
  directions = 8,
  pairs = TRUE,
  include = FALSE
)

wclass <- cell_values(
  water_class,
  wp[, 2]
)

is_water_neighbor <- is.finite(
  wclass
)

wp <- wp[
  is_water_neighbor,
  ,
  drop = FALSE
]

wclass <- as.integer(
  wclass[
    is_water_neighbor
  ]
)

stopifnot(
  nrow(wp) > 0,
  all(
    wclass %in% c(
      1L,
      2L,
      3L
    )
  )
)


# ------------------------------------------------------------
# 32. LAKE ID FOR WATER NEIGHBOURS
# ------------------------------------------------------------

neighbor_lake_id <- rep(
  NA_integer_,
  nrow(wp)
)

is_lake_neighbor <- wclass == 1L

if (any(is_lake_neighbor)) {

  tmp <- cell_values(
    lake_id,
    wp[
      is_lake_neighbor,
      2
    ]
  )

  stopifnot(
    all(
      is.finite(tmp)
    )
  )

  neighbor_lake_id[
    is_lake_neighbor
  ] <- as.integer(tmp)
}


# ------------------------------------------------------------
# 33. ELEVATIONS
# ------------------------------------------------------------

zero_z <- cell_values(
  land_water,
  zero_cells
)

water_neighbor_z <- cell_values(
  land_water,
  wp[, 2]
)


# ------------------------------------------------------------
# 34. EDGE QA
# ------------------------------------------------------------

zero_rc <- rowColFromCell(
  ptr_land_water,
  zero_cells
)

zero_edge <- (
  zero_rc[, 1] == 1 |
    zero_rc[, 1] == nrow(ptr_land_water) |
    zero_rc[, 2] == 1 |
    zero_rc[, 2] == ncol(ptr_land_water)
)


# ------------------------------------------------------------
# 35. ZERO-CELL TABLE
# ------------------------------------------------------------

zero_xy <- xyFromCell(
  ptr_land_water,
  zero_cells
)

zero_table <- data.frame(
  cell = zero_cells,
  component_id = component,
  x = zero_xy[, 1],
  y = zero_xy[, 2],
  z_m = zero_z,
  raster_edge = zero_edge,
  stringsAsFactors = FALSE
)

f_zero_cells <- file.path(
  DIR_02,
  "02C_zero_pointer_cells.csv"
)

write.csv(
  zero_table,
  f_zero_cells,
  row.names = FALSE
)


# ------------------------------------------------------------
# 36. WATER-NEIGHBOUR TABLE
# ------------------------------------------------------------

source_component <- component[
  match(
    wp[, 1],
    zero_cells
  )
]

water_neighbor_table <- data.frame(
  component_id = source_component,
  source_cell = wp[, 1],
  water_cell = wp[, 2],
  water_class = wclass,
  lake_objectid = neighbor_lake_id,
  water_z_m = water_neighbor_z,
  stringsAsFactors = FALSE
)

f_neighbors <- file.path(
  DIR_02,
  "02C_zero_pointer_water_neighbors.csv"
)

write.csv(
  water_neighbor_table,
  f_neighbors,
  row.names = FALSE
)


# ------------------------------------------------------------
# 37. COMPONENT SUMMARY
# ------------------------------------------------------------

summary_list <- vector(
  "list",
  component_id
)

for (cid in seq_len(component_id)) {

  zi <- which(
    component == cid
  )

  source_cells_c <- zero_cells[
    zi
  ]

  wi <- which(
    source_component == cid
  )

  wc <- unique(
    wclass[
      wi
    ]
  )

  lids <- unique(
    neighbor_lake_id[
      wi
    ]
  )

  lids <- lids[
    is.finite(lids)
  ]

  touches_lake <- 1L %in% wc
  touches_area <- 2L %in% wc
  touches_line <- 3L %in% wc

  if (
    touches_lake &&
    !touches_area &&
    !touches_line
  ) {

    signature <- "LAKE_ONLY"

  } else if (
    !touches_lake &&
    touches_area &&
    !touches_line
  ) {

    signature <- "RIVER_AREA_ONLY"

  } else if (
    !touches_lake &&
    !touches_area &&
    touches_line
  ) {

    signature <- "RIVER_LINE_ONLY"

  } else {

    signature <- "MIXED"
  }

  z_terminal <- zero_z[
    zi
  ]

  z_water <- water_neighbor_z[
    wi
  ]

  summary_list[[cid]] <- data.frame(

    component_id = cid,

    n_zero_cells =
      length(zi),

    n_water_neighbor_cells =
      length(
        unique(
          wp[
            wi,
            2
          ]
        )
      ),

    touches_lake =
      touches_lake,

    touches_river_area =
      touches_area,

    touches_river_line =
      touches_line,

    n_lake_objectids =
      length(lids),

    lake_objectids =
      if (
        length(lids) == 0
      ) {
        ""
      } else {
        paste(
          sort(lids),
          collapse = ";"
        )
      },

    water_signature =
      signature,

    terminal_min_z_m =
      min(
        z_terminal,
        na.rm = TRUE
      ),

    terminal_max_z_m =
      max(
        z_terminal,
        na.rm = TRUE
      ),

    min_adjacent_water_z_m =
      min(
        z_water,
        na.rm = TRUE
      ),

    terminal_minus_water_m =
      min(
        z_terminal,
        na.rm = TRUE
      ) -
      min(
        z_water,
        na.rm = TRUE
      ),

    touches_raster_edge =
      any(
        zero_edge[
          zi
        ]
      ),

    stringsAsFactors = FALSE
  )
}

component_summary <- do.call(
  rbind,
  summary_list
)

row.names(
  component_summary
) <- NULL


# ------------------------------------------------------------
# 38. SAVE COMPONENT QA
# ------------------------------------------------------------

f_component_qa <- file.path(
  DIR_02,
  "02C_zero_pointer_component_QA.csv"
)

write.csv(
  component_summary,
  f_component_qa,
  row.names = FALSE
)


# ------------------------------------------------------------
# 39. SHORT SUMMARY
# ------------------------------------------------------------

n_components <- nrow(
  component_summary
)

n_lake_only <- sum(
  component_summary$water_signature ==
    "LAKE_ONLY"
)

n_area_only <- sum(
  component_summary$water_signature ==
    "RIVER_AREA_ONLY"
)

n_line_only <- sum(
  component_summary$water_signature ==
    "RIVER_LINE_ONLY"
)

n_mixed <- sum(
  component_summary$water_signature ==
    "MIXED"
)

n_multi_lake <- sum(
  component_summary$n_lake_objectids > 1
)

n_edge_components <- sum(
  component_summary$touches_raster_edge
)

size_q <- quantile(
  component_summary$n_zero_cells,
  probs = c(
    0,
    0.5,
    0.95,
    1
  ),
  names = FALSE
)


# ------------------------------------------------------------
# 40. PRINT
# ------------------------------------------------------------

cat("\n")
cat("=== 02C ZERO POINTER COMPONENT QA ===\n")

cat(sprintf(
  "Zero land cells            : %d\n",
  n_zero
))

cat(sprintf(
  "Connected components       : %d\n",
  n_components
))

cat(sprintf(
  "LAKE_ONLY                  : %d\n",
  n_lake_only
))

cat(sprintf(
  "RIVER_AREA_ONLY            : %d\n",
  n_area_only
))

cat(sprintf(
  "RIVER_LINE_ONLY            : %d\n",
  n_line_only
))

cat(sprintf(
  "MIXED                      : %d\n",
  n_mixed
))

cat(sprintf(
  "Components with >1 lake ID : %d\n",
  n_multi_lake
))

cat(sprintf(
  "Components touching edge   : %d\n",
  n_edge_components
))

cat(sprintf(
  "Component size min/med/q95/max: %.0f / %.0f / %.0f / %.0f\n",
  size_q[1],
  size_q[2],
  size_q[3],
  size_q[4]
))

cat(sprintf(
  "Component QA               : %s\n",
  basename(f_component_qa)
))

cat("======================================\n")

# LAKE_ONLY + exactly 1 lake ID + not edge
        # → SAFE_LAKE_CONNECTOR

# RIVER_LINE_ONLY
        # → säilytetään river-line receiverina,
          # ei käsitellä järven shore connectorina

# MIXED
        # → ratkaistaan vesiluokkien ja D8:n perusteella erikseen

# >1 lake ID
        # → AMBIGUOUS, ei automaattista valintaa

# touches raster edge
        # → EDGE_CASE, ei pakoteta sisäiseksi connectoriksi
		
# ============================================================
# 02C.2 - SHORE TARGET CLASSIFICATION
#
# Luokat:
#
# SAFE_LAKE_CONNECTOR
#   - LAKE_ONLY
#   - exactly 1 lake objectid
#   - not raster edge
#
# EDGE_CASE
#   - component touches raster edge
#
# INTERIOR_REVIEW
#   - kaikki muut sisäiset tapaukset
#
# Tässä EI muuteta pointeria.
# ============================================================


# ------------------------------------------------------------
# 41. CLASSIFY COMPONENTS
# ------------------------------------------------------------

component_summary$connector_status <- NA_character_

safe <- (
  component_summary$water_signature == "LAKE_ONLY" &
    component_summary$n_lake_objectids == 1 &
    !component_summary$touches_raster_edge
)

edge <- component_summary$touches_raster_edge

review <- !safe & !edge


component_summary$connector_status[
  safe
] <- "SAFE_LAKE_CONNECTOR"

component_summary$connector_status[
  edge
] <- "EDGE_CASE"

component_summary$connector_status[
  review
] <- "INTERIOR_REVIEW"

stopifnot(
  all(
    !is.na(
      component_summary$connector_status
    )
  )
)


# ------------------------------------------------------------
# 42. SAFE TARGET LAKE
# ------------------------------------------------------------

component_summary$target_lake_objectid <- NA_integer_

component_summary$target_lake_objectid[
  safe
] <- as.integer(
  component_summary$lake_objectids[
    safe
  ]
)

stopifnot(
  all(
    is.finite(
      component_summary$target_lake_objectid[
        safe
      ]
    )
  )
)


# ------------------------------------------------------------
# 43. SAVE FULL CLASSIFICATION
# ------------------------------------------------------------

f_connector_class <- file.path(
  DIR_02,
  "02C_shore_component_classification.csv"
)

write.csv(
  component_summary,
  f_connector_class,
  row.names = FALSE
)


# ------------------------------------------------------------
# 44. SAFE CONNECTOR TARGET TABLE
# ------------------------------------------------------------

safe_targets <- component_summary[
  safe,
  c(
    "component_id",
    "n_zero_cells",
    "target_lake_objectid",
    "terminal_min_z_m",
    "terminal_max_z_m",
    "min_adjacent_water_z_m",
    "terminal_minus_water_m"
  ),
  drop = FALSE
]

f_safe_targets <- file.path(
  DIR_02,
  "02C_safe_lake_connector_targets.csv"
)

write.csv(
  safe_targets,
  f_safe_targets,
  row.names = FALSE
)


# ------------------------------------------------------------
# 45. INTERIOR REVIEW DETAILS
# ------------------------------------------------------------

review_ids <- component_summary$component_id[
  review
]

review_detail <- vector(
  "list",
  length(review_ids)
)

for (k in seq_along(review_ids)) {

  cid <- review_ids[k]

  comp <- component_summary[
    component_summary$component_id == cid,
    ,
    drop = FALSE
  ]

  wn <- water_neighbor_table[
    water_neighbor_table$component_id == cid,
    ,
    drop = FALSE
  ]

  zc <- zero_table[
    zero_table$component_id == cid,
    ,
    drop = FALSE
  ]

  n_lake <- sum(
    wn$water_class == 1
  )

  n_area <- sum(
    wn$water_class == 2
  )

  n_line <- sum(
    wn$water_class == 3
  )

  lake_ids <- sort(
    unique(
      wn$lake_objectid[
        is.finite(
          wn$lake_objectid
        )
      ]
    )
  )

  review_detail[[k]] <- data.frame(
    component_id = cid,

    n_zero_cells =
      nrow(zc),

    n_lake_neighbors =
      n_lake,

    n_river_area_neighbors =
      n_area,

    n_river_line_neighbors =
      n_line,

    lake_objectids =
      if (length(lake_ids) == 0) {
        ""
      } else {
        paste(
          lake_ids,
          collapse = ";"
        )
      },

    min_x =
      min(zc$x),

    max_x =
      max(zc$x),

    min_y =
      min(zc$y),

    max_y =
      max(zc$y),

    terminal_min_z_m =
      comp$terminal_min_z_m,

    min_adjacent_water_z_m =
      comp$min_adjacent_water_z_m,

    dz_m =
      comp$terminal_minus_water_m,

    stringsAsFactors = FALSE
  )
}

if (length(review_detail) > 0) {

  review_detail <- do.call(
    rbind,
    review_detail
  )

} else {

  review_detail <- data.frame()
}


f_review <- file.path(
  DIR_02,
  "02C_interior_review.csv"
)

write.csv(
  review_detail,
  f_review,
  row.names = FALSE
)


# ------------------------------------------------------------
# 46. QA
# ------------------------------------------------------------

n_safe <- sum(
  component_summary$connector_status ==
    "SAFE_LAKE_CONNECTOR"
)

n_edge <- sum(
  component_summary$connector_status ==
    "EDGE_CASE"
)

n_review <- sum(
  component_summary$connector_status ==
    "INTERIOR_REVIEW"
)


cat("\n")
cat("=== 02C SHORE TARGET CLASSIFICATION ===\n")

cat(sprintf(
  "Components total       : %d\n",
  nrow(component_summary)
))

cat(sprintf(
  "SAFE_LAKE_CONNECTOR    : %d\n",
  n_safe
))

cat(sprintf(
  "EDGE_CASE              : %d\n",
  n_edge
))

cat(sprintf(
  "INTERIOR_REVIEW        : %d\n",
  n_review
))

cat(sprintf(
  "Safe zero cells        : %d / %d\n",
  sum(
    component_summary$n_zero_cells[
      safe
    ]
  ),
  sum(
    component_summary$n_zero_cells
  )
))

cat("\n--- INTERIOR REVIEW ---\n")

if (nrow(review_detail) == 0) {

  cat("NONE\n")

} else {

  print(
    review_detail,
    row.names = FALSE
  )
}

cat("========================================\n")

# ============================================================
# 02C.3 - FINAL SAFE SHORE TARGETS
#
# SAFE connector = target classification only.
# D8 POINTER IS NOT MODIFIED.
# ============================================================


# ------------------------------------------------------------
# 47. SAFE COMPONENT -> LAKE TARGET
# ------------------------------------------------------------

safe_component_target <- component_summary[
  component_summary$connector_status ==
    "SAFE_LAKE_CONNECTOR",
  c(
    "component_id",
    "target_lake_objectid"
  ),
  drop = FALSE
]

stopifnot(
  nrow(safe_component_target) == 585,
  all(
    is.finite(
      safe_component_target$target_lake_objectid
    )
  )
)


# ------------------------------------------------------------
# 48. SAFE ZERO CELLS
# ------------------------------------------------------------

safe_cells <- merge(
  zero_table,
  safe_component_target,
  by = "component_id",
  all = FALSE,
  sort = FALSE
)

safe_cells <- safe_cells[
  order(safe_cells$cell),
  ,
  drop = FALSE
]

stopifnot(
  nrow(safe_cells) == 732,
  !anyDuplicated(safe_cells$cell)
)


f_safe_cells <- file.path(
  DIR_02,
  "02C_safe_shore_target_cells.csv"
)

write.csv(
  safe_cells,
  f_safe_cells,
  row.names = FALSE
)


# ------------------------------------------------------------
# 49. SAFE TARGET RASTER
# ------------------------------------------------------------

safe_points <- vect(
  data.frame(
    x = safe_cells$x,
    y = safe_cells$y,
    lake_objectid =
      safe_cells$target_lake_objectid
  ),
  geom = c("x", "y"),
  crs = crs(ptr_land_water)
)

shore_target_lake <- rasterize(
  safe_points,
  ptr_land_water,
  field = "lake_objectid",
  background = NA
)

f_shore_target_lake <- file.path(
  DIR_02,
  "shore_target_lake_objectid.tif"
)

writeRaster(
  shore_target_lake,
  f_shore_target_lake,
  overwrite = TRUE,
  datatype = "INT4S",
  gdal = c(
    "COMPRESS=DEFLATE",
    "BIGTIFF=YES"
  )
)


# ------------------------------------------------------------
# 50. DEFERRED COMPONENTS
# ------------------------------------------------------------

deferred <- component_summary[
  component_summary$connector_status !=
    "SAFE_LAKE_CONNECTOR",
  ,
  drop = FALSE
]

f_deferred <- file.path(
  DIR_02,
  "02C_deferred_shore_components.csv"
)

write.csv(
  deferred,
  f_deferred,
  row.names = FALSE
)


# ------------------------------------------------------------
# 51. FINAL 02C QA
# ------------------------------------------------------------

n_safe_components <- nrow(
  safe_component_target
)

n_safe_cells <- nrow(
  safe_cells
)

n_edge_components <- sum(
  component_summary$connector_status ==
    "EDGE_CASE"
)

n_review_components <- sum(
  component_summary$connector_status ==
    "INTERIOR_REVIEW"
)

n_deferred_cells <- sum(
  component_summary$n_zero_cells[
    component_summary$connector_status !=
      "SAFE_LAKE_CONNECTOR"
  ]
)

cat("\n")
cat("=== 02C FINAL SHORE TARGETS ===\n")

cat(sprintf(
  "Safe components       : %d\n",
  n_safe_components
))

cat(sprintf(
  "Safe zero cells       : %d\n",
  n_safe_cells
))

cat(sprintf(
  "Edge components       : %d\n",
  n_edge_components
))

cat(sprintf(
  "Interior review       : %d\n",
  n_review_components
))

cat(sprintf(
  "Deferred zero cells   : %d\n",
  n_deferred_cells
))

cat(sprintf(
  "D8 pointer modified   : NO\n"
))

cat(sprintf(
  "Target raster         : %s\n",
  basename(f_shore_target_lake)
))

cat("=================================\n")

# ============================================================
# 02D.1 - LAKE SHORE OUTLET CANDIDATE INVENTORY
#
# Tavoite:
# - kaikki järvisolu -> järven ulkopuolinen naapuri -parit
# - EI vielä outlet-valintaa
# - EI pointer-muutoksia
#
# Vastaanottaja voi olla:
#   LAND
#   RIVER_AREA
#   RIVER_LINE
#   OTHER_LAKE
#
# Lisäksi tallennetaan:
# - järven korkeus
# - naapurin korkeus
# - WATER_STORAGE-korkeudet
# - paikallinen step/spill-taso
# ============================================================


# ------------------------------------------------------------
# 52. INPUT SURFACES
# ------------------------------------------------------------

f_surface_land_water <- file.path(
  DIR_02,
  "routing_surface_land_water_FLT8S.tif"
)

f_surface_storage <- file.path(
  DIR_02,
  "routing_surface_water_storage_FLT8S.tif"
)

stopifnot(
  file.exists(f_surface_land_water),
  file.exists(f_surface_storage)
)

surface_land_water <- rast(
  f_surface_land_water
)

surface_storage <- rast(
  f_surface_storage
)

stopifnot(
  compareGeom(
    surface_land_water,
    lake_id,
    stopOnError = FALSE
  ),
  compareGeom(
    surface_storage,
    lake_id,
    stopOnError = FALSE
  )
)


# ------------------------------------------------------------
# 53. ALL LAKE CELLS
# ------------------------------------------------------------

lake_tab_02d <- as.data.frame(
  lake_id,
  cells = TRUE,
  na.rm = TRUE
)

stopifnot(
  nrow(lake_tab_02d) > 0
)

lake_cells_02d <- lake_tab_02d$cell


# ------------------------------------------------------------
# 54. ALL 8-NEIGHBOURS OF LAKE CELLS
# ------------------------------------------------------------

lake_adj <- terra::adjacent(
  lake_id,
  cells = lake_cells_02d,
  directions = 8,
  pairs = TRUE,
  include = FALSE
)

source_cell <- lake_adj[, 1]
receiver_cell <- lake_adj[, 2]

source_lake_id <- cell_values(
  lake_id,
  source_cell
)

receiver_lake_id <- cell_values(
  lake_id,
  receiver_cell
)


# ------------------------------------------------------------
# 55. KEEP ONLY EDGES LEAVING THE SAME LAKE
#
# Remove:
# lake A -> lake A
#
# Keep:
# lake A -> land
# lake A -> river
# lake A -> different lake B
# ------------------------------------------------------------

leaves_lake <- (
  !is.finite(receiver_lake_id) |
    receiver_lake_id != source_lake_id
)

source_cell <- source_cell[
  leaves_lake
]

receiver_cell <- receiver_cell[
  leaves_lake
]

source_lake_id <- as.integer(
  source_lake_id[
    leaves_lake
  ]
)

receiver_lake_id <- receiver_lake_id[
  leaves_lake
]


# ------------------------------------------------------------
# 56. RECEIVER WATER CLASS
# ------------------------------------------------------------

receiver_water_class <- cell_values(
  water_class,
  receiver_cell
)

receiver_type <- rep(
  "LAND",
  length(receiver_cell)
)

receiver_type[
  receiver_water_class == 2
] <- "RIVER_AREA"

receiver_type[
  receiver_water_class == 3
] <- "RIVER_LINE"

is_other_lake <- (
  receiver_water_class == 1 &
    is.finite(receiver_lake_id) &
    receiver_lake_id != source_lake_id
)

receiver_type[
  is_other_lake
] <- "OTHER_LAKE"


# ------------------------------------------------------------
# 57. D8 DIRECTION CODE FOR EACH SHORE EDGE
#
# Whitebox:
#
#   64 128  1
#   32  x   2
#   16  8   4
# ------------------------------------------------------------

src_rc <- rowColFromCell(
  lake_id,
  source_cell
)

rec_rc <- rowColFromCell(
  lake_id,
  receiver_cell
)

row_delta <- rec_rc[, 1] -
  src_rc[, 1]

col_delta <- rec_rc[, 2] -
  src_rc[, 2]

direction_key <- paste(
  row_delta,
  col_delta,
  sep = ","
)

direction_lookup <- c(
  "-1,1"  = 1L,
  "0,1"   = 2L,
  "1,1"   = 4L,
  "1,0"   = 8L,
  "1,-1"  = 16L,
  "0,-1"  = 32L,
  "-1,-1" = 64L,
  "-1,0"  = 128L
)

d8_code_out <- unname(
  direction_lookup[
    direction_key
  ]
)

stopifnot(
  all(
    is.finite(d8_code_out)
  )
)


# ------------------------------------------------------------
# 58. ELEVATIONS
# ------------------------------------------------------------

lake_z <- cell_values(
  surface_land_water,
  source_cell
)

receiver_z <- cell_values(
  surface_land_water,
  receiver_cell
)

lake_storage_z <- cell_values(
  surface_storage,
  source_cell
)

receiver_storage_z <- cell_values(
  surface_storage,
  receiver_cell
)


# Local immediate shore step:
# minimum level needed to cross this single lake boundary edge.

local_step_level_m <- rep(
  NA_real_,
  length(source_cell)
)

ok_local <- is.finite(lake_z) &
  is.finite(receiver_z)

local_step_level_m[
  ok_local
] <- pmax(
  lake_z[ok_local],
  receiver_z[ok_local]
)


# Same diagnostic after WATER_STORAGE filling.

storage_step_level_m <- rep(
  NA_real_,
  length(source_cell)
)

ok_storage <- is.finite(lake_storage_z) &
  is.finite(receiver_storage_z)

storage_step_level_m[
  ok_storage
] <- pmax(
  lake_storage_z[ok_storage],
  receiver_storage_z[ok_storage]
)


storage_raise_m <- lake_storage_z -
  lake_z

receiver_drop_from_lake_m <- lake_z -
  receiver_z


# ------------------------------------------------------------
# 59. COORDINATES
# ------------------------------------------------------------

src_xy <- xyFromCell(
  lake_id,
  source_cell
)

rec_xy <- xyFromCell(
  lake_id,
  receiver_cell
)


# ------------------------------------------------------------
# 60. FULL SHORE EDGE INVENTORY
# ------------------------------------------------------------

shore_candidates <- data.frame(

  lake_objectid =
    source_lake_id,

  source_cell =
    source_cell,

  source_x =
    src_xy[, 1],

  source_y =
    src_xy[, 2],

  receiver_cell =
    receiver_cell,

  receiver_x =
    rec_xy[, 1],

  receiver_y =
    rec_xy[, 2],

  d8_code_out =
    as.integer(d8_code_out),

  receiver_type =
    receiver_type,

  receiver_water_class =
    as.integer(receiver_water_class),

  receiver_lake_objectid =
    as.integer(receiver_lake_id),

  lake_z_m =
    lake_z,

  receiver_z_m =
    receiver_z,

  local_step_level_m =
    local_step_level_m,

  lake_storage_z_m =
    lake_storage_z,

  receiver_storage_z_m =
    receiver_storage_z,

  storage_step_level_m =
    storage_step_level_m,

  storage_raise_m =
    storage_raise_m,

  receiver_drop_from_lake_m =
    receiver_drop_from_lake_m,

  stringsAsFactors = FALSE
)

shore_candidates <- shore_candidates[
  order(
    shore_candidates$lake_objectid,
    shore_candidates$storage_step_level_m,
    shore_candidates$source_cell,
    shore_candidates$receiver_cell
  ),
  ,
  drop = FALSE
]

row.names(
  shore_candidates
) <- NULL


# ------------------------------------------------------------
# 61. SAVE FULL INVENTORY
# ------------------------------------------------------------

f_shore_candidates <- file.path(
  DIR_02,
  "02D_lake_shore_candidates_all.csv"
)

write.csv(
  shore_candidates,
  f_shore_candidates,
  row.names = FALSE
)


# ------------------------------------------------------------
# 62. PER-LAKE SUMMARY
# ------------------------------------------------------------

lake_split <- split(
  seq_len(nrow(shore_candidates)),
  shore_candidates$lake_objectid
)

lake_summary_list <- lapply(
  names(lake_split),
  function(id) {

    ii <- lake_split[[id]]

    x <- shore_candidates[
      ii,
      ,
      drop = FALSE
    ]

    finite_storage <- is.finite(
      x$storage_step_level_m
    )

    min_storage_step <- if (
      any(finite_storage)
    ) {
      min(
        x$storage_step_level_m[
          finite_storage
        ]
      )
    } else {
      NA_real_
    }

    at_min <- if (
      is.finite(min_storage_step)
    ) {
      abs(
        x$storage_step_level_m -
          min_storage_step
      ) <= 1e-7
    } else {
      rep(
        FALSE,
        nrow(x)
      )
    }

    finite_raise <- is.finite(
      x$storage_raise_m
    )

    data.frame(

      lake_objectid =
        as.integer(id),

      n_shore_edges =
        nrow(x),

      n_land_edges =
        sum(
          x$receiver_type ==
            "LAND"
        ),

      n_river_area_edges =
        sum(
          x$receiver_type ==
            "RIVER_AREA"
        ),

      n_river_line_edges =
        sum(
          x$receiver_type ==
            "RIVER_LINE"
        ),

      n_other_lake_edges =
        sum(
          x$receiver_type ==
            "OTHER_LAKE"
        ),

      min_storage_step_m =
        min_storage_step,

      n_edges_at_min_storage =
        sum(
          at_min,
          na.rm = TRUE
        ),

      min_storage_raise_m =
        if (
          any(finite_raise)
        ) {
          min(
            x$storage_raise_m[
              finite_raise
            ]
          )
        } else {
          NA_real_
        },

      max_storage_raise_m =
        if (
          any(finite_raise)
        ) {
          max(
            x$storage_raise_m[
              finite_raise
            ]
          )
        } else {
          NA_real_
        },

      stringsAsFactors = FALSE
    )
  }
)

lake_outlet_summary <- do.call(
  rbind,
  lake_summary_list
)

row.names(
  lake_outlet_summary
) <- NULL

lake_outlet_summary <- lake_outlet_summary[
  order(
    lake_outlet_summary$lake_objectid
  ),
  ,
  drop = FALSE
]


f_lake_outlet_summary <- file.path(
  DIR_02,
  "02D_lake_shore_candidate_summary.csv"
)

write.csv(
  lake_outlet_summary,
  f_lake_outlet_summary,
  row.names = FALSE
)


# ------------------------------------------------------------
# 63. QA
# ------------------------------------------------------------

n_lakes_02d <- nrow(
  lake_outlet_summary
)

n_edges_02d <- nrow(
  shore_candidates
)

n_land_edges <- sum(
  shore_candidates$receiver_type ==
    "LAND"
)

n_area_edges <- sum(
  shore_candidates$receiver_type ==
    "RIVER_AREA"
)

n_line_edges <- sum(
  shore_candidates$receiver_type ==
    "RIVER_LINE"
)

n_other_lake_edges <- sum(
  shore_candidates$receiver_type ==
    "OTHER_LAKE"
)

n_lakes_river_contact <- sum(
  (
    lake_outlet_summary$n_river_area_edges +
      lake_outlet_summary$n_river_line_edges
  ) > 0
)

n_lakes_other_lake <- sum(
  lake_outlet_summary$n_other_lake_edges > 0
)

n_lakes_raised <- sum(
  lake_outlet_summary$max_storage_raise_m >
    1e-7,
  na.rm = TRUE
)

max_raise_02d <- max(
  lake_outlet_summary$max_storage_raise_m,
  na.rm = TRUE
)

edge_q <- quantile(
  lake_outlet_summary$n_shore_edges,
  probs = c(
    0,
    0.5,
    0.95,
    1
  ),
  names = FALSE
)


# ------------------------------------------------------------
# 64. PRINT
# ------------------------------------------------------------

cat("\n")
cat("=== 02D.1 LAKE SHORE INVENTORY ===\n")

cat(sprintf(
  "Lakes                    : %d\n",
  n_lakes_02d
))

cat(sprintf(
  "Shore edges              : %d\n",
  n_edges_02d
))

cat(sprintf(
  "  -> LAND                : %d\n",
  n_land_edges
))

cat(sprintf(
  "  -> RIVER_AREA          : %d\n",
  n_area_edges
))

cat(sprintf(
  "  -> RIVER_LINE          : %d\n",
  n_line_edges
))

cat(sprintf(
  "  -> OTHER_LAKE          : %d\n",
  n_other_lake_edges
))

cat(sprintf(
  "Lakes touching river     : %d / %d\n",
  n_lakes_river_contact,
  n_lakes_02d
))

cat(sprintf(
  "Lakes touching other lake: %d\n",
  n_lakes_other_lake
))

cat(sprintf(
  "Lakes raised by storage  : %d / %d\n",
  n_lakes_raised,
  n_lakes_02d
))

cat(sprintf(
  "Maximum storage raise    : %.6f m\n",
  max_raise_02d
))

cat(sprintf(
  "Shore edges min/med/q95/max: %.0f / %.0f / %.0f / %.0f\n",
  edge_q[1],
  edge_q[2],
  edge_q[3],
  edge_q[4]
))

cat(sprintf(
  "Candidate CSV            : %s\n",
  basename(f_shore_candidates)
))

cat("=====================================\n")

# ============================================================
# 02D.2 - LOWEST SPILL SHORE GROUPS
#
# Tavoite:
# - etsi jokaiselle järvelle alin WATER_STORAGE spill-taso
# - ota kaikki siihen tasoon kuuluvat rantareunat
# - ryhmittele vierekkäiset source-rantapikselit
# - EI vielä outlet-valintaa
# - EI pointer-muutoksia
# ============================================================


# ------------------------------------------------------------
# 65. NUMERICAL TOLERANCE
# ------------------------------------------------------------

spill_tol_m <- 1e-6


# ------------------------------------------------------------
# 66. HELPERS
# ------------------------------------------------------------

make_components <- function(
  cells,
  template
) {

  cells <- sort(
    unique(cells)
  )

  n <- length(cells)

  if (n == 0) {
    return(
      integer(0)
    )
  }

  if (n == 1) {
    out <- 1L
    names(out) <- as.character(cells)
    return(out)
  }

  ap <- terra::adjacent(
    template,
    cells = cells,
    directions = 8,
    pairs = TRUE,
    include = FALSE
  )

  ap <- ap[
    ap[, 2] %in% cells,
    ,
    drop = FALSE
  ]

  adj_list <- vector(
    "list",
    n
  )

  if (nrow(ap) > 0) {

    ii <- match(
      ap[, 1],
      cells
    )

    jj <- match(
      ap[, 2],
      cells
    )

    for (k in seq_len(nrow(ap))) {

      i <- ii[k]
      j <- jj[k]

      if (
        is.na(i) ||
        is.na(j)
      ) {
        next
      }

      adj_list[[i]] <- c(
        adj_list[[i]],
        j
      )

      adj_list[[j]] <- c(
        adj_list[[j]],
        i
      )
    }
  }

  component <- integer(n)

  cid <- 0L

  for (start in seq_len(n)) {

    if (component[start] != 0L) {
      next
    }

    cid <- cid + 1L

    queue <- start

    component[start] <- cid

    qpos <- 1L

    while (qpos <= length(queue)) {

      i <- queue[qpos]

      nb <- unique(
        adj_list[[i]]
      )

      if (length(nb) > 0) {

        new <- nb[
          component[nb] == 0L
        ]

        if (length(new) > 0) {

          component[new] <- cid

          queue <- c(
            queue,
            new
          )
        }
      }

      qpos <- qpos + 1L
    }
  }

  names(component) <- as.character(cells)

  component
}


is_edge_cell <- function(
  r,
  cells
) {

  rc <- rowColFromCell(
    r,
    cells
  )

  rc[, 1] == 1 |
    rc[, 1] == nrow(r) |
    rc[, 2] == 1 |
    rc[, 2] == ncol(r)
}


# ------------------------------------------------------------
# 67. PROCESS EACH LAKE
# ------------------------------------------------------------

lake_ids_02d <- sort(
  unique(
    shore_candidates$lake_objectid
  )
)

low_edge_list <- vector(
  "list",
  length(lake_ids_02d)
)

group_summary_list <- list()

lake_low_summary_list <- vector(
  "list",
  length(lake_ids_02d)
)

group_counter <- 0L


for (i in seq_along(lake_ids_02d)) {

  lid <- lake_ids_02d[i]

  x <- shore_candidates[
    shore_candidates$lake_objectid == lid,
    ,
    drop = FALSE
  ]

  finite_spill <- is.finite(
    x$storage_step_level_m
  )

  stopifnot(
    any(finite_spill)
  )

  min_spill <- min(
    x$storage_step_level_m[
      finite_spill
    ]
  )

  low <- finite_spill &
    abs(
      x$storage_step_level_m -
        min_spill
    ) <= spill_tol_m

  lx <- x[
    low,
    ,
    drop = FALSE
  ]

  stopifnot(
    nrow(lx) > 0
  )


  # ----------------------------------------------------------
  # 67A. GROUP LOW-SHORE SOURCE CELLS
  # ----------------------------------------------------------

  src_cells <- sort(
    unique(
      lx$source_cell
    )
  )

  comp <- make_components(
    src_cells,
    lake_id
  )

  lx$local_group <- unname(
    comp[
      as.character(
        lx$source_cell
      )
    ]
  )

  stopifnot(
    all(
      is.finite(
        lx$local_group
      )
    )
  )

  n_groups <- max(
    lx$local_group
  )


  # ----------------------------------------------------------
  # 67B. GLOBAL GROUP IDS
  # ----------------------------------------------------------

  local_to_global <- integer(
    n_groups
  )

  for (g in seq_len(n_groups)) {

    group_counter <- group_counter + 1L

    local_to_global[g] <- group_counter
  }

  lx$spill_group_id <- local_to_global[
    lx$local_group
  ]


  # ----------------------------------------------------------
  # 67C. EDGE FLAGS
  # ----------------------------------------------------------

  lx$source_raster_edge <- is_edge_cell(
    lake_id,
    lx$source_cell
  )

  lx$receiver_raster_edge <- is_edge_cell(
    lake_id,
    lx$receiver_cell
  )


  # ----------------------------------------------------------
  # 67D. GROUP SUMMARIES
  # ----------------------------------------------------------

  for (g in seq_len(n_groups)) {

    gx <- lx[
      lx$local_group == g,
      ,
      drop = FALSE
    ]

    receiver_lakes <- sort(
      unique(
        gx$receiver_lake_objectid[
          is.finite(
            gx$receiver_lake_objectid
          )
        ]
      )
    )

    group_summary_list[[
      length(group_summary_list) + 1L
    ]] <- data.frame(

      spill_group_id =
        unique(
          gx$spill_group_id
        ),

      lake_objectid =
        lid,

      local_group =
        g,

      n_source_cells =
        length(
          unique(
            gx$source_cell
          )
        ),

      n_receiver_cells =
        length(
          unique(
            gx$receiver_cell
          )
        ),

      n_edges =
        nrow(gx),

      n_land_edges =
        sum(
          gx$receiver_type ==
            "LAND"
        ),

      n_river_area_edges =
        sum(
          gx$receiver_type ==
            "RIVER_AREA"
        ),

      n_river_line_edges =
        sum(
          gx$receiver_type ==
            "RIVER_LINE"
        ),

      n_other_lake_edges =
        sum(
          gx$receiver_type ==
            "OTHER_LAKE"
        ),

      n_receiver_lakes =
        length(
          receiver_lakes
        ),

      receiver_lake_objectids =
        if (
          length(receiver_lakes) == 0
        ) {
          ""
        } else {
          paste(
            receiver_lakes,
            collapse = ";"
          )
        },

      spill_level_m =
        min_spill,

      min_receiver_z_m =
        min(
          gx$receiver_z_m,
          na.rm = TRUE
        ),

      max_receiver_drop_m =
        max(
          gx$receiver_drop_from_lake_m,
          na.rm = TRUE
        ),

      touches_raster_edge =
        any(
          gx$source_raster_edge |
            gx$receiver_raster_edge
        ),

      stringsAsFactors = FALSE
    )
  }


  # ----------------------------------------------------------
  # 67E. PER-LAKE SUMMARY
  # ----------------------------------------------------------

  lake_z_unique <- x$lake_z_m[
    is.finite(
      x$lake_z_m
    )
  ]

  lake_z_reference <- if (
    length(lake_z_unique) > 0
  ) {
    median(
      lake_z_unique
    )
  } else {
    NA_real_
  }

  lake_low_summary_list[[i]] <- data.frame(

    lake_objectid =
      lid,

    lake_z_m =
      lake_z_reference,

    lowest_spill_level_m =
      min_spill,

    spill_raise_m =
      min_spill -
      lake_z_reference,

    n_low_edges =
      nrow(lx),

    n_low_source_cells =
      length(
        unique(
          lx$source_cell
        )
      ),

    n_low_groups =
      n_groups,

    stringsAsFactors = FALSE
  )


  low_edge_list[[i]] <- lx
}


# ------------------------------------------------------------
# 68. COMBINE TABLES
# ------------------------------------------------------------

low_shore_edges <- do.call(
  rbind,
  low_edge_list
)

row.names(
  low_shore_edges
) <- NULL


spill_group_summary <- do.call(
  rbind,
  group_summary_list
)

row.names(
  spill_group_summary
) <- NULL


lake_low_summary <- do.call(
  rbind,
  lake_low_summary_list
)

row.names(
  lake_low_summary
) <- NULL


# ------------------------------------------------------------
# 69. SAVE
# ------------------------------------------------------------

f_low_edges <- file.path(
  DIR_02,
  "02D_lowest_spill_shore_edges.csv"
)

write.csv(
  low_shore_edges,
  f_low_edges,
  row.names = FALSE
)


f_spill_groups <- file.path(
  DIR_02,
  "02D_lowest_spill_groups.csv"
)

write.csv(
  spill_group_summary,
  f_spill_groups,
  row.names = FALSE
)


f_lake_low_summary <- file.path(
  DIR_02,
  "02D_lowest_spill_lake_summary.csv"
)

write.csv(
  lake_low_summary,
  f_lake_low_summary,
  row.names = FALSE
)


# ------------------------------------------------------------
# 70. QA
# ------------------------------------------------------------

n_one_group <- sum(
  lake_low_summary$n_low_groups == 1
)

n_multi_group <- sum(
  lake_low_summary$n_low_groups > 1
)

n_groups_total <- nrow(
  spill_group_summary
)

n_groups_river <- sum(
  (
    spill_group_summary$n_river_area_edges +
      spill_group_summary$n_river_line_edges
  ) > 0
)

n_groups_other_lake <- sum(
  spill_group_summary$n_other_lake_edges > 0
)

n_groups_edge <- sum(
  spill_group_summary$touches_raster_edge
)

n_raised_low <- sum(
  lake_low_summary$spill_raise_m >
    1e-7,
  na.rm = TRUE
)

groups_q <- quantile(
  lake_low_summary$n_low_groups,
  probs = c(
    0,
    0.5,
    0.95,
    1
  ),
  names = FALSE
)

cells_q <- quantile(
  spill_group_summary$n_source_cells,
  probs = c(
    0,
    0.5,
    0.95,
    1
  ),
  names = FALSE
)


# ------------------------------------------------------------
# 71. PRINT
# ------------------------------------------------------------

cat("\n")
cat("=== 02D.2 LOWEST SPILL GROUPS ===\n")

cat(sprintf(
  "Lakes                    : %d\n",
  nrow(lake_low_summary)
))

cat(sprintf(
  "Lowest-spill groups      : %d\n",
  n_groups_total
))

cat(sprintf(
  "Lakes with 1 group       : %d\n",
  n_one_group
))

cat(sprintf(
  "Lakes with >1 groups     : %d\n",
  n_multi_group
))

cat(sprintf(
  "Groups touching river    : %d\n",
  n_groups_river
))

cat(sprintf(
  "Groups touching other lake: %d\n",
  n_groups_other_lake
))

cat(sprintf(
  "Groups touching edge     : %d\n",
  n_groups_edge
))

cat(sprintf(
  "Lakes requiring spill raise: %d\n",
  n_raised_low
))

cat(sprintf(
  "Groups/lake min/med/q95/max: %.0f / %.0f / %.0f / %.0f\n",
  groups_q[1],
  groups_q[2],
  groups_q[3],
  groups_q[4]
))

cat(sprintf(
  "Cells/group min/med/q95/max: %.0f / %.0f / %.0f / %.0f\n",
  cells_q[1],
  cells_q[2],
  cells_q[3],
  cells_q[4]
))

cat(sprintf(
  "Group CSV                : %s\n",
  basename(f_spill_groups)
))

cat("====================================\n")
# ============================================================
# 02D.2A - SPILL GROUP DIAGNOSTIC
#
# Tarkoitus:
# - erotellaan raised / non-raised lakes
# - tarkistetaan 50 vs 49 ristiriita
# - katsotaan missä 418 spill-ryhmää syntyvät
#
# EI muuteta routingia.
# ============================================================


# ------------------------------------------------------------
# 72. JOIN 02D.1 + 02D.2 SUMMARIES
# ------------------------------------------------------------

spill_diag <- merge(
  lake_low_summary,
  lake_outlet_summary,
  by = "lake_objectid",
  all = TRUE,
  sort = TRUE
)

stopifnot(
  nrow(spill_diag) == 108
)


# ------------------------------------------------------------
# 73. RAISED FLAGS
# ------------------------------------------------------------

tol_raise <- 1e-7

spill_diag$storage_raised <- (
  is.finite(
    spill_diag$max_storage_raise_m
  ) &
    spill_diag$max_storage_raise_m >
    tol_raise
)

spill_diag$spill_raised <- (
  is.finite(
    spill_diag$spill_raise_m
  ) &
    spill_diag$spill_raise_m >
    tol_raise
)

spill_diag$raise_mismatch <- (
  spill_diag$storage_raised !=
    spill_diag$spill_raised
)


# ------------------------------------------------------------
# 74. MULTI-GROUP FLAGS
# ------------------------------------------------------------

spill_diag$multi_group <- (
  spill_diag$n_low_groups > 1
)


# ------------------------------------------------------------
# 75. COUNTS BY RAISED STATUS
# ------------------------------------------------------------

n_storage_raised <- sum(
  spill_diag$storage_raised
)

n_spill_raised <- sum(
  spill_diag$spill_raised
)

n_mismatch <- sum(
  spill_diag$raise_mismatch
)

n_multi_raised <- sum(
  spill_diag$multi_group &
    spill_diag$spill_raised
)

n_multi_not_raised <- sum(
  spill_diag$multi_group &
    !spill_diag$spill_raised
)


# ------------------------------------------------------------
# 76. GROUP DISTRIBUTIONS
# ------------------------------------------------------------

groups_raised <- spill_diag$n_low_groups[
  spill_diag$spill_raised
]

groups_not_raised <- spill_diag$n_low_groups[
  !spill_diag$spill_raised
]

q_raised <- quantile(
  groups_raised,
  probs = c(
    0,
    0.5,
    0.95,
    1
  ),
  names = FALSE
)

q_not_raised <- quantile(
  groups_not_raised,
  probs = c(
    0,
    0.5,
    0.95,
    1
  ),
  names = FALSE
)


# ------------------------------------------------------------
# 77. MISMATCH TABLE
# ------------------------------------------------------------

mismatch_table <- spill_diag[
  spill_diag$raise_mismatch,
  c(
    "lake_objectid",
    "lake_z_m",
    "min_storage_raise_m",
    "max_storage_raise_m",
    "lowest_spill_level_m",
    "spill_raise_m",
    "n_low_groups",
    "n_low_edges",
    "n_land_edges",
    "n_river_area_edges",
    "n_river_line_edges",
    "n_other_lake_edges"
  ),
  drop = FALSE
]


# ------------------------------------------------------------
# 78. WORST MULTI-GROUP LAKES
# ------------------------------------------------------------

top_groups <- spill_diag[
  order(
    -spill_diag$n_low_groups,
    spill_diag$lake_objectid
  ),
  c(
    "lake_objectid",
    "storage_raised",
    "spill_raised",
    "spill_raise_m",
    "n_low_groups",
    "n_low_edges",
    "n_river_area_edges",
    "n_river_line_edges",
    "n_other_lake_edges"
  ),
  drop = FALSE
]

top_groups <- head(
  top_groups,
  15
)


# ------------------------------------------------------------
# 79. SAVE
# ------------------------------------------------------------

write.csv(
  spill_diag,
  file.path(
    DIR_02,
    "02D_spill_group_diagnostic.csv"
  ),
  row.names = FALSE
)

write.csv(
  mismatch_table,
  file.path(
    DIR_02,
    "02D_storage_vs_spill_raise_mismatch.csv"
  ),
  row.names = FALSE
)


# ------------------------------------------------------------
# 80. PRINT
# ------------------------------------------------------------

cat("\n")
cat("=== 02D.2A SPILL GROUP DIAGNOSTIC ===\n")

cat(sprintf(
  "Storage-raised lakes       : %d\n",
  n_storage_raised
))

cat(sprintf(
  "Spill-raised lakes         : %d\n",
  n_spill_raised
))

cat(sprintf(
  "Raise classification mismatch: %d\n",
  n_mismatch
))

cat(sprintf(
  "Multi-group raised lakes   : %d\n",
  n_multi_raised
))

cat(sprintf(
  "Multi-group non-raised     : %d\n",
  n_multi_not_raised
))

cat(sprintf(
  "Groups, raised min/med/q95/max    : %.0f / %.0f / %.0f / %.0f\n",
  q_raised[1],
  q_raised[2],
  q_raised[3],
  q_raised[4]
))

cat(sprintf(
  "Groups, non-raised min/med/q95/max: %.0f / %.0f / %.0f / %.0f\n",
  q_not_raised[1],
  q_not_raised[2],
  q_not_raised[3],
  q_not_raised[4]
))

cat("\n--- RAISE MISMATCH ---\n")

if (nrow(mismatch_table) == 0) {

  cat("NONE\n")

} else {

  print(
    mismatch_table,
    row.names = FALSE
  )
}

cat("\n--- TOP 15 BY NUMBER OF LOW GROUPS ---\n")

print(
  top_groups,
  row.names = FALSE
)

cat("========================================\n")

# ============================================================
# 02D.3 - LOW-SPILL TARGET EVIDENCE
#
# Luokittelee jokaisen alimman spill-tason ryhmän:
#
# LOWER_OTHER_LAKE
#   -> ryhmä koskettaa yhtä alempaa järveä
#
# RIVER_CONTACT
#   -> ryhmä koskettaa RANTA10-jokialuetta tai jokiviivaa
#
# MULTI_WATER_CONTACT
#   -> useita erilaisia suoria vesikohteita
#
# LAND_ONLY
#   -> ei suoraa vesikohdetta
#
# EDGE_CASE
#   -> koskettaa testirasterin reunaa
#
# EI vielä routing-muutoksia.
# ============================================================


# ------------------------------------------------------------
# 89. PARAMETERS
# ------------------------------------------------------------

water_drop_tol_m <- 1e-6


# ------------------------------------------------------------
# 90. PROCESS EACH SPILL GROUP
# ------------------------------------------------------------

group_ids <- sort(
  unique(
    low_shore_edges$spill_group_id
  )
)

target_evidence_list <- vector(
  "list",
  length(group_ids)
)


for (i in seq_along(group_ids)) {

  gid <- group_ids[i]

  gx <- low_shore_edges[
    low_shore_edges$spill_group_id == gid,
    ,
    drop = FALSE
  ]

  stopifnot(
    nrow(gx) > 0
  )

  lid <- unique(
    gx$lake_objectid
  )

  stopifnot(
    length(lid) == 1
  )


  # ----------------------------------------------------------
  # Direct river contacts
  # ----------------------------------------------------------

  n_river_area <- sum(
    gx$receiver_type ==
      "RIVER_AREA"
  )

  n_river_line <- sum(
    gx$receiver_type ==
      "RIVER_LINE"
  )

  has_river <- (
    n_river_area +
      n_river_line
  ) > 0


  # ----------------------------------------------------------
  # Direct OTHER_LAKE contacts
  # ----------------------------------------------------------

  ol <- gx[
    gx$receiver_type ==
      "OTHER_LAKE" &
      is.finite(
        gx$receiver_lake_objectid
      ),
    ,
    drop = FALSE
  ]

  lower_lake_ids <- integer(0)

  equal_lake_ids <- integer(0)

  higher_lake_ids <- integer(0)


  if (nrow(ol) > 0) {

    receiver_ids <- sort(
      unique(
        ol$receiver_lake_objectid
      )
    )

    for (rid in receiver_ids) {

      rx <- ol[
        ol$receiver_lake_objectid == rid,
        ,
        drop = FALSE
      ]

      dz <- median(
        rx$lake_z_m -
          rx$receiver_z_m,
        na.rm = TRUE
      )

      if (
        is.finite(dz) &&
        dz > water_drop_tol_m
      ) {

        lower_lake_ids <- c(
          lower_lake_ids,
          rid
        )

      } else if (
        is.finite(dz) &&
        abs(dz) <= water_drop_tol_m
      ) {

        equal_lake_ids <- c(
          equal_lake_ids,
          rid
        )

      } else {

        higher_lake_ids <- c(
          higher_lake_ids,
          rid
        )
      }
    }
  }


  lower_lake_ids <- sort(
    unique(
      lower_lake_ids
    )
  )

  equal_lake_ids <- sort(
    unique(
      equal_lake_ids
    )
  )

  higher_lake_ids <- sort(
    unique(
      higher_lake_ids
    )
  )


  # ----------------------------------------------------------
  # Classification
  # ----------------------------------------------------------

  edge_case <- any(
    gx$source_raster_edge |
      gx$receiver_raster_edge
  )

  n_lower <- length(
    lower_lake_ids
  )

  if (edge_case) {

    evidence_class <- "EDGE_CASE"

  } else if (
    n_lower == 1 &&
    !has_river
  ) {

    evidence_class <- "LOWER_OTHER_LAKE"

  } else if (
    n_lower == 0 &&
    has_river
  ) {

    evidence_class <- "RIVER_CONTACT"

  } else if (
    n_lower > 0 &&
    has_river
  ) {

    evidence_class <- "MULTI_WATER_CONTACT"

  } else if (
    n_lower > 1
  ) {

    evidence_class <- "MULTI_WATER_CONTACT"

  } else {

    evidence_class <- "LAND_ONLY"
  }


  # ----------------------------------------------------------
  # Summary
  # ----------------------------------------------------------

  target_evidence_list[[i]] <- data.frame(

    spill_group_id =
      gid,

    lake_objectid =
      lid,

    n_edges =
      nrow(gx),

    n_source_cells =
      length(
        unique(
          gx$source_cell
        )
      ),

    n_land_edges =
      sum(
        gx$receiver_type ==
          "LAND"
      ),

    n_river_area_edges =
      n_river_area,

    n_river_line_edges =
      n_river_line,

    n_other_lake_edges =
      nrow(ol),

    n_lower_lakes =
      length(
        lower_lake_ids
      ),

    lower_lake_objectids =
      if (
        length(lower_lake_ids) == 0
      ) {
        ""
      } else {
        paste(
          lower_lake_ids,
          collapse = ";"
        )
      },

    equal_lake_objectids =
      if (
        length(equal_lake_ids) == 0
      ) {
        ""
      } else {
        paste(
          equal_lake_ids,
          collapse = ";"
        )
      },

    higher_lake_objectids =
      if (
        length(higher_lake_ids) == 0
      ) {
        ""
      } else {
        paste(
          higher_lake_ids,
          collapse = ";"
        )
      },

    spill_level_m =
      unique(
        gx$storage_step_level_m
      )[1],

    evidence_class =
      evidence_class,

    stringsAsFactors = FALSE
  )
}


# ------------------------------------------------------------
# 91. COMBINE
# ------------------------------------------------------------

target_evidence <- do.call(
  rbind,
  target_evidence_list
)

row.names(
  target_evidence
) <- NULL

target_evidence <- target_evidence[
  order(
    target_evidence$lake_objectid,
    target_evidence$spill_group_id
  ),
  ,
  drop = FALSE
]


# ------------------------------------------------------------
# 92. SAVE
# ------------------------------------------------------------

f_target_evidence <- file.path(
  DIR_02,
  "02D_low_spill_target_evidence.csv"
)

write.csv(
  target_evidence,
  f_target_evidence,
  row.names = FALSE
)


# ------------------------------------------------------------
# 93. DIRECT LAKE -> LAKE LINKS
# ------------------------------------------------------------

direct_lake_links <- target_evidence[
  target_evidence$evidence_class ==
    "LOWER_OTHER_LAKE",
  c(
    "spill_group_id",
    "lake_objectid",
    "lower_lake_objectids",
    "n_other_lake_edges",
    "spill_level_m"
  ),
  drop = FALSE
]

write.csv(
  direct_lake_links,
  file.path(
    DIR_02,
    "02D_direct_lower_lake_links.csv"
  ),
  row.names = FALSE
)


# ------------------------------------------------------------
# 94. QA COUNTS
# ------------------------------------------------------------

n_lower_lake <- sum(
  target_evidence$evidence_class ==
    "LOWER_OTHER_LAKE"
)

n_river <- sum(
  target_evidence$evidence_class ==
    "RIVER_CONTACT"
)

n_multi_water <- sum(
  target_evidence$evidence_class ==
    "MULTI_WATER_CONTACT"
)

n_land_only <- sum(
  target_evidence$evidence_class ==
    "LAND_ONLY"
)

n_edge <- sum(
  target_evidence$evidence_class ==
    "EDGE_CASE"
)


# ------------------------------------------------------------
# 95. LAKES WITH DIRECT WATER EVIDENCE
# ------------------------------------------------------------

has_direct_water <- target_evidence$evidence_class %in%
  c(
    "LOWER_OTHER_LAKE",
    "RIVER_CONTACT",
    "MULTI_WATER_CONTACT"
  )

n_lakes_direct_water <- length(
  unique(
    target_evidence$lake_objectid[
      has_direct_water
    ]
  )
)

n_lakes_land_only <- length(
  setdiff(
    unique(
      target_evidence$lake_objectid
    ),
    unique(
      target_evidence$lake_objectid[
        has_direct_water
      ]
    )
  )
)


# ------------------------------------------------------------
# 96. PRINT
# ------------------------------------------------------------

cat("\n")
cat("=== 02D.3 LOW-SPILL TARGET EVIDENCE ===\n")

cat(sprintf(
  "Groups total             : %d\n",
  nrow(target_evidence)
))

cat(sprintf(
  "LOWER_OTHER_LAKE         : %d\n",
  n_lower_lake
))

cat(sprintf(
  "RIVER_CONTACT            : %d\n",
  n_river
))

cat(sprintf(
  "MULTI_WATER_CONTACT      : %d\n",
  n_multi_water
))

cat(sprintf(
  "LAND_ONLY                : %d\n",
  n_land_only
))

cat(sprintf(
  "EDGE_CASE                : %d\n",
  n_edge
))

cat(sprintf(
  "Lakes with direct water evidence: %d / %d\n",
  n_lakes_direct_water,
  length(
    unique(
      target_evidence$lake_objectid
    )
  )
))

cat(sprintf(
  "Lakes with only LAND_ONLY groups : %d\n",
  n_lakes_land_only
))

cat("\n--- DIRECT LOWER-LAKE LINKS ---\n")

if (nrow(direct_lake_links) == 0) {

  cat("NONE\n")

} else {

  print(
    direct_lake_links,
    row.names = FALSE
  )
}

cat("=========================================\n")

# ============================================================
# 02D.4 - RAISED DEPRESSION COMPONENTS
#
# WATER_STORAGE - LAND_WATER > tolerance
#       ↓
# connected raised components
#
# Tarkoitus:
# - tunnistaa FillDepressionsin oikeasti nostamat alueet
# - selvittää mihin komponentteihin järvet kuuluvat
# - tarkistaa spill-raised järvien rakenne
#
# EI outlet-valintaa.
# EI D8-muutoksia.
# ============================================================


# ------------------------------------------------------------
# 97. PARAMETERS
# ------------------------------------------------------------

depression_raise_tol_m <- 1e-7


# ------------------------------------------------------------
# 98. OUTPUT
# ------------------------------------------------------------

f_depression_components <- file.path(
  DIR_02,
  "02D_raised_depression_components.tif"
)


# ------------------------------------------------------------
# 99. BUILD RAISED-CELL COMPONENTS
# ------------------------------------------------------------

if (
  !file.exists(f_depression_components) ||
  OVERWRITE
) {

  cat(
    "\n02D.4: building raised depression components...\n"
  )

  storage_delta <- (
    surface_storage -
      surface_land_water
  )

  raised_mask <- terra::ifel(
    storage_delta >
      depression_raise_tol_m,
    1,
    NA
  )

  depression_components <- terra::patches(
    raised_mask,
    directions = 8
  )

  writeRaster(
    depression_components,
    f_depression_components,
    overwrite = TRUE,
    datatype = "INT4S",
    gdal = c(
      "COMPRESS=DEFLATE",
      "BIGTIFF=YES"
    )
  )

  rm(
    storage_delta,
    raised_mask
  )

  gc()

} else {

  depression_components <- rast(
    f_depression_components
  )
}


# Make sure raster geometry is correct.

stopifnot(
  compareGeom(
    depression_components,
    lake_id,
    stopOnError = FALSE
  )
)


# ------------------------------------------------------------
# 100. DEPRESSION COMPONENT ON EVERY LAKE CELL
# ------------------------------------------------------------

lake_cells_dep <- lake_cells_02d

lake_id_dep <- as.integer(
  cell_values(
    lake_id,
    lake_cells_dep
  )
)

depression_id_on_lake <- cell_values(
  depression_components,
  lake_cells_dep
)

stopifnot(
  length(lake_cells_dep) ==
    length(depression_id_on_lake)
)


# ------------------------------------------------------------
# 101. PER-LAKE DEPRESSION MEMBERSHIP
# ------------------------------------------------------------

lake_ids_dep <- sort(
  unique(
    lake_id_dep
  )
)

lake_dep_list <- vector(
  "list",
  length(lake_ids_dep)
)


for (i in seq_along(lake_ids_dep)) {

  lid <- lake_ids_dep[i]

  ii <- which(
    lake_id_dep == lid
  )

  dep <- depression_id_on_lake[
    ii
  ]

  dep_ids <- sort(
    unique(
      dep[
        is.finite(dep)
      ]
    )
  )

  n_total <- length(ii)

  n_raised <- sum(
    is.finite(dep)
  )

  lake_dep_list[[i]] <- data.frame(

    lake_objectid =
      lid,

    n_lake_cells =
      n_total,

    n_raised_lake_cells =
      n_raised,

    raised_fraction =
      n_raised /
      n_total,

    n_depression_components =
      length(dep_ids),

    depression_component_ids =
      if (
        length(dep_ids) == 0
      ) {
        ""
      } else {
        paste(
          dep_ids,
          collapse = ";"
        )
      },

    stringsAsFactors = FALSE
  )
}


lake_depression_summary <- do.call(
  rbind,
  lake_dep_list
)

row.names(
  lake_depression_summary
) <- NULL


# ------------------------------------------------------------
# 102. JOIN WITH PREVIOUS SPILL DIAGNOSTIC
# ------------------------------------------------------------

lake_depression_summary <- merge(
  lake_depression_summary,
  spill_diag[
    ,
    c(
      "lake_objectid",
      "storage_raised",
      "spill_raised",
      "spill_raise_m",
      "max_storage_raise_m",
      "n_low_groups"
    )
  ],
  by = "lake_objectid",
  all.x = TRUE,
  sort = TRUE
)

stopifnot(
  nrow(lake_depression_summary) == 108
)


# ------------------------------------------------------------
# 103. CLASSIFY
# ------------------------------------------------------------

lake_depression_summary$depression_status <-
  "NO_RAISED_COMPONENT"


# Spill-raised lake and exactly one connected raised component.

lake_depression_summary$depression_status[
  lake_depression_summary$spill_raised &
    lake_depression_summary$n_depression_components == 1
] <- "SPILL_RAISED_ONE_COMPONENT"


# Spill-raised but multiple components.

lake_depression_summary$depression_status[
  lake_depression_summary$spill_raised &
    lake_depression_summary$n_depression_components > 1
] <- "SPILL_RAISED_MULTI_COMPONENT"


# Spill-raised but no raised lake cell:
# this would be suspicious.

lake_depression_summary$depression_status[
  lake_depression_summary$spill_raised &
    lake_depression_summary$n_depression_components == 0
] <- "SPILL_RAISED_NO_COMPONENT"


# Not spill-raised, but some lake cells nevertheless raised.
# 111137 is expected to be here.

lake_depression_summary$depression_status[
  !lake_depression_summary$spill_raised &
    lake_depression_summary$n_raised_lake_cells > 0
] <- "PARTIAL_RAISE_NO_SPILL_RAISE"


# ------------------------------------------------------------
# 104. SAVE
# ------------------------------------------------------------

f_lake_dep_summary <- file.path(
  DIR_02,
  "02D_lake_depression_component_summary.csv"
)

write.csv(
  lake_depression_summary,
  f_lake_dep_summary,
  row.names = FALSE
)


# ------------------------------------------------------------
# 105. EXCEPTIONS
# ------------------------------------------------------------

dep_exception <- lake_depression_summary[
  lake_depression_summary$depression_status %in%
    c(
      "SPILL_RAISED_MULTI_COMPONENT",
      "SPILL_RAISED_NO_COMPONENT",
      "PARTIAL_RAISE_NO_SPILL_RAISE"
    ),
  ,
  drop = FALSE
]

write.csv(
  dep_exception,
  file.path(
    DIR_02,
    "02D_depression_component_exceptions.csv"
  ),
  row.names = FALSE
)


# ------------------------------------------------------------
# 106. COUNTS
# ------------------------------------------------------------

n_one_dep <- sum(
  lake_depression_summary$depression_status ==
    "SPILL_RAISED_ONE_COMPONENT"
)

n_multi_dep <- sum(
  lake_depression_summary$depression_status ==
    "SPILL_RAISED_MULTI_COMPONENT"
)

n_missing_dep <- sum(
  lake_depression_summary$depression_status ==
    "SPILL_RAISED_NO_COMPONENT"
)

n_partial_dep <- sum(
  lake_depression_summary$depression_status ==
    "PARTIAL_RAISE_NO_SPILL_RAISE"
)

n_no_dep <- sum(
  lake_depression_summary$depression_status ==
    "NO_RAISED_COMPONENT"
)


# ------------------------------------------------------------
# 107. PRINT
# ------------------------------------------------------------

cat("\n")
cat("=== 02D.4 RAISED DEPRESSION COMPONENTS ===\n")

cat(sprintf(
  "Lakes total                    : %d\n",
  nrow(lake_depression_summary)
))

cat(sprintf(
  "Spill-raised, one component    : %d\n",
  n_one_dep
))

cat(sprintf(
  "Spill-raised, multi-component  : %d\n",
  n_multi_dep
))

cat(sprintf(
  "Spill-raised, no component     : %d\n",
  n_missing_dep
))

cat(sprintf(
  "Partial raise, no spill raise  : %d\n",
  n_partial_dep
))

cat(sprintf(
  "No raised component            : %d\n",
  n_no_dep
))

cat("\n--- EXCEPTIONS ---\n")

if (nrow(dep_exception) == 0) {

  cat("NONE\n")

} else {

  print(
    dep_exception[
      ,
      c(
        "lake_objectid",
        "n_lake_cells",
        "n_raised_lake_cells",
        "raised_fraction",
        "n_depression_components",
        "depression_component_ids",
        "spill_raise_m",
        "max_storage_raise_m",
        "n_low_groups",
        "depression_status"
      )
    ],
    row.names = FALSE
  )
}

cat("============================================\n")

# ============================================================
# 02D.5 - DEPRESSION SPILL-GATE INVENTORY
#
# Jokaiselle spill-raised depression komponentille:
#
#   raised component
#        ↓
#   kaikki component -> outside boundary edges
#        ↓
#   edge crossing level =
#       max(storage_source, storage_receiver)
#        ↓
#   minimum crossing level
#        ↓
#   kaikki siihen kuuluvat gate edges
#        ↓
#   fyysisesti yhtenäiset gate groups
#
# EI vielä outlet-valintaa.
# EI D8-muutoksia.
# ============================================================


# ------------------------------------------------------------
# 108. PARAMETERS
# ------------------------------------------------------------

gate_level_tol_m <- 1e-6


# ------------------------------------------------------------
# 109. SPILL-RAISED LAKES -> DEPRESSION COMPONENT
# ------------------------------------------------------------

spill_lakes <- lake_depression_summary[
  lake_depression_summary$spill_raised,
  ,
  drop = FALSE
]

stopifnot(
  nrow(spill_lakes) == 49,
  all(
    spill_lakes$n_depression_components == 1
  )
)

spill_lakes$depression_component_id <-
  as.integer(
    spill_lakes$depression_component_ids
  )

stopifnot(
  all(
    is.finite(
      spill_lakes$depression_component_id
    )
  )
)


# ------------------------------------------------------------
# 110. TARGET DEPRESSION COMPONENTS
# ------------------------------------------------------------

target_dep_ids <- sort(
  unique(
    spill_lakes$depression_component_id
  )
)


# ------------------------------------------------------------
# 111. ALL RAISED CELLS + COMPONENT IDS
#
# One table is much cheaper than repeatedly scanning
# the complete 6000 x 6000 raster.
# ------------------------------------------------------------

dep_tab <- as.data.frame(
  depression_components,
  cells = TRUE,
  na.rm = TRUE
)

stopifnot(
  ncol(dep_tab) == 2
)

names(dep_tab)[2] <-
  "depression_component_id"

dep_tab$depression_component_id <-
  as.integer(
    dep_tab$depression_component_id
  )

dep_tab <- dep_tab[
  dep_tab$depression_component_id %in%
    target_dep_ids,
  ,
  drop = FALSE
]

stopifnot(
  all(
    target_dep_ids %in%
      unique(
        dep_tab$depression_component_id
      )
  )
)


# ------------------------------------------------------------
# 112. OUTPUT HOLDERS
# ------------------------------------------------------------

dep_gate_edges_list <- vector(
  "list",
  length(target_dep_ids)
)

dep_component_summary_list <- vector(
  "list",
  length(target_dep_ids)
)

dep_gate_group_list <- list()

global_gate_group_id <- 0L


# ------------------------------------------------------------
# 113. PROCESS EACH DEPRESSION COMPONENT
# ------------------------------------------------------------

for (i in seq_along(target_dep_ids)) {

  did <- target_dep_ids[i]

  cat(sprintf(
    "\r02D.5 depression %d / %d",
    i,
    length(target_dep_ids)
  ))

  comp_cells <- dep_tab$cell[
    dep_tab$depression_component_id == did
  ]

  stopifnot(
    length(comp_cells) > 0
  )


  # ----------------------------------------------------------
  # 113A. MEMBER LAKES
  # ----------------------------------------------------------

  member_rows <- spill_lakes[
    spill_lakes$depression_component_id == did,
    ,
    drop = FALSE
  ]

  member_lakes <- sort(
    unique(
      member_rows$lake_objectid
    )
  )

  expected_spill <- lake_low_summary$lowest_spill_level_m[
    match(
      member_lakes,
      lake_low_summary$lake_objectid
    )
  ]

  stopifnot(
    all(
      is.finite(
        expected_spill
      )
    )
  )


  # ----------------------------------------------------------
  # 113B. ALL 8-NEIGHBOUR EDGES FROM COMPONENT CELLS
  # ----------------------------------------------------------

  ap <- terra::adjacent(
    depression_components,
    cells = comp_cells,
    directions = 8,
    pairs = TRUE,
    include = FALSE
  )

  stopifnot(
    nrow(ap) > 0
  )


  # ----------------------------------------------------------
  # 113C. KEEP ONLY COMPONENT -> OUTSIDE EDGES
  # ----------------------------------------------------------

  receiver_dep <- cell_values(
    depression_components,
    ap[, 2]
  )

  outside <- (
    !is.finite(receiver_dep) |
      receiver_dep != did
  )

  boundary <- ap[
    outside,
    ,
    drop = FALSE
  ]

  receiver_dep_boundary <- receiver_dep[
    outside
  ]

  stopifnot(
    nrow(boundary) > 0
  )


  # Adjacent raised components should not normally occur,
  # because 8-neighbour raised cells should belong to
  # the same patch.

  n_other_dep_neighbors <- sum(
    is.finite(
      receiver_dep_boundary
    ) &
      receiver_dep_boundary != did
  )


  # ----------------------------------------------------------
  # 113D. SURFACE ELEVATIONS
  # ----------------------------------------------------------

  source_storage_z <- cell_values(
    surface_storage,
    boundary[, 1]
  )

  receiver_storage_z <- cell_values(
    surface_storage,
    boundary[, 2]
  )

  source_original_z <- cell_values(
    surface_land_water,
    boundary[, 1]
  )

  receiver_original_z <- cell_values(
    surface_land_water,
    boundary[, 2]
  )

  stopifnot(
    all(
      is.finite(
        source_storage_z
      )
    ),
    all(
      is.finite(
        receiver_storage_z
      )
    )
  )


  # ----------------------------------------------------------
  # 113E. CROSSING LEVEL
  #
  # D8 edge can cross only when both sides are at or below
  # this level.
  # ----------------------------------------------------------

  edge_crossing_level <- pmax(
    source_storage_z,
    receiver_storage_z
  )

  min_gate_level <- min(
    edge_crossing_level,
    na.rm = TRUE
  )

  is_min_gate <- abs(
    edge_crossing_level -
      min_gate_level
  ) <= gate_level_tol_m


  gate_boundary <- boundary[
    is_min_gate,
    ,
    drop = FALSE
  ]

  stopifnot(
    nrow(gate_boundary) > 0
  )


  # ----------------------------------------------------------
  # 113F. RECEIVER WATER TYPE
  # ----------------------------------------------------------

  gate_receiver_class <- cell_values(
    water_class,
    gate_boundary[, 2]
  )

  gate_receiver_lake <- cell_values(
    lake_id,
    gate_boundary[, 2]
  )

  gate_receiver_type <- rep(
    "LAND",
    nrow(gate_boundary)
  )

  gate_receiver_type[
    gate_receiver_class == 1
  ] <- "LAKE"

  gate_receiver_type[
    gate_receiver_class == 2
  ] <- "RIVER_AREA"

  gate_receiver_type[
    gate_receiver_class == 3
  ] <- "RIVER_LINE"


  # ----------------------------------------------------------
  # 113G. GATE COORDINATES + ELEVATIONS
  # ----------------------------------------------------------

  gate_source_storage <- source_storage_z[
    is_min_gate
  ]

  gate_receiver_storage <- receiver_storage_z[
    is_min_gate
  ]

  gate_source_original <- source_original_z[
    is_min_gate
  ]

  gate_receiver_original <- receiver_original_z[
    is_min_gate
  ]

  gate_source_xy <- xyFromCell(
    depression_components,
    gate_boundary[, 1]
  )

  gate_receiver_xy <- xyFromCell(
    depression_components,
    gate_boundary[, 2]
  )


  # ----------------------------------------------------------
  # 113H. GROUP GATE SOURCE CELLS
  # ----------------------------------------------------------

  gate_source_cells <- sort(
    unique(
      gate_boundary[, 1]
    )
  )

  gate_comp <- make_components(
    gate_source_cells,
    depression_components
  )

  gate_local_group <- unname(
    gate_comp[
      as.character(
        gate_boundary[, 1]
      )
    ]
  )

  stopifnot(
    all(
      is.finite(
        gate_local_group
      )
    )
  )

  n_gate_groups <- max(
    gate_local_group
  )


  # ----------------------------------------------------------
  # 113I. GLOBAL GATE GROUP IDS
  # ----------------------------------------------------------

  local_to_global <- integer(
    n_gate_groups
  )

  for (g in seq_len(n_gate_groups)) {

    global_gate_group_id <-
      global_gate_group_id + 1L

    local_to_global[g] <-
      global_gate_group_id
  }

  gate_global_group <-
    local_to_global[
      gate_local_group
    ]


  # ----------------------------------------------------------
  # 113J. GATE EDGE TABLE
  # ----------------------------------------------------------

  gate_edges <- data.frame(

    depression_component_id =
      did,

    gate_group_id =
      gate_global_group,

    gate_local_group =
      gate_local_group,

    source_cell =
      gate_boundary[, 1],

    source_x =
      gate_source_xy[, 1],

    source_y =
      gate_source_xy[, 2],

    receiver_cell =
      gate_boundary[, 2],

    receiver_x =
      gate_receiver_xy[, 1],

    receiver_y =
      gate_receiver_xy[, 2],

    receiver_type =
      gate_receiver_type,

    receiver_water_class =
      as.integer(
        gate_receiver_class
      ),

    receiver_lake_objectid =
      as.integer(
        gate_receiver_lake
      ),

    source_original_z_m =
      gate_source_original,

    receiver_original_z_m =
      gate_receiver_original,

    source_storage_z_m =
      gate_source_storage,

    receiver_storage_z_m =
      gate_receiver_storage,

    edge_crossing_level_m =
      pmax(
        gate_source_storage,
        gate_receiver_storage
      ),

    storage_drop_m =
      gate_source_storage -
      gate_receiver_storage,

    stringsAsFactors = FALSE
  )

  dep_gate_edges_list[[i]] <-
    gate_edges


  # ----------------------------------------------------------
  # 113K. GATE GROUP SUMMARIES
  # ----------------------------------------------------------

  for (g in seq_len(n_gate_groups)) {

    gx <- gate_edges[
      gate_edges$gate_local_group == g,
      ,
      drop = FALSE
    ]

    receiver_lakes <- sort(
      unique(
        gx$receiver_lake_objectid[
          is.finite(
            gx$receiver_lake_objectid
          )
        ]
      )
    )

    source_edge_flag <- is_edge_cell(
      depression_components,
      gx$source_cell
    )

    receiver_edge_flag <- is_edge_cell(
      depression_components,
      gx$receiver_cell
    )

    dep_gate_group_list[[
      length(dep_gate_group_list) + 1L
    ]] <- data.frame(

      gate_group_id =
        unique(
          gx$gate_group_id
        ),

      depression_component_id =
        did,

      member_lakes =
        paste(
          member_lakes,
          collapse = ";"
        ),

      n_member_lakes =
        length(
          member_lakes
        ),

      n_gate_source_cells =
        length(
          unique(
            gx$source_cell
          )
        ),

      n_gate_receiver_cells =
        length(
          unique(
            gx$receiver_cell
          )
        ),

      n_gate_edges =
        nrow(gx),

      n_land_edges =
        sum(
          gx$receiver_type ==
            "LAND"
        ),

      n_river_area_edges =
        sum(
          gx$receiver_type ==
            "RIVER_AREA"
        ),

      n_river_line_edges =
        sum(
          gx$receiver_type ==
            "RIVER_LINE"
        ),

      n_lake_edges =
        sum(
          gx$receiver_type ==
            "LAKE"
        ),

      receiver_lake_objectids =
        if (
          length(receiver_lakes) == 0
        ) {
          ""
        } else {
          paste(
            receiver_lakes,
            collapse = ";"
          )
        },

      gate_level_m =
        min_gate_level,

      min_storage_drop_m =
        min(
          gx$storage_drop_m,
          na.rm = TRUE
        ),

      max_storage_drop_m =
        max(
          gx$storage_drop_m,
          na.rm = TRUE
        ),

      touches_raster_edge =
        any(
          source_edge_flag |
            receiver_edge_flag
        ),

      stringsAsFactors = FALSE
    )
  }


  # ----------------------------------------------------------
  # 113L. FILLED SURFACE RANGE INSIDE COMPONENT
  # ----------------------------------------------------------

  comp_storage_z <- cell_values(
    surface_storage,
    comp_cells
  )

  comp_storage_min <- min(
    comp_storage_z,
    na.rm = TRUE
  )

  comp_storage_max <- max(
    comp_storage_z,
    na.rm = TRUE
  )

  comp_storage_range <-
    comp_storage_max -
    comp_storage_min


  # ----------------------------------------------------------
  # 113M. COMPONENT SUMMARY
  # ----------------------------------------------------------

  expected_min <- min(
    expected_spill
  )

  expected_max <- max(
    expected_spill
  )

  dep_component_summary_list[[i]] <-
    data.frame(

      depression_component_id =
        did,

      n_component_cells =
        length(
          comp_cells
        ),

      n_member_lakes =
        length(
          member_lakes
        ),

      member_lakes =
        paste(
          member_lakes,
          collapse = ";"
        ),

      n_boundary_edges =
        nrow(boundary),

      n_other_depression_neighbors =
        n_other_dep_neighbors,

      component_storage_min_m =
        comp_storage_min,

      component_storage_max_m =
        comp_storage_max,

      component_storage_range_m =
        comp_storage_range,

      expected_lake_spill_min_m =
        expected_min,

      expected_lake_spill_max_m =
        expected_max,

      depression_gate_level_m =
        min_gate_level,

      gate_minus_expected_min_m =
        min_gate_level -
        expected_min,

      gate_minus_expected_max_m =
        min_gate_level -
        expected_max,

      n_min_gate_edges =
        nrow(gate_boundary),

      n_min_gate_source_cells =
        length(
          gate_source_cells
        ),

      n_gate_groups =
        n_gate_groups,

      stringsAsFactors = FALSE
    )
}

cat("\n")


# ------------------------------------------------------------
# 114. COMBINE RESULTS
# ------------------------------------------------------------

depression_gate_edges <- do.call(
  rbind,
  dep_gate_edges_list
)

row.names(
  depression_gate_edges
) <- NULL


depression_gate_groups <- do.call(
  rbind,
  dep_gate_group_list
)

row.names(
  depression_gate_groups
) <- NULL


dep_gate_component_summary <- do.call(
  rbind,
  dep_component_summary_list
)

row.names(
  dep_gate_component_summary
) <- NULL


# ------------------------------------------------------------
# 115. SAVE
# ------------------------------------------------------------

write.csv(
  depression_gate_edges,
  file.path(
    DIR_02,
    "02D_depression_min_gate_edges.csv"
  ),
  row.names = FALSE
)

write.csv(
  depression_gate_groups,
  file.path(
    DIR_02,
    "02D_depression_gate_groups.csv"
  ),
  row.names = FALSE
)

write.csv(
  dep_gate_component_summary,
  file.path(
    DIR_02,
    "02D_depression_gate_component_summary.csv"
  ),
  row.names = FALSE
)


# ------------------------------------------------------------
# 116. QA COUNTS
# ------------------------------------------------------------

n_unique_dep <- nrow(
  dep_gate_component_summary
)

n_shared_dep <- sum(
  dep_gate_component_summary$n_member_lakes > 1
)

n_one_gate <- sum(
  dep_gate_component_summary$n_gate_groups == 1
)

n_multi_gate <- sum(
  dep_gate_component_summary$n_gate_groups > 1
)

n_gate_groups_total <- nrow(
  depression_gate_groups
)

n_gate_river <- sum(
  (
    depression_gate_groups$n_river_area_edges +
      depression_gate_groups$n_river_line_edges
  ) > 0
)

n_gate_lake <- sum(
  depression_gate_groups$n_lake_edges > 0
)

n_gate_edge <- sum(
  depression_gate_groups$touches_raster_edge
)

max_gate_spill_diff <- max(
  abs(
    dep_gate_component_summary$
      gate_minus_expected_min_m
  ),
  na.rm = TRUE
)

max_component_storage_range <- max(
  dep_gate_component_summary$
    component_storage_range_m,
  na.rm = TRUE
)


# ------------------------------------------------------------
# 117. EXCEPTION / REVIEW TABLE
# ------------------------------------------------------------

gate_review <- dep_gate_component_summary[
  dep_gate_component_summary$n_member_lakes > 1 |
    dep_gate_component_summary$n_gate_groups > 1 |
    dep_gate_component_summary$
      n_other_depression_neighbors > 0 |
    abs(
      dep_gate_component_summary$
        gate_minus_expected_min_m
    ) > 1e-5,
  ,
  drop = FALSE
]

gate_review <- gate_review[
  order(
    -gate_review$n_gate_groups,
    gate_review$depression_component_id
  ),
  ,
  drop = FALSE
]

write.csv(
  gate_review,
  file.path(
    DIR_02,
    "02D_depression_gate_review.csv"
  ),
  row.names = FALSE
)


# ------------------------------------------------------------
# 118. PRINT
# ------------------------------------------------------------

cat("\n")
cat("=== 02D.5 DEPRESSION SPILL GATES ===\n")

cat(sprintf(
  "Spill-raised lakes           : %d\n",
  nrow(spill_lakes)
))

cat(sprintf(
  "Unique depression components : %d\n",
  n_unique_dep
))

cat(sprintf(
  "Components shared by >1 lake : %d\n",
  n_shared_dep
))

cat(sprintf(
  "Depressions with 1 gate group: %d\n",
  n_one_gate
))

cat(sprintf(
  "Depressions with >1 groups   : %d\n",
  n_multi_gate
))

cat(sprintf(
  "Gate groups total            : %d\n",
  n_gate_groups_total
))

cat(sprintf(
  "Gate groups touching river   : %d\n",
  n_gate_river
))

cat(sprintf(
  "Gate groups touching lake    : %d\n",
  n_gate_lake
))

cat(sprintf(
  "Gate groups touching edge    : %d\n",
  n_gate_edge
))

cat(sprintf(
  "Max |gate - lake spill|      : %.9f m\n",
  max_gate_spill_diff
))

cat(sprintf(
  "Max storage range/component  : %.9f m\n",
  max_component_storage_range
))

cat(sprintf(
  "Components requiring review  : %d\n",
  nrow(gate_review)
))

cat("\n--- GATE REVIEW (first 20) ---\n")

if (nrow(gate_review) == 0) {

  cat("NONE\n")

} else {

  print(
    head(
      gate_review[
        ,
        c(
          "depression_component_id",
          "n_component_cells",
          "n_member_lakes",
          "member_lakes",
          "component_storage_range_m",
          "expected_lake_spill_min_m",
          "depression_gate_level_m",
          "gate_minus_expected_min_m",
          "n_min_gate_edges",
          "n_min_gate_source_cells",
          "n_gate_groups"
        )
      ],
      20
    ),
    row.names = FALSE
  )
}

cat("========================================\n")

# ============================================================
# 02D.5A - GATE ESCAPE EVIDENCE
#
# Selvittää min-gate-reunojen jälkeen:
#
# LOWER
#   receiver on jo spill-tason alapuolella
#
# LEVEL
#   receiver on samalla korkeudella -> flat pitää jäljittää
#
# ABOVE
#   ei pitäisi esiintyä minimum-gatessa
#
# Lisäksi tarkistetaan vastaanottavan solun nykyinen D8-pointer.
#
# EI routing-muutoksia.
# ============================================================


# ------------------------------------------------------------
# 119. PARAMETERS
# ------------------------------------------------------------

escape_tol_m <- 1e-6

valid_pointer_codes <- c(
  1, 2, 4, 8,
  16, 32, 64, 128
)


# ------------------------------------------------------------
# 120. RECEIVER RELATION TO GATE LEVEL
# ------------------------------------------------------------

gate_escape <- depression_gate_edges

gate_escape$receiver_below_gate_m <-
  gate_escape$edge_crossing_level_m -
  gate_escape$receiver_original_z_m


gate_escape$receiver_relation <- "LEVEL"

gate_escape$receiver_relation[
  gate_escape$receiver_original_z_m <
    gate_escape$edge_crossing_level_m -
    escape_tol_m
] <- "LOWER"

gate_escape$receiver_relation[
  gate_escape$receiver_original_z_m >
    gate_escape$edge_crossing_level_m +
    escape_tol_m
] <- "ABOVE"


# ------------------------------------------------------------
# 121. D8 POINTER ON RECEIVER CELL
# ------------------------------------------------------------

receiver_pointer <- cell_values(
  ptr_land_water,
  gate_escape$receiver_cell
)

gate_escape$receiver_pointer <-
  receiver_pointer

gate_escape$receiver_pointer_status <-
  "OTHER"

gate_escape$receiver_pointer_status[
  !is.finite(receiver_pointer)
] <- "NA"

gate_escape$receiver_pointer_status[
  receiver_pointer == 0
] <- "ZERO"

gate_escape$receiver_pointer_status[
  receiver_pointer %in%
    valid_pointer_codes
] <- "VALID"


# ------------------------------------------------------------
# 122. SAVE EDGE DETAIL
# ------------------------------------------------------------

write.csv(
  gate_escape,
  file.path(
    DIR_02,
    "02D_gate_escape_edge_diagnostic.csv"
  ),
  row.names = FALSE
)


# ------------------------------------------------------------
# 123. SUMMARIZE EACH GATE GROUP
# ------------------------------------------------------------

gid <- sort(
  unique(
    gate_escape$gate_group_id
  )
)

gate_escape_group_list <- vector(
  "list",
  length(gid)
)


for (i in seq_along(gid)) {

  g <- gid[i]

  x <- gate_escape[
    gate_escape$gate_group_id == g,
    ,
    drop = FALSE
  ]

  stopifnot(
    nrow(x) > 0
  )

  n_lower <- sum(
    x$receiver_relation == "LOWER"
  )

  n_level <- sum(
    x$receiver_relation == "LEVEL"
  )

  n_above <- sum(
    x$receiver_relation == "ABOVE"
  )

  n_water <- sum(
    x$receiver_type != "LAND"
  )

  if (n_lower > 0) {

    evidence_class <- "DIRECT_LOWER_ESCAPE"

  } else if (n_water > 0) {

    evidence_class <- "DIRECT_WATER_CONTACT"

  } else {

    evidence_class <- "LEVEL_LAND_ONLY"
  }

  gate_escape_group_list[[i]] <- data.frame(

    gate_group_id =
      g,

    depression_component_id =
      unique(
        x$depression_component_id
      )[1],

    n_edges =
      nrow(x),

    n_lower_edges =
      n_lower,

    n_level_edges =
      n_level,

    n_above_edges =
      n_above,

    n_land_edges =
      sum(
        x$receiver_type == "LAND"
      ),

    n_river_area_edges =
      sum(
        x$receiver_type == "RIVER_AREA"
      ),

    n_river_line_edges =
      sum(
        x$receiver_type == "RIVER_LINE"
      ),

    n_lake_edges =
      sum(
        x$receiver_type == "LAKE"
      ),

    n_pointer_valid =
      sum(
        x$receiver_pointer_status == "VALID"
      ),

    n_pointer_zero =
      sum(
        x$receiver_pointer_status == "ZERO"
      ),

    n_pointer_na =
      sum(
        x$receiver_pointer_status == "NA"
      ),

    evidence_class =
      evidence_class,

    stringsAsFactors = FALSE
  )
}


gate_escape_groups <- do.call(
  rbind,
  gate_escape_group_list
)

row.names(
  gate_escape_groups
) <- NULL


write.csv(
  gate_escape_groups,
  file.path(
    DIR_02,
    "02D_gate_escape_group_diagnostic.csv"
  ),
  row.names = FALSE
)


# ------------------------------------------------------------
# 124. DEPRESSION-LEVEL SUMMARY
# ------------------------------------------------------------

did <- sort(
  unique(
    gate_escape_groups$depression_component_id
  )
)

dep_escape_list <- vector(
  "list",
  length(did)
)


for (i in seq_along(did)) {

  d <- did[i]

  x <- gate_escape_groups[
    gate_escape_groups$depression_component_id == d,
    ,
    drop = FALSE
  ]

  dep_escape_list[[i]] <- data.frame(

    depression_component_id =
      d,

    n_gate_groups =
      nrow(x),

    groups_direct_lower =
      sum(
        x$evidence_class ==
          "DIRECT_LOWER_ESCAPE"
      ),

    groups_direct_water =
      sum(
        x$evidence_class ==
          "DIRECT_WATER_CONTACT"
      ),

    groups_level_land_only =
      sum(
        x$evidence_class ==
          "LEVEL_LAND_ONLY"
      ),

    all_groups_level_land_only =
      all(
        x$evidence_class ==
          "LEVEL_LAND_ONLY"
      ),

    stringsAsFactors = FALSE
  )
}


dep_escape_summary <- do.call(
  rbind,
  dep_escape_list
)

row.names(
  dep_escape_summary
) <- NULL


write.csv(
  dep_escape_summary,
  file.path(
    DIR_02,
    "02D_depression_escape_summary.csv"
  ),
  row.names = FALSE
)


# ------------------------------------------------------------
# 125. GLOBAL QA
# ------------------------------------------------------------

n_gate_edges_total <- nrow(
  gate_escape
)

n_lower_edges <- sum(
  gate_escape$receiver_relation ==
    "LOWER"
)

n_level_edges <- sum(
  gate_escape$receiver_relation ==
    "LEVEL"
)

n_above_edges <- sum(
  gate_escape$receiver_relation ==
    "ABOVE"
)

n_group_lower <- sum(
  gate_escape_groups$evidence_class ==
    "DIRECT_LOWER_ESCAPE"
)

n_group_water <- sum(
  gate_escape_groups$evidence_class ==
    "DIRECT_WATER_CONTACT"
)

n_group_level <- sum(
  gate_escape_groups$evidence_class ==
    "LEVEL_LAND_ONLY"
)

n_dep_with_lower <- sum(
  dep_escape_summary$groups_direct_lower > 0
)

n_dep_with_water <- sum(
  dep_escape_summary$groups_direct_water > 0
)

n_dep_all_level <- sum(
  dep_escape_summary$all_groups_level_land_only
)


# ------------------------------------------------------------
# 126. PRINT
# ------------------------------------------------------------

cat("\n")
cat("=== 02D.5A GATE ESCAPE EVIDENCE ===\n")

cat(sprintf(
  "Gate edges total              : %d\n",
  n_gate_edges_total
))

cat(sprintf(
  "Receiver LOWER than gate      : %d\n",
  n_lower_edges
))

cat(sprintf(
  "Receiver LEVEL with gate      : %d\n",
  n_level_edges
))

cat(sprintf(
  "Receiver ABOVE gate           : %d\n",
  n_above_edges
))

cat(sprintf(
  "Gate groups DIRECT_LOWER      : %d\n",
  n_group_lower
))

cat(sprintf(
  "Gate groups DIRECT_WATER      : %d\n",
  n_group_water
))

cat(sprintf(
  "Gate groups LEVEL_LAND_ONLY   : %d\n",
  n_group_level
))

cat(sprintf(
  "Depressions with lower escape : %d / %d\n",
  n_dep_with_lower,
  nrow(dep_escape_summary)
))

cat(sprintf(
  "Depressions with water contact: %d / %d\n",
  n_dep_with_water,
  nrow(dep_escape_summary)
))

cat(sprintf(
  "Depressions entirely LEVEL    : %d / %d\n",
  n_dep_all_level,
  nrow(dep_escape_summary)
))


cat("\n--- ALL-LEVEL DEPRESSIONS ---\n")

all_level <- dep_escape_summary[
  dep_escape_summary$all_groups_level_land_only,
  ,
  drop = FALSE
]

if (nrow(all_level) == 0) {

  cat("NONE\n")

} else {

  print(
    all_level,
    row.names = FALSE
  )
}

cat("========================================\n")

# ============================================================
# 02D.6 - LEVEL-FLAT ESCAPE TRACE
#
# Korvaa nykyinen 02D.6-osuus tällä kokonaisuudella.
#
# Tavoite:
# - käsitellä kaikki depression-komponentit, joiden minimum-gate
#   -ryhmät ovat LEVEL_LAND_ONLY
# - jäljittää gate-receivereistä ulkopuolinen LAND-flat
#   samalla spill-tasolla
# - tunnistaa flatin rajalta:
#       * LOWER escape
#       * LEVEL water escape
#       * yhteys toiseen raised depressioniin
#       * rasterin reuna
# - erottaa oikea puuttuva LEVEL-land-yhteys takaisin alkuperäiseen
#   depressioniin menevistä rajareunoista
#
# TÄRKEÄÄ:
# - kaikki raised-depression-solut poistetaan ENNEN patches()-vaihetta
# - takaisin alkuperäiseen depressioniin menevät reunat poistetaan
#   ENNEN untraced LEVEL-land QA:ta
# - EI vielä muuta D8-pointeria
# - EI vielä valitse lopullista outlet-pikseliä
# ============================================================


# ------------------------------------------------------------
# 127. PARAMETERS
# ------------------------------------------------------------

flat_tol_m <- 1e-6
initial_margin_m <- 250


# ------------------------------------------------------------
# 128. REQUIRED OBJECTS
# ------------------------------------------------------------

required_objects_02d6 <- c(
    "dep_escape_summary",
    "dep_tab",
    "gate_escape",
    "surface_storage",
    "water_class",
    "lake_id",
    "depression_components",
    "cell_values",
    "is_edge_cell",
    "DIR_02"
)

missing_objects_02d6 <- required_objects_02d6[
    !vapply(
        required_objects_02d6,
        exists,
        logical(1),
        inherits = TRUE
    )
]

if (length(missing_objects_02d6) > 0) {
    stop(
        paste0(
            "02D.6 missing required objects: ",
            paste(
                missing_objects_02d6,
                collapse = ", "
            )
        )
    )
}


# ------------------------------------------------------------
# 129. TARGET DEPRESSIONS
# ------------------------------------------------------------

level_dep_ids <- sort(
    unique(
        dep_escape_summary$depression_component_id[
            dep_escape_summary$all_groups_level_land_only
        ]
    )
)

stopifnot(
    length(level_dep_ids) > 0
)

cat("\n")
cat(
    "02D.6 target LEVEL_LAND_ONLY depressions: ",
    length(level_dep_ids),
    "\n",
    sep = ""
)


# ------------------------------------------------------------
# 130. OUTPUT HOLDERS
# ------------------------------------------------------------

gate_flat_results <- list()
flat_escape_edges_results <- list()
flat_component_results <- list()
dep_flat_results <- list()


# ------------------------------------------------------------
# 131. FULL RASTER EXTENT
# ------------------------------------------------------------

full_ext <- ext(
    surface_storage
)

full_width_m <-
    xmax(full_ext) -
    xmin(full_ext)

full_height_m <-
    ymax(full_ext) -
    ymin(full_ext)

max_margin_m <- max(
    full_width_m,
    full_height_m
)


# ------------------------------------------------------------
# 132. PROCESS EACH LEVEL-LAND-ONLY DEPRESSION
# ------------------------------------------------------------

for (ii in seq_along(level_dep_ids)) {

    did <- level_dep_ids[ii]

    cat(sprintf(
        "\r02D.6 depression %d / %d | ID %d",
        ii,
        length(level_dep_ids),
        did
    ))


    # --------------------------------------------------------
    # 132A. DEPRESSION CELLS
    # --------------------------------------------------------

    comp_cells <- dep_tab$cell[
        dep_tab$depression_component_id == did
    ]

    stopifnot(
        length(comp_cells) > 0
    )


    # --------------------------------------------------------
    # 132B. MIN-GATE EDGES
    # --------------------------------------------------------

    gx <- gate_escape[
        gate_escape$depression_component_id == did,
        ,
        drop = FALSE
    ]

    stopifnot(
        nrow(gx) > 0
    )

    # Target set came from all_groups_level_land_only.
    # Therefore all minimum-gate receiver edges must be
    # LEVEL + LAND.

    stopifnot(
        all(
            gx$receiver_relation == "LEVEL"
        ),
        all(
            gx$receiver_type == "LAND"
        )
    )

    gate_levels <- gx$edge_crossing_level_m[
        is.finite(
            gx$edge_crossing_level_m
        )
    ]

    stopifnot(
        length(gate_levels) > 0,
        max(gate_levels) -
            min(gate_levels) <=
            flat_tol_m
    )

    gate_level <- median(
        gate_levels
    )


    # --------------------------------------------------------
    # 132C. GATE RECEIVER CELLS
    # --------------------------------------------------------

    seed_all <- sort(
        unique(
            gx$receiver_cell
        )
    )

    stopifnot(
        length(seed_all) > 0
    )

    seed_dep <- cell_values(
        depression_components,
        seed_all
    )

    # The receiver of a component -> outside gate must never
    # belong to the same raised component.

    same_dep_seed <- (
        is.finite(seed_dep) &
            seed_dep == did
    )

    stopifnot(
        !any(
            same_dep_seed
        )
    )

    # A gate can theoretically meet another raised depression.
    # Keep that as a separate link; do not traverse through it
    # as normal flat land.

    seed_other_dep <- (
        is.finite(seed_dep) &
            seed_dep != did
    )

    n_direct_other_dep_seeds <- sum(
        seed_other_dep
    )

    # Only cells outside ALL raised depressions are ordinary
    # level-flat seeds.

    seed_flat <- seed_all[
        !is.finite(seed_dep)
    ]

    if (length(seed_flat) > 0) {

        seed_flat_z <- cell_values(
            surface_storage,
            seed_flat
        )

        stopifnot(
            all(
                is.finite(
                    seed_flat_z
                )
            ),
            all(
                abs(
                    seed_flat_z -
                        gate_level
                ) <= flat_tol_m
            )
        )
    }


    # --------------------------------------------------------
    # 132D. DEPRESSION BOUNDING BOX
    # --------------------------------------------------------

    comp_xy <- xyFromCell(
        surface_storage,
        comp_cells
    )

    xmin_comp <- min(
        comp_xy[, 1]
    )

    xmax_comp <- max(
        comp_xy[, 1]
    )

    ymin_comp <- min(
        comp_xy[, 2]
    )

    ymax_comp <- max(
        comp_xy[, 2]
    )


    # --------------------------------------------------------
    # 132E. TRACE COMPLETE OUTSIDE LEVEL-FLAT
    #
    # Crop grows until:
    # 1) selected gate-connected flat no longer touches crop
    #    boundary
    # OR
    # 2) crop is the complete raster.
    #
    # CRITICAL:
    # depression_components must be NA for a cell to enter
    # flat_land. Raised cells are removed BEFORE patches().
    # --------------------------------------------------------

    plateau_map <- NULL
    used_margin <- NA_real_
    plateau_reaches_raster_edge <- FALSE

    if (length(seed_flat) > 0) {

        margin_m <- initial_margin_m

        repeat {

            if (
                margin_m >=
                    max_margin_m
            ) {

                e <- full_ext

            } else {

                e <- ext(
                    max(
                        xmin(full_ext),
                        xmin_comp - margin_m
                    ),
                    min(
                        xmax(full_ext),
                        xmax_comp + margin_m
                    ),
                    max(
                        ymin(full_ext),
                        ymin_comp - margin_m
                    ),
                    min(
                        ymax(full_ext),
                        ymax_comp + margin_m
                    )
                )
            }


            s_local <- crop(
                surface_storage,
                e
            )

            w_local <- crop(
                water_class,
                e
            )

            dep_local <- crop(
                depression_components,
                e
            )


            # TRUE OUTSIDE LAND FLAT:
            # - same filled-surface elevation as the gate
            # - not RANTA10 water
            # - not part of any raised depression

            flat_land <- ifel(
                abs(
                    s_local -
                        gate_level
                ) <= flat_tol_m &
                    is.na(w_local) &
                    is.na(dep_local),
                1,
                NA
            )


            flat_patch <- patches(
                flat_land,
                directions = 8
            )


            # Gate receiver seeds -> local raster cells.

            seed_xy <- xyFromCell(
                surface_storage,
                seed_flat
            )

            seed_local <- cellFromXY(
                flat_patch,
                seed_xy
            )

            seed_local <- seed_local[
                is.finite(
                    seed_local
                )
            ]

            if (length(seed_local) == 0) {
                break
            }

            seed_patch_id <- cell_values(
                flat_patch,
                seed_local
            )

            seed_patch_id <- sort(
                unique(
                    seed_patch_id[
                        is.finite(
                            seed_patch_id
                        )
                    ]
                )
            )

            if (length(seed_patch_id) == 0) {
                break
            }


            patch_tab <- as.data.frame(
                flat_patch,
                cells = TRUE,
                na.rm = TRUE
            )

            if (nrow(patch_tab) == 0) {
                break
            }

            names(patch_tab)[2] <-
                "flat_patch_id"

            selected <- patch_tab[
                patch_tab$flat_patch_id %in%
                    seed_patch_id,
                ,
                drop = FALSE
            ]

            if (nrow(selected) == 0) {
                break
            }


            # Does the selected flat touch the current crop edge?

            rc_local <- rowColFromCell(
                flat_patch,
                selected$cell
            )

            touches_crop_edge <- any(
                rc_local[, 1] == 1 |
                    rc_local[, 1] ==
                    nrow(flat_patch) |
                    rc_local[, 2] == 1 |
                    rc_local[, 2] ==
                    ncol(flat_patch)
            )


            ee <- ext(
                flat_patch
            )

            full_crop <- (
                abs(
                    xmin(ee) -
                        xmin(full_ext)
                ) <= 1e-8 &&
                    abs(
                        xmax(ee) -
                            xmax(full_ext)
                    ) <= 1e-8 &&
                    abs(
                        ymin(ee) -
                            ymin(full_ext)
                    ) <= 1e-8 &&
                    abs(
                        ymax(ee) -
                            ymax(full_ext)
                    ) <= 1e-8
            )


            # Complete enough:
            # - flat does not touch crop boundary, or
            # - complete raster has already been reached.

            if (
                !touches_crop_edge ||
                    full_crop
            ) {

                selected_xy <- xyFromCell(
                    flat_patch,
                    selected$cell
                )

                global_cells <- cellFromXY(
                    surface_storage,
                    selected_xy
                )

                plateau_map <- data.frame(
                    cell =
                        as.integer(
                            global_cells
                        ),
                    flat_patch_id =
                        as.integer(
                            selected$flat_patch_id
                        ),
                    stringsAsFactors = FALSE
                )

                plateau_map <- unique(
                    plateau_map
                )

                plateau_map <- plateau_map[
                    is.finite(
                        plateau_map$cell
                    ),
                    ,
                    drop = FALSE
                ]

                stopifnot(
                    nrow(plateau_map) > 0,
                    !anyDuplicated(
                        plateau_map$cell
                    )
                )

                used_margin <- margin_m

                if (
                    touches_crop_edge &&
                        full_crop
                ) {

                    plateau_reaches_raster_edge <-
                        TRUE
                }

                break
            }


            # Enlarge crop.

            old_margin <- margin_m

            margin_m <- min(
                margin_m * 2,
                max_margin_m
            )

            if (
                margin_m <= old_margin
            ) {

                stop(
                    sprintf(
                        paste0(
                            "02D.6 crop could not be enlarged ",
                            "for depression %d."
                        ),
                        did
                    )
                )
            }
        }
    }


    # --------------------------------------------------------
    # 132F. NO OUTSIDE FLAT
    # --------------------------------------------------------

    if (
        is.null(plateau_map) ||
            nrow(plateau_map) == 0
    ) {

        dep_status <- if (
            n_direct_other_dep_seeds > 0
        ) {
            "OTHER_DEPRESSION"
        } else {
            "NO_OUTSIDE_FLAT"
        }

        dep_flat_results[[
            length(dep_flat_results) + 1L
        ]] <- data.frame(

            depression_component_id =
                did,

            gate_level_m =
                gate_level,

            n_gate_groups =
                length(
                    unique(
                        gx$gate_group_id
                    )
                ),

            n_gate_edges =
                nrow(gx),

            n_gate_receiver_cells =
                length(seed_all),

            n_direct_other_dep_seeds =
                n_direct_other_dep_seeds,

            n_flat_cells =
                0L,

            n_flat_components =
                0L,

            n_back_to_origin_edges_filtered =
                0L,

            n_lower_escape_edges =
                0L,

            n_level_water_edges =
                0L,

            n_other_depression_edges =
                n_direct_other_dep_seeds,

            n_untraced_level_land_edges =
                0L,

            n_components_raster_edge =
                0L,

            has_terminal_escape =
                FALSE,

            has_other_depression_link =
                n_direct_other_dep_seeds > 0,

            touches_raster_edge =
                FALSE,

            used_margin_m =
                NA_real_,

            status =
                dep_status,

            stringsAsFactors = FALSE
        )

        next
    }


    # --------------------------------------------------------
    # 132G. HARD CHECKS ON TRACED FLAT
    # --------------------------------------------------------

    plateau_cells <- sort(
        unique(
            plateau_map$cell
        )
    )

    stopifnot(
        length(plateau_cells) > 0
    )

    plateau_dep <- cell_values(
        depression_components,
        plateau_cells
    )

    plateau_water <- cell_values(
        water_class,
        plateau_cells
    )

    plateau_z <- cell_values(
        surface_storage,
        plateau_cells
    )

    stopifnot(
        # No raised-depression cell may be part of the outside flat.
        all(
            !is.finite(
                plateau_dep
            )
        ),

        # Outside flat is land only.
        all(
            !is.finite(
                plateau_water
            )
        ),

        # Every traced cell is at the gate level.
        all(
            is.finite(
                plateau_z
            )
        ),
        all(
            abs(
                plateau_z -
                    gate_level
            ) <= flat_tol_m
        )
    )


    # --------------------------------------------------------
    # 132H. GLOBAL FLAT COMPONENT IDS
    # --------------------------------------------------------

    plateau_map$flat_component_uid <- paste(
        did,
        plateau_map$flat_patch_id,
        sep = "_"
    )


    # --------------------------------------------------------
    # 132I. MAP ORIGINAL GATE GROUPS -> OUTSIDE FLAT
    # --------------------------------------------------------

    gate_flat <- gx[
        gx$receiver_cell %in%
            plateau_cells,
        c(
            "gate_group_id",
            "depression_component_id",
            "receiver_cell"
        ),
        drop = FALSE
    ]

    if (nrow(gate_flat) > 0) {

        gate_flat$flat_patch_id <-
            plateau_map$flat_patch_id[
                match(
                    gate_flat$receiver_cell,
                    plateau_map$cell
                )
            ]

        gate_flat$flat_component_uid <-
            plateau_map$flat_component_uid[
                match(
                    gate_flat$receiver_cell,
                    plateau_map$cell
                )
            ]

        gate_flat <- unique(
            gate_flat
        )

        stopifnot(
            all(
                !is.na(
                    gate_flat$flat_patch_id
                )
            ),
            all(
                !is.na(
                    gate_flat$flat_component_uid
                )
            )
        )

        gate_flat_results[[
            length(gate_flat_results) + 1L
        ]] <- gate_flat
    }


    # --------------------------------------------------------
    # 132J. ALL BOUNDARY EDGES FROM TRACED OUTSIDE FLAT
    #
    # CRITICAL FIX:
    #
    # Remove:
    # 1) edges to another cell in the same traced flat
    # 2) edges BACK INTO THE ORIGINAL RAISED DEPRESSION
    #
    # The original depression is where the trace came from.
    # It is NOT an untraced continuation of the outside flat.
    # --------------------------------------------------------

    ap_all <- adjacent(
        surface_storage,
        cells = plateau_cells,
        directions = 8,
        pairs = TRUE,
        include = FALSE
    )

    stopifnot(
        nrow(ap_all) > 0
    )

    edge_inside_flat <- (
        ap_all[, 2] %in%
            plateau_cells
    )

    edge_back_to_origin <- (
        ap_all[, 2] %in%
            comp_cells
    )

    n_back_to_origin_edges <- sum(
        edge_back_to_origin &
            !edge_inside_flat
    )

    keep_boundary <- (
        !edge_inside_flat &
            !edge_back_to_origin
    )

    ap <- ap_all[
        keep_boundary,
        ,
        drop = FALSE
    ]

    # This is the specific invariant that fixes the previous
    # false TRACE_INCOMPLETE result.

    stopifnot(
        !any(
            ap[, 2] %in%
                comp_cells
        )
    )


    # --------------------------------------------------------
    # 132K. RECEIVER INFORMATION
    # --------------------------------------------------------

    if (nrow(ap) > 0) {

        receiver_storage <- cell_values(
            surface_storage,
            ap[, 2]
        )

        receiver_water <- cell_values(
            water_class,
            ap[, 2]
        )

        receiver_lake <- cell_values(
            lake_id,
            ap[, 2]
        )

        receiver_dep <- cell_values(
            depression_components,
            ap[, 2]
        )


        # Relation to gate level.

        relation <- rep(
            "NA",
            nrow(ap)
        )

        finite_receiver <- is.finite(
            receiver_storage
        )

        relation[
            finite_receiver &
                receiver_storage <
                gate_level -
                flat_tol_m
        ] <- "LOWER"

        relation[
            finite_receiver &
                abs(
                    receiver_storage -
                        gate_level
                ) <= flat_tol_m
        ] <- "LEVEL"

        relation[
            finite_receiver &
                receiver_storage >
                gate_level +
                flat_tol_m
        ] <- "ABOVE"


        # Receiver water type.

        receiver_type <- rep(
            "LAND",
            nrow(ap)
        )

        receiver_type[
            receiver_water == 1
        ] <- "LAKE"

        receiver_type[
            receiver_water == 2
        ] <- "RIVER_AREA"

        receiver_type[
            receiver_water == 3
        ] <- "RIVER_LINE"


        # Any remaining finite depression ID is necessarily
        # another raised component, because the original one
        # was already removed above.

        other_depression <- is.finite(
            receiver_dep
        )


        # Source flat component.

        source_flat_patch <-
            plateau_map$flat_patch_id[
                match(
                    ap[, 1],
                    plateau_map$cell
                )
            ]

        source_flat_uid <-
            plateau_map$flat_component_uid[
                match(
                    ap[, 1],
                    plateau_map$cell
                )
            ]

        stopifnot(
            all(
                !is.na(
                    source_flat_patch
                )
            ),
            all(
                !is.na(
                    source_flat_uid
                )
            )
        )


        # ----------------------------------------------------
        # 132L. ESCAPE / QA EDGE TABLE
        # ----------------------------------------------------

        edge_table <- data.frame(

            depression_component_id =
                did,

            gate_level_m =
                gate_level,

            flat_patch_id =
                source_flat_patch,

            flat_component_uid =
                source_flat_uid,

            source_cell =
                ap[, 1],

            receiver_cell =
                ap[, 2],

            receiver_storage_z_m =
                receiver_storage,

            relation =
                relation,

            receiver_type =
                receiver_type,

            receiver_lake_objectid =
                as.integer(
                    receiver_lake
                ),

            receiver_depression_component_id =
                as.integer(
                    receiver_dep
                ),

            other_depression =
                other_depression,

            stringsAsFactors = FALSE
        )


        # A lower receiver is a true topographic escape.

        edge_table$is_lower_escape <-
            edge_table$relation ==
            "LOWER"


        # Water at exactly the same spill level is an explicit
        # water target.

        edge_table$is_level_water <-
            edge_table$relation ==
            "LEVEL" &
            edge_table$receiver_type !=
            "LAND"


        # Same-level contact to another raised depression is
        # kept as a depression-to-depression link.
        #
        # It is NOT yet considered a terminal escape.

        edge_table$is_other_depression <-
            edge_table$relation ==
            "LEVEL" &
            edge_table$other_depression


        # If tracing is complete this MUST be zero:
        # a same-level LAND receiver outside:
        # - the traced flat
        # - the original depression
        # - every other raised depression
        #
        # means a same-level land cell was genuinely missed.

        edge_table$is_untraced_level_land <-
            edge_table$relation ==
            "LEVEL" &
            edge_table$receiver_type ==
            "LAND" &
            !edge_table$other_depression


        flat_escape_edges_results[[
            length(flat_escape_edges_results) + 1L
        ]] <- edge_table

    } else {

        edge_table <- data.frame(
            depression_component_id = integer(0),
            gate_level_m = numeric(0),
            flat_patch_id = integer(0),
            flat_component_uid = character(0),
            source_cell = integer(0),
            receiver_cell = integer(0),
            receiver_storage_z_m = numeric(0),
            relation = character(0),
            receiver_type = character(0),
            receiver_lake_objectid = integer(0),
            receiver_depression_component_id = integer(0),
            other_depression = logical(0),
            is_lower_escape = logical(0),
            is_level_water = logical(0),
            is_other_depression = logical(0),
            is_untraced_level_land = logical(0),
            stringsAsFactors = FALSE
        )
    }


    # --------------------------------------------------------
    # 132M. SUMMARY BY OUTSIDE FLAT COMPONENT
    # --------------------------------------------------------

    flat_uids <- sort(
        unique(
            plateau_map$flat_component_uid
        )
    )

    this_flat_list <- vector(
        "list",
        length(flat_uids)
    )

    for (jj in seq_along(flat_uids)) {

        uid <- flat_uids[jj]

        pc <- plateau_map[
            plateau_map$flat_component_uid == uid,
            ,
            drop = FALSE
        ]

        ee <- edge_table[
            edge_table$flat_component_uid == uid,
            ,
            drop = FALSE
        ]

        if (nrow(gate_flat) > 0) {

            gg <- gate_flat$gate_group_id[
                gate_flat$flat_component_uid == uid
            ]

            gg <- sort(
                unique(gg)
            )

        } else {

            gg <- integer(0)
        }


        touches_edge <- any(
            is_edge_cell(
                surface_storage,
                pc$cell
            )
        )

        n_lower <- if (
            nrow(ee) > 0
        ) {
            sum(
                ee$is_lower_escape,
                na.rm = TRUE
            )
        } else {
            0L
        }

        n_level_water <- if (
            nrow(ee) > 0
        ) {
            sum(
                ee$is_level_water,
                na.rm = TRUE
            )
        } else {
            0L
        }

        n_other_dep <- if (
            nrow(ee) > 0
        ) {
            sum(
                ee$is_other_depression,
                na.rm = TRUE
            )
        } else {
            0L
        }

        n_untraced <- if (
            nrow(ee) > 0
        ) {
            sum(
                ee$is_untraced_level_land,
                na.rm = TRUE
            )
        } else {
            0L
        }

        has_terminal_escape <- (
            n_lower > 0 |
                n_level_water > 0
        )

        has_other_dep_link <- (
            n_other_dep > 0
        )


        # Conservative component classification.

        if (n_untraced > 0) {

            flat_status <-
                "TRACE_INCOMPLETE"

        } else if (
            has_terminal_escape &&
                touches_edge
        ) {

            flat_status <-
                "RESOLVED_BUT_EDGE_AMBIGUITY"

        } else if (n_lower > 0) {

            flat_status <-
                "LOWER_ESCAPE"

        } else if (n_level_water > 0) {

            flat_status <-
                "LEVEL_WATER_ESCAPE"

        } else if (
            has_other_dep_link &&
                touches_edge
        ) {

            flat_status <-
                "OTHER_DEPRESSION_AND_EDGE"

        } else if (has_other_dep_link) {

            flat_status <-
                "OTHER_DEPRESSION"

        } else if (touches_edge) {

            flat_status <-
                "CENSORED_BY_RASTER_EDGE"

        } else {

            flat_status <-
                "NO_ESCAPE"
        }


        this_flat_list[[jj]] <- data.frame(

            depression_component_id =
                did,

            gate_level_m =
                gate_level,

            flat_patch_id =
                pc$flat_patch_id[1],

            flat_component_uid =
                uid,

            n_flat_cells =
                nrow(pc),

            n_gate_groups =
                length(gg),

            gate_group_ids =
                if (
                    length(gg) == 0
                ) {
                    ""
                } else {
                    paste(
                        gg,
                        collapse = ";"
                    )
                },

            n_boundary_edges =
                nrow(ee),

            n_lower_escape_edges =
                n_lower,

            n_level_water_edges =
                n_level_water,

            n_other_depression_edges =
                n_other_dep,

            n_untraced_level_land_edges =
                n_untraced,

            has_terminal_escape =
                has_terminal_escape,

            has_other_depression_link =
                has_other_dep_link,

            touches_raster_edge =
                touches_edge,

            status =
                flat_status,

            stringsAsFactors = FALSE
        )
    }

    this_flat <- do.call(
        rbind,
        this_flat_list
    )

    row.names(
        this_flat
    ) <- NULL

    flat_component_results[[
        length(flat_component_results) + 1L
    ]] <- this_flat


    # --------------------------------------------------------
    # 132N. DEPRESSION-LEVEL SUMMARY
    # --------------------------------------------------------

    n_lower_total <- sum(
        this_flat$n_lower_escape_edges
    )

    n_water_total <- sum(
        this_flat$n_level_water_edges
    )

    n_other_dep_total <- sum(
        this_flat$n_other_depression_edges
    ) +
        n_direct_other_dep_seeds

    n_untraced_total <- sum(
        this_flat$n_untraced_level_land_edges
    )

    n_edge_components <- sum(
        this_flat$touches_raster_edge
    )

    has_terminal_escape <- (
        n_lower_total > 0 |
            n_water_total > 0
    )

    has_other_dep_link <- (
        n_other_dep_total > 0
    )


    # --------------------------------------------------------
    # Depression-level status
    # --------------------------------------------------------

    if (n_untraced_total > 0) {

        dep_status <-
            "TRACE_INCOMPLETE"

    } else if (
        has_terminal_escape &&
            n_edge_components > 0
    ) {

        dep_status <-
            "RESOLVED_BUT_EDGE_AMBIGUITY"

    } else if (has_terminal_escape) {

        dep_status <-
            "RESOLVED"

    } else if (
        has_other_dep_link &&
            n_edge_components > 0
    ) {

        dep_status <-
            "OTHER_DEPRESSION_AND_EDGE"

    } else if (has_other_dep_link) {

        dep_status <-
            "OTHER_DEPRESSION"

    } else if (n_edge_components > 0) {

        dep_status <-
            "CENSORED_BY_RASTER_EDGE"

    } else {

        dep_status <-
            "NO_ESCAPE"
    }


    dep_flat_results[[
        length(dep_flat_results) + 1L
    ]] <- data.frame(

        depression_component_id =
            did,

        gate_level_m =
            gate_level,

        n_gate_groups =
            length(
                unique(
                    gx$gate_group_id
                )
            ),

        n_gate_edges =
            nrow(gx),

        n_gate_receiver_cells =
            length(seed_all),

        n_direct_other_dep_seeds =
            n_direct_other_dep_seeds,

        n_flat_cells =
            nrow(
                plateau_map
            ),

        n_flat_components =
            nrow(
                this_flat
            ),

        n_back_to_origin_edges_filtered =
            n_back_to_origin_edges,

        n_lower_escape_edges =
            n_lower_total,

        n_level_water_edges =
            n_water_total,

        n_other_depression_edges =
            n_other_dep_total,

        n_untraced_level_land_edges =
            n_untraced_total,

        n_components_raster_edge =
            n_edge_components,

        has_terminal_escape =
            has_terminal_escape,

        has_other_depression_link =
            has_other_dep_link,

        touches_raster_edge =
            n_edge_components > 0 |
            plateau_reaches_raster_edge,

        used_margin_m =
            used_margin,

        status =
            dep_status,

        stringsAsFactors = FALSE
    )
}

cat("\n")


# ------------------------------------------------------------
# 133. COMBINE RESULTS
# ------------------------------------------------------------

if (length(gate_flat_results) > 0) {

    gate_flat_all <- do.call(
        rbind,
        gate_flat_results
    )

    row.names(
        gate_flat_all
    ) <- NULL

} else {

    gate_flat_all <- data.frame()
}


if (length(flat_escape_edges_results) > 0) {

    flat_escape_edges <- do.call(
        rbind,
        flat_escape_edges_results
    )

    row.names(
        flat_escape_edges
    ) <- NULL

} else {

    flat_escape_edges <- data.frame()
}


if (length(flat_component_results) > 0) {

    flat_component_summary <- do.call(
        rbind,
        flat_component_results
    )

    row.names(
        flat_component_summary
    ) <- NULL

} else {

    flat_component_summary <- data.frame()
}


dep_flat_summary <- do.call(
    rbind,
    dep_flat_results
)

row.names(
    dep_flat_summary
) <- NULL

dep_flat_summary <- dep_flat_summary[
    order(
        dep_flat_summary$depression_component_id
    ),
    ,
    drop = FALSE
]


# ------------------------------------------------------------
# 134. SAVE
# ------------------------------------------------------------

f_02d6_gate_flat <- file.path(
    DIR_02,
    "02D6_gate_to_flat_component.csv"
)

f_02d6_edges <- file.path(
    DIR_02,
    "02D6_flat_escape_edges.csv"
)

f_02d6_flat_summary <- file.path(
    DIR_02,
    "02D6_flat_component_summary.csv"
)

f_02d6_dep_summary <- file.path(
    DIR_02,
    "02D6_depression_flat_escape_summary.csv"
)


write.csv(
    gate_flat_all,
    f_02d6_gate_flat,
    row.names = FALSE
)

write.csv(
    flat_escape_edges,
    f_02d6_edges,
    row.names = FALSE
)

write.csv(
    flat_component_summary,
    f_02d6_flat_summary,
    row.names = FALSE
)

write.csv(
    dep_flat_summary,
    f_02d6_dep_summary,
    row.names = FALSE
)


# ------------------------------------------------------------
# 135. GLOBAL QA
# ------------------------------------------------------------

n_dep_02d6 <- nrow(
    dep_flat_summary
)

n_resolved <- sum(
    dep_flat_summary$status ==
        "RESOLVED"
)

n_resolved_edge <- sum(
    dep_flat_summary$status ==
        "RESOLVED_BUT_EDGE_AMBIGUITY"
)

n_other_dep <- sum(
    dep_flat_summary$status ==
        "OTHER_DEPRESSION"
)

n_other_dep_edge <- sum(
    dep_flat_summary$status ==
        "OTHER_DEPRESSION_AND_EDGE"
)

n_censored <- sum(
    dep_flat_summary$status ==
        "CENSORED_BY_RASTER_EDGE"
)

n_incomplete <- sum(
    dep_flat_summary$status ==
        "TRACE_INCOMPLETE"
)

n_no_escape <- sum(
    dep_flat_summary$status %in%
        c(
            "NO_ESCAPE",
            "NO_OUTSIDE_FLAT"
        )
)

n_untraced <- sum(
    dep_flat_summary$
        n_untraced_level_land_edges
)

n_back_filtered <- sum(
    dep_flat_summary$
        n_back_to_origin_edges_filtered
)

n_with_lower <- sum(
    dep_flat_summary$
        n_lower_escape_edges > 0
)

n_with_water <- sum(
    dep_flat_summary$
        n_level_water_edges > 0
)

n_with_other_dep <- sum(
    dep_flat_summary$
        n_other_depression_edges > 0
)

n_touch_edge <- sum(
    dep_flat_summary$
        touches_raster_edge
)


# ------------------------------------------------------------
# 136. PRINT
# ------------------------------------------------------------

cat("\n")
cat("=== 02D.6 LEVEL-FLAT ESCAPE TRACE ===\n")

cat(sprintf(
    "Target depressions              : %d\n",
    n_dep_02d6
))

cat(sprintf(
    "Resolved                        : %d\n",
    n_resolved
))

cat(sprintf(
    "Resolved + edge ambiguity       : %d\n",
    n_resolved_edge
))

cat(sprintf(
    "Other-depression only           : %d\n",
    n_other_dep
))

cat(sprintf(
    "Other-depression + edge         : %d\n",
    n_other_dep_edge
))

cat(sprintf(
    "Censored by raster edge         : %d\n",
    n_censored
))

cat(sprintf(
    "Trace incomplete                : %d\n",
    n_incomplete
))

cat(sprintf(
    "No escape found                 : %d\n",
    n_no_escape
))

cat(sprintf(
    "Depressions with LOWER escape   : %d\n",
    n_with_lower
))

cat(sprintf(
    "Depressions with LEVEL water    : %d\n",
    n_with_water
))

cat(sprintf(
    "Depressions -> other depression : %d\n",
    n_with_other_dep
))

cat(sprintf(
    "Depressions touching raster edge: %d\n",
    n_touch_edge
))

cat(sprintf(
    "Back-to-origin edges filtered   : %d\n",
    n_back_filtered
))

cat(sprintf(
    "Untraced LEVEL-land edges       : %d\n",
    n_untraced
))


cat("\n--- STATUS ---\n")

print(
    table(
        dep_flat_summary$status
    )
)


cat("\n--- UNRESOLVED / EDGE CASES ---\n")

review_02d6 <- dep_flat_summary[
    !dep_flat_summary$status %in%
        c(
            "RESOLVED"
        ),
    ,
    drop = FALSE
]

if (nrow(review_02d6) == 0) {

    cat("NONE\n")

} else {

    print(
        review_02d6[
            ,
            c(
                "depression_component_id",
                "gate_level_m",
                "n_gate_groups",
                "n_flat_cells",
                "n_flat_components",
                "n_back_to_origin_edges_filtered",
                "n_lower_escape_edges",
                "n_level_water_edges",
                "n_other_depression_edges",
                "n_untraced_level_land_edges",
                "n_components_raster_edge",
                "used_margin_m",
                "status"
            )
        ],
        row.names = FALSE
    )
}


cat("\n")

cat(sprintf(
    "Depression summary : %s\n",
    basename(
        f_02d6_dep_summary
    )
))

cat(sprintf(
    "Flat summary       : %s\n",
    basename(
        f_02d6_flat_summary
    )
))

cat(sprintf(
    "Escape edges       : %s\n",
    basename(
        f_02d6_edges
    )
))

cat(sprintf(
    "Gate -> flat       : %s\n",
    basename(
        f_02d6_gate_flat
    )
))

cat("=========================================\n")


# ------------------------------------------------------------
# 137. HARD QA
# ------------------------------------------------------------

stopifnot(
    # Every target depression must occur exactly once.
    n_dep_02d6 ==
        length(level_dep_ids),

    !anyDuplicated(
        dep_flat_summary$
            depression_component_id
    ),

    # Core flat-trace requirement.
    n_untraced == 0
)

cat("\n02D.6 HARD QA: PASS\n")


# ============================================================
# 02D.7A - NON-RAISED LAKE COVERAGE
#
# Tavoite:
# - varmista että kaikki ei-spill-raised järvet ovat mukana
# - luokittele olemassa olevan 02D.3 evidence-aineiston perusteella
#   suora vesikontakti / LAND_ONLY / EDGE_CASE
# - tunnista järvet, jotka tarvitsevat seuraavassa vaiheessa
#   LAND-tracen
# - pidä 111137 partial-raise-erikoistapaus näkyvissä
#
# EI outlet-valintaa.
# EI D8-muutoksia.
# EI flow accumulationia.
# ============================================================


# ------------------------------------------------------------
# 138. LAKE SETS
# ------------------------------------------------------------

all_lakes_02d7 <- sort(
    unique(
        lake_depression_summary$lake_objectid
    )
)

raised_ids <- sort(
    unique(
        lake_depression_summary$lake_objectid[
            lake_depression_summary$spill_raised
        ]
    )
)

nonraised_ids <- setdiff(
    all_lakes_02d7,
    raised_ids
)

stopifnot(
    length(all_lakes_02d7) == 108,
    length(raised_ids) == 49,
    length(nonraised_ids) == 59
)


# ------------------------------------------------------------
# 139. BASE TABLE
# ------------------------------------------------------------

nonraised_base <- lake_depression_summary[
    lake_depression_summary$lake_objectid %in%
        nonraised_ids,
    c(
        "lake_objectid",
        "depression_status"
    ),
    drop = FALSE
]

nonraised_base <- nonraised_base[
    order(
        nonraised_base$lake_objectid
    ),
    ,
    drop = FALSE
]

stopifnot(
    nrow(nonraised_base) == 59,
    !anyDuplicated(
        nonraised_base$lake_objectid
    )
)


# ------------------------------------------------------------
# 140. SUMMARISE LOW-SPILL EVIDENCE BY LAKE
# ------------------------------------------------------------

nonraised_evidence_list <- vector(
    "list",
    length(nonraised_ids)
)

for (i in seq_along(nonraised_ids)) {

    lid <- nonraised_ids[i]

    gx <- target_evidence[
        target_evidence$lake_objectid == lid,
        ,
        drop = FALSE
    ]

    stopifnot(
        nrow(gx) > 0
    )

    nonraised_evidence_list[[i]] <- data.frame(

        lake_objectid =
            lid,

        n_low_groups =
            nrow(gx),

        n_lower_lake_groups =
            sum(
                gx$evidence_class ==
                    "LOWER_OTHER_LAKE"
            ),

        n_river_groups =
            sum(
                gx$evidence_class ==
                    "RIVER_CONTACT"
            ),

        n_multi_water_groups =
            sum(
                gx$evidence_class ==
                    "MULTI_WATER_CONTACT"
            ),

        n_land_only_groups =
            sum(
                gx$evidence_class ==
                    "LAND_ONLY"
            ),

        n_edge_groups =
            sum(
                gx$evidence_class ==
                    "EDGE_CASE"
            ),

        stringsAsFactors = FALSE
    )
}

nonraised_evidence <- do.call(
    rbind,
    nonraised_evidence_list
)

row.names(
    nonraised_evidence
) <- NULL


# ------------------------------------------------------------
# 141. JOIN + CLASSIFY
# ------------------------------------------------------------

nonraised_summary <- merge(
    nonraised_base,
    nonraised_evidence,
    by = "lake_objectid",
    all.x = TRUE,
    sort = TRUE
)

stopifnot(
    nrow(nonraised_summary) == 59,
    !anyDuplicated(
        nonraised_summary$lake_objectid
    ),
    all(
        is.finite(
            nonraised_summary$n_low_groups
        )
    )
)

nonraised_summary$has_direct_water <- (
    nonraised_summary$n_lower_lake_groups +
        nonraised_summary$n_river_groups +
        nonraised_summary$n_multi_water_groups
) > 0

nonraised_summary$needs_land_trace <- (
    nonraised_summary$n_land_only_groups > 0 |
        nonraised_summary$n_edge_groups > 0
)

nonraised_summary$lake_class <-
    "UNCLASSIFIED"

nonraised_summary$lake_class[
    nonraised_summary$has_direct_water &
        nonraised_summary$n_land_only_groups == 0 &
        nonraised_summary$n_edge_groups == 0
] <- "DIRECT_WATER_ONLY"

nonraised_summary$lake_class[
    nonraised_summary$has_direct_water &
        nonraised_summary$n_land_only_groups > 0
] <- "DIRECT_WATER_AND_LAND"

nonraised_summary$lake_class[
    !nonraised_summary$has_direct_water &
        nonraised_summary$n_land_only_groups > 0 &
        nonraised_summary$n_edge_groups > 0
] <- "LAND_AND_EDGE"

nonraised_summary$lake_class[
    !nonraised_summary$has_direct_water &
        nonraised_summary$n_land_only_groups > 0 &
        nonraised_summary$n_edge_groups == 0
] <- "LAND_ONLY"

nonraised_summary$lake_class[
    !nonraised_summary$has_direct_water &
        nonraised_summary$n_land_only_groups == 0 &
        nonraised_summary$n_edge_groups > 0
] <- "EDGE_ONLY"


# ------------------------------------------------------------
# 142. REVIEW SETS
# ------------------------------------------------------------

land_trace_lakes <- nonraised_summary[
    nonraised_summary$needs_land_trace,
    ,
    drop = FALSE
]

partial_raise <- nonraised_summary[
    nonraised_summary$depression_status ==
        "PARTIAL_RAISE_NO_SPILL_RAISE",
    ,
    drop = FALSE
]


# ------------------------------------------------------------
# 143. SAVE
# ------------------------------------------------------------

f_02d7_nonraised <- file.path(
    DIR_02,
    "02D7_nonraised_lake_coverage.csv"
)

f_02d7_land_trace <- file.path(
    DIR_02,
    "02D7_nonraised_land_trace_lakes.csv"
)

f_02d7_partial_raise <- file.path(
    DIR_02,
    "02D7_nonraised_partial_raise_cases.csv"
)

write.csv(
    nonraised_summary,
    f_02d7_nonraised,
    row.names = FALSE
)

write.csv(
    land_trace_lakes,
    f_02d7_land_trace,
    row.names = FALSE
)

write.csv(
    partial_raise,
    f_02d7_partial_raise,
    row.names = FALSE
)


# ------------------------------------------------------------
# 144. PRINT
# ------------------------------------------------------------

cat("\n")
cat("=== 02D.7A NON-RAISED LAKE COVERAGE ===\n")

cat(sprintf(
    "All lakes                  : %d\n",
    length(all_lakes_02d7)
))

cat(sprintf(
    "Spill-raised lakes         : %d\n",
    length(raised_ids)
))

cat(sprintf(
    "Non-raised lakes           : %d\n",
    length(nonraised_ids)
))

cat(sprintf(
    "Direct-water only          : %d\n",
    sum(
        nonraised_summary$lake_class ==
            "DIRECT_WATER_ONLY"
    )
))

cat(sprintf(
    "Direct-water + LAND        : %d\n",
    sum(
        nonraised_summary$lake_class ==
            "DIRECT_WATER_AND_LAND"
    )
))

cat(sprintf(
    "LAND_ONLY                  : %d\n",
    sum(
        nonraised_summary$lake_class ==
            "LAND_ONLY"
    )
))

cat(sprintf(
    "LAND + EDGE                : %d\n",
    sum(
        nonraised_summary$lake_class ==
            "LAND_AND_EDGE"
    )
))

cat(sprintf(
    "EDGE_ONLY                  : %d\n",
    sum(
        nonraised_summary$lake_class ==
            "EDGE_ONLY"
    )
))

cat(sprintf(
    "UNCLASSIFIED               : %d\n",
    sum(
        nonraised_summary$lake_class ==
            "UNCLASSIFIED"
    )
))

cat(sprintf(
    "Lakes requiring LAND trace : %d\n",
    nrow(
        land_trace_lakes
    )
))

cat(sprintf(
    "Partial-raise special cases: %d\n",
    nrow(
        partial_raise
    )
))

cat("\n--- LAKE CLASS ---\n")

print(
    table(
        nonraised_summary$lake_class,
        useNA = "ifany"
    )
)

cat("\n--- PARTIAL-RAISE CASES ---\n")

if (nrow(partial_raise) == 0) {

    cat("NONE\n")

} else {

    print(
        partial_raise,
        row.names = FALSE
    )
}

cat("\n--- NON-RAISED LAKES REQUIRING LAND TRACE ---\n")

print(
    land_trace_lakes[
        ,
        c(
            "lake_objectid",
            "depression_status",
            "n_low_groups",
            "n_lower_lake_groups",
            "n_river_groups",
            "n_land_only_groups",
            "n_edge_groups",
            "lake_class"
        )
    ],
    row.names = FALSE
)

cat("==========================================\n")


# ------------------------------------------------------------
# 145. HARD QA
# ------------------------------------------------------------

stopifnot(
    sum(
        nonraised_summary$lake_class ==
            "DIRECT_WATER_ONLY"
    ) == 1,

    sum(
        nonraised_summary$lake_class ==
            "DIRECT_WATER_AND_LAND"
    ) == 8,

    sum(
        nonraised_summary$lake_class ==
            "LAND_ONLY"
    ) == 48,

    sum(
        nonraised_summary$lake_class ==
            "LAND_AND_EDGE"
    ) == 2,

    sum(
        nonraised_summary$lake_class ==
            "EDGE_ONLY"
    ) == 0,

    sum(
        nonraised_summary$lake_class ==
            "UNCLASSIFIED"
    ) == 0,

    nrow(
        land_trace_lakes
    ) == 58,

    nrow(
        partial_raise
    ) == 1,

    partial_raise$lake_objectid == 111137
)

cat("\n02D.7A HARD QA: PASS\n")


# ============================================================
# 02D.7B - NON-RAISED LAND SEED INVENTORY
#
# Tavoite:
# - inventoi 02D.7A:n LAND-tracea tarvitsevien järvien
#   LAND_ONLY spill-ryhmien ulkopuoliset LAND-vastaanottajat
# - tarkista diagnostic D8 pointer näissä seed-soluissa
# - erottele:
#     VALID_D8 / ZERO / NA / INVALID
# - katso vain ENSIMMÄINEN D8-askel ilman reitityspäätöstä
# - liitä pointer=0-solut olemassa olevaan 02C-komponentti-QA:han
#
# Tämä on pelkkä diagnostiikka.
# EI outlet-valintaa.
# EI pointer-muutoksia.
# EI flow accumulationia.
# ============================================================


# ------------------------------------------------------------
# 146. TARGET LAND_ONLY SPILL GROUPS
# ------------------------------------------------------------

land_trace_ids <- sort(
    unique(
        land_trace_lakes$lake_objectid
    )
)

land_only_groups_02d7b <- target_evidence[
    target_evidence$lake_objectid %in%
        land_trace_ids &
        target_evidence$evidence_class ==
            "LAND_ONLY",
    c(
        "spill_group_id",
        "lake_objectid"
    ),
    drop = FALSE
]

land_only_groups_02d7b <- unique(
    land_only_groups_02d7b
)

stopifnot(
    length(land_trace_ids) == 58,
    nrow(land_only_groups_02d7b) > 0,
    !anyDuplicated(
        land_only_groups_02d7b$spill_group_id
    )
)

lakes_with_land_groups_02d7b <- sort(
    unique(
        land_only_groups_02d7b$lake_objectid
    )
)

stopifnot(
    identical(
        lakes_with_land_groups_02d7b,
        land_trace_ids
    )
)


# ------------------------------------------------------------
# 147. LAND RECEIVER SEEDS
# ------------------------------------------------------------

land_edges_02d7b <- low_shore_edges[
    low_shore_edges$spill_group_id %in%
        land_only_groups_02d7b$spill_group_id &
        low_shore_edges$receiver_type ==
            "LAND",
    ,
    drop = FALSE
]

stopifnot(
    nrow(land_edges_02d7b) > 0
)

land_seed_inventory <- unique(
    land_edges_02d7b[
        ,
        c(
            "spill_group_id",
            "lake_objectid",
            "receiver_cell"
        ),
        drop = FALSE
    ]
)

names(
    land_seed_inventory
)[
    names(land_seed_inventory) ==
        "receiver_cell"
] <- "seed_cell"

land_seed_inventory <- land_seed_inventory[
    order(
        land_seed_inventory$lake_objectid,
        land_seed_inventory$spill_group_id,
        land_seed_inventory$seed_cell
    ),
    ,
    drop = FALSE
]

row.names(
    land_seed_inventory
) <- NULL

stopifnot(
    nrow(land_seed_inventory) > 0,
    all(
        land_seed_inventory$seed_cell >= 1 &
            land_seed_inventory$seed_cell <=
                ncell(ptr_land_water)
    )
)


# ------------------------------------------------------------
# 148. SEED ELEVATION / EDGE / POINTER
# ------------------------------------------------------------

land_seed_inventory$seed_storage_z_m <-
    cell_values(
        surface_storage,
        land_seed_inventory$seed_cell
    )

land_seed_inventory$seed_land_water_z_m <-
    cell_values(
        surface_land_water,
        land_seed_inventory$seed_cell
    )

land_seed_inventory$touches_raster_edge <-
    is_edge_cell(
        ptr_land_water,
        land_seed_inventory$seed_cell
    )

seed_pointer <- cell_values(
    ptr_land_water,
    land_seed_inventory$seed_cell
)

land_seed_inventory$d8_code <-
    seed_pointer

land_seed_inventory$pointer_status <-
    "INVALID"

land_seed_inventory$pointer_status[
    !is.finite(seed_pointer)
] <- "NA"

land_seed_inventory$pointer_status[
    is.finite(seed_pointer) &
        seed_pointer == 0
] <- "ZERO"

land_seed_inventory$pointer_status[
    is.finite(seed_pointer) &
        seed_pointer %in%
            valid_pointer_codes
] <- "VALID_D8"


# ------------------------------------------------------------
# 149. MAP ZERO POINTER SEEDS TO 02C COMPONENTS
# ------------------------------------------------------------

land_seed_inventory$zero_component_id <-
    NA_integer_

land_seed_inventory$zero_component_status <-
    NA_character_

land_seed_inventory$zero_target_lake_objectid <-
    NA_integer_

is_zero_seed <- (
    land_seed_inventory$pointer_status ==
        "ZERO"
)

if (any(is_zero_seed)) {

    zero_match <- match(
        land_seed_inventory$seed_cell[
            is_zero_seed
        ],
        zero_table$cell
    )

    stopifnot(
        all(
            !is.na(
                zero_match
            )
        )
    )

    zero_component_id <- zero_table$component_id[
        zero_match
    ]

    land_seed_inventory$zero_component_id[
        is_zero_seed
    ] <- as.integer(
        zero_component_id
    )

    comp_match <- match(
        zero_component_id,
        component_summary$component_id
    )

    stopifnot(
        all(
            !is.na(
                comp_match
            )
        )
    )

    land_seed_inventory$zero_component_status[
        is_zero_seed
    ] <- component_summary$connector_status[
        comp_match
    ]

    land_seed_inventory$zero_target_lake_objectid[
        is_zero_seed
    ] <- as.integer(
        component_summary$target_lake_objectid[
            comp_match
        ]
    )
}


# ------------------------------------------------------------
# 150. FIRST D8 STEP FROM VALID LAND SEEDS
# ------------------------------------------------------------

n_seed_02d7b <- nrow(
    land_seed_inventory
)

land_seed_inventory$next_cell <-
    NA_integer_

land_seed_inventory$next_type <-
    NA_character_

land_seed_inventory$next_water_class <-
    NA_integer_

land_seed_inventory$next_lake_objectid <-
    NA_integer_

is_valid_seed <- (
    land_seed_inventory$pointer_status ==
        "VALID_D8"
)

if (any(is_valid_seed)) {

    idx <- which(
        is_valid_seed
    )

    src <- land_seed_inventory$seed_cell[
        idx
    ]

    p <- as.integer(
        land_seed_inventory$d8_code[
            idx
        ]
    )

    rc <- rowColFromCell(
        ptr_land_water,
        src
    )

    rr <- rc[, 1] +
        unname(
            dr[
                as.character(p)
            ]
        )

    cc <- rc[, 2] +
        unname(
            dc[
                as.character(p)
            ]
        )

    inside <- (
        rr >= 1 &
            rr <= nrow(ptr_land_water) &
            cc >= 1 &
            cc <= ncol(ptr_land_water)
    )

    land_seed_inventory$next_type[
        idx[!inside]
    ] <- "DOMAIN_EXIT"

    if (any(inside)) {

        next_cells <- cellFromRowCol(
            ptr_land_water,
            rr[inside],
            cc[inside]
        )

        inside_idx <- idx[
            inside
        ]

        land_seed_inventory$next_cell[
            inside_idx
        ] <- as.integer(
            next_cells
        )

        next_water <- cell_values(
            water_class,
            next_cells
        )

        next_lake <- cell_values(
            lake_id,
            next_cells
        )

        land_seed_inventory$next_water_class[
            inside_idx
        ] <- as.integer(
            next_water
        )

        is_land_next <- !is.finite(
            next_water
        )

        land_seed_inventory$next_type[
            inside_idx[
                is_land_next
            ]
        ] <- "LAND"

        is_lake_next <- (
            is.finite(next_water) &
                next_water == 1
        )

        if (any(is_lake_next)) {

            lake_idx <- inside_idx[
                is_lake_next
            ]

            lake_values <- as.integer(
                next_lake[
                    is_lake_next
                ]
            )

            stopifnot(
                all(
                    is.finite(
                        lake_values
                    )
                )
            )

            land_seed_inventory$next_lake_objectid[
                lake_idx
            ] <- lake_values

            is_origin <- (
                lake_values ==
                    land_seed_inventory$lake_objectid[
                        lake_idx
                    ]
            )

            land_seed_inventory$next_type[
                lake_idx[
                    is_origin
                ]
            ] <- "ORIGIN_LAKE"

            land_seed_inventory$next_type[
                lake_idx[
                    !is_origin
                ]
            ] <- "OTHER_LAKE"
        }

        land_seed_inventory$next_type[
            inside_idx[
                is.finite(next_water) &
                    next_water == 2
            ]
        ] <- "RIVER_AREA"

        land_seed_inventory$next_type[
            inside_idx[
                is.finite(next_water) &
                    next_water == 3
            ]
        ] <- "RIVER_LINE"

        unexpected_water <- (
            is.finite(next_water) &
                !next_water %in%
                    c(
                        1,
                        2,
                        3
                    )
        )

        land_seed_inventory$next_type[
            inside_idx[
                unexpected_water
            ]
        ] <- "UNKNOWN_WATER_CLASS"
    }
}

land_seed_inventory$next_type[
    land_seed_inventory$pointer_status ==
        "ZERO"
] <- "ZERO_POINTER"

land_seed_inventory$next_type[
    land_seed_inventory$pointer_status ==
        "NA"
] <- "POINTER_NA"

land_seed_inventory$next_type[
    land_seed_inventory$pointer_status ==
        "INVALID"
] <- "POINTER_INVALID"

stopifnot(
    all(
        !is.na(
            land_seed_inventory$next_type
        )
    )
)


# ------------------------------------------------------------
# 151. GROUP SUMMARY
# ------------------------------------------------------------

land_group_ids_02d7b <- sort(
    unique(
        land_seed_inventory$spill_group_id
    )
)

land_group_summary_list <- vector(
    "list",
    length(land_group_ids_02d7b)
)

for (i in seq_along(land_group_ids_02d7b)) {

    gid <- land_group_ids_02d7b[i]

    gx <- land_seed_inventory[
        land_seed_inventory$spill_group_id == gid,
        ,
        drop = FALSE
    ]

    stopifnot(
        nrow(gx) > 0,
        length(
            unique(
                gx$lake_objectid
            )
        ) == 1
    )

    land_group_summary_list[[i]] <- data.frame(

        spill_group_id =
            gid,

        lake_objectid =
            gx$lake_objectid[1],

        n_seed_cells =
            nrow(gx),

        n_valid_d8 =
            sum(
                gx$pointer_status ==
                    "VALID_D8"
            ),

        n_zero =
            sum(
                gx$pointer_status ==
                    "ZERO"
            ),

        n_pointer_na =
            sum(
                gx$pointer_status ==
                    "NA"
            ),

        n_pointer_invalid =
            sum(
                gx$pointer_status ==
                    "INVALID"
            ),

        n_next_land =
            sum(
                gx$next_type ==
                    "LAND"
            ),

        n_next_origin_lake =
            sum(
                gx$next_type ==
                    "ORIGIN_LAKE"
            ),

        n_next_other_lake =
            sum(
                gx$next_type ==
                    "OTHER_LAKE"
            ),

        n_next_river_area =
            sum(
                gx$next_type ==
                    "RIVER_AREA"
            ),

        n_next_river_line =
            sum(
                gx$next_type ==
                    "RIVER_LINE"
            ),

        n_domain_exit =
            sum(
                gx$next_type ==
                    "DOMAIN_EXIT"
            ),

        n_zero_safe =
            sum(
                gx$pointer_status ==
                    "ZERO" &
                    gx$zero_component_status ==
                        "SAFE_LAKE_CONNECTOR",
                na.rm = TRUE
            ),

        n_zero_edge =
            sum(
                gx$pointer_status ==
                    "ZERO" &
                    gx$zero_component_status ==
                        "EDGE_CASE",
                na.rm = TRUE
            ),

        n_zero_review =
            sum(
                gx$pointer_status ==
                    "ZERO" &
                    gx$zero_component_status ==
                        "INTERIOR_REVIEW",
                na.rm = TRUE
            ),

        stringsAsFactors = FALSE
    )
}

land_group_summary_02d7b <- do.call(
    rbind,
    land_group_summary_list
)

row.names(
    land_group_summary_02d7b
) <- NULL


# ------------------------------------------------------------
# 152. LAKE SUMMARY
# ------------------------------------------------------------

land_lake_summary_list <- vector(
    "list",
    length(land_trace_ids)
)

for (i in seq_along(land_trace_ids)) {

    lid <- land_trace_ids[i]

    gx <- land_seed_inventory[
        land_seed_inventory$lake_objectid == lid,
        ,
        drop = FALSE
    ]

    stopifnot(
        nrow(gx) > 0
    )

    land_lake_summary_list[[i]] <- data.frame(

        lake_objectid =
            lid,

        n_land_only_groups =
            length(
                unique(
                    gx$spill_group_id
                )
            ),

        n_seed_cells =
            nrow(gx),

        n_valid_d8 =
            sum(
                gx$pointer_status ==
                    "VALID_D8"
            ),

        n_zero =
            sum(
                gx$pointer_status ==
                    "ZERO"
            ),

        n_pointer_na =
            sum(
                gx$pointer_status ==
                    "NA"
            ),

        n_pointer_invalid =
            sum(
                gx$pointer_status ==
                    "INVALID"
            ),

        n_next_land =
            sum(
                gx$next_type ==
                    "LAND"
            ),

        n_next_origin_lake =
            sum(
                gx$next_type ==
                    "ORIGIN_LAKE"
            ),

        n_next_other_lake =
            sum(
                gx$next_type ==
                    "OTHER_LAKE"
            ),

        n_next_river =
            sum(
                gx$next_type %in%
                    c(
                        "RIVER_AREA",
                        "RIVER_LINE"
                    )
            ),

        n_domain_exit =
            sum(
                gx$next_type ==
                    "DOMAIN_EXIT"
            ),

        stringsAsFactors = FALSE
    )
}

land_lake_summary_02d7b <- do.call(
    rbind,
    land_lake_summary_list
)

row.names(
    land_lake_summary_02d7b
) <- NULL


# ------------------------------------------------------------
# 153. SAVE
# ------------------------------------------------------------

f_02d7b_seed_inventory <- file.path(
    DIR_02,
    "02D7B_nonraised_land_seed_inventory.csv"
)

f_02d7b_group_summary <- file.path(
    DIR_02,
    "02D7B_nonraised_land_group_summary.csv"
)

f_02d7b_lake_summary <- file.path(
    DIR_02,
    "02D7B_nonraised_land_lake_summary.csv"
)

write.csv(
    land_seed_inventory,
    f_02d7b_seed_inventory,
    row.names = FALSE
)

write.csv(
    land_group_summary_02d7b,
    f_02d7b_group_summary,
    row.names = FALSE
)

write.csv(
    land_lake_summary_02d7b,
    f_02d7b_lake_summary,
    row.names = FALSE
)


# ------------------------------------------------------------
# 154. PRINT
# ------------------------------------------------------------

cat("\n")
cat("=== 02D.7B NON-RAISED LAND SEED INVENTORY ===\n")

cat(sprintf(
    "LAND-trace lakes             : %d\n",
    length(land_trace_ids)
))

cat(sprintf(
    "LAND_ONLY spill groups       : %d\n",
    nrow(land_only_groups_02d7b)
))

cat(sprintf(
    "Unique group/seed rows       : %d\n",
    n_seed_02d7b
))

cat("\n--- POINTER STATUS ---\n")
print(
    table(
        land_seed_inventory$pointer_status,
        useNA = "ifany"
    )
)

cat("\n--- FIRST D8 STEP ---\n")
print(
    table(
        land_seed_inventory$next_type,
        useNA = "ifany"
    )
)

cat("\n--- ZERO POINTER COMPONENT STATUS ---\n")

if (any(is_zero_seed)) {

    print(
        table(
            land_seed_inventory$zero_component_status[
                is_zero_seed
            ],
            useNA = "ifany"
        )
    )

} else {

    cat("NONE\n")
}

cat(sprintf(
    "\nLakes with at least one ZERO seed : %d\n",
    length(
        unique(
            land_seed_inventory$lake_objectid[
                land_seed_inventory$pointer_status ==
                    "ZERO"
            ]
        )
    )
))

cat(sprintf(
    "Lakes with at least one next-LAND: %d\n",
    length(
        unique(
            land_seed_inventory$lake_objectid[
                land_seed_inventory$next_type ==
                    "LAND"
            ]
        )
    )
))

cat(sprintf(
    "Lakes with origin-lake return    : %d\n",
    length(
        unique(
            land_seed_inventory$lake_objectid[
                land_seed_inventory$next_type ==
                    "ORIGIN_LAKE"
            ]
        )
    )
))

cat(sprintf(
    "Lakes with domain-exit seed      : %d\n",
    length(
        unique(
            land_seed_inventory$lake_objectid[
                land_seed_inventory$next_type ==
                    "DOMAIN_EXIT"
            ]
        )
    )
))

cat("===============================================\n")


# ------------------------------------------------------------
# 155. HARD QA
# ------------------------------------------------------------

stopifnot(
    length(land_trace_ids) == 58,

    identical(
        sort(
            unique(
                land_seed_inventory$lake_objectid
            )
        ),
        land_trace_ids
    ),

    sum(
        land_seed_inventory$pointer_status %in%
            c(
                "VALID_D8",
                "ZERO",
                "NA",
                "INVALID"
            )
    ) ==
        nrow(
            land_seed_inventory
        ),

    !any(
        land_seed_inventory$pointer_status ==
            "ZERO" &
            is.na(
                land_seed_inventory$zero_component_id
            )
    )
)

cat("\n02D.7B HARD QA: PASS\n")


# ============================================================
# 02D.7C - NON-RAISED LAND D8 TRACE
#
# Tavoite:
# - seuraa jokainen 02D.7B LAND seed diagnostisella
#   land+water D8-pointerilla terminaaliin asti
# - erottele terminaalit:
#     RANTA10 water
#     02C zero-pointer component
#     domain exit
#     pointer NA / invalid
#     cycle / max-steps guard
# - luokittele järvikontakti suhteessa alkuperäiseen järveen
#
# Tämä on pelkkä diagnostiikka.
# EI outlet-valintaa.
# EI pointer-muutoksia.
# EI final D8:aa.
# EI flow accumulationia.
# ============================================================


# ------------------------------------------------------------
# 156. TRACE PARAMETERS
# ------------------------------------------------------------

max_trace_steps_02d7c <- 100000L


# ------------------------------------------------------------
# 157. UNIQUE START CELLS
# ------------------------------------------------------------

trace_start_cells_02d7c <- sort(
    unique(
        land_seed_inventory$seed_cell
    )
)

stopifnot(
    length(trace_start_cells_02d7c) > 0
)


# ------------------------------------------------------------
# 158. TRACE ONE LAND SEED
# ------------------------------------------------------------

trace_one_land_seed_02d7c <- function(
    start_cell
) {

    current_cell <- as.integer(
        start_cell
    )

    path <- integer(0)

    terminal_status <- NA_character_
    terminal_cell <- NA_integer_
    terminal_water_class <- NA_integer_
    terminal_lake_objectid <- NA_integer_
    terminal_zero_component_id <- NA_integer_
    terminal_zero_component_status <- NA_character_
    terminal_zero_target_lake_objectid <- NA_integer_
    cycle_length <- 0L

    for (step in 0:max_trace_steps_02d7c) {

        if (
            !is.finite(current_cell) ||
            current_cell < 1L ||
            current_cell > ncell(ptr_land_water)
        ) {

            terminal_status <- "DOMAIN_EXIT"
            break
        }

        cycle_at <- match(
            current_cell,
            path
        )

        if (!is.na(cycle_at)) {

            terminal_status <- "CYCLE"
            terminal_cell <- current_cell
            cycle_length <- as.integer(
                length(path) -
                    cycle_at +
                    1L
            )
            break
        }

        path <- c(
            path,
            current_cell
        )

        current_water <- cell_values(
            water_class,
            current_cell
        )

        if (is.finite(current_water)) {

            terminal_status <- "WATER"
            terminal_cell <- current_cell
            terminal_water_class <- as.integer(
                current_water
            )

            if (
                terminal_water_class == 1L
            ) {

                current_lake <- cell_values(
                    lake_id,
                    current_cell
                )

                stopifnot(
                    is.finite(
                        current_lake
                    )
                )

                terminal_lake_objectid <- as.integer(
                    current_lake
                )
            }

            break
        }

        current_pointer <- cell_values(
            ptr_land_water,
            current_cell
        )

        if (!is.finite(current_pointer)) {

            terminal_status <- "POINTER_NA"
            terminal_cell <- current_cell
            break
        }

        current_pointer <- as.integer(
            current_pointer
        )

        if (current_pointer == 0L) {

            terminal_status <- "ZERO_POINTER"
            terminal_cell <- current_cell

            zero_match <- match(
                current_cell,
                zero_table$cell
            )

            if (!is.na(zero_match)) {

                terminal_zero_component_id <-
                    as.integer(
                        zero_table$component_id[
                            zero_match
                        ]
                    )

                comp_match <- match(
                    terminal_zero_component_id,
                    component_summary$component_id
                )

                if (!is.na(comp_match)) {

                    terminal_zero_component_status <-
                        component_summary$connector_status[
                            comp_match
                        ]

                    terminal_zero_target_lake_objectid <-
                        as.integer(
                            component_summary$target_lake_objectid[
                                comp_match
                            ]
                        )
                }
            }

            break
        }

        if (
            !current_pointer %in%
                valid_pointer_codes
        ) {

            terminal_status <- "POINTER_INVALID"
            terminal_cell <- current_cell
            break
        }

        rc <- rowColFromCell(
            ptr_land_water,
            current_cell
        )

        next_row <- rc[1, 1] +
            unname(
                dr[
                    as.character(
                        current_pointer
                    )
                ]
            )

        next_col <- rc[1, 2] +
            unname(
                dc[
                    as.character(
                        current_pointer
                    )
                ]
            )

        if (
            next_row < 1L ||
            next_row > nrow(ptr_land_water) ||
            next_col < 1L ||
            next_col > ncol(ptr_land_water)
        ) {

            terminal_status <- "DOMAIN_EXIT"
            terminal_cell <- current_cell
            break
        }

        current_cell <- as.integer(
            cellFromRowCol(
                ptr_land_water,
                next_row,
                next_col
            )
        )

        if (
            step ==
                max_trace_steps_02d7c
        ) {

            terminal_status <- "MAX_STEPS"
            terminal_cell <- current_cell
            break
        }
    }

    if (is.na(terminal_status)) {

        terminal_status <- "MAX_STEPS"
        terminal_cell <- current_cell
    }

    path_touch_edge <- if (
        length(path) > 0
    ) {
        any(
            is_edge_cell(
                ptr_land_water,
                path
            )
        )
    } else {
        FALSE
    }

    data.frame(
        seed_cell =
            as.integer(start_cell),

        terminal_status =
            terminal_status,

        terminal_cell =
            as.integer(terminal_cell),

        terminal_water_class =
            as.integer(terminal_water_class),

        terminal_lake_objectid =
            as.integer(terminal_lake_objectid),

        terminal_zero_component_id =
            as.integer(
                terminal_zero_component_id
            ),

        terminal_zero_component_status =
            terminal_zero_component_status,

        terminal_zero_target_lake_objectid =
            as.integer(
                terminal_zero_target_lake_objectid
            ),

        d8_steps =
            max(
                0L,
                length(path) - 1L
            ),

        n_path_cells =
            length(path),

        cycle_length =
            cycle_length,

        touches_raster_edge =
            path_touch_edge,

        stringsAsFactors = FALSE
    )
}


# ------------------------------------------------------------
# 159. TRACE ALL UNIQUE SEEDS
# ------------------------------------------------------------

trace_result_list_02d7c <- vector(
    "list",
    length(trace_start_cells_02d7c)
)

for (i in seq_along(trace_start_cells_02d7c)) {

    if (
        i == 1L ||
        i %% 100L == 0L ||
        i == length(trace_start_cells_02d7c)
    ) {

        cat(sprintf(
            "\r02D.7C trace %d / %d",
            i,
            length(trace_start_cells_02d7c)
        ))
    }

    trace_result_list_02d7c[[i]] <-
        trace_one_land_seed_02d7c(
            trace_start_cells_02d7c[i]
        )
}

cat("\n")

unique_trace_results_02d7c <- do.call(
    rbind,
    trace_result_list_02d7c
)

row.names(
    unique_trace_results_02d7c
) <- NULL

stopifnot(
    nrow(unique_trace_results_02d7c) ==
        length(trace_start_cells_02d7c),

    !anyDuplicated(
        unique_trace_results_02d7c$seed_cell
    ),

    all(
        !is.na(
            unique_trace_results_02d7c$terminal_status
        )
    )
)


# ------------------------------------------------------------
# 160. JOIN TRACE RESULTS BACK TO GROUP/LAKE SEEDS
# ------------------------------------------------------------

trace_seed_results_02d7c <- merge(
    land_seed_inventory,
    unique_trace_results_02d7c,
    by = "seed_cell",
    all.x = TRUE,
    sort = FALSE
)

trace_seed_results_02d7c <- trace_seed_results_02d7c[
    order(
        trace_seed_results_02d7c$lake_objectid,
        trace_seed_results_02d7c$spill_group_id,
        trace_seed_results_02d7c$seed_cell
    ),
    ,
    drop = FALSE
]

row.names(
    trace_seed_results_02d7c
) <- NULL

stopifnot(
    nrow(trace_seed_results_02d7c) ==
        nrow(land_seed_inventory),

    all(
        !is.na(
            trace_seed_results_02d7c$terminal_status
        )
    )
)


# ------------------------------------------------------------
# 161. ORIGIN-RELATIVE TERMINAL CLASS
# ------------------------------------------------------------

trace_seed_results_02d7c$terminal_class <-
    trace_seed_results_02d7c$terminal_status


water_terminal <- (
    trace_seed_results_02d7c$terminal_status ==
        "WATER"
)

trace_seed_results_02d7c$terminal_class[
    water_terminal &
        trace_seed_results_02d7c$terminal_water_class ==
            2L
] <- "RIVER_AREA"

trace_seed_results_02d7c$terminal_class[
    water_terminal &
        trace_seed_results_02d7c$terminal_water_class ==
            3L
] <- "RIVER_LINE"

water_lake_terminal <- (
    water_terminal &
        trace_seed_results_02d7c$terminal_water_class ==
            1L
)

trace_seed_results_02d7c$terminal_class[
    water_lake_terminal &
        trace_seed_results_02d7c$terminal_lake_objectid ==
            trace_seed_results_02d7c$lake_objectid
] <- "ORIGIN_LAKE"

trace_seed_results_02d7c$terminal_class[
    water_lake_terminal &
        trace_seed_results_02d7c$terminal_lake_objectid !=
            trace_seed_results_02d7c$lake_objectid
] <- "OTHER_LAKE"


zero_terminal <- (
    trace_seed_results_02d7c$terminal_status ==
        "ZERO_POINTER"
)

trace_seed_results_02d7c$terminal_class[
    zero_terminal &
        trace_seed_results_02d7c$terminal_zero_component_status ==
            "SAFE_LAKE_CONNECTOR" &
        trace_seed_results_02d7c$terminal_zero_target_lake_objectid ==
            trace_seed_results_02d7c$lake_objectid
] <- "ZERO_SAFE_ORIGIN_LAKE"

trace_seed_results_02d7c$terminal_class[
    zero_terminal &
        trace_seed_results_02d7c$terminal_zero_component_status ==
            "SAFE_LAKE_CONNECTOR" &
        is.finite(
            trace_seed_results_02d7c$terminal_zero_target_lake_objectid
        ) &
        trace_seed_results_02d7c$terminal_zero_target_lake_objectid !=
            trace_seed_results_02d7c$lake_objectid
] <- "ZERO_SAFE_OTHER_LAKE"

trace_seed_results_02d7c$terminal_class[
    zero_terminal &
        trace_seed_results_02d7c$terminal_zero_component_status ==
            "INTERIOR_REVIEW"
] <- "ZERO_INTERIOR_REVIEW"

trace_seed_results_02d7c$terminal_class[
    zero_terminal &
        trace_seed_results_02d7c$terminal_zero_component_status ==
            "EDGE_CASE"
] <- "ZERO_EDGE_CASE"

trace_seed_results_02d7c$terminal_class[
    zero_terminal &
        (
            is.na(
                trace_seed_results_02d7c$terminal_zero_component_status
            ) |
            !trace_seed_results_02d7c$terminal_zero_component_status %in%
                c(
                    "SAFE_LAKE_CONNECTOR",
                    "INTERIOR_REVIEW",
                    "EDGE_CASE"
                )
        )
] <- "ZERO_UNCLASSIFIED"


# ------------------------------------------------------------
# 162. LAKE SUMMARY
# ------------------------------------------------------------

trace_lake_ids_02d7c <- sort(
    unique(
        trace_seed_results_02d7c$lake_objectid
    )
)

lake_trace_summary_list_02d7c <- vector(
    "list",
    length(trace_lake_ids_02d7c)
)

for (i in seq_along(trace_lake_ids_02d7c)) {

    lid <- trace_lake_ids_02d7c[i]

    gx <- trace_seed_results_02d7c[
        trace_seed_results_02d7c$lake_objectid == lid,
        ,
        drop = FALSE
    ]

    classes <- gx$terminal_class

    lake_trace_summary_list_02d7c[[i]] <- data.frame(

        lake_objectid =
            lid,

        n_seed_rows =
            nrow(gx),

        n_unique_seed_cells =
            length(
                unique(
                    gx$seed_cell
                )
            ),

        max_d8_steps =
            max(
                gx$d8_steps,
                na.rm = TRUE
            ),

        n_origin_lake =
            sum(
                classes ==
                    "ORIGIN_LAKE"
            ),

        n_other_lake =
            sum(
                classes ==
                    "OTHER_LAKE"
            ),

        n_river_area =
            sum(
                classes ==
                    "RIVER_AREA"
            ),

        n_river_line =
            sum(
                classes ==
                    "RIVER_LINE"
            ),

        n_zero_safe_origin =
            sum(
                classes ==
                    "ZERO_SAFE_ORIGIN_LAKE"
            ),

        n_zero_safe_other =
            sum(
                classes ==
                    "ZERO_SAFE_OTHER_LAKE"
            ),

        n_zero_review =
            sum(
                classes ==
                    "ZERO_INTERIOR_REVIEW"
            ),

        n_zero_edge =
            sum(
                classes ==
                    "ZERO_EDGE_CASE"
            ),

        n_zero_unclassified =
            sum(
                classes ==
                    "ZERO_UNCLASSIFIED"
            ),

        n_pointer_na =
            sum(
                classes ==
                    "POINTER_NA"
            ),

        n_pointer_invalid =
            sum(
                classes ==
                    "POINTER_INVALID"
            ),

        n_domain_exit =
            sum(
                classes ==
                    "DOMAIN_EXIT"
            ),

        n_cycle =
            sum(
                classes ==
                    "CYCLE"
            ),

        n_max_steps =
            sum(
                classes ==
                    "MAX_STEPS"
            ),

        touches_raster_edge =
            any(
                gx$touches_raster_edge
            ),

        stringsAsFactors = FALSE
    )
}

lake_trace_summary_02d7c <- do.call(
    rbind,
    lake_trace_summary_list_02d7c
)

row.names(
    lake_trace_summary_02d7c
) <- NULL


# ------------------------------------------------------------
# 163. SAVE
# ------------------------------------------------------------

f_02d7c_unique_trace <- file.path(
    DIR_02,
    "02D7C_nonraised_unique_seed_trace.csv"
)

f_02d7c_seed_results <- file.path(
    DIR_02,
    "02D7C_nonraised_land_trace_seed_results.csv"
)

f_02d7c_lake_summary <- file.path(
    DIR_02,
    "02D7C_nonraised_land_trace_lake_summary.csv"
)

write.csv(
    unique_trace_results_02d7c,
    f_02d7c_unique_trace,
    row.names = FALSE
)

write.csv(
    trace_seed_results_02d7c,
    f_02d7c_seed_results,
    row.names = FALSE
)

write.csv(
    lake_trace_summary_02d7c,
    f_02d7c_lake_summary,
    row.names = FALSE
)


# ------------------------------------------------------------
# 164. PRINT
# ------------------------------------------------------------

cat("\n")
cat("=== 02D.7C NON-RAISED LAND D8 TRACE ===\n")

cat(sprintf(
    "Unique start cells            : %d\n",
    nrow(
        unique_trace_results_02d7c
    )
))

cat(sprintf(
    "Group/seed rows               : %d\n",
    nrow(
        trace_seed_results_02d7c
    )
))

cat(sprintf(
    "Lakes                         : %d\n",
    nrow(
        lake_trace_summary_02d7c
    )
))

cat(sprintf(
    "Maximum D8 steps              : %d\n",
    max(
        unique_trace_results_02d7c$d8_steps,
        na.rm = TRUE
    )
))

cat("\n--- RAW TERMINAL STATUS, UNIQUE SEEDS ---\n")

print(
    table(
        unique_trace_results_02d7c$terminal_status,
        useNA = "ifany"
    )
)

cat("\n--- ORIGIN-RELATIVE TERMINAL CLASS, GROUP/SEED ROWS ---\n")

print(
    table(
        trace_seed_results_02d7c$terminal_class,
        useNA = "ifany"
    )
)

cat(sprintf(
    "\nLakes with ORIGIN_LAKE terminal       : %d\n",
    sum(
        (
            lake_trace_summary_02d7c$n_origin_lake +
                lake_trace_summary_02d7c$n_zero_safe_origin
        ) > 0
    )
))

cat(sprintf(
    "Lakes with OTHER_LAKE terminal        : %d\n",
    sum(
        (
            lake_trace_summary_02d7c$n_other_lake +
                lake_trace_summary_02d7c$n_zero_safe_other
        ) > 0
    )
))

cat(sprintf(
    "Lakes with river terminal             : %d\n",
    sum(
        (
            lake_trace_summary_02d7c$n_river_area +
                lake_trace_summary_02d7c$n_river_line
        ) > 0
    )
))

cat(sprintf(
    "Lakes with zero-pointer review        : %d\n",
    sum(
        (
            lake_trace_summary_02d7c$n_zero_review +
                lake_trace_summary_02d7c$n_zero_edge +
                lake_trace_summary_02d7c$n_zero_unclassified
        ) > 0
    )
))

cat(sprintf(
    "Lakes with pointer/domain/cycle issue : %d\n",
    sum(
        (
            lake_trace_summary_02d7c$n_pointer_na +
                lake_trace_summary_02d7c$n_pointer_invalid +
                lake_trace_summary_02d7c$n_domain_exit +
                lake_trace_summary_02d7c$n_cycle +
                lake_trace_summary_02d7c$n_max_steps
        ) > 0
    )
))

cat("=============================================\n")


# ------------------------------------------------------------
# 165. HARD QA
# ------------------------------------------------------------

stopifnot(
    nrow(trace_seed_results_02d7c) ==
        nrow(land_seed_inventory),

    identical(
        sort(
            unique(
                trace_seed_results_02d7c$lake_objectid
            )
        ),
        land_trace_ids
    ),

    !any(
        is.na(
            trace_seed_results_02d7c$terminal_class
        )
    ),

    sum(
        table(
            trace_seed_results_02d7c$terminal_class
        )
    ) ==
        nrow(
            trace_seed_results_02d7c
        )
)

cat("\n02D.7C HARD QA: PASS\n")


# ============================================================
# 02D.7D - ZERO TERMINAL EVIDENCE
#
# Tavoite:
# - tarkenna 02D.7C:ssa INTERIOR_REVIEW- tai muuten
#   luokittelemattomaan zero-pointer-terminaaliin päätyneet polut
# - inventoi koko 02C zero-komponentin viereiset RANTA10-vesisolut
# - tunnista yksikäsitteinen alin viereinen vesikohde
# - pidä rasterireunan luokittelemattomat zero-solut erillisinä
#
# Tämä tuottaa vain evidenssiä.
# EI outlet-valintaa.
# EI pointer-muutoksia.
# EI final D8:aa.
# EI flow accumulationia.
# ============================================================


# ------------------------------------------------------------
# 166. PARAMETERS
# ------------------------------------------------------------

zero_water_tol_m_02d7d <- 1e-6


# ------------------------------------------------------------
# 167. INTERIOR-REVIEW ZERO COMPONENTS REACHED BY LAND TRACE
# ------------------------------------------------------------

review_zero_rows_02d7d <- trace_seed_results_02d7c[
    trace_seed_results_02d7c$terminal_class ==
        "ZERO_INTERIOR_REVIEW",
    ,
    drop = FALSE
]

review_component_ids_02d7d <- sort(
    unique(
        review_zero_rows_02d7d$terminal_zero_component_id[
            is.finite(
                review_zero_rows_02d7d$terminal_zero_component_id
            )
        ]
    )
)

review_component_evidence_list_02d7d <- vector(
    "list",
    length(review_component_ids_02d7d)
)

review_water_neighbors_list_02d7d <- vector(
    "list",
    length(review_component_ids_02d7d)
)


for (i in seq_along(review_component_ids_02d7d)) {

    cid <- review_component_ids_02d7d[i]

    cx <- component_summary[
        component_summary$component_id == cid,
        ,
        drop = FALSE
    ]

    stopifnot(
        nrow(cx) == 1,
        cx$connector_status ==
            "INTERIOR_REVIEW"
    )

    wn <- water_neighbor_table[
        water_neighbor_table$component_id == cid,
        ,
        drop = FALSE
    ]

    stopifnot(
        nrow(wn) > 0
    )

    wn_unique <- unique(
        wn[
            ,
            c(
                "water_cell",
                "water_class",
                "lake_objectid",
                "water_z_m"
            ),
            drop = FALSE
        ]
    )

    wn_unique <- wn_unique[
        order(
            wn_unique$water_z_m,
            wn_unique$water_class,
            wn_unique$water_cell
        ),
        ,
        drop = FALSE
    ]

    min_water_z <- min(
        wn_unique$water_z_m,
        na.rm = TRUE
    )

    wn_unique$is_min_water <- (
        is.finite(
            wn_unique$water_z_m
        ) &
        abs(
            wn_unique$water_z_m -
                min_water_z
        ) <=
            zero_water_tol_m_02d7d
    )

    wn_unique$target_key <- NA_character_

    wn_unique$target_key[
        wn_unique$water_class == 1 &
        is.finite(
            wn_unique$lake_objectid
        )
    ] <- paste0(
        "LAKE:",
        as.integer(
            wn_unique$lake_objectid[
                wn_unique$water_class == 1 &
                is.finite(
                    wn_unique$lake_objectid
                )
            ]
        )
    )

    wn_unique$target_key[
        wn_unique$water_class == 2
    ] <- "RIVER_AREA"

    wn_unique$target_key[
        wn_unique$water_class == 3
    ] <- "RIVER_LINE"

    min_targets <- sort(
        unique(
            wn_unique$target_key[
                wn_unique$is_min_water &
                !is.na(
                    wn_unique$target_key
                )
            ]
        )
    )

    min_lake_ids <- sort(
        unique(
            as.integer(
                wn_unique$lake_objectid[
                    wn_unique$is_min_water &
                    wn_unique$water_class == 1 &
                    is.finite(
                        wn_unique$lake_objectid
                    )
                ]
            )
        )
    )

    n_min_river_area <- sum(
        wn_unique$is_min_water &
        wn_unique$water_class == 2
    )

    n_min_river_line <- sum(
        wn_unique$is_min_water &
        wn_unique$water_class == 3
    )

    evidence_class <- "AMBIGUOUS_MIN_WATER"
    evidence_target_lake <- NA_integer_

    if (
        length(min_targets) == 1 &&
        length(min_lake_ids) == 1 &&
        n_min_river_area == 0 &&
        n_min_river_line == 0
    ) {

        evidence_class <-
            "UNIQUE_MIN_LAKE"

        evidence_target_lake <-
            min_lake_ids[1]

    } else if (
        length(min_targets) == 1 &&
        length(min_lake_ids) == 0 &&
        n_min_river_area > 0 &&
        n_min_river_line == 0
    ) {

        evidence_class <-
            "UNIQUE_MIN_RIVER_AREA"

    } else if (
        length(min_targets) == 1 &&
        length(min_lake_ids) == 0 &&
        n_min_river_area == 0 &&
        n_min_river_line > 0
    ) {

        evidence_class <-
            "UNIQUE_MIN_RIVER_LINE"
    }

    origin_lakes <- sort(
        unique(
            review_zero_rows_02d7d$lake_objectid[
                review_zero_rows_02d7d$
                    terminal_zero_component_id ==
                    cid
            ]
        )
    )

    review_component_evidence_list_02d7d[[i]] <-
        data.frame(

            component_id =
                cid,

            n_zero_cells =
                cx$n_zero_cells,

            water_signature =
                cx$water_signature,

            adjacent_lake_objectids =
                cx$lake_objectids,

            terminal_min_z_m =
                cx$terminal_min_z_m,

            min_adjacent_water_z_m =
                min_water_z,

            n_unique_water_neighbor_cells =
                nrow(wn_unique),

            n_min_target_keys =
                length(min_targets),

            min_target_keys =
                if (
                    length(min_targets) == 0
                ) {
                    ""
                } else {
                    paste(
                        min_targets,
                        collapse = ";"
                    )
                },

            n_min_lake_objectids =
                length(min_lake_ids),

            min_lake_objectids =
                if (
                    length(min_lake_ids) == 0
                ) {
                    ""
                } else {
                    paste(
                        min_lake_ids,
                        collapse = ";"
                    )
                },

            n_min_river_area =
                n_min_river_area,

            n_min_river_line =
                n_min_river_line,

            trace_origin_lake_objectids =
                if (
                    length(origin_lakes) == 0
                ) {
                    ""
                } else {
                    paste(
                        origin_lakes,
                        collapse = ";"
                    )
                },

            evidence_class =
                evidence_class,

            evidence_target_lake_objectid =
                evidence_target_lake,

            stringsAsFactors = FALSE
        )

    wn_unique$component_id <- cid

    review_water_neighbors_list_02d7d[[i]] <-
        wn_unique[
            ,
            c(
                "component_id",
                "water_cell",
                "water_class",
                "lake_objectid",
                "water_z_m",
                "is_min_water",
                "target_key"
            ),
            drop = FALSE
        ]
}


if (length(review_component_evidence_list_02d7d) > 0) {

    review_component_evidence_02d7d <- do.call(
        rbind,
        review_component_evidence_list_02d7d
    )

    review_water_neighbors_02d7d <- do.call(
        rbind,
        review_water_neighbors_list_02d7d
    )

} else {

    review_component_evidence_02d7d <- data.frame(
        component_id = integer(0),
        n_zero_cells = integer(0),
        water_signature = character(0),
        adjacent_lake_objectids = character(0),
        terminal_min_z_m = numeric(0),
        min_adjacent_water_z_m = numeric(0),
        n_unique_water_neighbor_cells = integer(0),
        n_min_target_keys = integer(0),
        min_target_keys = character(0),
        n_min_lake_objectids = integer(0),
        min_lake_objectids = character(0),
        n_min_river_area = integer(0),
        n_min_river_line = integer(0),
        trace_origin_lake_objectids = character(0),
        evidence_class = character(0),
        evidence_target_lake_objectid = integer(0),
        stringsAsFactors = FALSE
    )

    review_water_neighbors_02d7d <- data.frame()
}


# ------------------------------------------------------------
# 168. UNMAPPED ZERO TERMINALS
# ------------------------------------------------------------

unmapped_zero_rows_02d7d <- trace_seed_results_02d7c[
    trace_seed_results_02d7c$terminal_class ==
        "ZERO_UNCLASSIFIED",
    ,
    drop = FALSE
]

if (nrow(unmapped_zero_rows_02d7d) > 0) {

    unmapped_zero_summary_02d7d <- unique(
        unmapped_zero_rows_02d7d[
            ,
            c(
                "terminal_cell"
            ),
            drop = FALSE
        ]
    )

    names(
        unmapped_zero_summary_02d7d
    )[1] <- "zero_cell"

    unmapped_zero_summary_02d7d$touches_raster_edge <-
        is_edge_cell(
            ptr_land_water,
            unmapped_zero_summary_02d7d$zero_cell
        )

    unmapped_zero_summary_02d7d$evidence_class <-
        ifelse(
            unmapped_zero_summary_02d7d$touches_raster_edge,
            "RASTER_EDGE_CENSORED",
            "UNMAPPED_INTERIOR_ZERO"
        )

} else {

    unmapped_zero_summary_02d7d <- data.frame(
        zero_cell = integer(0),
        touches_raster_edge = logical(0),
        evidence_class = character(0),
        stringsAsFactors = FALSE
    )
}


# ------------------------------------------------------------
# 169. APPLY EVIDENCE TO TRACE ROWS
# ------------------------------------------------------------

trace_zero_evidence_02d7d <-
    trace_seed_results_02d7c

trace_zero_evidence_02d7d$
    refined_terminal_class <-
    trace_zero_evidence_02d7d$
        terminal_class

trace_zero_evidence_02d7d$
    refined_target_lake_objectid <-
    NA_integer_


is_review_terminal_02d7d <- (
    trace_zero_evidence_02d7d$terminal_class ==
        "ZERO_INTERIOR_REVIEW"
)

if (any(is_review_terminal_02d7d)) {

    evidence_match <- match(
        trace_zero_evidence_02d7d$
            terminal_zero_component_id[
                is_review_terminal_02d7d
            ],
        review_component_evidence_02d7d$
            component_id
    )

    stopifnot(
        all(
            !is.na(
                evidence_match
            )
        )
    )

    ev_class <- review_component_evidence_02d7d$
        evidence_class[
            evidence_match
        ]

    ev_lake <- review_component_evidence_02d7d$
        evidence_target_lake_objectid[
            evidence_match
        ]

    review_rows <- which(
        is_review_terminal_02d7d
    )

    unique_min_lake <- (
        ev_class ==
            "UNIQUE_MIN_LAKE" &
        is.finite(
            ev_lake
        )
    )

    if (any(unique_min_lake)) {

        rr <- review_rows[
            unique_min_lake
        ]

        target_lake <- as.integer(
            ev_lake[
                unique_min_lake
            ]
        )

        trace_zero_evidence_02d7d$
            refined_target_lake_objectid[
                rr
            ] <- target_lake

        same_origin <- (
            target_lake ==
                trace_zero_evidence_02d7d$
                    lake_objectid[
                        rr
                    ]
        )

        trace_zero_evidence_02d7d$
            refined_terminal_class[
                rr[
                    same_origin
                ]
            ] <-
            "ZERO_REVIEW_MIN_LAKE_ORIGIN"

        trace_zero_evidence_02d7d$
            refined_terminal_class[
                rr[
                    !same_origin
                ]
            ] <-
            "ZERO_REVIEW_MIN_LAKE_OTHER"
    }

    river_area_rows <- review_rows[
        ev_class ==
            "UNIQUE_MIN_RIVER_AREA"
    ]

    if (length(river_area_rows) > 0) {

        trace_zero_evidence_02d7d$
            refined_terminal_class[
                river_area_rows
            ] <-
            "ZERO_REVIEW_MIN_RIVER_AREA"
    }

    river_line_rows <- review_rows[
        ev_class ==
            "UNIQUE_MIN_RIVER_LINE"
    ]

    if (length(river_line_rows) > 0) {

        trace_zero_evidence_02d7d$
            refined_terminal_class[
                river_line_rows
            ] <-
            "ZERO_REVIEW_MIN_RIVER_LINE"
    }

    ambiguous_rows <- review_rows[
        ev_class ==
            "AMBIGUOUS_MIN_WATER"
    ]

    if (length(ambiguous_rows) > 0) {

        trace_zero_evidence_02d7d$
            refined_terminal_class[
                ambiguous_rows
            ] <-
            "ZERO_REVIEW_AMBIGUOUS"
    }
}


is_unmapped_terminal_02d7d <- (
    trace_zero_evidence_02d7d$terminal_class ==
        "ZERO_UNCLASSIFIED"
)

if (any(is_unmapped_terminal_02d7d)) {

    unmapped_match <- match(
        trace_zero_evidence_02d7d$terminal_cell[
            is_unmapped_terminal_02d7d
        ],
        unmapped_zero_summary_02d7d$zero_cell
    )

    stopifnot(
        all(
            !is.na(
                unmapped_match
            )
        )
    )

    unmapped_class <- unmapped_zero_summary_02d7d$
        evidence_class[
            unmapped_match
        ]

    rr <- which(
        is_unmapped_terminal_02d7d
    )

    trace_zero_evidence_02d7d$
        refined_terminal_class[
            rr[
                unmapped_class ==
                    "RASTER_EDGE_CENSORED"
            ]
        ] <-
        "ZERO_UNMAPPED_EDGE"

    trace_zero_evidence_02d7d$
        refined_terminal_class[
            rr[
                unmapped_class ==
                    "UNMAPPED_INTERIOR_ZERO"
            ]
        ] <-
        "ZERO_UNMAPPED_INTERIOR"
}


# ------------------------------------------------------------
# 170. SAVE
# ------------------------------------------------------------

f_02d7d_component_evidence <- file.path(
    DIR_02,
    "02D7D_review_zero_component_evidence.csv"
)

f_02d7d_water_neighbors <- file.path(
    DIR_02,
    "02D7D_review_zero_water_neighbors.csv"
)

f_02d7d_unmapped_zero <- file.path(
    DIR_02,
    "02D7D_unmapped_zero_terminal_summary.csv"
)

f_02d7d_trace_evidence <- file.path(
    DIR_02,
    "02D7D_trace_zero_evidence.csv"
)

write.csv(
    review_component_evidence_02d7d,
    f_02d7d_component_evidence,
    row.names = FALSE
)

write.csv(
    review_water_neighbors_02d7d,
    f_02d7d_water_neighbors,
    row.names = FALSE
)

write.csv(
    unmapped_zero_summary_02d7d,
    f_02d7d_unmapped_zero,
    row.names = FALSE
)

write.csv(
    trace_zero_evidence_02d7d,
    f_02d7d_trace_evidence,
    row.names = FALSE
)


# ------------------------------------------------------------
# 171. PRINT
# ------------------------------------------------------------

cat("\n")
cat("=== 02D.7D ZERO TERMINAL EVIDENCE ===\n")

cat(sprintf(
    "Interior-review components reached : %d\n",
    nrow(
        review_component_evidence_02d7d
    )
))

if (
    nrow(
        review_component_evidence_02d7d
    ) > 0
) {

    cat("\n--- COMPONENT EVIDENCE ---\n")

    print(
        review_component_evidence_02d7d[
            ,
            c(
                "component_id",
                "water_signature",
                "adjacent_lake_objectids",
                "min_adjacent_water_z_m",
                "min_target_keys",
                "trace_origin_lake_objectids",
                "evidence_class",
                "evidence_target_lake_objectid"
            )
        ],
        row.names = FALSE
    )
}

cat(sprintf(
    "\nUnmapped zero terminal cells      : %d\n",
    nrow(
        unmapped_zero_summary_02d7d
    )
))

cat(sprintf(
    "Unmapped zero cells on edge      : %d\n",
    sum(
        unmapped_zero_summary_02d7d$
            evidence_class ==
            "RASTER_EDGE_CENSORED"
    )
))

cat(sprintf(
    "Unmapped interior zero cells     : %d\n",
    sum(
        unmapped_zero_summary_02d7d$
            evidence_class ==
            "UNMAPPED_INTERIOR_ZERO"
    )
))

cat("\n--- REFINED TERMINAL CLASS ---\n")

print(
    table(
        trace_zero_evidence_02d7d$
            refined_terminal_class,
        useNA = "ifany"
    )
)

remaining_interior_zero_ambiguity_02d7d <- (
    trace_zero_evidence_02d7d$
        refined_terminal_class %in%
        c(
            "ZERO_REVIEW_AMBIGUOUS",
            "ZERO_UNMAPPED_INTERIOR"
        )
)

cat(sprintf(
    "\nSeed rows with interior zero ambiguity : %d\n",
    sum(
        remaining_interior_zero_ambiguity_02d7d
    )
))

cat(sprintf(
    "Lakes with interior zero ambiguity     : %d\n",
    length(
        unique(
            trace_zero_evidence_02d7d$
                lake_objectid[
                    remaining_interior_zero_ambiguity_02d7d
                ]
        )
    )
))

cat(sprintf(
    "Seed rows censored by raster edge      : %d\n",
    sum(
        trace_zero_evidence_02d7d$
            refined_terminal_class ==
            "ZERO_UNMAPPED_EDGE"
    )
))

cat("===========================================\n")


# ------------------------------------------------------------
# 172. HARD QA
# ------------------------------------------------------------

stopifnot(
    nrow(
        trace_zero_evidence_02d7d
    ) ==
        nrow(
            trace_seed_results_02d7c
        ),

    all(
        !is.na(
            trace_zero_evidence_02d7d$
                refined_terminal_class
        )
    ),

    length(
        review_component_ids_02d7d
    ) ==
        nrow(
            review_component_evidence_02d7d
        ),

    !anyDuplicated(
        review_component_evidence_02d7d$
            component_id
    )
)

cat("\n02D.7D HARD QA: PASS\n")


# ============================================================
# 02D.7E - LAND SEED SPILL-LEVEL PARTITION
#
# Tavoite:
# - jaa 02D.7B LAND_ONLY spill-ryhmien seed-solut
#   suhteessa ryhmän spill-tasoon:
#     LOWER / LEVEL / ABOVE
# - erottele ryhmät:
#     LOWER_ONLY
#     LOWER_AND_LEVEL
#     LEVEL_ONLY
#     ABOVE_INVALID
# - tunnista LEVEL-ryhmät, jotka tarvitsevat seuraavaksi
#   eksplisiittisen flat-escape-jäljityksen
#
# Tämä on pelkkä diagnostiikka.
# EI outlet-valintaa.
# EI pointer-muutoksia.
# EI final D8:aa.
# EI flow accumulationia.
# ============================================================


# ------------------------------------------------------------
# 173. JOIN SPILL LEVEL TO LAND SEEDS
# ------------------------------------------------------------

spill_level_lookup_02d7e <- unique(
    target_evidence[
        target_evidence$spill_group_id %in%
            land_only_groups_02d7b$spill_group_id,
        c(
            "spill_group_id",
            "lake_objectid",
            "spill_level_m"
        ),
        drop = FALSE
    ]
)

stopifnot(
    nrow(spill_level_lookup_02d7e) ==
        nrow(land_only_groups_02d7b),

    !anyDuplicated(
        spill_level_lookup_02d7e$spill_group_id
    )
)


land_seed_level_02d7e <- merge(
    land_seed_inventory,
    spill_level_lookup_02d7e,
    by = c(
        "spill_group_id",
        "lake_objectid"
    ),
    all.x = TRUE,
    sort = FALSE
)

land_seed_level_02d7e <- land_seed_level_02d7e[
    order(
        land_seed_level_02d7e$lake_objectid,
        land_seed_level_02d7e$spill_group_id,
        land_seed_level_02d7e$seed_cell
    ),
    ,
    drop = FALSE
]

row.names(
    land_seed_level_02d7e
) <- NULL

stopifnot(
    nrow(land_seed_level_02d7e) ==
        nrow(land_seed_inventory),

    all(
        is.finite(
            land_seed_level_02d7e$spill_level_m
        )
    )
)


# ------------------------------------------------------------
# 174. CLASSIFY EACH SEED AGAINST SPILL LEVEL
# ------------------------------------------------------------

land_seed_level_02d7e$seed_minus_spill_m <-
    land_seed_level_02d7e$seed_storage_z_m -
    land_seed_level_02d7e$spill_level_m

land_seed_level_02d7e$level_relation <-
    "ABOVE"

land_seed_level_02d7e$level_relation[
    land_seed_level_02d7e$seed_storage_z_m <
        land_seed_level_02d7e$spill_level_m -
        escape_tol_m
] <- "LOWER"

land_seed_level_02d7e$level_relation[
    abs(
        land_seed_level_02d7e$seed_storage_z_m -
            land_seed_level_02d7e$spill_level_m
    ) <=
        escape_tol_m
] <- "LEVEL"


# ------------------------------------------------------------
# 175. GROUP SUMMARY
# ------------------------------------------------------------

land_level_group_ids_02d7e <- sort(
    unique(
        land_seed_level_02d7e$spill_group_id
    )
)

land_level_group_list_02d7e <- vector(
    "list",
    length(land_level_group_ids_02d7e)
)

for (i in seq_along(land_level_group_ids_02d7e)) {

    gid <- land_level_group_ids_02d7e[i]

    gx <- land_seed_level_02d7e[
        land_seed_level_02d7e$spill_group_id == gid,
        ,
        drop = FALSE
    ]

    stopifnot(
        nrow(gx) > 0,
        length(
            unique(
                gx$lake_objectid
            )
        ) == 1,
        length(
            unique(
                gx$spill_level_m
            )
        ) == 1
    )

    n_lower <- sum(
        gx$level_relation ==
            "LOWER"
    )

    n_level <- sum(
        gx$level_relation ==
            "LEVEL"
    )

    n_above <- sum(
        gx$level_relation ==
            "ABOVE"
    )

    group_class <- "UNCLASSIFIED"

    if (n_above > 0) {

        group_class <-
            "ABOVE_INVALID"

    } else if (
        n_lower > 0 &&
        n_level > 0
    ) {

        group_class <-
            "LOWER_AND_LEVEL"

    } else if (
        n_lower > 0 &&
        n_level == 0
    ) {

        group_class <-
            "LOWER_ONLY"

    } else if (
        n_lower == 0 &&
        n_level > 0
    ) {

        group_class <-
            "LEVEL_ONLY"
    }

    land_level_group_list_02d7e[[i]] <- data.frame(

        spill_group_id =
            gid,

        lake_objectid =
            gx$lake_objectid[1],

        spill_level_m =
            gx$spill_level_m[1],

        n_seed_cells =
            nrow(gx),

        n_lower =
            n_lower,

        n_level =
            n_level,

        n_above =
            n_above,

        min_seed_minus_spill_m =
            min(
                gx$seed_minus_spill_m,
                na.rm = TRUE
            ),

        max_seed_minus_spill_m =
            max(
                gx$seed_minus_spill_m,
                na.rm = TRUE
            ),

        group_class =
            group_class,

        needs_flat_trace =
            group_class %in%
                c(
                    "LEVEL_ONLY",
                    "LOWER_AND_LEVEL"
                ),

        stringsAsFactors = FALSE
    )
}

land_level_group_summary_02d7e <- do.call(
    rbind,
    land_level_group_list_02d7e
)

row.names(
    land_level_group_summary_02d7e
) <- NULL


# ------------------------------------------------------------
# 176. LAKE SUMMARY
# ------------------------------------------------------------

land_level_lake_ids_02d7e <- sort(
    unique(
        land_level_group_summary_02d7e$lake_objectid
    )
)

land_level_lake_list_02d7e <- vector(
    "list",
    length(land_level_lake_ids_02d7e)
)

for (i in seq_along(land_level_lake_ids_02d7e)) {

    lid <- land_level_lake_ids_02d7e[i]

    gx <- land_level_group_summary_02d7e[
        land_level_group_summary_02d7e$lake_objectid == lid,
        ,
        drop = FALSE
    ]

    land_level_lake_list_02d7e[[i]] <- data.frame(

        lake_objectid =
            lid,

        n_land_only_groups =
            nrow(gx),

        n_lower_only_groups =
            sum(
                gx$group_class ==
                    "LOWER_ONLY"
            ),

        n_lower_and_level_groups =
            sum(
                gx$group_class ==
                    "LOWER_AND_LEVEL"
            ),

        n_level_only_groups =
            sum(
                gx$group_class ==
                    "LEVEL_ONLY"
            ),

        n_above_invalid_groups =
            sum(
                gx$group_class ==
                    "ABOVE_INVALID"
            ),

        n_groups_needing_flat_trace =
            sum(
                gx$needs_flat_trace
            ),

        stringsAsFactors = FALSE
    )
}

land_level_lake_summary_02d7e <- do.call(
    rbind,
    land_level_lake_list_02d7e
)

row.names(
    land_level_lake_summary_02d7e
) <- NULL


# ------------------------------------------------------------
# 177. SAVE
# ------------------------------------------------------------

f_02d7e_seed_level <- file.path(
    DIR_02,
    "02D7E_nonraised_land_seed_level_partition.csv"
)

f_02d7e_group_summary <- file.path(
    DIR_02,
    "02D7E_nonraised_land_group_level_summary.csv"
)

f_02d7e_lake_summary <- file.path(
    DIR_02,
    "02D7E_nonraised_land_lake_level_summary.csv"
)

write.csv(
    land_seed_level_02d7e,
    f_02d7e_seed_level,
    row.names = FALSE
)

write.csv(
    land_level_group_summary_02d7e,
    f_02d7e_group_summary,
    row.names = FALSE
)

write.csv(
    land_level_lake_summary_02d7e,
    f_02d7e_lake_summary,
    row.names = FALSE
)


# ------------------------------------------------------------
# 178. PRINT
# ------------------------------------------------------------

cat("\n")
cat("=== 02D.7E LAND SEED SPILL-LEVEL PARTITION ===\n")

cat(sprintf(
    "LAND_ONLY spill groups       : %d\n",
    nrow(
        land_level_group_summary_02d7e
    )
))

cat(sprintf(
    "Seed rows                    : %d\n",
    nrow(
        land_seed_level_02d7e
    )
))

cat("\n--- SEED LEVEL RELATION ---\n")

print(
    table(
        land_seed_level_02d7e$level_relation,
        useNA = "ifany"
    )
)

cat("\n--- GROUP CLASS ---\n")

print(
    table(
        land_level_group_summary_02d7e$group_class,
        useNA = "ifany"
    )
)

cat(sprintf(
    "\nGroups needing flat trace    : %d\n",
    sum(
        land_level_group_summary_02d7e$
            needs_flat_trace
    )
))

cat(sprintf(
    "Lakes needing flat trace     : %d\n",
    length(
        unique(
            land_level_group_summary_02d7e$
                lake_objectid[
                    land_level_group_summary_02d7e$
                        needs_flat_trace
                ]
        )
    )
))

cat(sprintf(
    "ABOVE seed rows              : %d\n",
    sum(
        land_seed_level_02d7e$level_relation ==
            "ABOVE"
    )
))

cat("================================================\n")


# ------------------------------------------------------------
# 179. HARD QA
# ------------------------------------------------------------

stopifnot(
    nrow(
        land_level_group_summary_02d7e
    ) ==
        265,

    nrow(
        land_seed_level_02d7e
    ) ==
        1967,

    sum(
        land_seed_level_02d7e$level_relation ==
            "LOWER"
    ) ==
        1003,

    sum(
        land_seed_level_02d7e$level_relation ==
            "LEVEL"
    ) ==
        964,

    sum(
        land_seed_level_02d7e$level_relation ==
            "ABOVE"
    ) ==
        0,

    sum(
        land_level_group_summary_02d7e$group_class ==
            "LOWER_ONLY"
    ) ==
        50,

    sum(
        land_level_group_summary_02d7e$group_class ==
            "LOWER_AND_LEVEL"
    ) ==
        7,

    sum(
        land_level_group_summary_02d7e$group_class ==
            "LEVEL_ONLY"
    ) ==
        208,

    sum(
        land_level_group_summary_02d7e$group_class ==
            "ABOVE_INVALID"
    ) ==
        0,

    !any(
        land_level_group_summary_02d7e$group_class ==
            "UNCLASSIFIED"
    )
)

cat("\n02D.7E HARD QA: PASS\n")

source(file.path("R", "02D7F_nonraised_level_flat_trace.R"))


source(file.path("R", "02D7G_candidate_evidence.R"))


source(file.path("R", "02D7H_nonraised_depression_links.R"))

source(file.path("R", "02D7I_non_target_raised_gate_evidence.R"))

# 02D.7J: diagnostic LEVEL-flat trace; no routing or outlet changes.
source(file.path("R", "02D7J_non_target_raised_level_flat_trace.R"))


# 02D.7K: resolve non-target raised links as external vs origin-return evidence.
source(file.path("R", "02D7K_non_target_raised_link_resolution.R"))
