#!/usr/bin/env Rscript
# Read-only, fixed-centre LOW window. Sourcing this file performs no data I/O.
# CLI: Rscript --vanilla run_one_low_network_window.R [BASELINE_DIR]
# No 02B selection, independent D8 decoder, output files, Whitebox or Slurm.
low_network_required_file <- function(path, max_bytes = Inf) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path) ||
      !file.exists(path) || dir.exists(path) || nzchar(Sys.readlink(path))) {
    stop("MISSING_OR_LINKED_FILE: ", paste(path, collapse = ","), call. = FALSE)
  }
  size <- file.info(path)$size
  if (!is.finite(size) || size > max_bytes) stop("FILE_TOO_LARGE_OR_UNKNOWN: ", path)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

low_network_read_kv <- function(path, key_column) {
  if (!identical(key_column, "key") && !identical(key_column, "item"))
    stop("Unsupported metadata key column.")
  path <- low_network_required_file(path, 65536)
  x <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE, row.names = NULL,
                colClasses = "character", na.strings = character(),
                comment.char = "", fill = FALSE)
  if (!identical(names(x), c(key_column, "value")) || !nrow(x) ||
      anyNA(x) || anyDuplicated(x[[key_column]]) ||
      any(!nzchar(trimws(x[[key_column]]))) || any(!nzchar(trimws(x$value)))) {
    stop("BAD_METADATA_SCHEMA: expected unique ", key_column, ",value; got ",
         paste(names(x), collapse = ","), call. = FALSE)
  }
  x
}

low_network_window <- function(nrow, ncol) {
  whole <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x) &&
    x == floor(x) && x >= 11 && x <= .Machine$integer.max
  if (!whole(nrow) || !whole(ncol) || nrow * as.double(ncol) > .Machine$integer.max)
    stop("UNSUPPORTED_GRID: need at least 11 rows/columns and safe cell IDs.")
  row <- floor((nrow + 1) / 2)
  col <- floor((ncol + 1) / 2)
  list(centre_row = row, centre_col = col,
       row_start = row - 5, row_end = row + 5,
       col_start = col - 5, col_end = col + 5,
       core_row_start = row - 4, core_row_end = row + 4,
       core_col_start = col - 4, core_col_end = col + 4,
       nrows = 11L, ncols = 11L, positions = 121L)
}

low_network_terra_backend <- function() {
  if (!requireNamespace("terra", quietly = TRUE)) stop("terra is required for raster reads.")
  list(
    open = function(path) terra::rast(path),
    header = function(r) list(
      nrow = terra::nrow(r), ncol = terra::ncol(r), nlyr = terra::nlyr(r),
      resolution = terra::res(r), xmin = terra::xmin(r), xmax = terra::xmax(r),
      ymin = terra::ymin(r), ymax = terra::ymax(r),
      crs_ok = isTRUE(terra::same.crs(r, "EPSG:3067"))),
    read_window = function(r, row_start, col_start, nrows, ncols) {
      terra::values(r, mat = FALSE, row = row_start, nrows = nrows,
                    col = col_start, ncols = ncols)
    }
  )
}

# Injectable backend makes metadata/one-read budgets testable without terra.
# code_revision here is declared; only the CLI below verifies its local Git SHA.
run_one_low_network_window <- function(baseline_dir, manifest_path = NULL, qa_path = NULL,
                                       backend = low_network_terra_backend(),
                                       code_revision = "UNKNOWN", emit = TRUE,
                                       expected_full_grid = NULL) {
  if (!is.character(baseline_dir) || length(baseline_dir) != 1L ||
      is.na(baseline_dir) || !dir.exists(baseline_dir)) stop("BASELINE_DIR_MISSING")
  base <- normalizePath(baseline_dir, winslash = "/", mustWork = TRUE)
  if (basename(base) != "02_baseline" || basename(dirname(base)) != "E200000_N6900000")
    stop("WRONG_LOW_TILE: expected E200000_N6900000/02_baseline")
  if (is.null(manifest_path))
    manifest_path <- file.path(dirname(base), "01_inputs", "01_input_manifest.csv")
  if (is.null(qa_path)) qa_path <- file.path(dirname(base), "01_inputs", "01_input_QA.csv")
  manifest_path <- low_network_required_file(manifest_path, 65536)
  qa_path <- low_network_required_file(qa_path, 65536)
  man <- low_network_read_kv(manifest_path, "key")
  qa <- low_network_read_kv(qa_path, "item")
  get_value <- function(x, key_column, key) {
    value <- x$value[x[[key_column]] == key]
    if (length(value) != 1L) stop("MISSING_METADATA_KEY: ", key)
    value
  }
  manifest_value <- function(key) get_value(man, "key", key)
  if (manifest_value("pointer_scheme") != "whitebox" ||
      manifest_value("test_id") != "E200000_N6900000" ||
      !identical(suppressWarnings(as.numeric(manifest_value("cell_size_m"))), 2))
    stop("MANIFEST_GRID_OR_POINTER_CONTRACT_MISMATCH")
  if ("run_mode" %in% man$key && manifest_value("run_mode") == "NATIONAL")
    stop("NATIONAL_LOCKED")
  manifest_source <- function(key, expected_name) {
    path <- manifest_value(key)
    if (!grepl("^/", path) || basename(path) != expected_name)
      stop("EXPECTED_ABSOLUTE_MANIFEST_RASTER: ", key)
    low_network_required_file(path)
  }
  files <- list(
    pointer = low_network_required_file(file.path(base, "d8_pointer_land_water_FLT8S.tif")),
    water = manifest_source("water_class_raster", "ranta10_water_class.tif"),
    lake = manifest_source("lake_id_raster", "ranta10_lake_id.tif"),
    land = low_network_required_file(file.path(base, "routing_surface_land_water_FLT8S.tif"))
  )
  if (anyDuplicated(unlist(files, use.names = FALSE))) stop("RASTER_PATHS_NOT_DISTINCT")
  if (!is.list(backend) || !all(c("open", "header", "read_window") %in% names(backend)) ||
      !all(vapply(backend[c("open", "header", "read_window")], is.function, logical(1))))
    stop("INVALID_RASTER_BACKEND")
  rasters <- lapply(files, backend$open)
  headers <- lapply(rasters, backend$header)
  finite <- function(x, n) is.numeric(x) && length(x) == n && all(is.finite(x))
  header_ok <- function(h) {
    is.list(h) && all(c("nrow", "ncol", "nlyr", "resolution", "xmin", "xmax", "ymin", "ymax", "crs_ok") %in% names(h)) &&
      finite(h$nrow, 1L) && finite(h$ncol, 1L) &&
      h$nrow >= 11 && h$ncol >= 11 && h$nrow == floor(h$nrow) && h$ncol == floor(h$ncol) &&
      finite(h$nlyr, 1L) && h$nlyr == 1 && # nlyr may be integer OR double.
      finite(h$resolution, 2L) && all(abs(h$resolution - 2) <= 1e-9) &&
      all(vapply(h[c("xmin", "xmax", "ymin", "ymax")], finite, logical(1), n = 1L)) &&
      isTRUE(h$crs_ok) &&
      abs(h$xmax - h$xmin - h$ncol * 2) <= 1e-7 &&
      abs(h$ymax - h$ymin - h$nrow * 2) <= 1e-7
  }
  if (!all(vapply(headers, header_ok, logical(1)))) stop("INVALID_RASTER_GEOMETRY_OR_CRS")
  ref <- headers$pointer
  same_geometry <- function(h) {
    h$nrow == ref$nrow && h$ncol == ref$ncol &&
      all(vapply(c("xmin", "xmax", "ymin", "ymax"), function(k)
        abs(h[[k]] - ref[[k]]) <= 1e-7, logical(1)))
  }
  if (!all(vapply(headers, same_geometry, logical(1)))) stop("RASTER_GEOMETRY_MISMATCH")
  # Production CLI pins the previously observed LOW grid. The optional worker
  # argument leaves the existing small synthetic backends testable.
  if (!is.null(expected_full_grid)) {
    if (!is.list(expected_full_grid) ||
        !identical(sort(names(expected_full_grid)), c("ncol", "nrow")) ||
        !all(vapply(expected_full_grid, function(x) finite(x, 1L) &&
          x >= 11 && x == floor(x), logical(1)))) stop("INVALID_EXPECTED_FULL_GRID")
    if (ref$nrow != expected_full_grid$nrow || ref$ncol != expected_full_grid$ncol)
      stop("LOCKED_LOW_GRID_MISMATCH: no alternative window selected")
  }
  expected_qa <- c(dem_rows = ref$nrow, dem_cols = ref$ncol,
                   dem_res_x = 2, dem_res_y = 2,
                   xmin = ref$xmin, xmax = ref$xmax, ymin = ref$ymin, ymax = ref$ymax)
  observed_qa <- vapply(names(expected_qa), function(k) {
    x <- suppressWarnings(as.numeric(get_value(qa, "item", k)))
    if (length(x) != 1L || !is.finite(x)) stop("INVALID_QA_NUMBER: ", k)
    x
  }, numeric(1))
  if (any(abs(observed_qa - expected_qa) > 1e-7)) stop("INPUT_QA_GEOMETRY_MISMATCH")
  if (!is.character(code_revision) || length(code_revision) != 1L ||
      is.na(code_revision) || !nzchar(trimws(code_revision))) stop("INVALID_CODE_REVISION")
  if (!is.logical(emit) || length(emit) != 1L || is.na(emit)) stop("INVALID_EMIT_FLAG")
  if (!exists("build_land_d8_network", mode = "function") ||
      !exists("select_land_network_cases", mode = "function") ||
      !exists("analyse_land_network_topology", mode = "function"))
    stop("Source the reviewed land-network functions first.")

  # Window depends on checked headers ONLY; no 02B or values inform selection.
  window <- low_network_window(ref$nrow, ref$ncol)
  read_count <- 0L
  values_returned <- 0L
  matrices <- lapply(rasters, function(r) {
    x <- backend$read_window(r, window$row_start, window$col_start, 11L, 11L)
    read_count <<- read_count + 1L
    if (!is.numeric(x) || !is.null(dim(x)) || length(x) != 121L)
      stop("BAD_BOUNDED_RASTER_READ")
    values_returned <<- values_returned + length(x)
    matrix(as.numeric(x), nrow = 11L, ncol = 11L, byrow = TRUE)
  })
  if (read_count != 4L || values_returned != 484L) stop("RASTER_READ_BUDGET_MISMATCH")
  grid <- list(grid_id = "LOW-E200000-N6900000", nrow = 11L, ncol = 11L,
               row_offset = window$row_start - 1, col_offset = window$col_start - 1,
               xmin = ref$xmin, ymax = ref$ymax, resolution_m = 2, crs = "EPSG:3067")
  provenance <- list(run_id = "LOW-fixed-geographic-centre-network-window",
    code_revision = code_revision, pointer_source = files$pointer,
    water_source = files$water, lake_id_source = files$lake,
    validity_source = files$land, lake_id_namespace = "RANTA10:UNVERIFIED_VERSION")
  network <- build_land_d8_network(matrices$pointer, matrices$water,
                                   is.finite(matrices$land), grid, provenance,
                                   lake_id = matrices$lake, max_steps = 32L)
  if (network$work_budget$n_transitions > 3872 || network$work_budget$n_cell_reads > 3993)
    stop("IN_MEMORY_WORK_BUDGET_EXCEEDED")
  topology_inventory <- analyse_land_network_topology(network,
    full_grid = list(nrow = ref$nrow, ncol = ref$ncol))
  core_cases <- select_land_network_cases(network, scope = "core")
  halo_cases <- select_land_network_cases(network, scope = "halo")
  statuses <- c("D8_ZERO", "POINTER_NA", "INVALID_POINTER", "NO_DATA", "INVALID_WATER_CLASS",
                "CYCLE", "DOMAIN_EXIT_UNRESOLVED", "STEP_LIMIT", "FIRST_WATER_CONTACT")
  route_counts <- do.call(rbind, lapply(c("window", "core", "halo"), function(scope) {
    keep <- switch(scope, window = rep(TRUE, nrow(network$route_summary)),
                   core = network$route_summary$is_core, halo = network$route_summary$is_halo)
    data.frame(scope = scope, route_status = statuses,
               n_routes = as.integer(table(factor(network$route_summary$route_status[keep], levels = statuses))),
               stringsAsFactors = FALSE)
  }))
  contacts <- data.frame(source_uid = character(), source_is_core = logical(),
    first_water_uid = character(), water_class = numeric(), lake_objectid = numeric(),
    n_transitions = numeric(), stringsAsFactors = FALSE)
  contact_rows <- which(network$route_summary$route_status == "FIRST_WATER_CONTACT")
  if (length(contact_rows)) contacts <- do.call(rbind, lapply(contact_rows, function(i) {
    route <- network$routes[[network$route_summary$source_uid[i]]]
    data.frame(source_uid = route$source$cell_uid,
      source_is_core = network$route_summary$is_core[i], first_water_uid = route$first_water$cell_uid,
      water_class = route$contact$water_class, lake_objectid = route$contact$lake_objectid,
      n_transitions = route$n_transitions, stringsAsFactors = FALSE)
  }))
  result <- list(network = network, topology_inventory = topology_inventory,
    core_cases = core_cases, halo_cases = halo_cases,
    route_counts = route_counts, contacts = contacts, files = files, headers = headers,
    manifest_path = manifest_path, qa_path = qa_path, manifest = man, qa = qa,
    window = window, raster_reads = read_count, raster_values_returned = values_returned,
    code_revision = code_revision, code_version_verification = "DECLARED_ONLY",
    historical_source_commit = "UNKNOWN", historical_provenance = "INCOMPLETE",
    geometry_check = "PASS", provenance = provenance)
  if (emit) low_network_print_result(result)
  invisible(result)
}

low_network_print_result <- function(result, inventory_row_limit = 121L) {
  n <- result$network
  w <- result$window
  cat("========== TULOKSET ALKAVAT ==========\n")
  cat("MODE=READ_ONLY FIXED_GEOGRAPHIC_CENTRE NO_02B_SELECTION\n")
  cat("COMMIT=", result$code_revision, " CODE_VERSION_VERIFICATION=", result$code_version_verification, "\n", sep = "")
  cat("HISTORICAL_SOURCE_COMMIT=", result$historical_source_commit,
      " HISTORICAL_PROVENANCE=", result$historical_provenance, "\n", sep = "")
  cat("MANIFEST=", result$manifest_path, "\nQA=", result$qa_path, "\n", sep = "")
  cat("GEOMETRY_CHECK=", result$geometry_check, " CRS=EPSG:3067 RESOLUTION_M=2\n", sep = "")
  for (key in names(result$files)) {
    h <- result$headers[[key]]
    cat("RASTER", key, "PATH", result$files[[key]], "ROWS", h$nrow, "COLS", h$ncol,
        "LAYERS", h$nlyr, "EXTENT", h$xmin, h$xmax, h$ymin, h$ymax, "\n")
  }
  cat("DECLARED_PROVENANCE\n"); print(as.data.frame(result$provenance, stringsAsFactors = FALSE), row.names = FALSE)
  cat("PROVENANCE_VERIFICATION=DECLARED_ONLY\n")
  cat("WINDOW_GLOBAL_ROWS", w$row_start, w$row_end, "COLS", w$col_start, w$col_end, "\n")
  cat("CORE_GLOBAL_ROWS", w$core_row_start, w$core_row_end, "COLS", w$core_col_start, w$core_col_end, "\n")
  cat("VALID_LAND CORE", sum(n$land_nodes$is_core), "HALO", sum(n$land_nodes$is_halo), "\n")
  cat("LAND_TO_LAND_EDGE_COUNTS\n"); print(n$land_edge_zone_counts, row.names = FALSE)
  cat("CORE_CONFLUENCES", sum(n$confluences$is_core), "HALO_CONFLUENCES", sum(n$confluences$is_halo), "\n")
  cat("CORE_CASES\n"); print(result$core_cases, row.names = FALSE)
  cat("HALO_CASES\n"); print(result$halo_cases, row.names = FALSE)
  cat("ROUTE_STATUS_COUNTS\n"); print(result$route_counts, row.names = FALSE)
  cat("FIRST_RANTA10_CONTACTS\n")
  if (nrow(result$contacts)) print(result$contacts, row.names = FALSE) else cat("NOT_OBSERVED\n")
  low_network_print_inventory(result$topology_inventory, n, row_limit = inventory_row_limit)
  cat("RASTER_READ_CALLS", result$raster_reads, "RETURNED_VALUES", result$raster_values_returned,
      "IN_MEMORY_TRANSITIONS", n$work_budget$n_transitions,
      "CELL_OBSERVATION_CALLS", n$work_budget$n_cell_reads, "MAX_STEPS=32\n")
  cat("WINDOW_CENSORED=TRUE external_inflow=UNKNOWN upstream_coverage=WINDOW_ONLY accumulation=NOT_COMPUTED\n")
  cat("DOMAIN_EXIT_UNRESOLVED_AND_STEP_LIMIT_ARE_CENSORED_NOT_PHYSICAL_BREAKS\n")
  cat("hydrological_validation=NOT_ASSESSED channel_interpretation=NOT_ASSESSED\n")
  cat("MODERATE=REVIEW_REQUIRED NATIONAL=LOCKED\n")
  cat("========== TULOKSET LOPPUVAT ==========\n")
}

# Noncryptographic inventory checksum only, never raster provenance or approval.
# Serialize the COMPLETE typed table in ASCII v2; no temporary file or package.
low_network_inventory_checksum <- function(x) {
  payload <- serialize(x, NULL, ascii = TRUE, version = 2)
  a <- 1; b <- 0
  for (byte in as.integer(payload)) {
    a <- (a + byte) %% 65521
    b <- (b + a) %% 65521
  }
  sprintf("%04x%04x", as.integer(b), as.integer(a))
}

# All tables remain in the result; stdout is bounded without hiding totals.
low_network_print_inventory <- function(inventory, network, row_limit = 121L) {
  if (!is.numeric(row_limit) || length(row_limit) != 1L || !is.finite(row_limit) ||
      row_limit != floor(row_limit) || row_limit < 1 || row_limit > 121^2)
    stop("INVALID_INVENTORY_PRINT_LIMIT")
  metadata <- list()
  show_table <- function(label, x) {
    printed <- min(nrow(x), row_limit)
    checksum <- low_network_inventory_checksum(x)
    metadata[[length(metadata) + 1L]] <<- data.frame(inventory = label,
      total_rows = nrow(x), printed_rows = printed, truncated = printed < nrow(x),
      checksum = checksum, stringsAsFactors = FALSE)
    cat(label, "TOTAL_ROWS", nrow(x), "PRINTED_ROWS", printed,
        "TRUNCATED", printed < nrow(x), "ADLER32_SERIALIZE_ASCII_V2", checksum, "\n")
    if (!nrow(x)) cat("NOT_OBSERVED\n") else
      print(head(x, row_limit), row.names = FALSE, max = printed * ncol(x) + 1L)
  }
  show_table("UNIQUE_INTERNAL_EDGES", network$edges)
  for (scope in c("CORE", "HALO")) {
    keep <- if (scope == "CORE") inventory$confluence_details$is_core else
      inventory$confluence_details$is_halo
    details <- inventory$confluence_details[keep, , drop = FALSE]
    show_table(paste0(scope, "_CONFLUENCE_DETAILS"), details)
    incoming <- inventory$confluence_incoming[
      inventory$confluence_incoming$confluence_uid %in% details$confluence_uid, , drop = FALSE]
    show_table(paste0(scope, "_CONFLUENCE_INCOMING_EDGES"), incoming)
  }
  show_table("SHARED_DOWNSTREAM_SEGMENTS", inventory$shared_segments)
  show_table("SHARED_SEGMENT_CELLS", inventory$segment_cells)
  show_table("SHARED_SEGMENT_EDGES", inventory$segment_edges)
  show_table("SOURCE_CONFLUENCE_MEMBERSHIP", inventory$source_confluences)
  show_table("UNIQUE_WINDOW_EXIT_EDGES", inventory$exit_edges)
  show_table("SOURCE_ROUTES_PER_EXIT", inventory$source_routes_per_exit)
  show_table("TOPOLOGY_ACCOUNTING_QA", inventory$accounting_qa)
  cat("INVENTORY_PRINT_ROW_LIMIT", row_limit,
      "CHECKSUM_NONCRYPTOGRAPHIC=TRUE COMPLETE_TABLES=RESULT_TOPOLOGY_INVENTORY OUTSIDE_RASTER_READS=0\n")
  invisible(do.call(rbind, metadata))
}

low_network_cli <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) > 1L) stop("Usage: Rscript run_one_low_network_window.R [BASELINE_DIR]")
  script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(script_arg) != 1L) stop("Rscript --file= required")
  here <- dirname(normalizePath(sub("^--file=", "", script_arg), mustWork = TRUE))
  repo <- dirname(dirname(here))
  git <- function(arguments) {
    out <- suppressWarnings(system2("git", c("-C", shQuote(repo), arguments), stdout = TRUE, stderr = TRUE))
    status <- attr(out, "status")
    if (!is.null(status) && status != 0L) stop("LOCAL_GIT_CHECK_FAILED")
    out
  }
  origin <- git(c("remote", "get-url", "origin"))
  if (length(origin) != 1L || !origin %in% c("https://github.com/annasuuronen/MaaltaMerelle.git",
      "https://github.com/annasuuronen/MaaltaMerelle", "git@github.com:annasuuronen/MaaltaMerelle.git"))
    stop("WRONG_REPOSITORY_ORIGIN")
  commit <- git(c("rev-parse", "HEAD"))
  if (length(commit) != 1L || !grepl("^[0-9a-f]{40}$", commit) ||
      length(git(c("status", "--porcelain", "--untracked-files=normal"))))
    stop("A_CLEAN_COMMITTED_CHECKOUT_IS_REQUIRED")
  expected <- Sys.getenv("MM_EXPECTED_COMMIT", unset = "")
  if (nzchar(expected) && (!grepl("^[0-9a-f]{40}$", expected) || expected != commit))
    stop("EXPECTED_COMMIT_MISMATCH")
  source(file.path(here, "..", "low_d8_scope", "lake_1847_focus_core.R"), local = FALSE)
  source(file.path(here, "..", "land_first_water", "first_water_contact.R"), local = FALSE)
  source(file.path(here, "..", "land_d8_continuity", "trace_land_d8_route.R"), local = FALSE)
  source(file.path(here, "land_network_topology.R"), local = FALSE)
  source(file.path(here, "analyse_land_network_topology.R"), local = FALSE)
  base <- if (length(args)) args[[1L]] else paste0(
    "/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/",
    "runs/E200000_N6900000/02_baseline")
  result <- run_one_low_network_window(base, code_revision = commit, emit = FALSE,
    expected_full_grid = list(nrow = 6000, ncol = 6000))
  result$code_version_verification <- "LOCAL_GIT_CLEAN"
  low_network_print_result(result)
  invisible(result)
}

if (sys.nframe() == 0L) low_network_cli()
