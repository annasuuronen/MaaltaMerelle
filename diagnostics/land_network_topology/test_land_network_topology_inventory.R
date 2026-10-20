#!/usr/bin/env Rscript
# Synthetic memory networks only: no raster reads, CSC or new routing.
s <- grep("^--file=", commandArgs(), value = TRUE)
stopifnot(length(s) == 1L)
here <- dirname(normalizePath(sub("^--file=", "", s)))
source(file.path(here, "..", "low_d8_scope", "lake_1847_focus_core.R"))
source(file.path(here, "..", "land_first_water", "first_water_contact.R"))
source(file.path(here, "..", "land_d8_continuity", "trace_land_d8_route.R"))
source(file.path(here, "land_network_topology.R"))
source(file.path(here, "analyse_land_network_topology.R"))

assert <- function(x, message = "Assertion failed") {
  if (!isTRUE(x)) stop(message, call. = FALSE)
}
expect_error <- function(expr) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  assert(inherits(error, "error"), "Expected rejected input")
}
grid <- list(grid_id = "synthetic-inventory", nrow = 5L, ncol = 5L,
  row_offset = 0L, col_offset = 0L, xmin = 200000, ymax = 6900010,
  resolution_m = 2, crs = "EPSG:3067")
provenance <- list(run_id = "synthetic-inventory", code_revision = "fixture-v1",
  pointer_source = "synthetic-LAND_WATER-D8", water_source = "synthetic-water",
  lake_id_source = "synthetic-lake-id", validity_source = "synthetic-validity",
  lake_id_namespace = "synthetic-lake-namespace")
fixture <- function() list(pointer = matrix(0, 5L, 5L),
  water = matrix(NA_real_, 5L, 5L), lake = matrix(NA_real_, 5L, 5L),
  valid = matrix(FALSE, 5L, 5L))
mark <- function(f, cells, pointer = 0, water = NA_real_, lake = NA_real_, valid = TRUE) {
  rc <- cbind((cells - 1L) %/% 5L + 1L, (cells - 1L) %% 5L + 1L)
  f$pointer[rc] <- pointer; f$water[rc] <- water
  f$lake[rc] <- lake; f$valid[rc] <- valid
  f
}
network <- function(f, g = grid, max_steps = 32L) {
  build_land_d8_network(f$pointer, f$water, f$valid, g, provenance,
    lake_id = f$lake, max_steps = max_steps)
}
one_exit <- function() {
  f <- mark(fixture(), 7L, 4)
  f <- mark(f, c(12L, 13L, 14L, 15L), 2)
  f
}
uid <- function(n, cell) n$cells$cell_uid[match(cell, n$cells$local_cell)]
analyse <- function(n, full_grid = NULL) {
  a <- analyse_land_network_topology(n, full_grid = full_grid)
  assert(a$accumulation == "NOT_COMPUTED")
  assert(a$external_inflow == "UNKNOWN")
  assert(a$hydrological_validation == "NOT_ASSESSED")
  assert(a$channel_interpretation == "NOT_ASSESSED")
  assert(a$MODERATE == "REVIEW_REQUIRED" && a$NATIONAL == "LOCKED")
  assert(nrow(a$accounting_qa) == 1L && a$accounting_qa$direct_partition_ok)
  assert(a$accounting_qa$route_allocation_ok)
  assert(!anyDuplicated(a$exit_edges$exit_id))
  assert(!anyDuplicated(a$source_routes_per_exit[, c("exit_id", "source_uid")]))
  assert(!any(a$exit_edges$receiver_raster_read))
  assert(nrow(a$exit_edges) <= 121L && nrow(a$source_routes_per_exit) <= 121L)
  a
}
qa <- new.env(parent = emptyenv()); qa$total <- 0L; qa$failed <- character()
case <- function(label, expr) {
  qa$total <- qa$total + 1L
  tryCatch({ force(expr); cat("PASS:", label, "\n") }, error = function(e) {
    qa$failed <- c(qa$failed, label)
    cat("FAIL:", label, "-", conditionMessage(e), "\n")
  })
}

case("two land branches merge and share one unique boundary exit", {
  n <- network(one_exit()); a <- analyse(n)
  assert(nrow(a$confluence_details) == 1L)
  assert(a$confluence_details$confluence_uid == uid(n, 13L))
  assert(a$confluence_details$land_indegree_in_window == 2L)
  assert(nrow(a$exit_edges) == 1L && a$exit_edges$exit_cell_uid == uid(n, 15L))
  assert(a$exit_edges$n_source_routes == 5L)
  assert(setequal(a$source_routes_per_exit$source_uid, n$land_nodes$cell_uid))
})

case("three independent branches retain three separate exit events", {
  f <- mark(fixture(), 1L, 128)
  f <- mark(f, c(11L, 12L), 32)
  f <- mark(f, c(19L, 24L), 8)
  n <- network(f); a <- analyse(n)
  assert(nrow(a$confluence_details) == 0L && nrow(a$exit_edges) == 3L)
  assert(setequal(a$exit_edges$local_cell, c(1L, 11L, 24L)))
  assert(all(sort(a$exit_edges$n_source_routes) == c(1, 2, 2)))
  assert(sum(a$exit_edges$n_source_routes) == 5L)
})

case("one source can be observed through two consecutive confluences", {
  n <- network(mark(one_exit(), 9L, 8)); a <- analyse(n)
  assert(setequal(a$confluence_details$confluence_uid, uid(n, c(13L, 14L))))
  rows <- a$source_confluences[a$source_confluences$source_uid == uid(n, 7L), ]
  assert(nrow(rows) == 2L && setequal(rows$confluence_uid, uid(n, c(13L, 14L))))
  assert(!anyDuplicated(a$source_confluences[, c("source_uid", "confluence_uid")]))
  assert(nrow(a$exit_edges) == 1L && a$exit_edges$n_source_routes == 6L)
})

case("core confluences preserve the identity and code of a halo incoming edge", {
  f <- mark(mark(fixture(), 6L, 4), 7L, 8)
  f <- mark(f, c(12L, 13L, 14L, 15L), 2)
  n <- network(f); a <- analyse(n)
  c <- a$confluence_details[a$confluence_details$local_cell == 12L, ]
  assert(nrow(c) == 1L && c$is_core && !c$is_halo && c$land_indegree_in_window == 2L)
  edges <- a$confluence_incoming[a$confluence_incoming$confluence_uid == uid(n, 12L), ]
  assert(nrow(edges) == 2L && setequal(edges$from_uid, uid(n, c(6L, 7L))))
  assert(sum(edges$from_is_core) == 1L && setequal(edges$d8_code, c(4, 8)))
})

case("shared downstream segments reference deduplicated canonical edges and known lengths", {
  n <- network(one_exit()); a <- analyse(n)
  assert(nrow(a$shared_segments) == 1L)
  segment <- a$shared_segments[1L, ]
  assert(segment$confluence_uid == uid(n, 13L))
  assert(segment$n_observed_edges == 2L && segment$n_unique_edges == 2L)
  assert(segment$n_observed_land_edges == 2L && segment$n_unique_cells == 3L)
  assert(abs(segment$observed_length_m - 4) < 1e-9)
  edges <- a$segment_edges[a$segment_edges$segment_id == segment$segment_id, ]
  assert(!anyDuplicated(edges$edge_id) && all(edges$edge_id %in% n$edges$edge_id))
  assert(identical(edges$from_uid, uid(n, c(13L, 14L))))
  assert(identical(edges$to_uid, uid(n, c(14L, 15L))))
  cells <- a$segment_cells[a$segment_cells$segment_id == segment$segment_id, ]
  assert(identical(cells$cell_uid, uid(n, c(13L, 14L, 15L))))
  for (source in c(7L, 12L)) {
    membership <- a$source_confluences[a$source_confluences$source_uid == uid(n, source), ]
    assert(membership$n_unique_shared_edges == 2L)
  }
})

case("exit groups contain each observed source once including the direct exit cell", {
  n <- network(one_exit()); a <- analyse(n)
  group <- a$source_routes_per_exit
  assert(nrow(group) == 5L && length(unique(group$source_uid)) == 5L)
  direct <- group[group$source_uid == uid(n, 15L), ]
  assert(nrow(direct) == 1L && direct$n_transitions == 0L)
  assert(all(group$exit_cell_uid == uid(n, 15L)))
  assert(a$accounting_qa$n_exit_terminating_routes == 5L)
})

case("shared geometry measures observed diagonal steps without inventing an exit step", {
  f <- mark(mark(fixture(), 7L, 4), 12L, 2)
  f <- mark(f, c(13L, 19L, 25L), 4)
  n <- network(f); a <- analyse(n)
  assert(a$shared_segments$n_observed_edges == 2L)
  assert(abs(a$shared_segments$observed_length_m - 2 * sqrt(8)) < 1e-9)
  assert(all(abs(a$segment_edges$step_length_m - sqrt(8)) < 1e-9))
  assert(a$exit_edges$exit_cell_uid == uid(n, 25L))
})

case("a boundary cell pointing inward is not a direct exit", {
  n <- network(mark(mark(fixture(), 11L, 2), 12L))
  a <- analyse(n)
  assert(n$cells$on_window_boundary[11L])
  assert(nrow(a$exit_edges) == 0L && nrow(a$source_routes_per_exit) == 0L)
  assert(a$accounting_qa$n_nonexit_routes == 2L)
})

case("an outward receiver is only predicted from an already observed core direction", {
  n <- network(one_exit()); a <- analyse(n, list(nrow = 5L, ncol = 5L))
  e <- a$exit_edges[1L, ]
  assert(e$d8_code == 2 && e$direction == "E")
  assert(e$predicted_receiver_row == 3L && e$predicted_receiver_col == 6L)
  assert(!e$receiver_raster_read)
  assert(e$receiver_status == "FULL_GRID_EXIT" && is.na(e$predicted_receiver_uid))
  assert(!e$predicted_receiver_uid %in% n$cells$cell_uid)
})

case("an exit code absent from observed internal edges stays explicitly unknown", {
  n <- network(mark(fixture(), 1L, 128)); a <- analyse(n)
  assert(nrow(a$exit_edges) == 1L && a$exit_edges$d8_code == 128)
  assert(is.na(a$exit_edges$predicted_receiver_row) && is.na(a$exit_edges$predicted_receiver_col))
  assert(a$exit_edges$direction == "UNKNOWN")
  assert(!a$exit_edges$receiver_raster_read)
})

case("full-grid exits differ from local-window exits and missing full-grid knowledge", {
  n <- network(one_exit())
  outside <- analyse(n, list(nrow = 5, ncol = 5))$exit_edges$receiver_status
  inside <- analyse(n, list(nrow = 50, ncol = 50))$exit_edges$receiver_status
  unknown <- analyse(n)$exit_edges$receiver_status
  assert(outside != inside && unknown != inside && unknown != outside)
})

case("zero pointers and missing or invalid pointers never become exit events", {
  for (p in c(0, NA_real_, 3, Inf)) {
    n <- network(mark(fixture(), 12L, p)); a <- analyse(n)
    expected <- if (is.na(p)) "POINTER_NA" else if (p == 0) "D8_ZERO" else "INVALID_POINTER"
    assert(nrow(a$exit_edges) == 0L && nrow(a$source_routes_per_exit) == 0L)
    assert(a$route_status_counts$n_routes[a$route_status_counts$route_status == expected] == 1L)
    assert(!a$accounting_qa$n_minus_e_applicable)
  }
})

case("NoData targets remain explicit internal unusable transitions rather than exits", {
  n <- network(mark(fixture(), 12L, 2)); a <- analyse(n)
  assert(nrow(a$exit_edges) == 0L && a$accounting_qa$n_other_internal_edges == 1L)
  assert(a$route_status_counts$n_routes[a$route_status_counts$route_status == "NO_DATA"] == 1L)
  assert(!a$accounting_qa$n_minus_e_applicable)
})

case("cycles remain bounded observations without inventing exits or accumulation", {
  n <- network(mark(mark(fixture(), 12L, 2), 13L, 32)); a <- analyse(n)
  assert(nrow(a$exit_edges) == 0L && a$accounting_qa$n_nonexit_routes == 2L)
  assert(a$route_status_counts$n_routes[a$route_status_counts$route_status == "CYCLE"] == 2L)
  assert(!a$accounting_qa$n_minus_e_applicable && a$accumulation == "NOT_COMPUTED")
})

case("capped source routes are not extended to a graph-reachable exit", {
  n <- network(mark(fixture(), c(13L, 14L, 15L), 2), max_steps = 1L)
  a <- analyse(n)
  assert(nrow(a$exit_edges) == 1L && a$exit_edges$local_cell == 15L)
  assert(nrow(a$source_routes_per_exit) == 1L && a$source_routes_per_exit$source_uid == uid(n, 15L))
  assert(a$route_status_counts$n_routes[a$route_status_counts$route_status == "STEP_LIMIT"] == 2L)
  assert(!a$accounting_qa$n_minus_e_applicable)
})

case("a capped source reaching a confluence cannot claim its longer observed suffix", {
  n <- network(one_exit(), max_steps = 1L); a <- analyse(n)
  assert(a$shared_segments$n_observed_edges == 1L)
  for (source in c(7L, 12L)) {
    m <- a$source_confluences[a$source_confluences$source_uid == uid(n, source), ]
    assert(nrow(m) == 1L && m$reached_at_step == 1L)
    assert(m$n_observed_shared_edges == 0L && m$source_route_status == "STEP_LIMIT")
    assert(m$shared_extent == "PARTIAL_OBSERVED_SUFFIX")
  }
})

case("N minus E equals zero in a complete cycle without validating an exit identity", {
  g <- grid; g$nrow <- 1L; g$ncol <- 2L
  n <- build_land_d8_network(matrix(c(2, 32), 1, 2), matrix(NA_real_, 1, 2),
    matrix(TRUE, 1, 2), g, provenance)
  a <- analyse(n)
  assert(a$accounting_qa$all_cells_valid_land && a$accounting_qa$n_minus_internal_edges == 0L)
  assert(a$accounting_qa$n_exit_events == 0L && !a$accounting_qa$all_source_routes_exit)
  assert(!a$accounting_qa$n_minus_e_applicable && a$accounting_qa$n_minus_e_check == "NOT_APPLICABLE")
})

case("local indegree and observed source memberships are not total accumulation", {
  n <- network(one_exit()); a <- analyse(n)
  assert(a$confluence_details$land_indegree_in_window == 2L)
  assert(a$exit_edges$n_source_routes == 5L)
  assert(a$confluence_details$external_inflow == "UNKNOWN")
  assert(a$accumulation == "NOT_COMPUTED" && a$external_inflow == "UNKNOWN")
})

case("global offsets remain stable for confluences and predicted exit recipients", {
  g <- grid; g$row_offset <- 2994; g$col_offset <- 2994
  n <- network(one_exit(), g); a <- analyse(n, list(nrow = 6000, ncol = 6000))
  c <- a$confluence_details[1L, ]
  assert(c$confluence_uid == "synthetic-inventory:2997:2997")
  assert(c$global_row == 2997 && c$global_col == 2997)
  assert(a$exit_edges$global_row == 2997 && a$exit_edges$global_col == 2999)
  assert(a$exit_edges$predicted_receiver_row == 2997 && a$exit_edges$predicted_receiver_col == 3000)
})

case("water-only and NoData-only windows return typed empty inventories", {
  for (f in list(fixture(), mark(fixture(), 1:25, water = 1, lake = 9001))) {
    a <- analyse(network(f))
    for (name in c("confluence_details", "confluence_incoming", "shared_segments", "segment_cells",
                   "segment_edges", "source_confluences", "exit_edges", "source_routes_per_exit")) {
      assert(is.data.frame(a[[name]]) && nrow(a[[name]]) == 0L)
    }
    assert(a$accounting_qa$n_land_nodes == 0L && a$accounting_qa$n_exit_events == 0L)
  }
})

case("N minus internal edges is conditional and never forced to sixteen", {
  n <- network(one_exit()); a <- analyse(n)
  assert(a$accounting_qa$n_land_nodes == 5L && a$accounting_qa$n_internal_land_edges == 4L)
  assert(a$accounting_qa$n_exit_events == 1L && a$accounting_qa$n_minus_internal_edges == 1L)
  # Other cells in this synthetic window are NoData: all-cell premise is false.
  assert(!a$accounting_qa$n_minus_e_applicable)
  f <- mark(fixture(), 1:25, 2)
  all_land <- analyse(network(f))
  assert(all_land$accounting_qa$n_minus_e_applicable)
  assert(all_land$accounting_qa$n_exit_events == 5L)
  assert(all_land$accounting_qa$n_minus_internal_edges == 5L)
  assert(all_land$accounting_qa$n_exit_difference == 0L && all_land$accounting_qa$n_minus_e_check == "PASS")
})

case("a cycle-closing edge is a canonical reference and finite observed segment", {
  f <- mark(mark(mark(fixture(), 7L, 8), 12L, 2), 13L, 32)
  n <- network(f); a <- analyse(n)
  assert(nrow(a$confluence_details) == 1L && a$confluence_details$local_cell == 12L)
  assert(a$shared_segments$route_status == "CYCLE")
  assert(a$shared_segments$n_unique_edges == 2L && a$shared_segments$n_unique_cells == 2L)
  assert(sum(a$segment_edges$closes_cycle) == 1L)
  assert(!anyDuplicated(a$segment_edges$edge_id))
})

case("inventories are deterministic and leave every source observation unchanged", {
  n <- network(one_exit()); before <- serialize(n, NULL)
  a <- analyse(n); b <- analyse(n)
  assert(identical(a, b) && identical(before, serialize(n, NULL)))
})

case("inventory formation performs no fresh trace or observation callback", {
  n <- network(one_exit())
  local({
    names <- c("l1847_trace", "first_water_contact", "trace_land_d8_route")
    previous <- mget(names, envir = .GlobalEnv)
    on.exit(list2env(previous, envir = .GlobalEnv))
    for (name in names) assign(name, function(...) stop("UNEXPECTED_NEW_TRACE"), envir = .GlobalEnv)
    a <- analyse(n)
    assert(a$accounting_qa$n_exit_events == 1L)
  })
})

case("malformed graph and route identity cannot produce plausible inventories", {
  n <- network(one_exit())
  bad <- n; bad$edges$edge_id[2L] <- bad$edges$edge_id[1L]
  expect_error(analyse_land_network_topology(bad))
  bad <- n; bad$route_summary$source_uid[1L] <- "unknown-source"
  expect_error(analyse_land_network_topology(bad))
  bad <- n; bad$land_nodes$cell_uid[1L] <- "unknown-node"
  expect_error(analyse_land_network_topology(bad))
  bad <- n; bad$land_edges$d8_code[1L] <- 128
  expect_error(analyse_land_network_topology(bad))
  expect_error(analyse_land_network_topology(n, full_grid = list(nrow = NA_real_, ncol = 5L)))
})

if (qa$total == 0L) stop("FAIL: no topology-inventory tests were executed")
cat(sprintf("TESTS=%d PASS=%d FAIL=%d\n", qa$total, qa$total - length(qa$failed), length(qa$failed)))
if (length(qa$failed)) stop("Topology inventory failures: ", paste(qa$failed, collapse = "; "))
cat("PASS: synthetic topology inventory only; no CSC or hydrological approval\n")
