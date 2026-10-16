# Small synthetic regressions against selected production expressions.
# Does NOT source the pipeline, read real inputs or select hydrological outlets.
# Optional Whitebox integration: HYDRO_TEST_WHITEBOX_EXE=/verified/binary.
suppressPackageStartupMessages(library(terra))

run_tests <- function() {
  source_path <- file.path("R", "02_build_baseline_hydrology.R")
  lines <- readLines(source_path, warn = FALSE)
  code <- parse(source_path)
  checked <- 0L
  check <- function(name, condition) {
    stopifnot(isTRUE(condition))
    checked <<- checked + 1L
    cat("PASS:", name, "\n")
  }
  section <- function(first, last) {
    a <- grep(first, lines, fixed = TRUE)
    b <- grep(last, lines, fixed = TRUE)
    stopifnot(length(a) == 1L, length(b) == 1L, a < b)
    parse(text = lines[seq.int(a + 1L, b - 1L)])
  }
  assignment <- function(name, expressions = code) {
    found <- list()
    visit <- function(x) {
      if (!is.call(x) && !is.expression(x)) return()
      if (is.call(x) && identical(x[[1L]], as.name("<-")) &&
          identical(x[[2L]], as.name(name))) found[[length(found) + 1L]] <<- x
      indices <- seq_along(x)
      if (is.call(x)) indices <- indices[-1L]
      for (j in indices) {
        if (!identical(x[[j]], quote(expr = ))) visit(x[[j]])
      }
    }
    # Explicit loop avoids dropping the first element of expression vectors.
    for (x in expressions) visit(x)
    stopifnot(length(found) == 1L)
    found[[1L]]
  }
  raster <- function(m) {
    r <- rast(m)
    crs(r) <- "EPSG:3067"
    r
  }
  fixture <- function(kind) {
    m <- matrix(12, 7, 7)
    m[c(1, 7), ] <- 8
    m[, c(1, 7)] <- 8
    ids <- matrix(NA_real_, 7, 7)
    ids[3:5, 3:5] <- 1
    m[3:5, 3:5] <- 10
    if (kind == "edge") {
      ids[,] <- NA_real_
      ids[1, 4] <- 1
      m[3:5, 3:5] <- 12
      m[1, ] <- 12
      m[1, 4] <- 10
    }
    if (kind == "nodata") {
      ids[,] <- NA_real_
      ids[4, 4] <- 1
      m[3:5, 3:5] <- 12
      m[4, 4] <- 10
      m[4, 5] <- NA_real_
    }
    if (kind == "flat_rim") {
      m[,] <- 12
      m[3:5, 3:5] <- 10
    }
    list(surface = raster(m), lake = raster(ids))
  }
  diagnose <- function(f, storage) {
    e <- new.env(parent = environment())
    e$lake_id <- f$lake
    e$surface_land_water <- f$surface
    e$surface_storage <- storage
    e$water_class <- ifel(is.na(f$lake), 0, 1)
    eval(assignment("cell_values"), e)
    eval(section("# 53. ALL LAKE CELLS", "# 61. SAVE FULL INVENTORY"), e)
    eval(section("# 62. PER-LAKE SUMMARY", "f_lake_outlet_summary <-"), e)
    eval(assignment("spill_tol_m"), e)
    eval(assignment("make_components"), e)
    eval(assignment("is_edge_cell"), e)
    eval(section("# 67. PROCESS EACH LAKE", "# 69. SAVE"), e)
    # Only the merge is needed from 72; no tile-specific 108-lake assertion.
    eval(section("# 72. JOIN 02D.1 + 02D.2 SUMMARIES", "# 73. RAISED FLAGS")[[1L]], e)
    eval(section("# 73. RAISED FLAGS", "# 74. MULTI-GROUP FLAGS"), e)
    eval(assignment("depression_raise_tol_m"), e)
    build <- section("# 99. BUILD RAISED-CELL COMPONENTS", "# 100. DEPRESSION COMPONENT ON EVERY LAKE CELL")
    for (name in c("storage_delta", "raised_mask", "depression_components")) {
      # depression_components also has a cache-read assignment; select fresh branch.
      expr <- if (name == "depression_components") build[[1L]][[3L]] else build
      eval(assignment(name, if (is.call(expr)) as.expression(list(expr)) else expr), e)
    }
    eval(section("# 100. DEPRESSION COMPONENT ON EVERY LAKE CELL", "# 102. JOIN WITH PREVIOUS SPILL DIAGNOSTIC"), e)
    join <- section("# 102. JOIN WITH PREVIOUS SPILL DIAGNOSTIC", "# 103. CLASSIFY")
    eval(join[1:2], e) # actual merge and generic ID/cardinality assertions
    eval(section("# 103. CLASSIFY", "# 104. SAVE"), e)
    e
  }

  f <- fixture("closed")
  unchanged <- diagnose(f, f$surface)
  s <- unchanged$lake_depression_summary
  check("positive shore threshold is not an observed storage raise",
        s$spill_raise_m == 2 && s$max_storage_raise_m == 0 && s$spill_raised && !s$storage_raised)
  check("identical surfaces have no raised components, despite legacy label",
        s$n_raised_lake_cells == 0 && s$n_depression_components == 0 &&
          s$depression_status == "SPILL_RAISED_NO_COMPONENT")

  filled <- ifel(is.na(f$lake), f$surface, 12)
  raised <- diagnose(f, filled)$lake_depression_summary
  check("actual storage raise produces raised cells and a component",
        raised$max_storage_raise_m == 2 && raised$n_raised_lake_cells == 9 &&
          raised$n_depression_components == 1 && raised$storage_raised)

  edge <- fixture("edge")
  edge_result <- diagnose(edge, edge$surface)
  check("domain-edge lake can have a positive finite shore threshold without raise",
        edge_result$lake_depression_summary$spill_raise_m == 2 &&
          edge_result$lake_depression_summary$n_raised_lake_cells == 0 &&
          any(edge_result$spill_group_summary$touches_raster_edge))

  nodata <- fixture("nodata")
  nd <- diagnose(nodata, nodata$surface)
  check("NoData shore edges are omitted from the finite-threshold minimum",
        any(!is.finite(nd$shore_candidates$storage_step_level_m)) &&
          nd$lake_depression_summary$spill_raise_m == 2 &&
          nd$lake_depression_summary$n_raised_lake_cells == 0)

  tiny <- ifel(is.na(f$lake), f$surface, 10 + 0.5e-7)
  tiny_result <- diagnose(f, tiny)$lake_depression_summary
  check("sub-tolerance changes do not create raised components",
        tiny_result$max_storage_raise_m > 0 && !tiny_result$storage_raised &&
          tiny_result$n_raised_lake_cells == 0 && tiny_result$spill_raised)

  partial <- f$surface
  partial[25] <- 12 # centre cell; shore unchanged
  partial_result <- diagnose(f, partial)$lake_depression_summary
  check("shore-only storage summary can miss an interior raised cell",
        partial_result$max_storage_raise_m == 0 && !partial_result$storage_raised &&
          partial_result$n_raised_lake_cells == 1)

  # Uneven source levels disprove the uniform-lake assumption, not the arithmetic.
  uneven <- f
  uneven$surface <- f$surface + 0
  uneven$surface[17] <- 8
  uneven$surface[10] <- 8
  nonflat <- diagnose(uneven, uneven$surface)
  check("median source reference is not a guarantee of a constant lake level",
        length(unique(nonflat$shore_candidates$lake_z_m)) > 1 &&
          nonflat$lake_depression_summary$n_raised_lake_cells == 0)

  # Read the actual production call flags, without running either pipeline stage.
  fills <- list()
  visit_fill <- function(x) {
    if (!is.call(x)) return()
    if (identical(x[[1L]], quote(whitebox::wbt_fill_depressions))) fills[[length(fills) + 1L]] <<- x
    for (j in seq_along(x)[-1L]) {
      if (!identical(x[[j]], quote(expr = ))) visit_fill(x[[j]])
    }
  }
  for (x in code) visit_fill(x)
  check("production uses flat correction only for LAND fill",
        length(fills) == 2L && identical(fills[[1L]]$fix_flats, TRUE) &&
          identical(fills[[2L]]$fix_flats, FALSE) && is.null(fills[[2L]]$max_depth))

  exe <- Sys.getenv("HYDRO_TEST_WHITEBOX_EXE", unset = "")
  if (nzchar(exe)) {
    stopifnot(file.exists(exe), requireNamespace("whitebox", quietly = TRUE))
    old <- Sys.getenv("R_WHITEBOX_MAX_PROCS", unset = NA_character_)
    on.exit(if (is.na(old)) Sys.unsetenv("R_WHITEBOX_MAX_PROCS") else
              Sys.setenv(R_WHITEBOX_MAX_PROCS = old), add = TRUE)
    Sys.setenv(R_WHITEBOX_MAX_PROCS = "1")
    whitebox::wbt_init(exe_path = normalizePath(exe))
    tmp <- tempfile("spill-storage-semantics-")
    dir.create(tmp)
    on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
    for (kind in c("closed", "edge", "nodata", "flat_rim")) {
      small <- fixture(kind)
      input <- file.path(tmp, paste0(kind, ".tif"))
      output <- file.path(tmp, paste0(kind, "-filled.tif"))
      writeRaster(small$surface, input, datatype = "FLT8S")
      # Evaluate the actual WATER_STORAGE call, replacing only input/output paths.
      e <- new.env(parent = environment())
      e$f_land_water <- input
      e$f_storage <- output
      call <- fills[[2L]]
      call$command_only <- TRUE
      command <- eval(call, e)
      # whitebox 2.4.3 returns text and can discard a child exit status.
      # Execute its generated command while preserving the underlying status.
      log <- system(command, intern = TRUE)
      status <- attr(log, "status")
      stopifnot(is.null(status) || identical(as.integer(status), 0L), file.exists(output))
      result <- diagnose(small, rast(output))$lake_depression_summary
      expected <- if (kind == "closed") 9 else 0
      check(paste("Whitebox fix_flats=FALSE:", kind),
            result$spill_raise_m == 2 && result$n_raised_lake_cells == expected &&
              result$storage_raised == (kind == "closed"))
    }
  } else {
    cat("SKIP: 4 optional Whitebox integration cases; HYDRO_TEST_WHITEBOX_EXE unset.\n")
  }
  stopifnot(checked >= 9L)
  cat(sprintf("Completed %d synthetic checks; no CSC or real-data validation.\n", checked))
}

run_tests()
