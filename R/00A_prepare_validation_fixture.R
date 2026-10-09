# ============================================================
# 00A_prepare_validation_fixture.R
#
# Deterministically build canonical RANTA10 fixture inputs for a new
# validation tile on the exact uploaded 2 m DEM grid.
#
# Fixture preparation only: no DEM edits, routing changes, outlet
# selection, D8 edits, or accumulation.
# ============================================================

PROJECT_ROOT <- local({
  override <- Sys.getenv("HYDRO_PROJECT_ROOT", unset = "")
  if (nzchar(override)) {
    normalizePath(override, winslash = "/", mustWork = TRUE)
  } else {
    normalizePath(".", winslash = "/", mustWork = TRUE)
  }
})

source(file.path(PROJECT_ROOT, "R", "00_pipeline_config.R"))

suppressPackageStartupMessages({
  library(terra)
  library(sf)
})

source_gpkg <- Sys.getenv("VALIDATION_SOURCE_GPKG", unset = "")
if (!nzchar(source_gpkg) || !file.exists(source_gpkg)) {
  stop("VALIDATION_SOURCE_GPKG is missing or does not exist.")
}

stopifnot(file.exists(DEM_FILE))
dir.create(SOURCE_TEST_ROOT, recursive = TRUE, showWarnings = FALSE)

dem <- rast(DEM_FILE)
stopifnot(
  ncol(dem) == TEST_NCOL,
  nrow(dem) == TEST_NROW,
  abs(res(dem)[1] - CELL_SIZE_M) < 1e-9,
  abs(res(dem)[2] - CELL_SIZE_M) < 1e-9,
  abs(xmin(dem) - TEST_EXTENT["xmin"]) < 1e-6,
  abs(xmax(dem) - TEST_EXTENT["xmax"]) < 1e-6,
  abs(ymin(dem) - TEST_EXTENT["ymin"]) < 1e-6,
  abs(ymax(dem) - TEST_EXTENT["ymax"]) < 1e-6
)

required_source_layers <- c(
  "ranta10_lakes",
  "ranta10_river_areas",
  "ranta10_river_lines"
)
stopifnot(all(required_source_layers %in% st_layers(source_gpkg)$name))

read_layer <- function(layer) {
  x <- st_read(source_gpkg, layer = layer, quiet = TRUE)
  if (is.na(st_crs(x))) stop(paste("Missing CRS:", layer))
  x <- st_transform(x, CRS_EPSG)
  x <- st_make_valid(x)
  x[!st_is_empty(x), , drop = FALSE]
}

lakes <- read_layer("ranta10_lakes")
river_areas <- read_layer("ranta10_river_areas")
river_lines <- read_layer("ranta10_river_lines")

stopifnot(
  nrow(lakes) == EXPECTED_TEST$lakes,
  nrow(river_areas) == EXPECTED_TEST$river_areas,
  nrow(river_lines) == EXPECTED_TEST$river_lines
)

objectid_field <- names(lakes)[tolower(names(lakes)) == "objectid"]
height_field <- names(lakes)[tolower(names(lakes)) == "korkeus_m"]
stopifnot(length(objectid_field) == 1L, length(height_field) == 1L)

lake_objectid <- suppressWarnings(as.numeric(lakes[[objectid_field]]))
lake_height <- suppressWarnings(as.numeric(lakes[[height_field]]))
stopifnot(
  all(is.finite(lake_objectid)),
  !anyDuplicated(lake_objectid),
  all(is.finite(lake_height))
)

if (file.exists(RANTA10_GPKG)) unlink(RANTA10_GPKG)
st_write(lakes, RANTA10_GPKG, layer = "lakes", quiet = TRUE)
st_write(river_areas, RANTA10_GPKG, layer = "river_areas",
         append = TRUE, quiet = TRUE)
st_write(river_lines, RANTA10_GPKG, layer = "river_lines",
         append = TRUE, quiet = TRUE)

template <- rast(
  nrows = nrow(dem),
  ncols = ncol(dem),
  xmin = xmin(dem),
  xmax = xmax(dem),
  ymin = ymin(dem),
  ymax = ymax(dem),
  crs = crs(dem)
)

lake_id <- rasterize(
  vect(lakes), template,
  field = objectid_field,
  background = NA,
  touches = TRUE
)
river_area_mask <- rasterize(
  vect(river_areas), template,
  field = 1,
  background = NA,
  touches = TRUE
)
river_line_mask <- rasterize(
  vect(river_lines), template,
  field = 1,
  background = NA,
  touches = TRUE
)
water_class <- ifel(
  !is.na(lake_id), 1L,
  ifel(!is.na(river_area_mask), 2L,
       ifel(!is.na(river_line_mask), 3L, NA))
)
water_mask <- ifel(!is.na(water_class), 1L, NA)

f_lake_id <- file.path(SOURCE_TEST_ROOT, "ranta10_lake_id.tif")
f_river_area <- file.path(SOURCE_TEST_ROOT, "ranta10_river_area_mask.tif")
f_river_line <- file.path(SOURCE_TEST_ROOT, "ranta10_river_line_mask.tif")
f_water_class <- file.path(SOURCE_TEST_ROOT, "ranta10_water_class.tif")
f_water_mask <- file.path(SOURCE_TEST_ROOT, "ranta10_water_mask.tif")

writeRaster(lake_id, f_lake_id, overwrite = TRUE, datatype = "INT4S",
            gdal = c("COMPRESS=DEFLATE", "BIGTIFF=YES"))
writeRaster(river_area_mask, f_river_area, overwrite = TRUE, datatype = "INT1U",
            gdal = c("COMPRESS=DEFLATE", "BIGTIFF=YES"))
writeRaster(river_line_mask, f_river_line, overwrite = TRUE, datatype = "INT1U",
            gdal = c("COMPRESS=DEFLATE", "BIGTIFF=YES"))
writeRaster(water_class, f_water_class, overwrite = TRUE, datatype = "INT1U",
            gdal = c("COMPRESS=DEFLATE", "BIGTIFF=YES"))
writeRaster(water_mask, f_water_mask, overwrite = TRUE, datatype = "INT1U",
            gdal = c("COMPRESS=DEFLATE", "BIGTIFF=YES"))

generated <- c(
  f_lake_id, f_river_area, f_river_line, f_water_class, f_water_mask
)
stopifnot(all(vapply(generated, file.exists, logical(1))))
for (f in generated) {
  stopifnot(compareGeom(dem, rast(f), stopOnError = FALSE))
}

raster_ids <- unique(freq(rast(f_lake_id))$value)
raster_ids <- raster_ids[is.finite(raster_ids)]
missing_vector_ids <- setdiff(lake_objectid, raster_ids)
extra_raster_ids <- setdiff(raster_ids, lake_objectid)

qa <- data.frame(
  item = c(
    "test_id", "vector_lakes", "vector_river_areas",
    "vector_river_lines", "lake_ids_raster",
    "vector_lake_ids_missing_from_raster", "extra_lake_ids_in_raster",
    "rasterization_touches"
  ),
  value = c(
    TEST_ID, nrow(lakes), nrow(river_areas), nrow(river_lines),
    length(raster_ids), length(missing_vector_ids),
    length(extra_raster_ids), "TRUE"
  ),
  stringsAsFactors = FALSE
)
write.csv(
  qa,
  file.path(SOURCE_TEST_ROOT, "00A_validation_fixture_QA.csv"),
  row.names = FALSE
)

stopifnot(
  length(missing_vector_ids) == 0L,
  length(extra_raster_ids) == 0L
)

cat("=== 00A VALIDATION FIXTURE PREP PASS ===\n")
print(qa, row.names = FALSE)
