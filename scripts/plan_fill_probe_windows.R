#!/usr/bin/env Rscript
# Headers and a bounded, streamed ID scan only. Does not read surface values.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 9L)
suppressPackageStartupMessages(library(terra))
cat(R.version.string, " terra=", as.character(packageVersion("terra")), "\n", sep = "")
terraOptions(memmax = 0.25, memfrac = 0.1, tempdir = Sys.getenv("TMPDIR"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])
source(file.path(dirname(normalizePath(script)), "lib", "classify_02d5_readiness.R"))
w <- rast(args[1]); l <- rast(args[2])
q <- read.csv(args[3], colClasses = "character", check.names = FALSE)
out <- args[4]; real <- args[5] == "real"
expected_total <- as.integer(args[6]); expected_positive <- as.integer(args[7])
excluded <- as.numeric(strsplit(args[8], ",", fixed = TRUE)[[1]])
if (identical(args[8], "none")) excluded <- numeric()
max_window <- as.integer(args[9])
stopifnot(is.finite(max_window), max_window >= 9, max_window <= 250000,
          nlyr(w) == 1L, nlyr(l) == 1L, compareGeom(w, l, stopOnError = FALSE),
          ncell(l) <= 36000000, ncol(l) <= 65536, nrow(l) >= 3L, ncol(l) >= 3L,
          !anyDuplicated(names(q)))
if (real) stopifnot(nrow(l) == 6000L, ncol(l) == 6000L,
                    all(res(l) == 2), isTRUE(same.crs(l, "EPSG:3067")))
c <- classify_02d5_readiness(q)
stopifnot(nrow(q) == expected_total, all(c$per_lake$evidence_consistent))
positive <- c$per_lake$technical_class == "POSITIVE_THRESHOLD_NO_OBSERVED_RAISE"
stopifnot(sum(positive) == expected_positive,
          all(excluded %in% as.numeric(q$lake_objectid[positive])),
          all(as.numeric(q$n_raised_lake_cells) == 0),
          all(as.numeric(q$n_depression_components) == 0))
write.csv(c$per_lake, file.path(out, "readiness.csv"), row.names = FALSE)
targets <- q[positive & !as.numeric(q$lake_objectid) %in% excluded, , drop = FALSE]
targets <- targets[order(as.numeric(targets$lake_objectid)), , drop = FALSE]
stopifnot(nrow(targets) >= 1, nrow(targets) <= 49)
ids <- as.numeric(targets$lake_objectid)
count <- numeric(length(ids)); rmin <- cmin <- rep(Inf, length(ids))
rmax <- cmax <- rep(-Inf, length(ids))
block_rows <- max(1L, floor(65536 / ncol(l)))
readStart(l)
tryCatch({
  for (row in seq.int(1L, nrow(l), by = block_rows)) {
    nr <- min(block_rows, nrow(l) - row + 1L)
    v <- as.numeric(readValues(l, row = row, nrows = nr, mat = FALSE))
    stopifnot(length(v) == nr * ncol(l), length(v) <= 65536)
    for (i in seq_along(ids)) {
      at <- which(is.finite(v) & v == ids[i])
      if (!length(at)) next
      rr <- row + (at - 1L) %/% ncol(l)
      cc <- 1L + (at - 1L) %% ncol(l)
      count[i] <- count[i] + length(at)
      rmin[i] <- min(rmin[i], rr); rmax[i] <- max(rmax[i], rr)
      cmin[i] <- min(cmin[i], cc); cmax[i] <- max(cmax[i], cc)
    }
  }
}, finally = readStop(l))
plan <- data.frame(lake_objectid = ids, reported_cells = as.numeric(targets$n_lake_cells),
                   observed_cells = count, row1 = NA_integer_, row2 = NA_integer_,
                   col1 = NA_integer_, col2 = NA_integer_, cells = 0,
                   status = "NOT_CHECKED")
total <- 0
for (i in seq_along(ids)) {
  if (count[i] != plan$reported_cells[i]) {
    plan$status[i] <- "BLOCKED_ID_COUNT_MISMATCH"; next
  }
  if (rmin[i] == 1 || rmax[i] == nrow(l) || cmin[i] == 1 || cmax[i] == ncol(l)) {
    plan$status[i] <- "BLOCKED_UNEXPECTED_DOMAIN_EDGE"; next
  }
  # Include ALL pieces of the ID. Never trim a large bbox to make it pass.
  rr <- c(max(1, rmin[i] - 32), min(nrow(l), rmax[i] + 32))
  cc <- c(max(1, cmin[i] - 32), min(ncol(l), cmax[i] + 32))
  plan[i, c("row1", "row2", "col1", "col2")] <- c(rr, cc)
  n <- prod(c(diff(rr) + 1, diff(cc) + 1)); plan$cells[i] <- n
  if (n > max_window) { plan$status[i] <- "BLOCKED_WINDOW_TOO_LARGE"; next }
  if (total + n > 4000000) { plan$status[i] <- "BLOCKED_TOTAL_CELL_BUDGET"; next }
  total <- total + n
  plan$status[i] <- "PLANNED"
  write.csv(targets[i, , drop = FALSE], file.path(out, paste0("target_", ids[i], ".csv")), row.names = FALSE)
}
write.csv(plan, file.path(out, "windows.csv"), row.names = FALSE, na = "NA")
cat("ID_SCAN_CELLS=", ncell(l), " MAX_BLOCK_CELLS=65536 TARGETS=", length(ids),
    " PLANNED_SURFACE_CELLS=", total, "\n", sep = "")
cat(R.version.string, " terra=", as.character(packageVersion("terra")), "\n", sep = "")
