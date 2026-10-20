#!/usr/bin/env Rscript
# Base R synthetic fixtures only: no real rasters, CSC, Whitebox or network.
s <- grep("^--file=", commandArgs(), value = TRUE)
stopifnot(length(s) == 1L)
test_dir <- dirname(normalizePath(sub("^--file=", "", s)))
source(file.path(test_dir, "..", "low_d8_scope", "lake_1847_focus_core.R"))
source(file.path(test_dir, "..", "land_first_water", "first_water_contact.R"))
source(file.path(test_dir, "trace_land_d8_route.R"))

grid <- list(grid_id = "synthetic-2m", nrow = 5L, ncol = 5L,
             row_offset = 0L, col_offset = 0L, xmin = 200000, ymax = 6900010,
             resolution_m = 2, crs = "EPSG:3067")
provenance <- list(run_id = "synthetic-land-route", code_revision = "fixture-v1",
                   pointer_source = "synthetic-LAND_WATER-pointer",
                   water_source = "synthetic-water", lake_id_source = "synthetic-lake-id",
                   validity_source = "synthetic-routing-domain",
                   lake_id_namespace = "RANTA10:synthetic-v1")
assert <- function(value, message = "Assertion failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}
expect_error <- function(expr) {
  result <- tryCatch({ force(expr); NULL }, error = identity)
  assert(inherits(result, "error"), "Expected rejected input or propagated read error")
}
fixture <- function(n = 25L) {
  list(pointer = rep(0, n), water_class = rep(NA_real_, n),
       lake_id = rep(NA_real_, n), valid = rep(TRUE, n))
}
lake_fixture <- function() {
  f <- fixture(); f$pointer[c(12L, 13L)] <- 2L
  f$water_class[14L] <- 1L; f$lake_id[14L] <- 1847L
  f
}
reader <- function(f) {
  function(cell) list(pointer = f$pointer[cell], water_class = f$water_class[cell],
                      lake_id = f$lake_id[cell], valid = f$valid[cell])
}
trace_fixture <- function(f, start = 12L, g = grid, budget = 128L, p = provenance) {
  reads <- integer()
  read <- function(cell) {
    assert(length(cell) == 1L && cell == floor(cell) && cell >= 1L &&
             cell <= length(f$pointer), "Callback received an invalid local cell")
    reads <<- c(reads, cell)
    reader(f)(cell)
  }
  result <- trace_land_d8_route(start, g, read, max_steps = budget, provenance = p)
  assert(!anyDuplicated(reads), "A previously observed cell was read again")
  assert(result$n_cell_reads == length(reads))
  assert(nrow(result$observations) == length(reads))
  assert(identical(as.integer(result$observations$local_cell), as.integer(reads)))
  assert(nrow(result$path) == result$n_transitions + 1L)
  assert(nrow(result$transitions) == result$n_transitions)
  assert(result$source$local_cell == start)
  assert(tail(result$path$local_cell, 1L) == result$terminal$local_cell)
  assert(identical(result$route_status, result$contact$route_status))
  assert(identical(result$first_water, result$contact$first_water))
  assert(identical(result$continuation_unresolved, !result$contact$water_reached))
  assert(identical(result$provenance, p) && identical(result$grid, g))
  assert(identical(result$provenance_verification, "DECLARED_ONLY"))
  assert(identical(result$method_version, "land-d8-continuity-prototype-v1"))
  assert(identical(result$hydrological_validation, "NOT_ASSESSED"))
  assert(identical(result$channel_interpretation, "NOT_ASSESSED"))
  assert(identical(result$MODERATE, "REVIEW_REQUIRED"))
  assert(identical(result$NATIONAL, "LOCKED"))
  list(result = result, reads = reads)
}
qa <- new.env(parent = emptyenv())
qa$total <- 0L
qa$failed <- character()
case <- function(label, expr) {
  qa$total <- qa$total + 1L
  tryCatch({ force(expr); cat("PASS:", label, "\n") }, error = function(e) {
    qa$failed <- c(qa$failed, label)
    cat("FAIL:", label, "-", conditionMessage(e), "\n")
  })
}

case("ordered land transitions and first lake contact retain their observations", {
  a <- trace_fixture(lake_fixture()); r <- a$result
  assert(r$route_status == "FIRST_WATER_CONTACT")
  assert(identical(as.integer(r$path$local_cell), c(12L, 13L, 14L)))
  assert(identical(as.integer(r$path$step), 0:2))
  assert(identical(as.integer(r$path$observation_index), 1:3))
  assert(!any(r$path$revisited))
  assert(identical(r$transitions$edge_kind, c("LAND_TO_LAND", "LAND_TO_WATER")))
  assert(identical(as.integer(r$transitions$d8_code), c(2L, 2L)))
  assert(nrow(r$land_edges) == 1L && r$land_edges$from_cell == 12L &&
           r$land_edges$to_cell == 13L)
  assert(r$last_valid_land$local_cell == 13L &&
           r$last_observed_valid_land$local_cell == 13L &&
           r$first_water$local_cell == 14L)
  assert(identical(r$observations$pointer_followed, c(TRUE, TRUE, FALSE)))
  assert(r$contact$lake_objectid == 1847L && r$contact$recipient_identified)
  cat("EXAMPLE: 12 --2--> 13 --2--> 14 [LAKE 1847]; land_edges=12->13;",
      "last_valid_land=13; first_water=14; hydrology=NOT_ASSESSED\n")
})

case("a longer land chain records every completed land-to-land transition", {
  f <- lake_fixture(); f$pointer[c(2L, 7L)] <- 8L
  r <- trace_fixture(f, start = 2L)$result
  assert(identical(as.integer(r$path$local_cell), c(2L, 7L, 12L, 13L, 14L)))
  assert(r$n_transitions == 4L && nrow(r$land_edges) == 3L)
  assert(identical(as.integer(r$land_edges$from_cell), c(2L, 7L, 12L)))
  assert(identical(as.integer(r$land_edges$to_cell), c(7L, 12L, 13L)))
})

case("two starts merge into a shared downstream land edge and water contact", {
  f <- fixture(); f$pointer[7L] <- 4L; f$pointer[c(12L, 13L, 14L)] <- 2L
  f$water_class[15L] <- 1L; f$lake_id[15L] <- 1847L
  a <- trace_fixture(f, start = 7L)$result
  b <- trace_fixture(f, start = 12L)$result
  assert(identical(as.integer(a$path$local_cell), c(7L, 13L, 14L, 15L)))
  assert(identical(as.integer(b$path$local_cell), c(12L, 13L, 14L, 15L)))
  assert(a$source$cell_uid != b$source$cell_uid)
  assert(a$land_edges$to_uid[1L] == b$land_edges$to_uid[1L])
  assert(identical(a$transitions[2:3, ], b$transitions[2:3, ]))
  assert(nrow(a$land_edges) == 2L && identical(a$land_edges[2L, ], b$land_edges[2L, ]))
  assert(a$land_edges$from_cell[2L] == 13L && a$land_edges$to_cell[2L] == 14L)
  assert(identical(a$first_water, b$first_water))
  assert(a$land_edges$d8_code[1L] == 4L && b$land_edges$d8_code[1L] == 2L)
  graph <- unique(rbind(a$transitions, b$transitions)[, c("from_cell", "to_cell")])
  assert(nrow(graph) == 4L)
  cat("CONFLUENCE: 7 --4--> 13 <--2-- 12; shared land 13 --2--> 14 --2--> 15 [LAKE];",
      "this is synthetic topology, not a verified ditch\n")
})

case("all eight Whitebox directions preserve exact neighbours and 2 m coordinates", {
  codes <- c(1L, 2L, 4L, 8L, 16L, 32L, 64L, 128L)
  targets <- c(9L, 14L, 19L, 18L, 17L, 12L, 7L, 8L)
  dx <- c(2, 2, 2, 0, -2, -2, -2, 0)
  dy <- c(2, 0, -2, -2, -2, 0, 2, 2)
  for (i in seq_along(codes)) {
    f <- fixture(); f$pointer[13L] <- codes[i]
    f$water_class[targets[i]] <- 1L; f$lake_id[targets[i]] <- 1847L
    r <- trace_fixture(f, start = 13L)$result
    assert(r$transitions$from_cell == 13L && r$transitions$to_cell == targets[i])
    assert(r$transitions$d8_code == codes[i] && nrow(r$land_edges) == 0L)
    assert(r$first_water$x_m - r$source$x_m == dx[i])
    assert(r$first_water$y_m - r$source$y_m == dy[i])
    assert(r$first_water$crs == "EPSG:3067")
  }
})

case("an interior zero preserves the whole land chain and last valid land", {
  f <- lake_fixture(); f$water_class[14L] <- NA_real_
  r <- trace_fixture(f)$result
  assert(r$route_status == "D8_ZERO" && r$continuation_unresolved)
  assert(nrow(r$land_edges) == 2L && is.null(r$first_water))
  assert(r$last_valid_land$local_cell == 14L && r$terminal$local_cell == 14L)
  assert(is.null(r$contact$last_land), "Legacy contact-only last_land changed")
  assert(r$observations$pointer[3L] == 0 && !r$observations$pointer_followed[3L])
})

case("a missing pointer remains a valid land observation rather than NoData", {
  f <- lake_fixture(); f$water_class[14L] <- NA_real_; f$pointer[14L] <- NA_real_
  r <- trace_fixture(f)$result
  assert(r$route_status == "POINTER_NA" && r$last_valid_land$local_cell == 14L)
  assert(r$observations$cell_kind[3L] == "LAND" && is.na(r$observations$pointer[3L]))
  assert(nrow(r$land_edges) == 2L && !r$observations$pointer_followed[3L])
})

case("invalid pointer values are observed but never invented into directions", {
  for (value in c(3, -1, 1.5, 256, Inf)) {
    f <- lake_fixture(); f$pointer[13L] <- value
    r <- trace_fixture(f)$result
    assert(r$route_status == "INVALID_POINTER" && r$n_transitions == 1L)
    assert(nrow(r$land_edges) == 1L && r$last_valid_land$local_cell == 13L)
    assert(r$observations$pointer[2L] == value &&
             !r$observations$pointer_followed[2L])
  }
})

case("movement into NoData is counted but is not a valid land-to-land edge", {
  f <- lake_fixture(); f$valid[14L] <- FALSE
  a <- trace_fixture(f); r <- a$result
  assert(r$route_status == "NO_DATA" && r$n_transitions == 2L)
  assert(identical(r$transitions$edge_kind, c("LAND_TO_LAND", "LAND_TO_NO_DATA")))
  assert(nrow(r$land_edges) == 1L && r$last_valid_land$local_cell == 13L)
  assert(r$observations$cell_kind[3L] == "NO_DATA" && is.null(r$first_water))
  assert(identical(as.integer(a$reads), c(12L, 13L, 14L)))
})

case("an unusable source has no valid land and no completed transition", {
  f <- fixture(); f$valid[12L] <- FALSE; f$water_class[12L] <- 1L
  r <- trace_fixture(f)$result
  assert(r$route_status == "NO_DATA" && r$n_transitions == 0L)
  assert(nrow(r$transitions) == 0L && nrow(r$land_edges) == 0L)
  assert(is.null(r$last_valid_land) && is.null(r$last_observed_valid_land))
  assert(!r$observations$pointer_followed && is.null(r$first_water))
})

case("an invalid water class is an explicit unusable target rather than water", {
  f <- lake_fixture(); f$water_class[14L] <- 4L
  r <- trace_fixture(f)$result
  assert(r$route_status == "INVALID_WATER_CLASS" && r$n_transitions == 2L)
  assert(r$transitions$edge_kind[2L] == "LAND_TO_INVALID_WATER_CLASS")
  assert(nrow(r$land_edges) == 1L && r$last_valid_land$local_cell == 13L)
  assert(r$observations$water_class[3L] == 4L && is.null(r$first_water))
})

case("cycle closure records an edge and cached target without a second read", {
  f <- fixture(); f$pointer[12L] <- 2L; f$pointer[13L] <- 32L
  a <- trace_fixture(f); r <- a$result
  assert(r$route_status == "CYCLE" && r$n_transitions == 2L && r$n_cell_reads == 2L)
  assert(identical(as.integer(r$path$local_cell), c(12L, 13L, 12L)))
  assert(identical(as.integer(r$path$observation_index), c(1L, 2L, 1L)))
  assert(identical(r$path$revisited, c(FALSE, FALSE, TRUE)))
  assert(identical(r$transitions$closes_cycle, c(FALSE, TRUE)))
  assert(nrow(r$land_edges) == 2L && r$transitions$d8_code[2L] == 32L)
  assert(r$last_valid_land$local_cell == 12L &&
           r$last_observed_valid_land$local_cell == 13L)
  assert(all(r$observations$pointer_followed))
  assert(identical(as.integer(a$reads), c(12L, 13L)))
})

case("a prefixed cycle closes exactly at the budget before cap classification", {
  f <- fixture(); f$pointer[7L] <- 8L; f$pointer[12L] <- 2L; f$pointer[13L] <- 32L
  r <- trace_fixture(f, start = 7L, budget = 3L)$result
  assert(r$route_status == "CYCLE" && !r$contact$visit_cap_reached)
  assert(identical(as.integer(r$path$local_cell), c(7L, 12L, 13L, 12L)))
  assert(tail(r$path$observation_index, 1L) == 2L)
  assert(r$n_transitions == 3L && r$n_cell_reads == 3L)
  assert(r$last_valid_land$local_cell == 12L &&
           r$last_observed_valid_land$local_cell == 13L)
})

case("raster exit cannot fabricate a wrapped receiver or completed edge", {
  f <- fixture(); f$pointer[c(13L, 14L, 15L)] <- 2L
  f$water_class[16L] <- 1L; f$lake_id[16L] <- 1847L
  a <- trace_fixture(f, start = 13L); r <- a$result
  assert(r$route_status == "DOMAIN_EXIT_UNRESOLVED" && r$continuation_unresolved)
  assert(identical(as.integer(r$path$local_cell), c(13L, 14L, 15L)))
  assert(r$n_transitions == 2L && nrow(r$land_edges) == 2L)
  assert(r$last_valid_land$local_cell == 15L && !r$observations$pointer_followed[3L])
  assert(!16L %in% a$reads && is.null(r$first_water))
  west <- fixture(); west$pointer[11L] <- 32L
  q <- trace_fixture(west, start = 11L)$result
  assert(q$route_status == "DOMAIN_EXIT_UNRESOLVED" && q$n_transitions == 0L)
})

case("a work limit censors continuation rather than proving a physical break", {
  a <- trace_fixture(lake_fixture(), budget = 1L); r <- a$result
  assert(r$route_status == "STEP_LIMIT" && r$contact$visit_cap_reached)
  assert(r$continuation_unresolved && is.null(r$first_water))
  assert(identical(as.integer(r$path$local_cell), c(12L, 13L)))
  assert(r$last_valid_land$local_cell == 13L && nrow(r$land_edges) == 1L)
  assert(r$observations$pointer[2L] == 2L && !r$observations$pointer_followed[2L])
  assert(!14L %in% a$reads)
})

case("water contact exactly at the transition budget is retained", {
  r <- trace_fixture(lake_fixture(), budget = 2L)$result
  assert(r$route_status == "FIRST_WATER_CONTACT" && !r$continuation_unresolved)
  assert(!r$contact$visit_cap_reached && r$n_transitions == 2L)
  assert(r$first_water$local_cell == 14L && r$last_valid_land$local_cell == 13L)
})

case("real pointer terminals exactly at the budget are not mislabeled caps", {
  for (value in c(0, NA_real_, 3)) {
    f <- lake_fixture(); f$pointer[13L] <- value
    r <- trace_fixture(f, budget = 1L)$result
    expected <- if (is.na(value)) "POINTER_NA" else if (value == 0) "D8_ZERO" else "INVALID_POINTER"
    assert(r$route_status == expected && !r$contact$visit_cap_reached)
    assert(r$n_transitions == 1L && r$last_valid_land$local_cell == 13L)
  }
})

case("all three water classes terminate tracing without inventing river IDs", {
  for (water in 1:3) {
    f <- fixture(); f$pointer[12L] <- 2L
    f$water_class[13L] <- water; f$lake_id[13L] <- 1847L
    r <- trace_fixture(f)$result
    assert(r$route_status == "FIRST_WATER_CONTACT" && r$contact$water_class == water)
    assert(r$last_valid_land$local_cell == 12L && r$first_water$local_cell == 13L)
    assert(r$transitions$edge_kind == "LAND_TO_WATER" && nrow(r$land_edges) == 0L)
    assert(r$contact$recipient_identified == (water == 1L))
    if (water == 1L) assert(r$contact$lake_objectid == 1847L)
    else assert(is.na(r$contact$recipient_id) && is.na(r$contact$lake_objectid))
  }
})

case("water outgoing pointers change raw audit values but not the land route", {
  f <- lake_fixture(); base <- trace_fixture(f)$result
  for (value in c(2, 32, 3, NA_real_, Inf)) {
    changed <- f; changed$pointer[14L] <- value
    r <- trace_fixture(changed)$result
    for (field in c("path", "transitions", "land_edges", "contact", "last_valid_land",
                    "last_observed_valid_land", "first_water")) {
      assert(identical(r[[field]], base[[field]]), paste("Water pointer changed", field))
    }
    assert(identical(r$observations$pointer[3L], value))
    assert(!r$observations$pointer_followed[3L])
  }
})

case("global offsets identify the same physical cell in two local windows", {
  a <- trace_fixture(fixture(), start = 13L)$result
  smaller <- grid; smaller$nrow <- 3L; smaller$ncol <- 3L
  smaller$row_offset <- 1L; smaller$col_offset <- 1L
  b <- trace_fixture(fixture(9L), start = 5L, g = smaller)$result
  assert(a$source$cell_uid == b$source$cell_uid)
  assert(a$source$x_m == b$source$x_m && a$source$y_m == b$source$y_m)
  offset <- grid; offset$row_offset <- 100L; offset$col_offset <- 20L
  c <- trace_fixture(lake_fixture(), g = offset)$result
  assert(c$path$cell_uid[1L] == "synthetic-2m:103:22")
  assert(c$path$cell_uid[3L] == "synthetic-2m:103:24")
  assert(c$first_water$x_m == 200047 && c$first_water$y_m == 6899805)
  other <- grid; other$grid_id <- "another-grid"
  d <- trace_fixture(fixture(), start = 13L, g = other)$result
  assert(a$source$cell_uid != d$source$cell_uid)
})

case("source and callback contract errors cannot become plausible route results", {
  water <- lake_fixture(); water$water_class[12L] <- 1L
  expect_error(trace_fixture(water))
  for (answer in list(NULL, list(pointer = 2),
                     list(pointer = "2", water_class = NA_real_, lake_id = NA_real_, valid = TRUE),
                     list(pointer = 2, water_class = NA_real_, lake_id = NA_real_, valid = NA))) {
    read <- local({ a <- answer; function(cell) a })
    expect_error(trace_land_d8_route(12L, grid, read, provenance = provenance))
  }
  expect_error(trace_land_d8_route(12L, grid, function(cell) stop("synthetic read failure"),
                                  provenance = provenance))
  expect_error(trace_land_d8_route(12L, grid, NULL, provenance = provenance))
})

case("invalid arguments fail without invoking the cell reader", {
  n_reads <- 0L
  read <- function(cell) { n_reads <<- n_reads + 1L; stop("MUST_NOT_READ") }
  for (start in list(0L, 26L, 1.5, NA_real_)) {
    expect_error(trace_land_d8_route(start, grid, read, provenance = provenance))
    assert(n_reads == 0L)
  }
  for (budget in list(0L, 257L, 1.5, NA_real_)) {
    expect_error(trace_land_d8_route(12L, grid, read, max_steps = budget, provenance = provenance))
    assert(n_reads == 0L)
  }
  bad <- grid; bad$resolution_m <- 3
  expect_error(trace_land_d8_route(12L, bad, read, provenance = provenance))
  missing <- provenance; missing$pointer_source <- NULL
  expect_error(trace_land_d8_route(12L, grid, read, provenance = missing))
  assert(n_reads == 0L)
})

case("supplied data and existing methods remain unchanged and repeatable", {
  f <- lake_fixture()
  before <- serialize(list(f, grid, provenance, formals(l1847_trace), body(l1847_trace),
                            formals(first_water_contact), body(first_water_contact)), NULL)
  a <- trace_fixture(f)$result
  b <- trace_fixture(f)$result
  after <- serialize(list(f, grid, provenance, formals(l1847_trace), body(l1847_trace),
                           formals(first_water_contact), body(first_water_contact)), NULL)
  assert(identical(before, after) && identical(a, b))
  expected <- first_water_contact(12L, grid, reader(f), provenance = provenance)
  assert(identical(a$contact, expected), "Existing first-contact semantics were altered")
})

case("the observer delegates exactly one traversal to each existing function", {
  verify_calls <- function() {
    env <- environment(trace_land_d8_route)
    original_contact <- get("first_water_contact", envir = env)
    original_core <- get("l1847_trace", envir = env)
    on.exit({ assign("first_water_contact", original_contact, envir = env)
              assign("l1847_trace", original_core, envir = env) }, add = TRUE)
    n_contact <- n_core <- 0L
    assign("first_water_contact", function(...) {
      n_contact <<- n_contact + 1L
      original_contact(...)
    }, envir = env)
    assign("l1847_trace", function(...) {
      n_core <<- n_core + 1L
      original_core(...)
    }, envir = env)
    trace_fixture(lake_fixture())
    assert(n_contact == 1L && n_core == 1L, "The route was traversed more than once")
  }
  verify_calls()
})

if (qa$total == 0L) stop("FAIL: no land-route tests were executed", call. = FALSE)
cat(sprintf("TESTS=%d PASS=%d FAIL=%d\n", qa$total, qa$total - length(qa$failed), length(qa$failed)))
if (length(qa$failed)) stop("Land-route regression failures: ", paste(qa$failed, collapse = "; "), call. = FALSE)
cat("PASS: synthetic D8 continuity only; no real LOW validation or verified ditch network\n")
