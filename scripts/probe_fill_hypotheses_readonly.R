#!/usr/bin/env Rscript
# FUTURE, separately approved local-window diagnostic. No fill, hash scan, D8,
# raster output, cropping, network access or submission. Prints bounded CSV only.
args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% c(4L, 6L)) stop("Expected: LAND_WATER LAKE_ID SUMMARY.csv MAX_VISITS [ROW1:ROW2 COL1:COL2]")
suppressPackageStartupMessages(library(terra))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])
lib <- file.path(dirname(normalizePath(script)), "lib")
source(file.path(lib, "classify_02d5_readiness.R"))
source(file.path(lib, "probe_fill_hypotheses.R"))
if (file.info(args[3L])$size > 5 * 1024^2) stop("Summary exceeds report limit.")
summary <- read.csv(args[3L], colClasses = "character", na.strings = "NA", check.names = FALSE)
classification <- classify_02d5_readiness(summary)
if (!nrow(summary) || any(!classification$per_lake$evidence_consistent)) stop("Incomplete or inconsistent target evidence.")
keep <- classification$per_lake$technical_class == "POSITIVE_THRESHOLD_NO_OBSERVED_RAISE"
targets <- data.frame(lake_objectid = as.numeric(summary$lake_objectid[keep]),
                      n_lake_cells = as.numeric(summary$n_lake_cells[keep]))
w <- rast(args[1L])
l <- rast(args[2L])
stopifnot(nlyr(w) == 1L, nlyr(l) == 1L,
          compareGeom(w, l, stopOnError = FALSE))
origin <- c(1L, 1L)
if (length(args) == 6L) {
  limits <- lapply(args[5:6], function(x) {
    if (!grepl("^[1-9][0-9]*:[1-9][0-9]*$", x)) stop("Window must have exact positive row/column bounds.")
    value <- as.numeric(strsplit(x, ":", fixed = TRUE)[[1L]])
    if (any(!is.finite(value)) || value[2] < value[1]) stop("Invalid window bounds.")
    value
  })
  rr <- limits[[1L]]
  cc <- limits[[2L]]
  stopifnot(rr[2] <= nrow(w), cc[2] <= ncol(w), prod(c(diff(rr) + 1, diff(cc) + 1)) <= 250000L)
  origin <- c(rr[1], cc[1])
  window <- ext(xFromCol(w, cc[1]) - res(w)[1] / 2, xFromCol(w, cc[2]) + res(w)[1] / 2,
                yFromRow(w, rr[2]) - res(w)[2] / 2, yFromRow(w, rr[1]) + res(w)[2] / 2)
  # Lazy, bounded window reads only; neither a whole-raster scan nor file output.
  w <- crop(w, window)
  l <- crop(l, window)
  stopifnot(nrow(w) == diff(rr) + 1, ncol(w) == diff(cc) + 1)
}
stopifnot(ncell(w) <= 250000L)
budget <- suppressWarnings(as.numeric(args[4L]))
result <- probe_fill_hypotheses(as.matrix(w, wide = TRUE), as.matrix(l, wide = TRUE), targets, budget)
for (name in c("seed_row", "witness_from_row", "witness_to_row")) result[[name]] <- result[[name]] + origin[1] - 1
for (name in c("seed_col", "witness_from_col", "witness_to_col")) result[[name]] <- result[[name]] + origin[2] - 1
result$window_origin_row <- origin[1]
result$window_origin_col <- origin[2]
result$window_rows <- nrow(w)
result$window_cols <- ncol(w)
write.csv(result, stdout(), row.names = FALSE, na = "NA")
