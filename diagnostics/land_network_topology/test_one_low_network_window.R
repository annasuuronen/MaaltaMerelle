#!/usr/bin/env Rscript
# Only synthetic metadata, mocked reads and tiny temporary GeoTIFFs.
s <- grep("^--file=", commandArgs(), value = TRUE)
stopifnot(length(s) == 1L)
here <- dirname(normalizePath(sub("^--file=", "", s)))
source(file.path(here, "..", "low_d8_scope", "lake_1847_focus_core.R"))
source(file.path(here, "..", "land_first_water", "first_water_contact.R"))
source(file.path(here, "..", "land_d8_continuity", "trace_land_d8_route.R"))
source(file.path(here, "land_network_topology.R"))
source(file.path(here, "analyse_land_network_topology.R"))
source(file.path(here, "run_one_low_network_window.R"))
assert <- function(x, message = "Assertion failed") {
  if (!isTRUE(x)) stop(message, call. = FALSE)
}
expect_error <- function(expr, pattern = NULL) {
  e <- tryCatch({ force(expr); NULL }, error = identity)
  assert(inherits(e, "error"), "Expected rejected input")
  if (!is.null(pattern)) assert(grepl(pattern, conditionMessage(e)), conditionMessage(e))
}
qa_tests <- new.env(parent = emptyenv())
qa_tests$total <- 0L; qa_tests$failed <- character(); qa_tests$skipped <- character()
case <- function(label, expr) {
  qa_tests$total <- qa_tests$total + 1L
  tryCatch({ force(expr); cat("PASS:", label, "\n") }, error = function(e) {
    qa_tests$failed <- c(qa_tests$failed, label)
    cat("FAIL:", label, "-", conditionMessage(e), "\n")
  })
}
root <- tempfile("low-network-synthetic-")
dir.create(root)
write_kv <- function(path, keys, values, column) {
  x <- data.frame(k = keys, value = as.character(values), stringsAsFactors = FALSE)
  names(x)[1L] <- column
  write.csv(x, path, row.names = FALSE)
}
fixture <- function(nr = 6000, nc = 6000) {
  directory <- tempfile("case-", tmpdir = root)
  base <- file.path(directory, "E200000_N6900000", "02_baseline")
  inputs <- file.path(dirname(base), "01_inputs")
  water_dir <- file.path(directory, "separate-ranta10-sources")
  dir.create(base, recursive = TRUE); dir.create(inputs); dir.create(water_dir)
  paths <- list(pointer = file.path(base, "d8_pointer_land_water_FLT8S.tif"),
                water = file.path(water_dir, "ranta10_water_class.tif"),
                lake = file.path(water_dir, "ranta10_lake_id.tif"),
                land = file.path(base, "routing_surface_land_water_FLT8S.tif"))
  for (path in paths) writeLines("synthetic backend placeholder", path)
  paths <- lapply(paths, normalizePath)
  manifest <- file.path(inputs, "01_input_manifest.csv")
  qa <- file.path(inputs, "01_input_QA.csv")
  keys <- c("pointer_scheme", "test_id", "cell_size_m", "run_mode",
            "water_class_raster", "lake_id_raster")
  values <- c("whitebox", "E200000_N6900000", "2", "CSC_TEST", paths$water, paths$lake)
  write_kv(manifest, keys, values, "key")
  h <- list(nrow = nr, ncol = nc, nlyr = 1, resolution = c(2, 2),
            xmin = 200000, xmax = 200000 + nc * 2,
            ymin = 6900000, ymax = 6900000 + nr * 2, crs_ok = TRUE)
  items <- c("dem_rows", "dem_cols", "dem_res_x", "dem_res_y", "xmin", "xmax", "ymin", "ymax")
  qvalues <- c(nr, nc, 2, 2, h$xmin, h$xmax, h$ymin, h$ymax)
  write_kv(qa, items, qvalues, "item")
  matrices <- list(pointer = matrix(0, 11L, 11L), water = matrix(NA_real_, 11L, 11L),
                   lake = matrix(NA_real_, 11L, 11L), land = matrix(NA_real_, 11L, 11L))
  # Halo 3 -> core 13 <- core 14; common core 13 -> 24 -> water 25.
  put <- function(m, cells, values) {
    m[cbind((cells - 1L) %/% 11L + 1L, (cells - 1L) %% 11L + 1L)] <- values
    m
  }
  matrices$pointer <- put(matrices$pointer, c(3L, 14L, 13L, 24L), c(16, 32, 8, 2))
  matrices$water <- put(matrices$water, 25L, 1)
  matrices$lake <- put(matrices$lake, 25L, 9001)
  matrices$land <- put(matrices$land, c(3L, 13L, 14L, 24L, 25L), 100)
  state <- new.env(parent = emptyenv())
  state$headers <- setNames(rep(list(h), 4L), names(paths))
  state$matrices <- matrices; state$reads <- list(); state$opens <- character()
  key <- function(path) names(paths)[match(path, unlist(paths, use.names = FALSE))]
  backend <- list(open = function(path) {
    state$opens <- c(state$opens, path); path
  }, header = function(path) state$headers[[key(path)]],
  read_window = function(path, row_start, col_start, nrows, ncols) {
    state$reads[[length(state$reads) + 1L]] <- list(path = path, row_start = row_start,
      col_start = col_start, nrows = nrows, ncols = ncols)
    as.vector(t(state$matrices[[key(path)]]))
  })
  list(base = normalizePath(base), paths = paths, manifest = manifest, qa = qa,
       keys = keys, values = values, items = items, qvalues = qvalues,
       header = h, state = state, backend = backend)
}
run <- function(f, backend = f$backend, ...) {
  run_one_low_network_window(f$base, backend = backend, code_revision = "synthetic-fixture-v1",
                             emit = FALSE, ...)
}
change_manifest <- function(f, key, value) {
  f$values[f$keys == key] <- value
  write_kv(f$manifest, f$keys, f$values, "key")
  f
}

case("sourcing the driver defines helpers without CLI or data I/O", {
  e <- new.env(parent = baseenv())
  output <- capture.output(source(file.path(here, "run_one_low_network_window.R"), local = e))
  assert(length(output) == 0L)
  assert(is.function(e$run_one_low_network_window) && is.function(e$low_network_cli))
})
case("fixed window uses checked dimensions, including even and odd centres", {
  w <- low_network_window(6000, 6000)
  assert(w$centre_row == 3000 && w$centre_col == 3000)
  assert(w$row_start == 2995 && w$row_end == 3005 && w$col_start == 2995 && w$col_end == 3005)
  assert(w$core_row_start == 2996 && w$core_row_end == 3004)
  odd <- low_network_window(21L, 25L)
  assert(odd$centre_row == 11 && odd$centre_col == 13 && odd$row_start == 6 && odd$col_start == 8)
  for (x in list(10, 11.5, NA_real_, Inf, "6000", .Machine$integer.max))
    expect_error(low_network_window(x, 6000))
})
case("manifest key,value and QA item,value contracts stay distinct", {
  f <- fixture()
  assert(identical(names(low_network_read_kv(f$manifest, "key")), c("key", "value")))
  assert(identical(names(low_network_read_kv(f$qa, "item")), c("item", "value")))
  expect_error(low_network_read_kv(f$manifest, "item"), "BAD_METADATA_SCHEMA")
  expect_error(low_network_read_kv(f$qa, "key"), "BAD_METADATA_SCHEMA")
})
case("duplicate keys and blank values fail before any raster sample", {
  f <- fixture()
  write_kv(f$manifest, c(f$keys, f$keys[1L]), c(f$values, f$values[1L]), "key")
  expect_error(run(f), "BAD_METADATA_SCHEMA"); assert(length(f$state$reads) == 0L)
  write_kv(f$manifest, f$keys, replace(f$values, 1L, " "), "key")
  expect_error(run(f), "BAD_METADATA_SCHEMA"); assert(length(f$state$reads) == 0L)
})
case("extra, empty and oversized metadata reports are rejected", {
  f <- fixture()
  write.csv(data.frame(key = "x", value = "y", extra = "z"), f$manifest, row.names = FALSE)
  expect_error(run(f), "BAD_METADATA_SCHEMA")
  writeLines("key,value", f$manifest); expect_error(run(f), "BAD_METADATA_SCHEMA")
  writeLines(paste(rep("x", 65537L), collapse = ""), f$manifest)
  expect_error(run(f), "FILE_TOO_LARGE_OR_UNKNOWN")
  assert(length(f$state$reads) == 0L)
})
case("extra CSV fields cannot hide in read.csv automatic row names", {
  f <- fixture()
  writeLines(c("key,value", "unexpected,pointer_scheme,whitebox"), f$manifest)
  expect_error(run(f), "BAD_METADATA_SCHEMA")
  assert(length(f$state$reads) == 0L)
})
case("missing manifest keys and missing original raster files are explicit failures", {
  f <- fixture()
  write_kv(f$manifest, f$keys[-6L], f$values[-6L], "key")
  expect_error(run(f), "MISSING_METADATA_KEY")
  write_kv(f$manifest, f$keys, f$values, "key")
  unlink(f$paths$lake); expect_error(run(f), "MISSING_OR_LINKED_FILE")
  assert(length(f$state$reads) == 0L)
})
case("wrong tile, pointer scheme and NATIONAL are rejected without samples", {
  for (entry in list(c("test_id", "OTHER"), c("pointer_scheme", "esri"), c("run_mode", "NATIONAL"))) {
    f <- change_manifest(fixture(), entry[1L], entry[2L])
    expect_error(run(f)); assert(length(f$state$reads) == 0L)
  }
  f <- fixture(); expect_error(run_one_low_network_window(dirname(f$base), backend = f$backend), "WRONG_LOW_TILE")
})
case("water and lake identities come from absolute manifest paths outside baseline", {
  f <- fixture(); result <- run(f)
  assert(result$files$water == f$paths$water && result$files$lake == f$paths$lake)
  assert(dirname(result$files$water) != f$base && dirname(result$files$lake) != f$base)
  f <- change_manifest(f, "water_class_raster", "ranta10_water_class.tif")
  expect_error(run(f), "EXPECTED_ABSOLUTE_MANIFEST_RASTER")
})
case("four bounded mock reads use one immutable centre and return exactly 484 values", {
  f <- fixture(); result <- run(f)
  assert(length(f$state$reads) == 4L && length(f$state$opens) == 4L)
  assert(setequal(f$state$opens, unlist(f$paths, use.names = FALSE)))
  for (call in f$state$reads) {
    assert(call$row_start == 2995 && call$col_start == 2995 && call$nrows == 11 && call$ncols == 11)
  }
  assert(result$raster_reads == 4L && result$raster_values_returned == 484L)
  assert(result$network$work_budget$n_transitions <= 3872 && result$network$work_budget$n_cell_reads <= 3993)
  assert(result$network$work_budget$max_steps == 32)
  assert(result$topology_inventory$extra_raster_reads == 0L &&
         result$topology_inventory$extra_route_traces == 0L)
})

case("the production grid pin rejects a different window before raster values", {
  f <- fixture(20, 24)
  expect_error(run(f, expected_full_grid = list(nrow = 6000, ncol = 6000)),
               "LOCKED_LOW_GRID_MISMATCH")
  assert(length(f$state$reads) == 0L)
  f <- fixture()
  result <- run(f, expected_full_grid = list(nrow = 6000, ncol = 6000))
  assert(result$window$row_start == 2995 && result$window$col_start == 2995)
})
case("numeric double layer counts are accepted and malformed header contracts fail before reads", {
  f <- fixture(); assert(typeof(f$header$nlyr) == "double"); assert(run(f)$geometry_check == "PASS")
  for (change in list(list(nlyr = 2), list(nlyr = "1"), list(crs_ok = FALSE),
                       list(resolution = c(1, 1)), list(nrow = 6000.5), list(xmin = NA_real_))) {
    bad <- fixture()
    for (field in names(change)) bad$state$headers$water[[field]] <- change[[field]]
    expect_error(run(bad), "INVALID_RASTER_GEOMETRY_OR_CRS")
    assert(length(bad$state$reads) == 0L)
  }
})
case("a valid but shifted raster geometry and inconsistent QA are rejected before samples", {
  f <- fixture(); f$state$headers$water$xmin <- f$header$xmin + 2; f$state$headers$water$xmax <- f$header$xmax + 2
  expect_error(run(f), "RASTER_GEOMETRY_MISMATCH"); assert(length(f$state$reads) == 0L)
  f <- fixture(); values <- f$qvalues; values[1L] <- 5999
  write_kv(f$qa, f$items, values, "item")
  expect_error(run(f), "INPUT_QA_GEOMETRY_MISMATCH"); assert(length(f$state$reads) == 0L)
})
case("missing QA geometry and nonnumeric QA values cannot become a pass", {
  f <- fixture(); write_kv(f$qa, f$items[-1L], f$qvalues[-1L], "item")
  expect_error(run(f), "MISSING_METADATA_KEY")
  write_kv(f$qa, f$items, replace(as.character(f$qvalues), 1L, "unknown"), "item")
  expect_error(run(f), "INVALID_QA_NUMBER"); assert(length(f$state$reads) == 0L)
})
case("core confluence includes halo inflow while shared edges and core selection stay bounded", {
  result <- run(fixture()); n <- result$network
  assert(sum(n$land_nodes$is_core) == 3L && sum(n$land_nodes$is_halo) == 1L)
  assert(nrow(n$land_edges) == 3L && nrow(n$edges) == 4L)
  assert(nrow(n$confluences) == 1L && n$confluences$local_cell == 13L && n$confluences$is_core)
  z <- setNames(n$land_edge_zone_counts$n_edges, n$land_edge_zone_counts$zone_transition)
  assert(z[["CORE_TO_CORE"]] == 2L && z[["HALO_TO_CORE"]] == 1L && sum(z) == 3L)
  assert(result$core_cases$source_cell[result$core_cases$category == "CONFLUENCE"] == 13L)
  assert(result$halo_cases$status[result$halo_cases$category == "CONFLUENCE"] == "NOT_OBSERVED")
  assert(n$external_inflow == "UNKNOWN" && n$accumulation == "NOT_COMPUTED")
})
case("row-major observations retain global IDs and independent raster lake values", {
  result <- run(fixture()); n <- result$network
  source <- n$cells[n$cells$local_cell == 13L, ]
  assert(source$global_row == 2996 && source$global_col == 2996)
  assert(source$cell_uid == "LOW-E200000-N6900000:2996:2996")
  assert(source$x_m == 205991 && source$y_m == 6906009)
  assert(n$cells$pointer[3L] == 16 && n$cells$pointer[14L] == 32)
  assert(nrow(result$contacts) == 4L && all(result$contacts$water_class == 1L))
  assert(all(result$contacts$lake_objectid == 9001L))
})
case("pointer observations remain diagnostic instead of being silently repaired", {
  f <- fixture()
  f$state$matrices$pointer[2L, 2L] <- 3
  result <- run(f)
  assert(any(result$network$route_summary$route_status == "INVALID_POINTER"))
  assert(result$network$cells$pointer[13L] == 3)
  f$state$matrices$pointer[2L, 2L] <- NA_real_
  assert(any(run(f)$network$route_summary$route_status == "POINTER_NA"))
})
case("empty real-window shapes keep missing cases and do not relocate the sample", {
  for (water_only in c(FALSE, TRUE)) {
    f <- fixture()
    f$state$matrices$land[,] <- if (water_only) 100 else NA_real_
    f$state$matrices$water[,] <- if (water_only) 1 else NA_real_
    result <- run(f)
    assert(nrow(result$network$land_nodes) == 0L && nrow(result$contacts) == 0L)
    assert(all(result$core_cases$status == "NOT_OBSERVED") && all(result$halo_cases$status == "NOT_OBSERVED"))
    assert(result$window$row_start == 2995 && result$window$col_start == 2995)
    assert(result$raster_values_returned == 484L)
  }
})
case("malformed bounded reader output fails instead of widening or repeating reads", {
  for (value in list(rep(0, 122L), rep(0, 120L), rep("0", 121L), matrix(0, 11L, 11L))) {
    f <- fixture(); bad <- f$backend
    bad$read_window <- function(...) value
    expect_error(run(f, backend = bad), "BAD_BOUNDED_RASTER_READ")
  }
})
case("reports preserve all termination bins and never promote declared provenance or technical success", {
  result <- run(fixture())
  expected <- c("D8_ZERO", "POINTER_NA", "INVALID_POINTER", "NO_DATA", "INVALID_WATER_CLASS",
                "CYCLE", "DOMAIN_EXIT_UNRESOLVED", "STEP_LIMIT", "FIRST_WATER_CONTACT")
  assert(setequal(result$route_counts$route_status, expected))
  assert(sum(result$route_counts$n_routes[result$route_counts$scope == "window"]) == 4L)
  assert(result$code_version_verification == "DECLARED_ONLY" && result$historical_provenance == "INCOMPLETE")
  assert(result$historical_source_commit == "UNKNOWN")
  assert(result$network$hydrological_validation == "NOT_ASSESSED" && result$network$channel_interpretation == "NOT_ASSESSED")
  assert(result$network$MODERATE == "REVIEW_REQUIRED" && result$network$NATIONAL == "LOCKED")
  output <- paste(capture.output(low_network_print_result(result)), collapse = "\n")
  for (text in c("========== TULOKSET ALKAVAT ==========", "========== TULOKSET LOPPUVAT ==========",
                 "CORE_CASES", "HALO_CASES", "FIRST_RANTA10_CONTACTS", "external_inflow=UNKNOWN",
                 "hydrological_validation=NOT_ASSESSED", "channel_interpretation=NOT_ASSESSED"))
    assert(grepl(text, output, fixed = TRUE), paste("Missing report field", text))
})
case("read-only driver leaves every existing fixture file unchanged and creates no report files", {
  f <- fixture()
  files <- list.files(dirname(dirname(f$base)), recursive = TRUE, full.names = TRUE)
  before <- tools::md5sum(files)
  result <- run(f)
  assert(identical(files, list.files(dirname(dirname(f$base)), recursive = TRUE, full.names = TRUE)))
  assert(identical(before, tools::md5sum(files)) && result$geometry_check == "PASS")
})

case("inventory output preserves complete counts and checksums when details are limited", {
  result <- run(fixture())
  full_text <- capture.output(full <- low_network_print_inventory(
    result$topology_inventory, result$network))
  short_text <- capture.output(short <- low_network_print_inventory(
    result$topology_inventory, result$network, row_limit = 1L))
  assert(identical(full$inventory, short$inventory) && identical(full$total_rows, short$total_rows))
  assert(identical(full$checksum, short$checksum) && any(short$truncated))
  assert(all(short$printed_rows <= 1L) && all(grepl("^[0-9a-f]{8}$", full$checksum)))
  for (name in c("CORE_CONFLUENCE_DETAILS", "HALO_CONFLUENCE_DETAILS", "SHARED_DOWNSTREAM_SEGMENTS",
                 "UNIQUE_WINDOW_EXIT_EDGES", "SOURCE_ROUTES_PER_EXIT", "TOPOLOGY_ACCOUNTING_QA"))
    assert(any(grepl(name, full_text, fixed = TRUE)))
  assert(any(grepl("TRUNCATED TRUE", short_text, fixed = TRUE)))
  mutated <- result$topology_inventory$confluence_details
  before <- low_network_inventory_checksum(mutated)
  mutated <- rbind(mutated, mutated)
  assert(before != low_network_inventory_checksum(mutated))
  expect_error(low_network_print_inventory(result$topology_inventory, result$network, row_limit = 0))
})

if (requireNamespace("terra", quietly = TRUE)) {
  cat("TERRA_VERSION=", as.character(utils::packageVersion("terra")), "\n", sep = "")
  write_terra_fixture <- function(f) {
    template <- terra::rast(nrows = 20, ncols = 24, xmin = 200000, xmax = 200048,
                            ymin = 6900000, ymax = 6900040, crs = "EPSG:3067")
    assert(typeof(terra::nlyr(template)) %in% c("integer", "double"))
    w <- low_network_window(20, 24)
    for (key in names(f$paths)) {
      values <- rep(NA_real_, 20L * 24L)
      if (key == "pointer") values[] <- 0
      rows <- rep(w$row_start:w$row_end, each = 11L)
      cols <- rep(w$col_start:w$col_end, times = 11L)
      ids <- (rows - 1L) * 24L + cols
      values[ids] <- as.vector(t(f$state$matrices[[key]]))
      r <- terra::setValues(template, values)
      terra::writeRaster(r, f$paths[[key]], overwrite = TRUE, datatype = "FLT8S")
    }
    f
  }
  case("actual tiny GeoTIFFs use bounded column reads and retain row-major raster values", {
    f <- write_terra_fixture(fixture(20, 24))
    inputs <- list.files(dirname(dirname(f$base)), recursive = TRUE, full.names = TRUE)
    before <- tools::md5sum(inputs)
    result <- run(f, backend = low_network_terra_backend())
    assert(result$raster_reads == 4L && result$raster_values_returned == 484L)
    assert(result$window$row_start == 5 && result$window$col_start == 7)
    assert(nrow(result$network$land_edges) == 3L && nrow(result$contacts) == 4L)
    assert(result$network$cells$pointer[3L] == 16 && result$network$cells$pointer[14L] == 32)
    assert(result$network$cells$global_row[13L] == 6 && result$network$cells$global_col[13L] == 8)
    assert(identical(before, tools::md5sum(inputs)))
  })
  case("actual terra rejects multilayer, shifted and wrong-CRS rasters before window reads", {
    for (kind in c("multilayer", "shifted", "wrong_crs")) {
      f <- fixture(20, 24)
      template <- terra::rast(nrows = 20, ncols = 24, xmin = 200000, xmax = 200048,
                              ymin = 6900000, ymax = 6900040, crs = "EPSG:3067")
      template <- terra::setValues(template, rep(0, 480L))
      for (key in names(f$paths)) terra::writeRaster(template, f$paths[[key]], overwrite = TRUE)
      bad <- switch(kind, multilayer = c(template, template),
                    shifted = terra::shift(template, dx = 2), wrong_crs = {
                      r <- template; terra::crs(r) <- "EPSG:4326"; r
                    })
      terra::writeRaster(bad, f$paths$water, overwrite = TRUE)
      backend <- low_network_terra_backend(); calls <- 0L
      backend$read_window <- function(...) { calls <<- calls + 1L; stop("UNEXPECTED_RASTER_VALUE_READ") }
      expect_error(run(f, backend = backend), "GEOMETRY")
      assert(calls == 0L)
    }
  })
  case("actual Rscript CLI verifies an isolated fixture commit and refuses wrong pins or a dirty checkout", {
    assert(nzchar(Sys.which("git")), "Git is needed for the CLI provenance regression")
    f <- write_terra_fixture(fixture(20, 24))
    # Four tiny source windows inside virtual 6000x6000 headers. No full-grid
    # value allocation, scan or write is needed to exercise the real CLI pin.
    for (path in f$paths) {
      source_path <- paste0(path, ".source.tif")
      assert(file.rename(path, source_path))
      writeLines(c('<VRTDataset rasterXSize="6000" rasterYSize="6000">',
        '<SRS>EPSG:3067</SRS><GeoTransform>200000,2,0,6912000,0,-2</GeoTransform>',
        '<VRTRasterBand dataType="Float64" band="1"><NoDataValue>nan</NoDataValue><SimpleSource>',
        paste0('<SourceFilename relativeToVRT="0">', source_path, '</SourceFilename><SourceBand>1</SourceBand>'),
        '<SrcRect xOff="6" yOff="4" xSize="11" ySize="11"/>',
        '<DstRect xOff="2994" yOff="2994" xSize="11" ySize="11"/>',
        '</SimpleSource></VRTRasterBand></VRTDataset>'), path)
    }
    write_kv(f$qa, f$items, c(6000, 6000, 2, 2, 200000, 212000, 6900000, 6912000), "item")
    repo <- tempfile("synthetic-code-", tmpdir = root)
    dir.create(repo)
    relative <- c("diagnostics/low_d8_scope/lake_1847_focus_core.R",
                  "diagnostics/land_first_water/first_water_contact.R",
                  "diagnostics/land_d8_continuity/trace_land_d8_route.R",
                  "diagnostics/land_network_topology/land_network_topology.R",
                  "diagnostics/land_network_topology/analyse_land_network_topology.R",
                  "diagnostics/land_network_topology/run_one_low_network_window.R")
    project <- dirname(dirname(here))
    for (path in relative) {
      dir.create(dirname(file.path(repo, path)), recursive = TRUE, showWarnings = FALSE)
      assert(file.copy(file.path(project, path), file.path(repo, path)))
    }
    git <- function(...) {
      output <- suppressWarnings(system2("git", shQuote(c("-C", repo, ...)), stdout = TRUE, stderr = TRUE))
      status <- attr(output, "status")
      assert(is.null(status) || status == 0L, paste(output, collapse = "\n"))
      output
    }
    git("-c", "init.defaultBranch=synthetic-fixture", "init", "--quiet")
    git("remote", "add", "origin", "https://github.com/annasuuronen/MaaltaMerelle.git")
    git("add", "--", "diagnostics")
    git("-c", "user.name=Synthetic fixture", "-c", "user.email=fixture@example.invalid",
        "commit", "--quiet", "-m", "Synthetic local CLI fixture only")
    commit <- git("rev-parse", "HEAD")
    assert(length(commit) == 1L && grepl("^[0-9a-f]{40}$", commit))
    script <- file.path(repo, tail(relative, 1L))
    cli <- function(pin) suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
      shQuote(c("--vanilla", script, f$base)), stdout = TRUE, stderr = TRUE,
      env = paste0("MM_EXPECTED_COMMIT=", pin)))
    output <- cli(commit)
    assert(is.null(attr(output, "status")), paste(output, collapse = "\n"))
    text <- paste(output, collapse = "\n")
    assert(grepl(paste0("COMMIT=", commit), text, fixed = TRUE))
    assert(grepl("CODE_VERSION_VERIFICATION=LOCAL_GIT_CLEAN", text, fixed = TRUE))
    assert(grepl("WINDOW_GLOBAL_ROWS 2995 3005 COLS 2995 3005", text, fixed = TRUE))
    assert(grepl("VALID_LAND CORE 3 HALO 1", text, fixed = TRUE))
    assert(grepl("CORE_CONFLUENCES 1 HALO_CONFLUENCES 0", text, fixed = TRUE))
    assert(grepl("RASTER_READ_CALLS 4 RETURNED_VALUES 484", text, fixed = TRUE))
    assert(grepl("========== TULOKSET LOPPUVAT ==========", text, fixed = TRUE))
    assert(grepl("hydrological_validation=NOT_ASSESSED", text, fixed = TRUE))
    wrong <- cli(paste(rep("0", 40L), collapse = ""))
    assert(!is.null(attr(wrong, "status")) && any(grepl("EXPECTED_COMMIT_MISMATCH", wrong)))
    writeLines("uncommitted synthetic note", file.path(repo, "dirty.txt"))
    dirty <- cli(commit)
    assert(!is.null(attr(dirty, "status")) && any(grepl("A_CLEAN_COMMITTED_CHECKOUT_IS_REQUIRED", dirty)))
    assert(!any(grepl("TULOKSET ALKAVAT", c(wrong, dirty), fixed = TRUE)))
  })
} else {
  qa_tests$skipped <- "actual tiny terra GeoTIFF integration (terra unavailable)"
  cat("NOT_RUN:", qa_tests$skipped, "\n")
}
unlink(root, recursive = TRUE)
if (qa_tests$total == 0L) stop("FAIL: no driver tests were executed")
cat(sprintf("TESTS=%d PASS=%d FAIL=%d NOT_RUN=%d\n", qa_tests$total,
            qa_tests$total - length(qa_tests$failed), length(qa_tests$failed), length(qa_tests$skipped)))
if (length(qa_tests$failed)) stop("LOW driver regression failures: ", paste(qa_tests$failed, collapse = "; "))
cat("PASS: synthetic read-only window contracts; no CSC data or hydrological approval\n")
