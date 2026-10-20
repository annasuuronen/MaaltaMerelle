#!/usr/bin/env Rscript
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
here <- dirname(normalizePath(script)); parent <- dirname(here)
source(file.path(parent, "..", "low_d8_scope", "lake_1847_focus_core.R"))
source(file.path(parent, "..", "land_first_water", "first_water_contact.R"))
source(file.path(parent, "..", "land_d8_continuity", "trace_land_d8_route.R"))
source(file.path(parent, "land_network_topology.R"))
source(file.path(parent, "analyse_land_network_topology.R"))
source(file.path(here, "generator.R")); source(file.path(here, "oracle.R"))
checks <- 0L
check <- function(ok) { stopifnot(isTRUE(ok)); checks <<- checks + 1L }
reject <- function(expr) check(inherits(tryCatch({force(expr); NULL}, error = identity), "error"))
original <- serialize(list(body(build_land_d8_network), body(analyse_land_network_topology), body(select_land_network_cases)), NULL)
# Identical-limit copies must preserve every AST node, including NULL and blank
# subscripts. The initial harness accidentally deleted literal NULL arguments.
copies <- synthetic_scale_methods(121L)
check(identical(body(copies$build), body(build_land_d8_network)))
check(identical(body(copies$analyse), body(analyse_land_network_topology)))
check(identical(body(copies$select), body(select_land_network_cases)))
for (scenario in c("fan", "long", "mixed", "random")) {
  f <- generate_scale_fixture(100L, scenario)
  a <- build_land_d8_network(f$pointer, f$water, f$valid, f$grid, f$provenance, f$lake, 4L)
  b <- copies$build(f$pointer, f$water, f$valid, f$grid, f$provenance, f$lake, 4L)
  check(identical(a, b))
  inv <- analyse_land_network_topology(a)
  check(identical(inv, copies$analyse(b)))
  check(compare_scale_result(f, a, inv, scale_reference(f, 4L), 4L) > 0L)
  bad <- a; bad$edges$to_cell[1] <- 1L
  reject(compare_scale_result(f, bad, inv, scale_reference(f, 4L), 4L))
  bad <- a; bad$land_nodes$land_indegree_in_window[1] <- 99L
  reject(compare_scale_result(f, bad, inv, scale_reference(f, 4L), 4L))
  bad <- inv; bad$accounting_qa$route_allocation_ok <- FALSE
  reject(compare_scale_result(f, a, bad, scale_reference(f, 4L), 4L))
}
set.seed(77); saved <- .Random.seed
f <- generate_scale_fixture(100L, "random")
check(identical(saved, .Random.seed))
check(identical(f, generate_scale_fixture(100L, "random")))
# All eight Whitebox directions and row-major global identity, independently
# specified centre-cell neighbours on a 3x3 fixture.
g <- f$grid; g$nrow <- g$ncol <- 3L
for (i in 1:8) {
  code <- c(1, 2, 4, 8, 16, 32, 64, 128)[i]
  target <- c(3L, 6L, 9L, 8L, 7L, 4L, 1L, 2L)[i]
  read <- function(cell) list(pointer = if (cell == 5L) code else 0,
    water_class = NA_real_, lake_id = NA_real_, valid = TRUE)
  r <- trace_land_d8_route(5L, g, read, 1L, f$provenance)
  check(identical(as.integer(r$path$local_cell), c(5L, target)))
  check(r$transitions$d8_code == code && r$n_transitions == 1L)
}
f <- generate_scale_fixture(1000L, "fan")
reject(build_land_d8_network(f$pointer, f$water, f$valid, f$grid, f$provenance, f$lake, 4L))
# Analyzer must reject >121 even before any large graph is built.
reject(analyse_land_network_topology(list(method_version = "land-network-topology-v1", grid = f$grid)))
check(identical(original, serialize(list(body(build_land_d8_network), body(analyse_land_network_topology), body(select_land_network_cases)), NULL)))
check(checks > 0L)
cat(sprintf("PASS: %d synthetic harness contracts; original 121-cell limits retained\n", checks))
