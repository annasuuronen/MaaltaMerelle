#!/usr/bin/env Rscript
# Small Base R fixtures only. Never opens real rasters or submits a job.
s <- grep("^--file=", commandArgs(), value = TRUE)
stopifnot(length(s) == 1L)
test_dir <- dirname(normalizePath(sub("^--file=", "", s)))
source(file.path(test_dir, "..", "low_d8_scope", "lake_1847_focus_core.R"))
source(file.path(test_dir, "first_water_contact.R"))

grid <- list(grid_id = "synthetic-2m", nrow = 5L, ncol = 5L,
             row_offset = 0L, col_offset = 0L, xmin = 200000, ymax = 6900010,
             resolution_m = 2, crs = "EPSG:3067")
provenance <- list(run_id = "synthetic-first-contact", code_revision = "fixture-v1",
                   pointer_source = "synthetic-pointer", water_source = "synthetic-water",
                   lake_id_source = "synthetic-lake-id", validity_source = "synthetic-domain",
                   lake_id_namespace = "RANTA10:synthetic-v1")

assert <- function(value, message = "Assertion failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}
expect_error <- function(expr) {
  caught <- tryCatch({ force(expr); NULL }, error = identity)
  assert(inherits(caught, "error"), "Expected a rejected contract")
}
fixture <- function(n = 25L) {
  list(pointer = rep(0, n), water_class = rep(NA_real_, n),
       lake_id = rep(NA_real_, n), valid = rep(TRUE, n))
}
trace_fixture <- function(f, start = 12L, g = grid, budget = 128L, p = provenance) {
  reads <- integer()
  read <- function(cell) {
    reads <<- c(reads, cell)
    assert(length(cell) == 1L && cell == floor(cell) && cell >= 1L &&
             cell <= length(f$pointer), "Callback received an out-of-domain cell")
    list(pointer = f$pointer[cell], water_class = f$water_class[cell],
         lake_id = f$lake_id[cell], valid = f$valid[cell])
  }
  result <- first_water_contact(start, g, read, max_steps = budget, provenance = p)
  assert(result$n_cell_reads == length(reads), "Read accounting disagrees with callback")
  assert(!anyDuplicated(reads), "A visited cell was read twice")
  assert(result$max_steps == budget)
  assert(identical(result$provenance, p))
  assert(identical(result$provenance_verification, "DECLARED_ONLY"))
  assert(identical(result$hydrological_validation, "NOT_ASSESSED"))
  assert(identical(result$MODERATE, "REVIEW_REQUIRED"))
  assert(identical(result$NATIONAL, "LOCKED"))
  list(result = result, reads = reads)
}
assert_unresolved <- function(result, status, terminal, transitions) {
  assert(identical(result$route_status, status))
  assert(result$terminal$local_cell == terminal)
  assert(result$n_transitions == transitions)
  assert(!result$water_reached && !result$recipient_identified)
  assert(is.null(result$first_water) && is.null(result$last_land))
  assert(is.na(result$recipient_id) && is.na(result$recipient_namespace))
  assert(length(result$uncertainty_reasons) > 0L)
}

qa <- new.env(parent = emptyenv())
qa$total <- 0L
qa$failed <- character()
case <- function(label, expr) {
  qa$total <- qa$total + 1L
  tryCatch({
    force(expr)
    cat("PASS:", label, "\n")
  }, error = function(e) {
    qa$failed <- c(qa$failed, label)
    cat("FAIL:", label, "-", conditionMessage(e), "\n")
  })
}

case("two land transitions terminate at the first identified lake", {
  f <- fixture(); f$pointer[c(12L, 13L)] <- 2L
  f$water_class[14L] <- 1L; f$lake_id[14L] <- 1847L
  a <- trace_fixture(f); r <- a$result
  assert(r$route_status == "FIRST_WATER_CONTACT")
  assert(r$raw_trace_status == "REACHES_WATER_CLASS")
  assert(r$source$local_cell == 12L && r$first_successor$local_cell == 13L)
  assert(r$terminal$local_cell == 14L && r$last_land$local_cell == 13L &&
           r$first_water$local_cell == 14L)
  assert(r$source$cell_uid == "synthetic-2m:3:2")
  assert(r$first_water$cell_uid == "synthetic-2m:3:4")
  assert(r$first_water$global_row == 3L && r$first_water$global_col == 4L)
  assert(r$first_water$x_m == 200007 && r$first_water$y_m == 6900005)
  assert(r$first_water$crs == "EPSG:3067")
  assert(r$n_transitions == 2L && r$n_cell_reads == 3L)
  assert(r$water_reached && r$recipient_identified && r$water_class == 1L &&
           r$lake_objectid == 1847L)
  assert(is.character(r$recipient_id) && length(r$recipient_id) == 1L &&
           !is.na(r$recipient_id) && nzchar(r$recipient_id))
  assert(r$recipient_namespace == provenance$lake_id_namespace)
  assert(!r$visit_cap_reached)
  assert(identical(as.integer(a$reads), c(12L, 13L, 14L)))
  cat("EXAMPLE: 12 -> 13 -> 14; last_land=13; first_water=14; lake=1847;",
      "x=200007 y=6900005; scientific=NOT_ASSESSED\n")
})

case("river-area contact is observed with an explicitly unknown recipient ID", {
  f <- fixture(); f$pointer[12L] <- 2L; f$water_class[13L] <- 2L
  r <- trace_fixture(f)$result
  assert(r$route_status == "FIRST_WATER_CONTACT" && r$water_reached)
  assert(r$water_class == 2L && r$first_water$local_cell == 13L)
  assert(!r$recipient_identified && is.na(r$recipient_id) &&
           is.na(r$recipient_namespace) && is.na(r$lake_objectid))
  assert(length(r$uncertainty_reasons) > 0L)
})

case("river-line contact is observed without inventing a waterbody ID", {
  f <- fixture(); f$pointer[12L] <- 2L; f$water_class[13L] <- 3L
  # A lake-ID raster value does not identify a river recipient.
  f$lake_id[13L] <- 1847L
  r <- trace_fixture(f)$result
  assert(r$route_status == "FIRST_WATER_CONTACT" && r$water_reached &&
           r$water_class == 3L)
  assert(!r$recipient_identified && is.na(r$recipient_id) && is.na(r$lake_objectid))
})

case("all eight Whitebox directions use row-major neighbour cells", {
  destinations <- c(9L, 14L, 19L, 18L, 17L, 12L, 7L, 8L)
  codes <- c(1L, 2L, 4L, 8L, 16L, 32L, 64L, 128L)
  for (i in seq_along(codes)) {
    f <- fixture(); f$pointer[13L] <- codes[i]
    f$water_class[destinations[i]] <- 1L; f$lake_id[destinations[i]] <- 1847L
    r <- trace_fixture(f, start = 13L)$result
    assert(r$route_status == "FIRST_WATER_CONTACT")
    assert(r$first_successor$local_cell == destinations[i] &&
             r$first_water$local_cell == destinations[i] && r$n_transitions == 1L)
  }
})

case("zero pointer remains an unresolved land terminal", {
  r <- trace_fixture(fixture())$result
  assert_unresolved(r, "D8_ZERO", 12L, 0L)
  assert(r$raw_trace_status == "D8_ZERO" && is.null(r$first_successor))
})

case("missing pointer is distinct from a zero pointer", {
  f <- fixture(); f$pointer[12L] <- NA_real_
  r <- trace_fixture(f)$result
  assert_unresolved(r, "POINTER_NA", 12L, 0L)
  assert(r$raw_trace_status == "POINTER_NA")
})

case("invalid finite and infinite pointers never create synthetic directions", {
  for (value in c(3, -1, 1.5, 256, Inf, -Inf)) {
    f <- fixture(); f$pointer[12L] <- value
    r <- trace_fixture(f)$result
    assert_unresolved(r, "INVALID_POINTER", 12L, 0L)
    assert(r$raw_trace_status == "INVALID_POINTER" && is.null(r$first_successor))
  }
})

case("a missing water-class value on valid land permits continued tracing", {
  f <- fixture(); f$pointer[c(12L, 13L)] <- 2L
  f$water_class[14L] <- 1L; f$lake_id[14L] <- 1847L
  r <- trace_fixture(f)$result
  assert(r$route_status == "FIRST_WATER_CONTACT" && r$n_transitions == 2L)
})

case("an invalid domain observation stops before reading beyond NoData", {
  f <- fixture(); f$pointer[c(12L, 13L)] <- 2L; f$valid[13L] <- FALSE
  f$water_class[14L] <- 1L; f$lake_id[14L] <- 1847L
  a <- trace_fixture(f); r <- a$result
  assert_unresolved(r, "NO_DATA", 13L, 1L)
  assert(is.na(r$raw_trace_status))
  assert(identical(as.integer(a$reads), c(12L, 13L)))
})

case("invalid source-domain data is an observation rather than a water hit", {
  f <- fixture(); f$valid[12L] <- FALSE; f$water_class[12L] <- 1L
  r <- trace_fixture(f)$result
  assert_unresolved(r, "NO_DATA", 12L, 0L)
})

case("invalid water classes stay explicit and never become first contacts", {
  for (value in c(0, 4, -1, 1.5, Inf)) {
    f <- fixture(); f$pointer[12L] <- 2L; f$water_class[13L] <- value
    r <- trace_fixture(f)$result
    assert_unresolved(r, "INVALID_WATER_CLASS", 13L, 1L)
    assert(is.na(r$raw_trace_status))
  }
})

case("a cycle includes its closing transition without rereading the cell", {
  f <- fixture(); f$pointer[12L] <- 2L; f$pointer[13L] <- 32L
  a <- trace_fixture(f); r <- a$result
  assert_unresolved(r, "CYCLE", 12L, 2L)
  assert(r$raw_trace_status == "CYCLE")
  assert(identical(as.integer(a$reads), c(12L, 13L)))
  at_limit <- trace_fixture(f, budget = 2L)$result
  assert_unresolved(at_limit, "CYCLE", 12L, 2L)
  assert(!at_limit$visit_cap_reached)
})

case("domain exit cannot wrap east or west into another raster row", {
  for (start in c(15L, 11L)) {
    f <- fixture(); f$pointer[start] <- if (start == 15L) 2L else 32L
    # The adjacent linear index would falsely appear to be water if wrapped.
    wrong <- if (start == 15L) 16L else 10L
    f$water_class[wrong] <- 1L; f$lake_id[wrong] <- 1847L
    a <- trace_fixture(f, start = start); r <- a$result
    assert_unresolved(r, "DOMAIN_EXIT_UNRESOLVED", start, 0L)
    assert(r$raw_trace_status == "DOMAIN_EXIT" && is.null(r$first_successor))
    assert(length(a$reads) == 1L)
  }
})

case("contact exactly at the transition budget is retained", {
  f <- fixture(); f$pointer[c(12L, 13L)] <- 2L
  f$water_class[14L] <- 1L; f$lake_id[14L] <- 1847L
  r <- trace_fixture(f, budget = 2L)$result
  assert(r$route_status == "FIRST_WATER_CONTACT" && r$n_transitions == 2L)
  assert(!r$visit_cap_reached)
})

case("a contact beyond the budget stays censored without an extra read", {
  f <- fixture(); f$pointer[c(12L, 13L)] <- 2L
  f$water_class[14L] <- 1L; f$lake_id[14L] <- 1847L
  a <- trace_fixture(f, budget = 1L); r <- a$result
  assert_unresolved(r, "STEP_LIMIT", 13L, 1L)
  assert(r$raw_trace_status == "MAX_STEPS" && r$visit_cap_reached)
  assert(identical(as.integer(a$reads), c(12L, 13L)))
})

case("a real terminal at the budget is not mislabeled as a visit cap", {
  f <- fixture(); f$pointer[12L] <- 2L
  r <- trace_fixture(f, budget = 1L)$result
  assert_unresolved(r, "D8_ZERO", 13L, 1L)
  assert(!r$visit_cap_reached)
})

case("merged land paths retain distinct source identities and one common contact", {
  f <- fixture(); f$pointer[7L] <- 4L; f$pointer[12L] <- 2L; f$pointer[13L] <- 2L
  f$water_class[14L] <- 1L; f$lake_id[14L] <- 1847L
  a <- trace_fixture(f, start = 7L)$result
  b <- trace_fixture(f, start = 12L)$result
  assert(a$route_status == "FIRST_WATER_CONTACT" && b$route_status == "FIRST_WATER_CONTACT")
  assert(a$source$cell_uid != b$source$cell_uid)
  assert(identical(a$first_water, b$first_water) && identical(a$last_land, b$last_land))
  assert(a$n_transitions == 2L && b$n_transitions == 2L)
})

case("water outgoing pointers cannot alter the first-water contact", {
  f <- fixture(); f$pointer[c(12L, 13L)] <- 2L
  f$water_class[14L] <- 1L; f$lake_id[14L] <- 1847L
  reference <- trace_fixture(f)$result
  for (pointer in c(0, 2, 32, 3, NA_real_, Inf)) {
    changed <- f; changed$pointer[14L] <- pointer
    r <- trace_fixture(changed)$result
    assert(identical(r, reference), "Water-only pointer modification changed land contact")
  }
})

case("a lake with a missing or invalid ID remains an unidentified water contact", {
  for (id in c(NA_real_, 0, -1, 1.5, Inf)) {
    f <- fixture(); f$pointer[12L] <- 2L; f$water_class[13L] <- 1L; f$lake_id[13L] <- id
    r <- trace_fixture(f)$result
    assert(r$route_status == "FIRST_WATER_CONTACT" && r$water_reached)
    assert(r$first_water$local_cell == 13L && r$last_land$local_cell == 12L)
    assert(!r$recipient_identified && is.na(r$recipient_id) &&
             is.na(r$recipient_namespace) && is.na(r$lake_objectid))
    assert(identical(r$observed_lake_id, id))
    assert(length(r$uncertainty_reasons) > 0L)
  }
})

case("global offsets preserve coordinates and identify the same cell across windows", {
  a <- trace_fixture(fixture(), start = 13L)$result
  small <- grid; small$nrow <- 3L; small$ncol <- 3L
  small$row_offset <- 1L; small$col_offset <- 1L
  b <- trace_fixture(fixture(9L), start = 5L, g = small)$result
  assert(a$source$cell_uid == b$source$cell_uid && a$source$x_m == b$source$x_m &&
           a$source$y_m == b$source$y_m)
  offset <- grid; offset$row_offset <- 100L; offset$col_offset <- 20L
  c <- trace_fixture(fixture(), g = offset)$result
  assert(c$source$global_row == 103L && c$source$global_col == 22L)
  assert(c$source$cell_uid == "synthetic-2m:103:22")
  assert(c$source$x_m == 200043 && c$source$y_m == 6899805)
  other <- grid; other$grid_id <- "another-grid"
  d <- trace_fixture(fixture(), start = 13L, g = other)$result
  assert(a$source$cell_uid != d$source$cell_uid)
})

case("an already valid water source is rejected rather than counted as land", {
  for (water in 1:3) {
    f <- fixture(); f$water_class[12L] <- water; f$lake_id[12L] <- 1847L
    expect_error(trace_fixture(f))
  }
})

case("invalid source indices and transition budgets fail before any callback", {
  n_reads <- 0L
  read <- function(cell) {
    n_reads <<- n_reads + 1L
    stop("CALLBACK_MUST_NOT_RUN")
  }
  for (start in list(0L, -1L, 26L, 1.5, NA_real_, Inf, "12", TRUE, c(12L, 13L))) {
    expect_error(first_water_contact(start, grid, read, provenance = provenance))
    assert(n_reads == 0L, "Invalid start was not rejected before the callback")
  }
  for (budget in list(0L, -1L, 257L, 1.5, NA_real_, Inf, "2", TRUE, c(1L, 2L))) {
    expect_error(first_water_contact(12L, grid, read, max_steps = budget, provenance = provenance))
    assert(n_reads == 0L, "Invalid budget was not rejected before the callback")
  }
})

case("invalid grid geometry is rejected", {
  changes <- list(list("nrow", 0L), list("nrow", 1.5), list("ncol", "5"),
                  list("row_offset", -1L), list("row_offset", 0.5),
                  list("col_offset", NA_real_), list("xmin", Inf), list("ymax", NA_real_),
                  list("resolution_m", 0), list("resolution_m", 3),
                  list("crs", "EPSG:4326"), list("grid_id", ""))
  for (change in changes) {
    bad <- grid; bad[[change[[1L]]]] <- change[[2L]]
    expect_error(trace_fixture(fixture(), g = bad))
  }
  bad <- grid; bad$nrow <- NULL
  expect_error(trace_fixture(fixture(), g = bad))
  expect_error(first_water_contact(12L, NULL, function(cell) NULL, provenance = provenance))
})

case("provenance is required and cannot become implied verification", {
  for (field in names(provenance)) {
    absent <- provenance; absent[[field]] <- NULL
    expect_error(trace_fixture(fixture(), p = absent))
    blank <- provenance; blank[[field]] <- ""
    expect_error(trace_fixture(fixture(), p = blank))
    bad <- provenance; bad[[field]] <- TRUE
    expect_error(trace_fixture(fixture(), p = bad))
  }
  expect_error(first_water_contact(12L, grid, function(cell) NULL))
})

case("malformed callback contracts and callback errors do not produce success", {
  good <- list(pointer = 0, water_class = NA_real_, lake_id = NA_real_, valid = TRUE)
  bad_values <- list(NULL, list(pointer = 0),
                     within(good, pointer <- c(2, 8)), within(good, pointer <- "2"),
                     within(good, water_class <- "1"), within(good, lake_id <- "1847"),
                     within(good, valid <- NA), within(good, valid <- 1),
                     within(good, valid <- c(TRUE, FALSE)))
  for (value in bad_values) {
    read <- local({ answer <- value; function(cell) answer })
    expect_error(first_water_contact(12L, grid, read, provenance = provenance))
  }
  expect_error(first_water_contact(12L, grid, function(cell) stop("synthetic read failure"),
                                  provenance = provenance))
  expect_error(first_water_contact(12L, grid, NULL, provenance = provenance))
})

case("method preserves supplied grid, source arrays, provenance and existing core", {
  f <- fixture(); f$pointer[c(12L, 13L)] <- 2L
  f$water_class[14L] <- 1L; f$lake_id[14L] <- 1847L
  before <- serialize(list(f, grid, provenance, formals(l1847_trace), body(l1847_trace)), NULL)
  trace_fixture(f)
  after <- serialize(list(f, grid, provenance, formals(l1847_trace), body(l1847_trace)), NULL)
  assert(identical(before, after))
})

if (qa$total == 0L) stop("FAIL: no first-water tests were executed", call. = FALSE)
cat(sprintf("TESTS=%d PASS=%d FAIL=%d\n", qa$total, qa$total - length(qa$failed), length(qa$failed)))
if (length(qa$failed)) stop("First-water regression failures: ", paste(qa$failed, collapse = "; "), call. = FALSE)
cat("PASS: first-water synthetic prototype only; no CSC evidence or hydrological approval\n")
