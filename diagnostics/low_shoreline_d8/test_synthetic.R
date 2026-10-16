# Run from this directory: Rscript --vanilla test_synthetic.R
args <- commandArgs(trailingOnly = FALSE)
script_arg <- grep("^--file=", args, value = TRUE)
if (length(script_arg) != 1L) stop("Run as Rscript test_synthetic.R")
source(file.path(dirname(normalizePath(sub("^--file=", "", script_arg))),
                 "diagnose.R"))

make_window <- function(flat = FALSE, wrong_direction = FALSE,
                        unmasked_lake = FALSE, no_downhill = FALSE,
                        nonzero_terminal = FALSE, corrupted_cell = FALSE) {
  rows <- rep(1:7, each = 7)
  cols <- rep(1:7, times = 7)
  data <- data.frame(
    cell = (rows - 1) * 7 + cols, row = rows, col = cols,
    dem = rep(0.92, 49), land_raw = rep(0.92, 49),
    land_fill = rep(0.92, 49), land_water = rep(0.92, 49),
    storage = rep(0.92, 49), water_class = rep(NA_real_, 49),
    lake_id = rep(NA_real_, 49), d8 = rep(0, 49)
  )
  center <- which(data$row == 4 & data$col == 4)
  lake <- which(data$row == 4 & data$col == 5)
  z <- if (flat) 0.3949002922 else 0.882
  data[center, c("dem", "land_raw", "land_fill", "land_water")] <- z
  data$storage[center] <- if (flat) z else 0.92
  data$water_class[lake] <- 1
  data$lake_id[lake] <- 1894
  data$land_raw[lake] <- NA_real_
  data$land_fill[lake] <- NA_real_
  data$d8[lake] <- if (wrong_direction) 2 else 32
  if (unmasked_lake) data$land_fill[lake] <- 0.92
  if (nonzero_terminal) data$d8[center] <- 32
  if (flat) {
    west <- which(data$row == 4 & data$col == 3)
    west2 <- which(data$row == 4 & data$col == 2)
    data[west, c("dem", "land_raw", "land_fill", "land_water", "storage")] <- z
    data$d8[west] <- 32
    data[west2, c("dem", "land_raw", "land_fill", "land_water", "storage")] <-
      if (no_downhill) z else 0.382
  }
  if (corrupted_cell) {
    # A deliberately invalid cell ID must occur within the returned 5x5
    # window (rows/cols 2:6); cell 1 lies outside the diagnostic window.
    data$cell[data$row == 3L & data$col == 3L] <- 9999
  }
  function(id, radius) {
    stopifnot(id == 25, radius == 2L)
    data[abs(data$row - 4) <= 2 & abs(data$col - 4) <= 2, , drop = FALSE]
  }
}

run_one <- function(reader) diagnose_shoreline_d8_terminals(
  25, reader, nrow_raster = 7, ncol_raster = 7)

sink_case <- run_one(make_window())
stopifnot(nrow(sink_case$summary) == 1,
          sink_case$summary$LAKE_D8_TO_INTERIOR_ZERO,
          sink_case$summary$MASKED_SHORE_FILL_UNCHANGED,
          !sink_case$summary$FLAT_CONTINUATION_REVIEW,
          sink_case$summary$incoming_lake_d8 == 1,
          sink_case$summary$scientific_status == "REVIEW_REQUIRED")
flat_case <- run_one(make_window(flat = TRUE))
stopifnot(flat_case$summary$LAKE_D8_TO_INTERIOR_ZERO,
          flat_case$summary$MASKED_SHORE_FILL_UNCHANGED,
          flat_case$summary$FLAT_CONTINUATION_REVIEW,
          flat_case$summary$flat_downhill_continuations == 1,
          nrow(flat_case$flat_downhill_escapes) == 1,
          flat_case$flat_downhill_escapes$flat_neighbor_cell == 24,
          flat_case$flat_downhill_escapes$lower_receiver_cell == 23)
no_downhill <- run_one(make_window(flat = TRUE, no_downhill = TRUE))
stopifnot(!no_downhill$summary$FLAT_CONTINUATION_REVIEW)
wrong_direction <- run_one(make_window(wrong_direction = TRUE))
stopifnot(!wrong_direction$summary$LAKE_D8_TO_INTERIOR_ZERO,
          wrong_direction$summary$MASKED_SHORE_FILL_UNCHANGED)
unmasked <- run_one(make_window(unmasked_lake = TRUE))
stopifnot(unmasked$summary$LAKE_D8_TO_INTERIOR_ZERO,
          !unmasked$summary$MASKED_SHORE_FILL_UNCHANGED)
corrupt_window <- make_window(corrupted_cell = TRUE)(25, 2L)
stopifnot(9999 %in% corrupt_window$cell)
for (reader in list(make_window(nonzero_terminal = TRUE),
                    make_window(corrupted_cell = TRUE))) {
  err <- tryCatch(run_one(reader), error = identity)
  stopifnot(inherits(err, "error"))
}
cat("PASS: synthetic shoreline D8 QA; lake-to-zero, mask, flat escape, negative controls, fail closed\n")
