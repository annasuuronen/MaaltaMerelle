# Read-only, bounded LOW 02F real-raster diagnosis; run after synthetic tests.
# Usage: Rscript --vanilla run_roihu_low.R BASELINE_DIR SOURCE_DIR
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: Rscript --vanilla run_roihu_low.R BASELINE_DIR SOURCE_DIR")
}
command <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(command) != 1L) stop("must be run as an Rscript file")
source(file.path(dirname(normalizePath(sub("^--file=", "", command))),
                 "diagnose.R"))
suppressPackageStartupMessages(library(terra))

b <- normalizePath(args[1], mustWork = TRUE)
src <- normalizePath(args[2], mustWork = TRUE)
files <- c(
  dem = file.path(src, "dem_12km_rumpukorjattu.tif"),
  land_raw = file.path(b, "land_dem_raw_FLT8S.tif"),
  land_fill = file.path(b, "land_dem_filled_FLT8S.tif"),
  land_water = file.path(b, "routing_surface_land_water_FLT8S.tif"),
  storage = file.path(b, "routing_surface_water_storage_FLT8S.tif"),
  water_class = file.path(src, "ranta10_water_class.tif"),
  lake_id = file.path(src, "ranta10_lake_id.tif"),
  d8 = file.path(b, "d8_pointer_land_water_FLT8S.tif")
)
if (!all(file.exists(files))) {
  stop("Missing input rasters: ", paste(names(files)[!file.exists(files)], collapse=", "))
}
x <- lapply(files, terra::rast)
p <- x$d8
if (!all(vapply(x, function(v) nlyr(v) == 1L &&
                  compareGeom(p, v, stopOnError = FALSE), logical(1)))) {
  stop("Raster geometry mismatch: refusing diagnostic")
}
route_file <- file.path(b, "02F_water_connected_route_evidence.csv")
if (!file.exists(route_file) || is.na(file.info(route_file)$size) ||
    file.info(route_file)$size > 5 * 1024^2) {
  stop("Route evidence missing or too large")
}
routes <- read.csv(route_file, stringsAsFactors = FALSE)
if (!all(c("route_status", "terminal_cell") %in% names(routes))) {
  stop("Incomplete 02F route evidence")
}
zero_rows <- routes[routes$route_status == "D8_ZERO_INTERIOR", , drop=FALSE]
if (nrow(routes) != 101L || nrow(zero_rows) != 41L ||
    anyNA(zero_rows$terminal_cell)) {
  stop("LOW reference route counts changed: review provenance before re-running")
}
terminals <- sort(unique(as.numeric(zero_rows$terminal_cell)))
expected <- c(10007129L, 10031127L, 15389414L, 15401414L,
              23211319L, 23355315L, 23373314L)
if (!identical(as.integer(terminals), expected)) {
  stop("LOW terminal cell set changed: review provenance")
}
read_window <- function(id, radius) {
  if (radius != 2L) stop("Only bounded radius=2 supported")
  r <- floor((id - 1) / ncol(p)) + 1
  c <- ((id - 1) %% ncol(p)) + 1
  if (r <= 2 || c <= 2 || r >= nrow(p)-1 || c >= ncol(p)-1) {
    stop("Terminal outside safe 5x5 raster window")
  }
  rr <- rep(seq.int(r - 2, r + 2), each=5)
  cc <- rep(seq.int(c - 2, c + 2), times=5)
  out <- data.frame(cell=(rr - 1)*ncol(p) + cc, row=rr, col=cc)
  for (name in names(x)) {
    out[[name]] <- as.numeric(terra::values(
      x[[name]], mat=FALSE, row=r-2, nrows=5,
      col=c-2, ncols=5
    ))
    if (length(out[[name]]) != 25L) stop("Incomplete raster window: ", name)
  }
  out
}

result <- diagnose_shoreline_d8_terminals(
  terminals, read_window, nrow(p), ncol(p), tolerance=1e-7)
q <- result$summary
if (!all(q$LAKE_D8_TO_INTERIOR_ZERO) ||
    !all(q$MASKED_SHORE_FILL_UNCHANGED) ||
    sum(q$FLAT_CONTINUATION_REVIEW) != 1L ||
    q$terminal_cell[q$FLAT_CONTINUATION_REVIEW] != 23373314L ||
    sum(q$incoming_lake_d8) != 10L ||
    any(q$scientific_status != "REVIEW_REQUIRED")) {
  stop("Unexpected LOW shoreline QA result: scientific review required")
}
cat("========== LOW 02F SHORELINE D8 DIAGNOSTIC (READ ONLY) ==========\n")
write.csv(q, stdout(), row.names=FALSE)
cat("========== INCOMING LAKE D8 EDGES ==========\n")
write.csv(result$incoming_lake_edges, stdout(), row.names=FALSE)
cat("========== FLAT NEIGHBOR DOWNHILL EDGES ==========\n")
write.csv(result$flat_downhill_escapes, stdout(), row.names=FALSE)
cat("PASS: LOW 7 terminal evidence reproduced; 41 route records; 10 incoming lake pointers\n")
cat("SCIENTIFIC_STATUS: REVIEW_REQUIRED; NOT SCIENTIFIC D8 PASS\n")
cat("NO DEM / D8 / OUTLET MODIFICATIONS; NATIONAL LOCKED\n")
