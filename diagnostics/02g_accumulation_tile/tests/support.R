root <- dirname(here)
repo <- normalizePath(file.path(root, "..", ".."))
source(file.path(repo, "diagnostics/low_d8_scope/lake_1847_focus_core.R"))
source(file.path(repo, "diagnostics/land_first_water/first_water_contact.R"))
source(file.path(repo, "diagnostics/land_d8_continuity/trace_land_d8_route.R"))
source(file.path(root, "accumulation.R")); source(file.path(root, "tiles.R"))
checks <- 0L
check <- function(ok, label = "check") {
  checks <<- checks + 1L
  if (!isTRUE(ok)) stop("02G_TEST_FAILURE: ", label, call. = FALSE)
}
reject <- function(expr) check(inherits(tryCatch({ force(expr); NULL }, error = identity), "error"), "invalid input rejected")
fixture <- function(nr = 3L, nc = 5L, land, arcs, water = integer(), water_class = 1,
                    boundary = integer(), missing_pointer = integer(), invalid_pointer = integer()) {
  n <- nr * nc; id <- seq_len(n); row <- (id - 1L) %/% nc + 1L; col <- (id - 1L) %% nc + 1L
  cells <- data.frame(cell = id, pointer = rep(0, n), water_class = rep(NA_real_, n),
    lake_id = rep(NA_real_, n), valid = id %in% c(land, water))
  successor <- integer(n); if (length(arcs)) successor[arcs[, 1]] <- arcs[, 2]
  for (from in which(successor > 0)) {
    to <- successor[from]; key <- paste(row[to] - row[from], col[to] - col[from], sep = ":")
    code <- c("-1:1" = 1, "0:1" = 2, "1:1" = 4, "1:0" = 8, "1:-1" = 16, "0:-1" = 32, "-1:-1" = 64, "-1:0" = 128)[key]
    stopifnot(!is.na(code)); cells$pointer[from] <- code
  }
  cells$water_class[water] <- water_class; cells$lake_id[water] <- if (water_class == 1) 9001 else NA_real_
  cells$pointer[boundary] <- 2; cells$pointer[missing_pointer] <- NA_real_; cells$pointer[invalid_pointer] <- 3
  terminal <- rep("D8_ZERO", n); terminal[successor > 0] <- ""; terminal[boundary] <- "DOMAIN_EXIT_UNRESOLVED"
  terminal[missing_pointer] <- "POINTER_NA"; terminal[invalid_pointer] <- "INVALID_POINTER"
  kind <- rep("NO_DATA", n); kind[land] <- "LAND"; kind[water] <- "WATER"
  g <- list(grid_id = "SYNTHETIC-02G", nrow = nr, ncol = nc, row_offset = 100L, col_offset = 200L,
    xmin = 200000, ymax = 6900000, resolution_m = 2, crs = "EPSG:3067")
  p <- list(run_id = "synthetic-02g", code_revision = "02g-fixture-v1", pointer_source = "generated",
    water_source = "generated", lake_id_source = "generated", validity_source = "generated",
    lake_id_namespace = "SYNTHETIC_ONLY", synthetic = TRUE)
  list(cells = cells, successor = successor, terminal = terminal, kind = kind, grid = g, provenance = p)
}
# Independent explicit source sets: follows known fixture successor IDs, never
# production pointers/decoder/routes, and partitions each seed exactly once.
reference <- function(f, cap, available = seq_len(nrow(f$cells))) {
  sources <- available[f$kind[available] == "LAND"]
  sets <- setNames(rep(list(integer()), length(available)), as.character(available))
  endings <- integer(length(sources)); statuses <- character(length(sources)); cycles <- integer()
  for (i in seq_along(sources)) {
    cell <- sources[i]; seen <- integer(); moved <- 0L
    repeat {
      if (!cell %in% available) { status <- "MISSING_NEIGHBOUR_TILE"; break }
      if (cell %in% seen) { status <- "CYCLE"; cycles <- union(cycles, seen[match(cell, seen):length(seen)]); break }
      seen <- c(seen, cell)
      if (f$kind[cell] != "LAND") { status <- if (f$kind[cell] == "WATER") "FIRST_WATER_CONTACT" else f$kind[cell]; break }
      sets[[as.character(cell)]] <- union(sets[[as.character(cell)]], sources[i])
      if (nzchar(f$terminal[cell]) && f$terminal[cell] != "DOMAIN_EXIT_UNRESOLVED") { status <- f$terminal[cell]; break }
      if (moved == cap) { status <- "STEP_LIMIT"; break }
      if (f$terminal[cell] == "DOMAIN_EXIT_UNRESOLVED") { status <- "DOMAIN_EXIT_UNRESOLVED"; break }
      cell <- f$successor[cell]; moved <- moved + 1L
    }
    endings[i] <- cell; statuses[i] <- status
  }
  list(sources = sources, sets = sets, endings = endings, statuses = statuses, cycles = cycles)
}
verify <- function(f, result, cap, available = seq_len(nrow(f$cells))) {
  ref <- reference(f, cap, available); ids <- g02_uid(ref$sources, f$grid)
  check(identical(result$nodes$cell_uid, ids), "exact source identities")
  check(identical(result$source_ledger$endpoint_type, ref$statuses), "independent endpoint partition")
  for (i in seq_along(ref$sources)) {
    cell <- ref$sources[i]; expected <- ref$sets[[as.character(cell)]]
    check(setequal(result$source_sets[[i]], g02_uid(expected, f$grid)), "independent source membership")
    check(result$nodes$observed_source_count[i] == length(expected), "unique observed count")
    if (cell %in% ref$cycles) check(is.na(result$nodes$local_upstream_cells[i]), "cycle A undefined") else
      check(result$nodes$local_upstream_cells[i] == length(expected) && result$nodes$local_upstream_area_m2[i] == 4 * length(expected), "local area")
  }
  for (i in seq_len(nrow(result$water))) {
    cell <- match(result$water$cell_uid[i], g02_uid(seq_len(nrow(f$cells)), f$grid))
    expected <- ref$sources[ref$statuses == "FIRST_WATER_CONTACT" & ref$endings == cell]
    check(setequal(result$water_source_sets[[i]], g02_uid(expected, f$grid)) &&
      result$water$local_source_cells[i] == length(expected), "first water unique sources")
  }
  check(result$balance$n_sources == length(ids) && result$balance$n_sources ==
    result$balance$n_first_water + result$balance$n_unresolved + result$balance$n_approved_exports, "source conservation")
  check(result$balance$n_approved_exports == 0 && !anyDuplicated(result$source_ledger$source_uid), "no approved outlet or duplicated seed")
  check(result$channel_threshold_cells == 10000 && result$channel_threshold_area_m2 == 40000 &&
    nrow(result$nodes) == length(ids), "4 ha presentation threshold never filters paths")
  check(result$hydrological_validation == "NOT_ASSESSED" && result$channel_interpretation == "NOT_ASSESSED" &&
    result$MODERATE == "REVIEW_REQUIRED" && result$NATIONAL == "LOCKED", "scientific locks")
  invisible(ref)
}
run_fixture <- function(f, cap = 32L, external = "UNKNOWN") {
  obs <- g02_observe(f$cells, f$grid, f$provenance, cap)
  g02_accumulate(obs$cells, obs$routes, f$grid, f$provenance, external_import = external)
}
