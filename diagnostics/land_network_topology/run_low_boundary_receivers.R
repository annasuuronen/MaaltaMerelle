#!/usr/bin/env Rscript
# Source-safe. Exact locked receiver samples only; never a window or route read.
low_boundary_terra_backend <- function() {
  backend <- low_network_terra_backend()
  backend$read_cells <- function(r, cells) {
    # Numeric y means raster cell IDs, NOT coordinates. Prevalidated integer
    # indices avoid extract()'s internal rounding. raw avoids factor labels.
    if (!is.numeric(cells) || length(cells) != 14L || anyDuplicated(cells) ||
        any(!is.finite(cells) | cells != floor(cells) | cells < 1 | cells > terra::ncell(r)))
      stop("INVALID_EXACT_TERRA_CELL_IDS")
    x <- terra::extract(r, as.numeric(cells), raw = TRUE)
    if (is.data.frame(x)) {
      if (ncol(x) != 1L || !is.numeric(x[[1L]])) stop("BAD_EXACT_TERRA_EXTRACT_SCHEMA")
      x <- x[[1L]]
    } else if (is.matrix(x)) {
      if (ncol(x) != 1L || !is.numeric(x)) stop("BAD_EXACT_TERRA_EXTRACT_SCHEMA")
      x <- x[, 1L]
    }
    if (!is.numeric(x) || !is.null(dim(x)) || length(x) != length(cells))
      stop("BAD_EXACT_TERRA_EXTRACT_RESULT")
    x
  }
  backend
}

read_low_boundary_lock <- function(path) {
  path <- low_network_required_file(path, 65536)
  x <- read.csv(path, row.names = NULL, check.names = FALSE, stringsAsFactors = FALSE)
  low_boundary_targets(x, x) # Validate the tracked source report before I/O.
  x
}

run_low_boundary_receivers <- function(baseline_dir, exits, locked_exits,
                                       backend = low_boundary_terra_backend(),
                                       code_revision = "UNKNOWN", emit = TRUE) {
  targets <- low_boundary_targets(exits, locked_exits)
  if (!is.character(code_revision) || length(code_revision) != 1L ||
      is.na(code_revision) || !nzchar(code_revision) ||
      !is.logical(emit) || length(emit) != 1L || is.na(emit)) stop("INVALID_RUN_METADATA")
  if (!is.list(backend) || !is.function(backend$read_cells)) stop("EXACT_CELL_BACKEND_REQUIRED")
  inputs <- low_network_open_inputs(baseline_dir, backend = backend,
                                    expected_full_grid = list(nrow = 6000, ncol = 6000))
  sampled <- read_boundary_cells(inputs$rasters, targets$receivers$cell,
                                 backend$read_cells, ncell = 6000 * 6000)
  samples <- data.frame(receiver_uid = targets$receivers$receiver_uid,
    land_water = sampled$values$land, water_class = sampled$values$water,
    lake_id = sampled$values$lake, pointer = sampled$values$pointer,
    stringsAsFactors = FALSE)
  result <- observe_boundary_receivers(targets, samples)
  result$budget <- sampled[c("read_calls", "unique_cell_positions", "returned_values")]
  result$targets <- targets; result$inputs <- inputs
  result$code_revision <- code_revision
  result$code_version_verification <- "DECLARED_ONLY"
  result$exit_inventory_source_commit <- "40509d5006cbf7fb431701e7a48383dde0fdb38c"
  result$reported_original_inventory_checksum <- "0f39c62a"
  result$original_inventory_checksum_verification <- "USER_REPORTED_FULL_TABLE_NOT_RECOMPUTED"
  result$historical_source_commit <- "UNKNOWN"
  result$historical_provenance <- "INCOMPLETE"
  if (emit) print_low_boundary_receivers(result)
  invisible(result)
}

print_low_boundary_receivers <- function(result) {
  cat("========== TULOKSET ALKAVAT ==========\n")
  cat("MODE=READ_ONLY_LOCKED_14_RECEIVERS NO_WINDOW_READ NO_DOWNSTREAM_TRACE\n")
  cat("COMMIT=", result$code_revision, " CODE_VERSION_VERIFICATION=",
      result$code_version_verification, "\n", sep = "")
  cat("EXIT_INVENTORY_SOURCE_COMMIT=", result$exit_inventory_source_commit,
      " USER_REPORTED_ORIGINAL_ADLER32=", result$reported_original_inventory_checksum, "\n", sep = "")
  cat("ORIGINAL_INVENTORY_CHECKSUM_VERIFICATION=", result$original_inventory_checksum_verification, "\n", sep = "")
  cat("HISTORICAL_SOURCE_COMMIT=UNKNOWN HISTORICAL_PROVENANCE=INCOMPLETE\n")
  cat("GEOMETRY_CHECK=PASS CRS=EPSG:3067 RESOLUTION_M=2 GRID=6000x6000\n")
  for (key in names(result$inputs$files)) cat("RASTER", key, result$inputs$files[[key]], "\n")
  show <- function(label, x) {
    cat(label, "ROWS", nrow(x), "\n")
    print(x, row.names = FALSE, max = nrow(x) * ncol(x) + 1L)
  }
  show("OBSERVED_RECEIVERS", result$receivers)
  show("ORIGINAL_EXIT_TO_RECEIVER_LINKS", result$exit_links)
  show("SHARED_RECEIVER_CELLS", result$receivers[result$receivers$shared_receiver, , drop = FALSE])
  cat("UNIQUE_RECEIVERS", result$n_unique_receivers, "EXIT_LINKS", result$n_exit_links,
      "RASTER_READ_CALLS", result$budget$read_calls,
      "RETURNED_VALUES", result$budget$returned_values, "DOWNSTREAM_STEPS", result$downstream_steps, "\n")
  cat("REPORTED_SOURCE_ROUTE_COUNTS_ARE_NOT_ACCUMULATION\n")
  cat("hydrological_validation=NOT_ASSESSED channel_interpretation=NOT_ASSESSED\n")
  cat("MODERATE=REVIEW_REQUIRED NATIONAL=LOCKED\n")
  cat("========== TULOKSET LOPPUVAT ==========\n")
}

low_boundary_cli <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) > 1L) stop("Usage: Rscript run_low_boundary_receivers.R [BASELINE_DIR]")
  script <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(script) != 1L) stop("Rscript --file= required")
  here <- dirname(normalizePath(sub("^--file=", "", script), mustWork = TRUE))
  repo <- dirname(dirname(here))
  git <- function(args) {
    x <- suppressWarnings(system2("git", c("-C", shQuote(repo), args), stdout = TRUE, stderr = TRUE))
    status <- attr(x, "status")
    if (!is.null(status) && status != 0L) stop("LOCAL_GIT_CHECK_FAILED")
    x
  }
  origin <- git(c("remote", "get-url", "origin"))
  if (length(origin) != 1L || !origin %in% c("https://github.com/annasuuronen/MaaltaMerelle.git",
      "https://github.com/annasuuronen/MaaltaMerelle", "git@github.com:annasuuronen/MaaltaMerelle.git"))
    stop("WRONG_REPOSITORY_ORIGIN")
  commit <- git(c("rev-parse", "HEAD"))
  if (length(commit) != 1L || !grepl("^[0-9a-f]{40}$", commit) ||
      length(git(c("status", "--porcelain", "--untracked-files=normal")))) stop("CLEAN_COMMITTED_CHECKOUT_REQUIRED")
  pin <- Sys.getenv("MM_EXPECTED_COMMIT", unset = "")
  if (nzchar(pin) && (!grepl("^[0-9a-f]{40}$", pin) || pin != commit)) stop("EXPECTED_COMMIT_MISMATCH")
  source(file.path(here, "run_one_low_network_window.R"), local = FALSE)
  source(file.path(here, "boundary_receivers.R"), local = FALSE)
  locked <- read_low_boundary_lock(file.path(here, "low_boundary_receivers_targets.csv"))
  base <- if (length(args)) args[[1L]] else paste0(
    "/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/",
    "runs/E200000_N6900000/02_baseline")
  result <- run_low_boundary_receivers(base, locked, locked, code_revision = commit, emit = FALSE)
  result$code_version_verification <- "LOCAL_GIT_CLEAN"
  print_low_boundary_receivers(result)
  invisible(result)
}

if (sys.nframe() == 0L) low_boundary_cli()
