#!/usr/bin/env Rscript
# Only the supplied coordinate contract and synthetic raster values. No CSC I/O.
s <- grep("^--file=", commandArgs(), value = TRUE)
stopifnot(length(s) == 1L)
here <- dirname(normalizePath(sub("^--file=", "", s)))
source(file.path(here, "run_one_low_network_window.R"))
source(file.path(here, "boundary_receivers.R"))
source(file.path(here, "run_low_boundary_receivers.R"))
locked <- read_low_boundary_lock(file.path(here, "low_boundary_receivers_targets.csv"))
targets <- low_boundary_targets(locked, locked)
assert <- function(x, message = "Assertion failed") if (!isTRUE(x)) stop(message, call. = FALSE)
expect_error <- function(expr) {
  e <- tryCatch({ force(expr); NULL }, error = identity)
  assert(inherits(e, "error"), "Expected rejected input")
}
q <- new.env(parent = emptyenv()); q$total <- 0L; q$failed <- character(); q$skipped <- character()
case <- function(label, expr) {
  q$total <- q$total + 1L
  tryCatch({ force(expr); cat("PASS:", label, "\n") }, error = function(e) {
    q$failed <- c(q$failed, label); cat("FAIL:", label, "-", conditionMessage(e), "\n")
  })
}
sample_values <- function() data.frame(receiver_uid = targets$receivers$receiver_uid,
  land_water = rep(100, 14), water_class = rep(NA_real_, 14),
  lake_id = rep(NA_real_, 14), pointer = rep(2, 14), stringsAsFactors = FALSE)

case("tracked exit rows equal all sixteen user-supplied coordinate, pointer and count records", {
  expected <- c("2995:2995:32:2995:2994:5", "2995:3005:2:2995:3006:6",
    "2996:2995:32:2996:2994:5", "2996:3005:2:2996:3006:6",
    "2997:2995:32:2997:2994:4", "2997:3005:2:2997:3006:6",
    "2998:2995:32:2998:2994:4", "2998:3005:2:2998:3006:8",
    "2999:2995:32:2999:2994:3", "3000:2995:32:3000:2994:2",
    "3001:2995:64:3000:2994:18", "3005:2995:32:3005:2994:1",
    "3005:3001:4:3006:3002:4", "3005:3002:8:3006:3002:28",
    "3005:3004:8:3006:3004:16", "3005:3005:8:3006:3005:5")
  assert(identical(do.call(paste, c(locked[3:8], sep = ":")), expected))
})
case("the exact fourteen receiver coordinates deduplicate the two known pairs", {
  expected <- c("2995:2994", "2995:3006", "2996:2994", "2996:3006", "2997:2994",
    "2997:3006", "2998:2994", "2998:3006", "2999:2994", "3000:2994", "3005:2994",
    "3006:3002", "3006:3004", "3006:3005")
  r <- targets$receivers
  assert(identical(paste(r$predicted_receiver_row, r$predicted_receiver_col, sep = ":"), expected))
  assert(nrow(r) == 14L && sum(r$n_exit_edges) == 16L && sum(r$reported_source_routes) == 121L)
  assert(identical(r$reported_source_routes[r$n_exit_edges == 2], c(20, 32)))
})
case("reordering the approved table cannot change targets and joins", {
  a <- low_boundary_targets(locked[16:1, ], locked)
  assert(identical(a, targets))
})
case("a changed receiver cannot pass merely by retaining sixteen-to-fourteen counts", {
  bad <- locked; bad$predicted_receiver_row[1L] <- 2994
  expect_error(low_boundary_targets(bad, locked))
})
case("missing duplicate extra and malformed exit records are rejected", {
  for (bad in list(locked[-1L, ], rbind(locked, locked[1L, ]), locked[c(1L, 1L, 3:16), ]))
    expect_error(low_boundary_targets(bad, locked))
  bad <- locked; bad$d8_code[1] <- NA_real_; expect_error(low_boundary_targets(bad, locked))
  bad <- locked; bad$global_col[1] <- 2995.5; expect_error(low_boundary_targets(bad, locked))
  bad <- locked; bad$exit_cell_uid[1] <- "invented"; expect_error(low_boundary_targets(bad, locked))
})
case("all original exit IDs remain mapped to the same deduplicated receivers", {
  r <- observe_boundary_receivers(targets, sample_values())
  assert(identical(r$exit_links$exit_cell_uid, targets$exits$exit_cell_uid))
  assert(identical(r$exit_links$receiver_uid, targets$exits$receiver_uid))
  assert(nrow(r$receivers) == 14L && nrow(r$exit_links) == 16L)
})
case("NoData and invalid water class do not become valid land or water", {
  v <- sample_values(); v$land_water[1:2] <- c(NA_real_, Inf); v$water_class[1:2] <- c(1, 2)
  v$water_class[3] <- 4
  r <- observe_boundary_receivers(targets, v)$receivers
  assert(identical(r$receiver_class[1:3], c("NO_DATA", "NO_DATA", "UNCLEAR")))
  assert(all(is.na(r$lake_objectid[1:3])))
})
case("zero missing invalid and valid pointers are recorded without following them", {
  v <- sample_values(); v$pointer[1:6] <- c(0, NA_real_, 3, Inf, 2.5, 128)
  r <- observe_boundary_receivers(targets, v)
  assert(identical(r$receivers$pointer_status[1:6],
    c("D8_ZERO", "POINTER_NA", "INVALID_POINTER", "INVALID_POINTER", "INVALID_POINTER", "VALID_D8_CODE")))
  assert(all(r$receivers$receiver_class == "LAND") && r$downstream_steps == 0L)
})
case("lake IDs survive only at usable lake cells while river IDs remain unknown", {
  v <- sample_values(); v$water_class[1:6] <- c(1, 1, 1, 2, 3, 1)
  v$lake_id[1:6] <- c(9001, NA_real_, -1, 9002, 9003, 4.5)
  r <- observe_boundary_receivers(targets, v)$receivers
  assert(r$lake_objectid[1] == 9001 && all(is.na(r$lake_objectid[2:6])))
  assert(identical(r$lake_id_status[1:6], c("VALID", "MISSING", "INVALID", "NOT_APPLICABLE", "NOT_APPLICABLE", "INVALID")))
})
case("duplicate missing or unexpected sampled cells cannot produce a plausible observation table", {
  v <- sample_values()
  bad <- v; bad$receiver_uid[1] <- bad$receiver_uid[2]; expect_error(observe_boundary_receivers(targets, bad))
  bad <- v; bad$receiver_uid[1] <- "extra-cell"; expect_error(observe_boundary_receivers(targets, bad))
  expect_error(observe_boundary_receivers(targets, v[-1, ]))
  bad <- v; bad$pointer <- as.character(bad$pointer); expect_error(observe_boundary_receivers(targets, bad))
})
case("shared cells remain two observed receivers and never become approved outlets", {
  v <- sample_values(); v$water_class[targets$receivers$n_exit_edges == 2] <- c(NA_real_, 3)
  r <- observe_boundary_receivers(targets, v)
  assert(sum(r$receivers$shared_receiver) == 2L && sum(r$exit_links$shared_receiver) == 4L)
  assert(r$hydrological_validation == "NOT_ASSESSED" && r$channel_interpretation == "NOT_ASSESSED")
  assert(r$MODERATE == "REVIEW_REQUIRED" && r$NATIONAL == "LOCKED" && r$accumulation == "NOT_COMPUTED")
})
case("the cell reader requests exactly fourteen unique cells per raster and nothing else", {
  reads <- list(); cells <- targets$receivers$cell
  rasters <- setNames(as.list(1:4), c("pointer", "water", "lake", "land"))
  read <- function(r, ids) { reads[[length(reads) + 1L]] <<- ids; rep(r, length(ids)) }
  x <- read_boundary_cells(rasters, cells, read, 36000000)
  assert(length(reads) == 4L && all(vapply(reads, identical, logical(1), cells)))
  assert(x$unique_cell_positions == 14L && x$returned_values == 56L)
})
case("fractional duplicate outside and excess IDs fail before touching any raster", {
  calls <- 0L
  read <- function(...) { calls <<- calls + 1L; stop("Unexpected read") }
  rasters <- setNames(as.list(1:4), c("pointer", "water", "lake", "land"))
  ids <- targets$receivers$cell
  for (bad in list(c(ids, 1), ids[-1], replace(ids, 1, ids[2]), replace(ids, 1, 1.5), replace(ids, 1, 36000001)))
    expect_error(read_boundary_cells(rasters, bad, read, 36000000))
  assert(calls == 0L)
})
case("a reader returning neighbours matrices or the wrong number of values is rejected", {
  rasters <- setNames(as.list(1:4), c("pointer", "water", "lake", "land"))
  for (x in list(rep(0, 15), matrix(0, 14, 1), rep("0", 14)))
    expect_error(read_boundary_cells(rasters, targets$receivers$cell, function(...) x, 36000000))
})

root <- tempfile("boundary-synthetic-"); dir.create(root)
fixture <- function() {
  parent <- tempfile("case-", tmpdir = root)
  base <- file.path(parent, "E200000_N6900000", "02_baseline")
  inputs <- file.path(dirname(base), "01_inputs"); waters <- file.path(parent, "water")
  dir.create(base, recursive = TRUE); dir.create(inputs); dir.create(waters)
  files <- list(pointer = file.path(base, "d8_pointer_land_water_FLT8S.tif"),
    water = file.path(waters, "ranta10_water_class.tif"), lake = file.path(waters, "ranta10_lake_id.tif"),
    land = file.path(base, "routing_surface_land_water_FLT8S.tif"))
  for (file in files) writeLines("SYNTHETIC PLACEHOLDER", file)
  write.csv(data.frame(key = c("pointer_scheme", "test_id", "cell_size_m", "water_class_raster", "lake_id_raster"),
    value = c("whitebox", "E200000_N6900000", "2", files$water, files$lake)),
    file.path(inputs, "01_input_manifest.csv"), row.names = FALSE)
  write.csv(data.frame(item = c("dem_rows", "dem_cols", "dem_res_x", "dem_res_y", "xmin", "xmax", "ymin", "ymax"),
    value = c(6000, 6000, 2, 2, 200000, 212000, 6900000, 6912000)),
    file.path(inputs, "01_input_QA.csv"), row.names = FALSE)
  state <- new.env(); state$reads <- list()
  h <- list(nrow = 6000, ncol = 6000, nlyr = 1, resolution = c(2, 2),
    xmin = 200000, xmax = 212000, ymin = 6900000, ymax = 6912000, crs_ok = TRUE)
  state$headers <- setNames(rep(list(h), 4), names(files))
  v <- sample_values(); state$values <- list(pointer = v$pointer, water = v$water_class, lake = v$lake_id, land = v$land_water)
  key <- function(p) names(files)[match(p, unlist(files, use.names = FALSE))]
  backend <- list(open = identity, header = function(p) state$headers[[key(p)]],
    read_cells = function(p, cells) {
      assert(identical(cells, targets$receivers$cell), "Unexpected logical raster position")
      state$reads[[length(state$reads) + 1L]] <- cells
      state$values[[key(p)]]
    }, read_window = function(...) stop("FORBIDDEN_WINDOW_READ"))
  list(base = base, files = files, backend = backend, state = state)
}
case("the integrated worker validates headers and joins sixteen exits using fifty-six values", {
  f <- fixture(); all_files <- list.files(dirname(dirname(f$base)), full.names = TRUE, recursive = TRUE)
  before <- tools::md5sum(all_files)
  r <- run_low_boundary_receivers(f$base, locked, locked, backend = f$backend, emit = FALSE)
  assert(length(f$state$reads) == 4L && r$budget$returned_values == 56L)
  assert(nrow(r$exit_links) == 16L && nrow(r$receivers) == 14L && r$downstream_steps == 0L)
  assert(identical(before, tools::md5sum(all_files)))
  assert(identical(all_files, list.files(dirname(dirname(f$base)), full.names = TRUE, recursive = TRUE)))
})
case("a changed target set stops before metadata or sample access", {
  f <- fixture(); bad <- locked; bad$n_source_routes[1] <- 6
  expect_error(run_low_boundary_receivers(f$base, bad, locked, backend = f$backend))
  assert(length(f$state$reads) == 0L)
})
case("geometry CRS layers and resolution disagreements fail before sampling", {
  for (change in list(list(xmin = 200002, xmax = 212002), list(crs_ok = FALSE), list(nlyr = 2), list(resolution = c(1, 1)))) {
    f <- fixture()
    for (name in names(change)) f$state$headers$water[[name]] <- change[[name]]
    expect_error(run_low_boundary_receivers(f$base, locked, locked, backend = f$backend))
    assert(length(f$state$reads) == 0L)
  }
})
case("the report distinguishes reported provenance from newly sampled receiver contents", {
  f <- fixture(); r <- run_low_boundary_receivers(f$base, locked, locked, backend = f$backend, emit = FALSE)
  text <- paste(capture.output(print_low_boundary_receivers(r)), collapse = "\n")
  for (s in c("NO_WINDOW_READ", "NO_DOWNSTREAM_TRACE", "RETURNED_VALUES 56", "ORIGINAL_EXIT_TO_RECEIVER_LINKS",
    "SHARED_RECEIVER_CELLS", "USER_REPORTED_FULL_TABLE_NOT_RECOMPUTED", "0f39c62a")) assert(grepl(s, text, fixed = TRUE))
  assert(r$historical_source_commit == "UNKNOWN" && r$code_version_verification == "DECLARED_ONLY")
})

if (requireNamespace("terra", quietly = TRUE)) {
  cat("TERRA_VERSION=", as.character(utils::packageVersion("terra")), "\n", sep = "")
  case("actual non-square GeoTIFF extraction uses exact numeric cell IDs and original request order", {
    path <- file.path(root, "irregular.tif")
    r <- terra::rast(nrows = 8, ncols = 9, xmin = 200000, xmax = 200018,
                    ymin = 6900000, ymax = 6900016, crs = "EPSG:3067")
    terra::writeRaster(terra::setValues(r, seq_len(72) * 10), path)
    r <- terra::rast(path)
    ids <- c(70, 1, 19, 9, 10, 64, 31, 55, 6, 39, 24, 46, 68, 14)
    backend <- low_boundary_terra_backend()
    assert(identical(as.numeric(backend$read_cells(r, ids)), ids * 10))
    expect_error(backend$read_cells(r, replace(ids, 1, 1.5)))
  })
  write_virtual <- function(f) {
    for (key in names(f$files)) {
      src <- paste0(f$files[[key]], ".source.tif")
      raster <- terra::rast(nrows = 1, ncols = 14, xmin = 0, xmax = 28, ymin = 0, ymax = 2, crs = "EPSG:3067")
      terra::writeRaster(terra::setValues(raster, f$state$values[[key]]), src, datatype = "FLT8S")
      xml <- c('<VRTDataset rasterXSize="6000" rasterYSize="6000">',
        '<SRS>EPSG:3067</SRS><GeoTransform>200000,2,0,6912000,0,-2</GeoTransform>',
        '<VRTRasterBand dataType="Float64" band="1"><NoDataValue>nan</NoDataValue>')
      for (i in seq_len(14)) xml <- c(xml, '<SimpleSource>',
        paste0('<SourceFilename relativeToVRT="0">', src, '</SourceFilename><SourceBand>1</SourceBand>'),
        sprintf('<SrcRect xOff="%d" yOff="0" xSize="1" ySize="1"/>', i - 1),
        sprintf('<DstRect xOff="%d" yOff="%d" xSize="1" ySize="1"/>',
          targets$receivers$predicted_receiver_col[i] - 1, targets$receivers$predicted_receiver_row[i] - 1), '</SimpleSource>')
      writeLines(c(xml, '</VRTRasterBand></VRTDataset>'), f$files[[key]])
    }
    f
  }
  case("actual terra reads only the locked fourteen cells in four virtual LOW rasters", {
    f <- fixture(); f$state$values$land[1] <- NA_real_; f$state$values$pointer[2] <- 0
    f <- write_virtual(f)
    backend <- low_boundary_terra_backend(); real <- backend$read_cells; seen <- list()
    backend$read_cells <- function(r, cells) { seen[[length(seen) + 1L]] <<- cells; real(r, cells) }
    backend$read_window <- function(...) stop("FORBIDDEN_WINDOW_READ")
    r <- run_low_boundary_receivers(f$base, locked, locked, backend = backend, emit = FALSE)
    assert(length(seen) == 4L && all(vapply(seen, identical, logical(1), targets$receivers$cell)))
    assert(r$receivers$receiver_class[1] == "NO_DATA" && r$receivers$pointer_status[2] == "D8_ZERO")
    assert(r$budget$returned_values == 56L)
  })
  case("the actual CLI uses the committed target file and refuses dirty or mismatched code", {
    f <- write_virtual(fixture()); repo <- tempfile("code-", tmpdir = root); dir.create(repo)
    relative <- c("run_one_low_network_window.R", "boundary_receivers.R", "run_low_boundary_receivers.R", "low_boundary_receivers_targets.csv")
    destination <- file.path(repo, "diagnostics", "land_network_topology"); dir.create(destination, recursive = TRUE)
    assert(all(file.copy(file.path(here, relative), destination)))
    git <- function(...) {
      out <- suppressWarnings(system2("git", shQuote(c("-C", repo, ...)), stdout = TRUE, stderr = TRUE))
      status <- attr(out, "status"); assert(is.null(status) || status == 0L, paste(out, collapse = "\n")); out
    }
    git("-c", "init.defaultBranch=synthetic", "init", "--quiet")
    git("remote", "add", "origin", "https://github.com/annasuuronen/MaaltaMerelle.git")
    git("add", "diagnostics")
    git("-c", "user.name=Synthetic fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "Synthetic fixture only")
    commit <- git("rev-parse", "HEAD")
    cli <- function(pin) suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
      shQuote(c("--vanilla", file.path(destination, "run_low_boundary_receivers.R"), f$base)),
      stdout = TRUE, stderr = TRUE, env = paste0("MM_EXPECTED_COMMIT=", pin)))
    out <- cli(commit); assert(is.null(attr(out, "status")), paste(out, collapse = "\n"))
    assert(any(grepl("UNIQUE_RECEIVERS 14 EXIT_LINKS 16 RASTER_READ_CALLS 4 RETURNED_VALUES 56", out, fixed = TRUE)))
    wrong <- cli(paste(rep("0", 40), collapse = ""))
    assert(!is.null(attr(wrong, "status")) && any(grepl("EXPECTED_COMMIT_MISMATCH", wrong)))
    writeLines("uncommitted", file.path(repo, "dirty.txt"))
    dirty <- cli(commit)
    assert(!is.null(attr(dirty, "status")) && any(grepl("CLEAN_COMMITTED_CHECKOUT_REQUIRED", dirty)))
  })
} else {
  q$skipped <- "actual terra GeoTIFF and CLI integration groups"
  cat("NOT_RUN:", q$skipped, "\n")
}
unlink(root, recursive = TRUE)
if (q$total == 0L) stop("No receiver tests executed")
cat(sprintf("TESTS=%d PASS=%d FAIL=%d NOT_RUN=%d\n", q$total, q$total - length(q$failed), length(q$failed), length(q$skipped)))
if (length(q$failed)) stop("Boundary receiver failures: ", paste(q$failed, collapse = "; "))
cat("PASS: contract and synthetic observations only; no CSC reads or hydrological approval\n")
