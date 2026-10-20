#!/usr/bin/env Rscript
# Synthetic Base R windows only. No raster reads, CSC, Whitebox or network.
s <- grep("^--file=", commandArgs(), value = TRUE)
stopifnot(length(s) == 1L)
test_dir <- dirname(normalizePath(sub("^--file=", "", s)))
source(file.path(test_dir, "..", "low_d8_scope", "lake_1847_focus_core.R"))
source(file.path(test_dir, "..", "land_first_water", "first_water_contact.R"))
source(file.path(test_dir, "..", "land_d8_continuity", "trace_land_d8_route.R"))
source(file.path(test_dir, "land_network_topology.R"))

grid <- list(grid_id = "synthetic-network", nrow = 5L, ncol = 5L,
             row_offset = 0L, col_offset = 0L, xmin = 200000, ymax = 6900010,
             resolution_m = 2, crs = "EPSG:3067")
provenance <- list(run_id = "synthetic-network", code_revision = "fixture-v1",
                   pointer_source = "synthetic-LAND_WATER-pointer",
                   water_source = "synthetic-water", lake_id_source = "synthetic-lake-id",
                   validity_source = "synthetic-domain", lake_id_namespace = "RANTA10:synthetic-v1")
assert <- function(value, message = "Assertion failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}
expect_error <- function(expr) {
  result <- tryCatch({ force(expr); NULL }, error = identity)
  assert(inherits(result, "error"), "Expected rejected input")
}
fixture <- function(nr = 5L, nc = 5L) {
  list(pointer = matrix(0, nr, nc), water_class = matrix(NA_real_, nr, nc),
       lake_id = matrix(NA_real_, nr, nc), valid = matrix(FALSE, nr, nc))
}
mark <- function(f, cells, pointer = 0, water_class = NA_real_, lake_id = NA_real_, valid = TRUE) {
  rc <- cbind((cells - 1L) %/% ncol(f$pointer) + 1L, (cells - 1L) %% ncol(f$pointer) + 1L)
  f$pointer[rc] <- pointer; f$water_class[rc] <- water_class
  f$lake_id[rc] <- lake_id; f$valid[rc] <- valid
  f
}
confluence_fixture <- function() {
  f <- fixture(); f <- mark(f, 7L, 4L)
  f <- mark(f, c(12L, 13L, 14L), 2L)
  mark(f, 15L, water_class = 1L, lake_id = 9001L)
}
run_fixture <- function(f, g = grid, budget = 32L, p = provenance, lake = f$lake_id) {
  n <- build_land_d8_network(f$pointer, f$water_class, f$valid, g, p,
                            lake_id = lake, max_steps = budget)
  assert(nrow(n$cells) == length(f$pointer))
  assert(identical(n$method_version, "land-network-topology-v1"))
  assert(identical(n$grid, g) && identical(n$provenance, p))
  assert(identical(n$external_inflow, "UNKNOWN"))
  assert(identical(n$upstream_coverage, "WINDOW_ONLY"))
  assert(identical(n$accumulation, "NOT_COMPUTED"))
  assert(identical(n$provenance_verification, "DECLARED_ONLY"))
  assert(identical(n$channel_interpretation, "NOT_ASSESSED"))
  assert(identical(n$hydrological_validation, "NOT_ASSESSED"))
  assert(identical(n$MODERATE, "REVIEW_REQUIRED") && identical(n$NATIONAL, "LOCKED"))
  assert(!anyDuplicated(n$edges$from_cell), "One land source generated duplicate outgoing edges")
  assert(!anyDuplicated(n$land_nodes$cell_uid))
  assert(length(n$routes) == nrow(n$land_nodes) && nrow(n$route_summary) == nrow(n$land_nodes))
  assert(setequal(names(n$routes), n$land_nodes$cell_uid))
  assert(n$work_budget$max_cells == 121L && n$work_budget$max_steps == budget)
  assert(n$work_budget$n_land_starts == nrow(n$land_nodes))
  assert(n$work_budget$max_transitions == nrow(n$land_nodes) * budget)
  assert(n$work_budget$max_cell_reads == nrow(n$land_nodes) * (budget + 1L))
  assert(n$work_budget$n_transitions == sum(n$route_summary$n_transitions))
  assert(n$work_budget$n_cell_reads == sum(n$route_summary$n_cell_reads))
  assert(n$work_budget$n_transitions <= n$work_budget$max_transitions)
  assert(n$work_budget$n_cell_reads <= n$work_budget$max_cell_reads)
  n
}
node <- function(n, cell) {
  a <- n$land_nodes[n$land_nodes$local_cell == cell, , drop = FALSE]
  assert(nrow(a) == 1L, "Expected one land node")
  a
}
route <- function(n, cell) n$routes[[node(n, cell)$cell_uid]]
selection <- function(n, category, scope = "window") {
  a <- select_land_network_cases(n, scope = scope)
  assert(nrow(a) == 4L && identical(a$category, c("CONFLUENCE", "LAND_CHAIN", "ZERO_CHAIN", "BOUNDARY_CHAIN")))
  assert(all(a$status %in% c("SELECTED", "NOT_OBSERVED")))
  a[a$category == category, , drop = FALSE]
}
qa <- new.env(parent = emptyenv()); qa$total <- 0L; qa$failed <- character()
case <- function(label, expr) {
  qa$total <- qa$total + 1L
  tryCatch({ force(expr); cat("PASS:", label, "\n") }, error = function(e) {
    qa$failed <- c(qa$failed, label)
    cat("FAIL:", label, "-", conditionMessage(e), "\n")
  })
}

case("three land cells form an internal chain without requiring any water", {
  f <- mark(mark(fixture(), c(12L, 13L), 2L), 14L)
  n <- run_fixture(f)
  assert(nrow(n$land_nodes) == 3L && nrow(n$land_edges) == 2L)
  assert(identical(as.integer(n$land_edges$from_cell), c(12L, 13L)))
  assert(identical(as.integer(n$land_edges$to_cell), c(13L, 14L)))
  assert(node(n, 12L)$land_indegree_in_window == 0L)
  assert(node(n, 13L)$land_indegree_in_window == 1L && node(n, 14L)$land_indegree_in_window == 1L)
  assert(route(n, 12L)$route_status == "D8_ZERO" && route(n, 12L)$n_transitions == 2L)
  assert(selection(n, "LAND_CHAIN")$source_cell == 12L)
  assert(selection(n, "ZERO_CHAIN")$source_cell == 12L)
  assert(selection(n, "CONFLUENCE")$status == "NOT_OBSERVED")
})

case("two upstream routes form one confluence and share deduplicated downstream edges", {
  n <- run_fixture(confluence_fixture())
  assert(nrow(n$edges) == 4L && nrow(n$land_edges) == 3L)
  assert(nrow(n$confluences) == 1L && n$confluences$local_cell == 13L)
  assert(node(n, 13L)$land_indegree_in_window == 2L && node(n, 13L)$is_confluence)
  assert(sum(n$edges$from_cell == 13L & n$edges$to_cell == 14L) == 1L)
  assert(sum(n$edges$from_cell == 14L & n$edges$to_cell == 15L) == 1L)
  assert(identical(as.integer(route(n, 7L)$path$local_cell), c(7L, 13L, 14L, 15L)))
  assert(identical(as.integer(route(n, 12L)$path$local_cell), c(12L, 13L, 14L, 15L)))
  assert(identical(route(n, 7L)$path[3:4, c("local_cell", "cell_uid")],
                   route(n, 12L)$path[3:4, c("local_cell", "cell_uid")]))
  assert(selection(n, "CONFLUENCE")$source_cell == 13L)
  assert(selection(n, "CONFLUENCE")$n_matches == 1L)
  cat("EXAMPLE: 7 --4--> 13 <--2-- 12; common 13 --2--> 14 --2--> 15 [LAKE 9001];",
      "unique land edges=3; confluence=13; accumulation=NOT_COMPUTED\n")
})

case("shared water targets are not misclassified as land confluences", {
  f <- mark(fixture(), 7L, 4L); f <- mark(f, 12L, 2L)
  f <- mark(f, 13L, water_class = 1L, lake_id = 9001L)
  n <- run_fixture(f)
  assert(nrow(n$land_edges) == 0L && nrow(n$edges) == 2L)
  assert(all(n$edges$edge_kind == "LAND_TO_WATER") && nrow(n$confluences) == 0L)
  assert(selection(n, "CONFLUENCE")$status == "NOT_OBSERVED")
})

case("outgoing edge kind belongs to the source even when the next land node is zero", {
  f <- mark(mark(fixture(), 12L, 2L), 13L)
  n <- run_fixture(f)
  assert(node(n, 12L)$outgoing_kind == "LAND_TO_LAND")
  assert(node(n, 12L)$outgoing_to_cell == 13L && node(n, 12L)$route_status == "D8_ZERO")
  assert(node(n, 13L)$outgoing_kind == "D8_ZERO" && is.na(node(n, 13L)$outgoing_to_cell))
  assert(selection(n, "ZERO_CHAIN")$source_cell == 12L)
})

case("missing and invalid pointers stay separate local terminals", {
  for (p in c(NA_real_, 3, Inf)) {
    f <- mark(mark(fixture(), 12L, 2L), 13L, pointer = p)
    n <- run_fixture(f)
    status <- if (is.na(p)) "POINTER_NA" else "INVALID_POINTER"
    assert(node(n, 13L)$outgoing_kind == status && node(n, 13L)$route_status == status)
    assert(node(n, 12L)$outgoing_kind == "LAND_TO_LAND" && route(n, 12L)$route_status == status)
    assert(nrow(n$edges) == 1L && nrow(n$land_edges) == 1L)
  }
})

case("a NoData target is an explicit edge but never a land node or water contact", {
  f <- mark(fixture(), 12L, 2L)
  f <- mark(f, 13L, pointer = 2L, water_class = 1L, lake_id = 9001L, valid = FALSE)
  f <- mark(f, 14L, water_class = 1L, lake_id = 9001L)
  n <- run_fixture(f)
  assert(nrow(n$land_nodes) == 1L && nrow(n$land_edges) == 0L)
  assert(n$edges$edge_kind == "LAND_TO_NO_DATA" && n$edges$to_cell == 13L)
  assert(route(n, 12L)$route_status == "NO_DATA" && is.null(route(n, 12L)$first_water))
  assert(n$cells$cell_kind[n$cells$local_cell == 13L] == "NO_DATA")
})

case("invalid water classes cannot become land or known water", {
  f <- mark(mark(fixture(), 12L, 2L), 13L, water_class = 4L)
  n <- run_fixture(f)
  assert(nrow(n$land_nodes) == 1L && nrow(n$land_edges) == 0L)
  assert(n$edges$edge_kind == "LAND_TO_INVALID_WATER_CLASS")
  assert(route(n, 12L)$route_status == "INVALID_WATER_CLASS")
})

case("cycles retain each directed edge once and do not create accumulation", {
  f <- mark(mark(fixture(), 12L, 2L), 13L, 32L)
  n <- run_fixture(f, budget = 2L)
  assert(nrow(n$land_edges) == 2L && all(n$route_summary$route_status == "CYCLE"))
  assert(all(n$land_nodes$land_indegree_in_window == 1L) && nrow(n$confluences) == 0L)
  assert(identical(as.integer(route(n, 12L)$path$local_cell), c(12L, 13L, 12L)))
  assert(route(n, 12L)$n_cell_reads == 2L && route(n, 12L)$n_transitions == 2L)
  assert(selection(n, "ZERO_CHAIN")$status == "NOT_OBSERVED")
})

case("cycle and incoming prefix use graph indegree rather than route multiplicity", {
  f <- mark(mark(mark(fixture(), 7L, 8L), 12L, 2L), 13L, 32L)
  n <- run_fixture(f, budget = 3L)
  assert(nrow(n$land_edges) == 3L && nrow(n$confluences) == 1L)
  assert(n$confluences$local_cell == 12L && node(n, 12L)$land_indegree_in_window == 2L)
  assert(all(n$route_summary$route_status == "CYCLE"))
})

case("window exits have no fabricated or row-wrapped outgoing edge", {
  f <- mark(fixture(), c(13L, 14L, 15L), 2L)
  f <- mark(f, 16L, water_class = 1L, lake_id = 9001L)
  n <- run_fixture(f)
  assert(nrow(n$edges) == 2L && all(n$edges$edge_kind == "LAND_TO_LAND"))
  assert(node(n, 15L)$outgoing_kind == "DOMAIN_EXIT_UNRESOLVED")
  assert(is.na(node(n, 15L)$outgoing_to_cell) && node(n, 15L)$on_window_boundary)
  assert(!node(n, 13L)$on_window_boundary)
  assert(route(n, 13L)$route_status == "DOMAIN_EXIT_UNRESOLVED")
  assert(selection(n, "BOUNDARY_CHAIN")$source_cell == 13L)
})

case("work limits censor routes while the local one-step edge graph stays complete", {
  f <- confluence_fixture()
  short <- run_fixture(f, budget = 1L); longer <- run_fixture(f, budget = 4L)
  assert(identical(short$edges, longer$edges) && identical(short$land_edges, longer$land_edges))
  assert(route(short, 7L)$route_status == "STEP_LIMIT" && route(short, 7L)$continuation_unresolved)
  assert(node(short, 7L)$outgoing_kind == "LAND_TO_LAND")
  assert(route(short, 14L)$route_status == "FIRST_WATER_CONTACT")
  assert(selection(short, "LAND_CHAIN")$status == "NOT_OBSERVED")
  assert(selection(longer, "LAND_CHAIN")$status == "SELECTED")
})

case("lake, river-area and river-line contacts retain classes but not invented river IDs", {
  for (wc in 1:3) {
    f <- mark(mark(fixture(), 12L, 2L), 13L, water_class = wc, lake_id = 9001L)
    n <- run_fixture(f)
    assert(n$edges$edge_kind == "LAND_TO_WATER" && n$route_summary$water_class == wc)
    assert(route(n, 12L)$contact$recipient_identified == (wc == 1L))
    if (wc == 1L) assert(n$route_summary$lake_objectid == 9001L)
    else assert(is.na(n$route_summary$lake_objectid) && is.na(route(n, 12L)$contact$recipient_id))
  }
})

case("all Whitebox directions preserve the expected one-step land neighbour", {
  codes <- c(1L, 2L, 4L, 8L, 16L, 32L, 64L, 128L)
  targets <- c(9L, 14L, 19L, 18L, 17L, 12L, 7L, 8L)
  for (i in seq_along(codes)) {
    f <- mark(mark(fixture(), 13L, codes[i]), targets[i])
    n <- run_fixture(f)
    e <- n$land_edges[n$land_edges$from_cell == 13L, , drop = FALSE]
    assert(nrow(e) == 1L && e$to_cell == targets[i] && e$d8_code == codes[i])
  }
})

case("non-square matrices use full row-major raster indexing", {
  f <- fixture(2L, 3L)
  f <- mark(mark(mark(mark(f, 1L, 2L), 2L, 8L), 5L, 2L), 6L,
            water_class = 1L, lake_id = 9001L)
  g <- grid; g$nrow <- 2L; g$ncol <- 3L
  n <- run_fixture(f, g)
  assert(identical(as.integer(route(n, 1L)$path$local_cell), c(1L, 2L, 5L, 6L)))
  assert(identical(as.integer(n$cells$pointer), c(2L, 8L, 0L, 0L, 2L, 0L)))
  assert(n$cells$global_row[5L] == 2L && n$cells$global_col[5L] == 2L)
})

case("overlapping windows give the same global IDs and coordinates to one edge", {
  f <- mark(mark(fixture(), 12L, 2L), 13L)
  a <- run_fixture(f)
  small <- mark(mark(fixture(3L, 3L), 4L, 2L), 5L)
  g <- grid; g$nrow <- 3L; g$ncol <- 3L; g$row_offset <- 1L; g$col_offset <- 1L
  b <- run_fixture(small, g)
  assert(a$land_edges$from_uid == b$land_edges$from_uid && a$land_edges$to_uid == b$land_edges$to_uid)
  assert(node(a, 12L)$x_m == node(b, 4L)$x_m && node(a, 12L)$y_m == node(b, 4L)$y_m)
  assert(node(a, 12L)$cell_uid == "synthetic-network:3:2")
  assert(node(a, 12L)$crs == "EPSG:3067")
})

case("integer and double matrices and numeric dimensions both satisfy the contract", {
  f <- confluence_fixture(); integer_f <- f
  storage.mode(integer_f$pointer) <- "integer"
  storage.mode(integer_f$water_class) <- "integer"
  storage.mode(integer_f$lake_id) <- "integer"
  g <- grid; g$nrow <- as.numeric(g$nrow); g$ncol <- as.numeric(g$ncol)
  a <- run_fixture(f, budget = 4); b <- run_fixture(integer_f, g, budget = 4L)
  assert(identical(a$edges$from_uid, b$edges$from_uid) && identical(a$edges$to_uid, b$edges$to_uid))
  assert(all(a$edges$d8_code == b$edges$d8_code))
  assert(identical(a$route_summary$route_status, b$route_summary$route_status))
})

case("a NULL lake-ID input stays explicitly unknown at a lake contact", {
  f <- mark(mark(fixture(), 12L, 2L), 13L, water_class = 1L, lake_id = 9001L)
  n <- run_fixture(f, lake = NULL)
  assert(all(is.na(n$cells$lake_id)) && is.na(n$route_summary$lake_objectid))
  assert(route(n, 12L)$route_status == "FIRST_WATER_CONTACT")
  assert(!route(n, 12L)$contact$recipient_identified)
})

case("a window containing only water has typed empty network and missing cases", {
  f <- fixture(); f <- mark(f, 1:25, water_class = 1L, lake_id = 9001L)
  n <- run_fixture(f)
  assert(nrow(n$land_nodes) == 0L && nrow(n$edges) == 0L && nrow(n$confluences) == 0L)
  assert(nrow(n$route_summary) == 0L && length(n$routes) == 0L)
  a <- select_land_network_cases(n)
  assert(all(a$status == "NOT_OBSERVED") && all(a$n_matches == 0L))
  assert(all(is.na(a$source_cell)) && all(is.na(a$source_uid)) && all(is.na(a$route_status)))
  assert(n$work_budget$n_cell_reads == 0L && n$work_budget$n_transitions == 0L)
})

case("all-NoData and all-invalid-class windows cannot create land sources", {
  missing <- run_fixture(fixture())
  assert(nrow(missing$land_nodes) == 0L && all(missing$cells$cell_kind == "NO_DATA"))
  f <- mark(fixture(), 1:25, water_class = 4L)
  invalid <- run_fixture(f)
  assert(nrow(invalid$land_nodes) == 0L && all(invalid$cells$cell_kind == "INVALID_WATER_CLASS"))
  assert(nrow(invalid$edges) == 0L && all(select_land_network_cases(invalid)$status == "NOT_OBSERVED"))
})

case("an isolated zero land cell has no fabricated edge or chain", {
  f <- mark(fixture(1L, 1L), 1L)
  g <- grid; g$nrow <- 1L; g$ncol <- 1L
  n <- run_fixture(f, g)
  assert(nrow(n$land_nodes) == 1L && nrow(n$edges) == 0L)
  assert(node(n, 1L)$outgoing_kind == "D8_ZERO" && node(n, 1L)$on_window_boundary)
  assert(all(select_land_network_cases(n)$status == "NOT_OBSERVED"))
})

case("unknown external inflow is retained even for a locally closed-looking chain", {
  f <- mark(mark(mark(fixture(), 12L, 2L), 13L, 2L), 14L)
  n <- run_fixture(f)
  assert(n$external_inflow == "UNKNOWN" && n$upstream_coverage == "WINDOW_ONLY")
  assert(n$accumulation == "NOT_COMPUTED")
  assert(node(n, 12L)$land_indegree_in_window == 0L)
})

case("case selection uses numeric global row then column instead of lexical UID order", {
  f <- fixture(3L, 5L)
  f <- mark(mark(f, c(2L, 3L), 2L), 4L)
  f <- mark(mark(f, c(11L, 12L), 2L), 13L)
  g <- grid; g$nrow <- 3L; g$ncol <- 5L; g$row_offset <- 8L
  n <- run_fixture(f, g)
  assert(selection(n, "LAND_CHAIN")$source_cell == 2L)
  assert(selection(n, "ZERO_CHAIN")$source_cell == 2L)
  wide <- fixture(3L, 12L)
  wide <- mark(mark(wide, c(1L, 13L), 8L), 25L)
  wide <- mark(mark(wide, c(2L, 14L), 8L), 26L)
  g$ncol <- 12L; g$col_offset <- 8L
  q <- run_fixture(wide, g)
  assert(selection(q, "LAND_CHAIN")$source_cell == 1L)
})

case("selection does not prefer a longer or successful water-ending route", {
  f <- fixture()
  f <- mark(mark(f, c(1L, 2L), 2L), 3L)
  f <- mark(f, c(7L, 8L, 9L), 2L)
  f <- mark(f, 10L, water_class = 1L, lake_id = 9001L)
  n <- run_fixture(f)
  assert(route(n, 1L)$n_transitions == 2L && route(n, 7L)$n_transitions == 3L)
  assert(selection(n, "LAND_CHAIN")$source_cell == 1L)
  assert(selection(n, "LAND_CHAIN")$route_status == "D8_ZERO")
})

case("work accounting accepts the 121-cell bound and rejects larger windows", {
  f <- fixture(11L, 11L); f <- mark(f, 1:121)
  g <- grid; g$nrow <- 11L; g$ncol <- 11L
  n <- run_fixture(f, g, budget = 2L)
  assert(nrow(n$land_nodes) == 121L && n$work_budget$n_cell_reads == 121L)
  assert(n$work_budget$n_transitions == 0L && n$work_budget$max_cell_reads == 363L)
  oversized <- fixture(1L, 122L); g$nrow <- 1L; g$ncol <- 122L
  expect_error(run_fixture(oversized, g))
})

case("input shape, types, missing validity and step bounds are rejected", {
  f <- confluence_fixture()
  invoke <- function(pointer = f$pointer, water = f$water_class, valid = f$valid,
                     lake = f$lake_id, g = grid, budget = 32L) {
    build_land_d8_network(pointer, water, valid, g, provenance, lake, budget)
  }
  expect_error(invoke(pointer = as.vector(f$pointer)))
  expect_error(invoke(pointer = matrix("2", 5L, 5L)))
  expect_error(invoke(water = matrix(NA_real_, 3L, 3L)))
  expect_error(invoke(water = matrix("NA", 5L, 5L)))
  expect_error(invoke(valid = matrix(1, 5L, 5L)))
  bad_valid <- f$valid; bad_valid[1L, 1L] <- NA
  expect_error(invoke(valid = bad_valid))
  expect_error(invoke(lake = matrix("9001", 5L, 5L)))
  expect_error(invoke(pointer = matrix(numeric(), 0L, 0L)))
  bad_grid <- grid; bad_grid$nrow <- 4L
  expect_error(invoke(g = bad_grid))
  for (budget in list(0L, 257L, 1.5, NA_real_, "2")) expect_error(invoke(budget = budget))
})

case("grid and provenance validation also runs when there are no land starts", {
  f <- mark(fixture(), 1:25, water_class = 1L, lake_id = 9001L)
  bad <- grid; bad$resolution_m <- 3
  expect_error(run_fixture(f, bad))
  bad <- grid; bad$crs <- "EPSG:4326"
  expect_error(run_fixture(f, bad))
  bad <- grid; bad$xmin <- Inf
  expect_error(run_fixture(f, bad))
  absent <- provenance; absent$pointer_source <- NULL
  expect_error(run_fixture(f, p = absent))
  blank <- provenance; blank$code_revision <- ""
  expect_error(run_fixture(f, p = blank))
})

case("case selection rejects malformed tables instead of reporting missing cases", {
  expect_error(select_land_network_cases(list(method_version = "land-network-topology-v1",
    land_nodes = data.frame(), route_summary = data.frame())))
  n <- run_fixture(confluence_fixture())
  bad <- n; bad$route_summary$source_uid[1L] <- "unmatched-source"
  expect_error(select_land_network_cases(bad))
  bad <- n; bad$land_nodes$global_row <- as.character(bad$land_nodes$global_row)
  expect_error(select_land_network_cases(bad))
  bad <- n; bad$land_nodes$cell_uid[2L] <- bad$land_nodes$cell_uid[1L]
  expect_error(select_land_network_cases(bad))
  bad <- n; bad$land_nodes$land_indegree_in_window[1L] <- NA_real_
  expect_error(select_land_network_cases(bad))
  bad <- n; bad$route_summary$n_land_edges[1L] <- -1L
  expect_error(select_land_network_cases(bad))
  bad <- n; bad$route_summary$route_status[1L] <- "HYDROLOGICAL_PASS"
  expect_error(select_land_network_cases(bad))
})

case("water outgoing pointers cannot change land edges, selections or contacts", {
  f <- confluence_fixture(); baseline <- run_fixture(f)
  for (p in c(2, 32, 3, NA_real_, Inf)) {
    changed <- mark(f, 15L, pointer = p, water_class = 1L, lake_id = 9001L)
    n <- run_fixture(changed)
    for (field in c("edges", "land_edges", "land_nodes", "confluences", "route_summary")) {
      assert(identical(n[[field]], baseline[[field]]), paste("Water pointer changed", field))
    }
    assert(identical(select_land_network_cases(n), select_land_network_cases(baseline)))
    for (uid in names(n$routes)) {
      assert(identical(n$routes[[uid]]$path, baseline$routes[[uid]]$path))
      assert(identical(n$routes[[uid]]$contact, baseline$routes[[uid]]$contact))
    }
  }
})

case("supplied matrices, metadata and existing route functions remain unchanged", {
  f <- confluence_fixture()
  snapshot <- function() serialize(list(f, grid, provenance,
    formals(l1847_trace), body(l1847_trace), formals(first_water_contact), body(first_water_contact),
    formals(trace_land_d8_route), body(trace_land_d8_route)), NULL)
  before <- snapshot(); a <- run_fixture(f); b <- run_fixture(f)
  assert(identical(before, snapshot()) && identical(a, b))
  uid <- node(a, 7L)$cell_uid
  read <- function(cell) {
    rc <- cbind((cell - 1L) %/% 5L + 1L, (cell - 1L) %% 5L + 1L)
    list(pointer = f$pointer[rc], water_class = f$water_class[rc],
         lake_id = f$lake_id[rc], valid = f$valid[rc])
  }
  expected <- trace_land_d8_route(7L, grid, read, max_steps = 32L, provenance = provenance)
  assert(identical(a$routes[[uid]], expected), "Stored routes differ from existing observer output")
})

case("an 11 by 11 window keeps all 121 cells and separates its exact 81-cell core", {
  f <- mark(fixture(11L, 11L), 1:121)
  g <- grid; g$nrow <- 11; g$ncol <- 11
  n <- run_fixture(f, g)
  rr <- (n$cells$local_cell - 1L) %/% 11L + 1L
  cc <- (n$cells$local_cell - 1L) %% 11L + 1L
  expected <- rr >= 2L & rr <= 10L & cc >= 2L & cc <= 10L
  assert(is.logical(n$cells$is_core) && is.logical(n$cells$is_halo))
  assert(identical(n$cells$is_core, expected) && identical(n$cells$is_halo, !expected))
  assert(sum(n$cells$is_core) == 81L && sum(n$cells$is_halo) == 40L)
  assert(nrow(n$land_nodes) == 121L && sum(n$land_nodes$is_core) == 81L)
  assert(all(n$cells$is_halo == n$cells$on_window_boundary))
})

case("a core confluence includes an observed incoming land edge from the halo", {
  f <- mark(mark(mark(fixture(), 6L, 4L), 7L, 8L), 12L, 2L)
  f <- mark(f, 13L)
  n <- run_fixture(f)
  assert(node(n, 6L)$is_halo && node(n, 7L)$is_core && node(n, 12L)$is_core)
  assert(node(n, 12L)$land_indegree_in_window == 2L)
  assert(selection(n, "CONFLUENCE", "core")$source_cell == 12L)
  assert(selection(n, "CONFLUENCE", "halo")$status == "NOT_OBSERVED")
  incoming <- n$land_edges[n$land_edges$to_cell == 12L, , drop = FALSE]
  assert(nrow(incoming) == 2L && sum(incoming$from_is_core) == 1L)
  assert(all(incoming$to_is_core))
})

case("a confluence only in the halo is never promoted to a core case", {
  f <- mark(mark(mark(fixture(), 1L, 2L), 7L, 128L), 2L)
  n <- run_fixture(f)
  assert(n$confluences$local_cell == 2L && n$confluences$is_halo)
  assert(selection(n, "CONFLUENCE")$source_cell == 2L)
  assert(selection(n, "CONFLUENCE", "halo")$source_cell == 2L)
  a <- selection(n, "CONFLUENCE", "core")
  assert(a$status == "NOT_OBSERVED" && a$n_matches == 0L && is.na(a$source_cell))
})

case("core selection skips a smaller global halo cell without ranking by route success", {
  f <- mark(mark(fixture(), c(1L, 2L), 2L), 3L)
  f <- mark(mark(f, c(12L, 13L), 2L), 14L)
  n <- run_fixture(f)
  assert(node(n, 1L)$is_halo && node(n, 12L)$is_core)
  assert(selection(n, "LAND_CHAIN")$source_cell == 1L)
  assert(selection(n, "LAND_CHAIN", "halo")$source_cell == 1L)
  assert(selection(n, "LAND_CHAIN", "core")$source_cell == 12L)
  assert(selection(n, "ZERO_CHAIN", "core")$source_cell == 12L)
})

case("a multi-cell core land chain remains observable without any water contact", {
  f <- mark(mark(fixture(), c(12L, 13L), 2L), 14L)
  n <- run_fixture(f)
  assert(all(n$land_nodes$is_core) && nrow(n$land_edges) == 2L)
  assert(all(n$land_edges$zone_transition == "CORE_TO_CORE"))
  a <- selection(n, "LAND_CHAIN", "core")
  assert(a$status == "SELECTED" && a$source_cell == 12L && a$route_status == "D8_ZERO")
  assert(is.null(route(n, 12L)$first_water))
})

case("a core route continues through halo before its unresolved window exit", {
  f <- mark(fixture(), c(13L, 14L, 15L), 2L)
  n <- run_fixture(f)
  assert(node(n, 13L)$is_core && node(n, 15L)$is_halo)
  assert(identical(as.integer(route(n, 13L)$path$local_cell), c(13L, 14L, 15L)))
  assert(route(n, 13L)$route_status == "DOMAIN_EXIT_UNRESOLVED")
  assert(node(n, 13L)$outgoing_kind == "LAND_TO_LAND")
  assert(node(n, 15L)$outgoing_kind == "DOMAIN_EXIT_UNRESOLVED")
  assert(selection(n, "BOUNDARY_CHAIN", "core")$source_cell == 13L)
  assert(selection(n, "BOUNDARY_CHAIN", "halo")$status == "NOT_OBSERVED")
  assert(sum(n$land_edges$zone_transition == "CORE_TO_CORE") == 1L)
  assert(sum(n$land_edges$zone_transition == "CORE_TO_HALO") == 1L)
})

case("a core confluence shared downstream edge is present once across halo-fed routes", {
  f <- mark(mark(mark(fixture(), 6L, 4L), 7L, 8L), c(12L, 13L), 2L)
  f <- mark(f, 14L)
  n <- run_fixture(f)
  assert(selection(n, "CONFLUENCE", "core")$source_cell == 12L)
  assert(nrow(n$land_edges) == 4L)
  assert(sum(n$land_edges$from_cell == 12L & n$land_edges$to_cell == 13L) == 1L)
  assert(sum(n$land_edges$from_cell == 13L & n$land_edges$to_cell == 14L) == 1L)
  assert(identical(as.integer(route(n, 6L)$path$local_cell), c(6L, 12L, 13L, 14L)))
  assert(identical(as.integer(route(n, 7L)$path$local_cell), c(7L, 12L, 13L, 14L)))
})

case("halo-only chains leave all absent core case rows explicit", {
  f <- mark(mark(fixture(), c(1L, 2L), 2L), 3L)
  n <- run_fixture(f)
  core <- select_land_network_cases(n, scope = "core")
  halo <- select_land_network_cases(n, scope = "halo")
  assert(nrow(core) == 4L && all(core$status == "NOT_OBSERVED"))
  assert(all(core$n_matches == 0L) && all(is.na(core$source_uid)))
  assert(halo$status[halo$category == "LAND_CHAIN"] == "SELECTED")
  assert(halo$status[halo$category == "ZERO_CHAIN"] == "SELECTED")
  assert(nrow(n$cells) == 25L && nrow(n$land_nodes) == 3L)
})

case("halo land indegree is observed locally without inventing total upstream accumulation", {
  f <- mark(mark(mark(fixture(), 6L, 4L), 7L, 8L), 12L)
  n <- run_fixture(f)
  assert(node(n, 12L)$land_indegree_in_window == 2L)
  assert(n$external_inflow == "UNKNOWN" && n$upstream_coverage == "WINDOW_ONLY")
  assert(n$accumulation == "NOT_COMPUTED")
  assert(selection(n, "CONFLUENCE", "core")$status == "SELECTED")
})

case("core and halo use local positions while offsets preserve global identity and coordinates", {
  f <- mark(mark(fixture(), 6L, 2L), 7L)
  g <- grid; g$row_offset <- 2994; g$col_offset <- 2994
  n <- run_fixture(f, g)
  a <- node(n, 6L); b <- node(n, 7L)
  assert(a$is_halo && b$is_core)
  assert(a$global_row == 2996 && a$global_col == 2995)
  assert(b$global_row == 2996 && b$global_col == 2996)
  assert(b$cell_uid == "synthetic-network:2996:2996")
  assert(b$x_m == grid$xmin + (2996 - 0.5) * 2)
  assert(b$y_m == grid$ymax - (2996 - 0.5) * 2)
  assert(n$land_edges$from_uid == a$cell_uid && n$land_edges$to_uid == b$cell_uid)
  assert(n$land_edges$zone_transition == "HALO_TO_CORE")
})

case("all four directed core-halo land-edge classes have separate exact counts", {
  f <- mark(fixture(), c(1L, 6L, 12L, 14L), 2L)
  f <- mark(f, c(2L, 7L, 13L, 15L))
  n <- run_fixture(f)
  expected <- c("CORE_TO_CORE", "CORE_TO_HALO", "HALO_TO_CORE", "HALO_TO_HALO")
  counts <- n$land_edge_zone_counts
  assert(is.data.frame(counts) && nrow(counts) == 4L)
  assert(setequal(counts$zone_transition, expected) && all(counts$n_edges == 1L))
  assert(nrow(n$land_edges) == 4L && sum(counts$n_edges) == nrow(n$land_edges))
  for (i in seq_len(nrow(n$land_edges))) {
    e <- n$land_edges[i, , drop = FALSE]
    assert(e$from_is_core == node(n, e$from_cell)$is_core)
    assert(e$to_is_core == node(n, e$to_cell)$is_core)
  }
})

case("water-only core and halo preserve empty scoped cases and zero typed edge counts", {
  f <- mark(fixture(11L, 11L), 1:121, water_class = 2L)
  g <- grid; g$nrow <- 11; g$ncol <- 11
  n <- run_fixture(f, g)
  assert(sum(n$cells$is_core) == 81L && sum(n$cells$is_halo) == 40L)
  assert(nrow(n$land_nodes) == 0L && nrow(n$land_edges) == 0L)
  assert(is.numeric(n$land_edge_zone_counts$n_edges) && all(n$land_edge_zone_counts$n_edges == 0))
  for (scope in c("window", "core", "halo")) {
    a <- select_land_network_cases(n, scope = scope)
    assert(nrow(a) == 4L && all(a$status == "NOT_OBSERVED") && all(a$n_matches == 0L))
  }
})

case("NoData-only and invalid-class-only windows cannot supply core or halo cases", {
  for (f in list(fixture(), mark(fixture(), 1:25, water_class = 4L))) {
    n <- run_fixture(f)
    assert(nrow(n$land_nodes) == 0L)
    assert(is.logical(n$land_nodes$is_core) && is.logical(n$land_nodes$is_halo))
    assert(all(select_land_network_cases(n, scope = "core")$status == "NOT_OBSERVED"))
    assert(all(select_land_network_cases(n, scope = "halo")$status == "NOT_OBSERVED"))
  }
})

case("scoping preserves all previous termination classes and source outgoing semantics", {
  fs <- list(
    D8_ZERO = mark(fixture(), 12L),
    POINTER_NA = mark(fixture(), 12L, NA_real_),
    INVALID_POINTER = mark(fixture(), 12L, 3),
    NO_DATA = mark(fixture(), 12L, 2),
    CYCLE = mark(mark(fixture(), 12L, 2), 13L, 32),
    DOMAIN_EXIT_UNRESOLVED = mark(fixture(), c(14L, 15L), 2),
    STEP_LIMIT = mark(mark(fixture(), c(12L, 13L), 2), 14L),
    FIRST_WATER_CONTACT = mark(mark(fixture(), 12L, 2), 13L, water_class = 3L)
  )
  for (status in names(fs)) {
    n <- run_fixture(fs[[status]], budget = if (status == "STEP_LIMIT") 1L else 32L)
    start <- if (status == "DOMAIN_EXIT_UNRESOLVED") 14L else 12L
    assert(node(n, start)$is_core && route(n, start)$route_status == status)
    if (status %in% c("NO_DATA", "CYCLE", "DOMAIN_EXIT_UNRESOLVED", "STEP_LIMIT", "FIRST_WATER_CONTACT")) {
      assert(grepl("^LAND_TO_", node(n, start)$outgoing_kind))
    } else assert(node(n, start)$outgoing_kind == status)
    before <- n$route_summary
    select_land_network_cases(n, scope = "core")
    select_land_network_cases(n, scope = "halo")
    assert(identical(before, n$route_summary))
  }
})

case("invalid scopes and missing nonlogical or inconsistent core-halo flags are rejected", {
  n <- run_fixture(confluence_fixture())
  for (scope in list("outside", NA_character_, 1, character(), c("core", "halo"))) {
    expect_error(select_land_network_cases(n, scope = scope))
  }
  for (field in c("is_core", "is_halo")) {
    bad <- n; bad$land_nodes[[field]] <- NULL
    expect_error(select_land_network_cases(bad, scope = "core"))
    bad <- n; bad$land_nodes[[field]] <- as.numeric(bad$land_nodes[[field]])
    expect_error(select_land_network_cases(bad, scope = "core"))
    bad <- n; bad$land_nodes[[field]][1L] <- NA
    expect_error(select_land_network_cases(bad, scope = "core"))
  }
  bad <- n; bad$land_nodes$is_halo <- bad$land_nodes$is_core
  expect_error(select_land_network_cases(bad, scope = "core"))
})

case("default whole-window selection remains explicit and never changes stored graph or routes", {
  n <- run_fixture(confluence_fixture())
  before <- serialize(n, NULL)
  whole <- select_land_network_cases(n)
  assert(identical(whole, select_land_network_cases(n, scope = "window")))
  assert(all(whole$n_matches_window == whole$n_matches_core + whole$n_matches_halo))
  select_land_network_cases(n, scope = "core")
  select_land_network_cases(n, scope = "halo")
  assert(identical(before, serialize(n, NULL)))
})

case("old serialized results without zone flags keep window selection and unknown zone counts", {
  n <- run_fixture(confluence_fixture())
  expected <- select_land_network_cases(n, scope = "window")
  n$land_nodes$is_core <- NULL
  n$land_nodes$is_halo <- NULL
  a <- select_land_network_cases(n)
  fields <- c("category", "status", "source_cell", "source_uid", "route_status", "n_matches")
  assert(identical(a[, fields], expected[, fields]))
  assert(all(a$scope == "window") && all(a$n_matches_window == a$n_matches))
  assert(all(is.na(a$n_matches_core)) && all(is.na(a$n_matches_halo)))
  expect_error(select_land_network_cases(n, scope = "core"))
  expect_error(select_land_network_cases(n, scope = "halo"))
})

if (qa$total == 0L) stop("FAIL: no land-network tests were executed", call. = FALSE)
cat(sprintf("TESTS=%d PASS=%d FAIL=%d\n", qa$total, qa$total - length(qa$failed), length(qa$failed)))
if (length(qa$failed)) stop("Land-network regression failures: ", paste(qa$failed, collapse = "; "), call. = FALSE)
cat("PASS: bounded synthetic topology only; no accumulation or hydrological approval\n")
