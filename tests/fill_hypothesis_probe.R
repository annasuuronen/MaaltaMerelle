# Bounded matrix and CLI fixtures only; no CSC access or new fill calls.
local({
  source("scripts/lib/probe_fill_hypotheses.R", local = TRUE)
  checks <- 0L
  check <- function(name, ok) {
    stopifnot(isTRUE(ok))
    checks <<- checks + 1L
    cat("PASS bounded fill probe:", name, "\n")
  }
  z <- matrix(12, 7, 7)
  z[c(1, 7), ] <- 8
  z[, c(1, 7)] <- 8
  z[4, 4] <- 10
  ids <- matrix(NA_real_, 7, 7)
  ids[4, 4] <- 101
  targets <- data.frame(lake_objectid = 101, n_lake_cells = 1)
  before <- z
  r <- probe_fill_hypotheses(z, ids, targets)
  check("interior closed-lake minimum is an exact pit candidate", r$exact_local_pit_candidates == 1)
  check("ordinary rim has a local lower-neighbour witness", r$lower_neighbour_witness_found &&
    r$witness_from_z == 12 && r$witness_to_z == 8 && !r$search_touched_window_edge)
  check("no data are changed or outlets approved", identical(z, before) &&
    !r$natural_outlet_verified && !r$actual_whitebox_behaviour_verified && r$national_status == "LOCKED")
  flat <- z
  flat[,] <- 12
  flat[4, 4] <- 10
  r <- probe_fill_hypotheses(flat, ids, targets)
  check("flat outer rim reaches a censored window boundary", !r$lower_neighbour_witness_found &&
    r$search_touched_window_edge && r$diagnostic_status == "CENSORED_LOCAL_SEARCH")
  r <- probe_fill_hypotheses(z, ids, targets, 1)
  check("visit cap censors absence of a witness", r$visit_cap_reached && r$visited_cells == 1 &&
    r$diagnostic_status == "CENSORED_LOCAL_SEARCH")
  separate <- ids
  separate[4, 6] <- 101
  separate_z <- flat
  separate_z[4, 6] <- 10
  two <- data.frame(lake_objectid = 101, n_lake_cells = 2)
  r <- probe_fill_hypotheses(separate_z, separate, two)
  check("disconnected ID parts remain separate", nrow(r) == 2 && all(r$window_mask_components == 2) &&
    all(r$component_cells == 1) && all(r$full_id_cell_count_matches_report))
  r <- probe_fill_hypotheses(z, ids, two)
  check("clipped ID coverage cannot produce a conclusive search", !r$full_id_cell_count_matches_report &&
    r$visited_cells == 0 && r$diagnostic_status == "INCOMPLETE_TARGET_WINDOW")
  absent <- data.frame(lake_objectid = 999, n_lake_cells = 1)
  r <- probe_fill_hypotheses(z, ids, absent)
  check("missing ID is explicit", r$window_mask_components == 0 && is.na(r$component_index) &&
    r$diagnostic_status == "INCOMPLETE_TARGET_WINDOW")
  large <- matrix(NA_real_, 11, 11)
  large[2:10, 2:10] <- 12
  large[6, 6] <- 10
  large[6, 9] <- NA # three cells from the source; NOT an immediate shore neighbour
  large_ids <- matrix(NA_real_, 11, 11)
  large_ids[6, 6] <- 101
  r <- probe_fill_hypotheses(large, large_ids, targets)
  check("distant nonfinite contact distinguished from direct shore NA", r$exact_local_pit_candidates == 1 &&
    r$search_contacted_nodata && !r$search_touched_window_edge &&
    r$diagnostic_status == "NO_LOWER_WITNESS_IN_EXPLORED_FINITE_COMPONENT" && !r$natural_outlet_verified)
  single_na <- z
  single_na[4, 5] <- NA
  r <- probe_fill_hypotheses(single_na, ids, targets)
  check("NoData-adjacent singleton has no exact pit seed", r$exact_local_pit_candidates == 0 &&
    r$diagnostic_status == "NO_EXACT_LOCAL_PIT_CANDIDATE")
  graded <- z
  graded[4, 5] <- 10 - 5e-8
  graded_ids <- ids
  graded_ids[4, 5] <- 101
  r <- probe_fill_hypotheses(graded, graded_ids, two)
  check("within-tolerance lake variation still affects exact Whitebox comparisons", r$exact_local_pit_candidates == 1 &&
    r$seed_row == 4 && r$seed_col == 5)
  boundary <- z
  boundary[,] <- 12
  boundary[1, 4] <- 10
  boundary_ids <- ids
  boundary_ids[,] <- NA
  boundary_ids[1, 4] <- 101
  r <- probe_fill_hypotheses(boundary, boundary_ids, targets)
  check("window-edge seed exclusion is censored, not an original-domain conclusion",
    r$diagnostic_status == "CENSORED_NO_INTERIOR_PIT_CANDIDATE")
  for (budget in c(0, -1, NA, Inf, 20001, 0.5)) {
    error <- tryCatch(probe_fill_hypotheses(z, ids, targets, budget), error = identity)
    check(paste("invalid budget", budget), inherits(error, "error"))
  }
  error <- tryCatch(probe_fill_hypotheses(matrix(1, 501, 501), matrix(NA_real_, 501, 501), targets), error = identity)
  check("oversized windows rejected", inherits(error, "error"))
  # End-to-end stdout-only CLI on a temporary raster pair and synthetic summary.
  suppressPackageStartupMessages(library(terra))
  d <- tempfile("probe-cli-")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  w <- rast(z)
  crs(w) <- "EPSG:3067"
  l <- rast(ids)
  crs(l) <- "EPSG:3067"
  wf <- file.path(d, "window-w.tif")
  lf <- file.path(d, "window-id.tif")
  sf <- file.path(d, "summary.csv")
  writeRaster(w, wf)
  writeRaster(l, lf)
  write.csv(data.frame(lake_objectid = 101, n_lake_cells = 1,
    n_raised_lake_cells = 0, raised_fraction = 0, n_depression_components = 0,
    depression_component_ids = "", spill_raised = TRUE, spill_raise_m = 2,
    storage_raised = FALSE, max_storage_raise_m = 0), sf, row.names = FALSE)
  old <- tools::md5sum(c(wf, lf, sf)) # tiny fixtures only, never real CSC rasters
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", "scripts/probe_fill_hypotheses_readonly.R", shQuote(wf), shQuote(lf), shQuote(sf), "100"),
    stdout = TRUE, stderr = TRUE))
  check("CLI observes a local witness and preserves inputs", is.null(attr(out, "status")) &&
    any(grepl("LOWER_NEIGHBOUR_WITNESS_IN_ISOLATED_SEARCH", out, fixed = TRUE)) &&
    identical(old, tools::md5sum(c(wf, lf, sf))))
  check("CLI writes no output files", setequal(list.files(d), c("window-w.tif", "window-id.tif", "summary.csv")))
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", "scripts/probe_fill_hypotheses_readonly.R", shQuote(wf), shQuote(lf), shQuote(sf), "100", "2:6", "2:6"),
    stdout = TRUE, stderr = TRUE))
  header <- grep('^"lake_objectid"', out)
  stopifnot(length(header) == 1)
  clipped <- read.csv(text = paste(out[c(header, header + 1L)], collapse = "\n"))
  check("explicit windows are censored and preserve original grid coordinates", is.null(attr(out, "status")) &&
    clipped$diagnostic_status == "CENSORED_LOCAL_SEARCH" && clipped$seed_row == 4 && clipped$seed_col == 4 &&
    clipped$window_origin_row == 2 && clipped$window_origin_col == 2 && clipped$window_rows == 5)
  stopifnot(checks > 0)
  cat("Completed", checks, "bounded-probe checks; MODERATE=REVIEW_REQUIRED; NATIONAL=LOCKED.\n")
})
