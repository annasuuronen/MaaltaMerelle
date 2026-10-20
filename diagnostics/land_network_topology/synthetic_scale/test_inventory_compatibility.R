#!/usr/bin/env Rscript
# Read only the pinned Git source object, never CSC data. Compare whole typed
# results to the previous inventory implementation, including row order.
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
here <- dirname(normalizePath(script)); parent <- dirname(here)
source(file.path(parent, "..", "low_d8_scope", "lake_1847_focus_core.R"))
source(file.path(parent, "..", "land_first_water", "first_water_contact.R"))
source(file.path(parent, "..", "land_d8_continuity", "trace_land_d8_route.R"))
source(file.path(parent, "land_network_topology.R"))
source(file.path(parent, "analyse_land_network_topology.R"))
source(file.path(here, "generator.R"))
pinned <- "effab29aa4d44ecc897efc0c91c96f3bfc1b4db6:diagnostics/land_network_topology/analyse_land_network_topology.R"
text <- system2("git", c("show", pinned), stdout = TRUE)
stopifnot(is.null(attr(text, "status")), length(text) > 0L)
env <- new.env(parent = .GlobalEnv); eval(parse(text = text), envir = env)
checks <- 0L
for (n in c(100L, 1000L)) {
  for (scenario in c("fan", "long", "mixed", "random")) {
    # The 1,000-cell dense fan exercises the performance repair; the small
    # cases also cover cycles, terminal cases and full exiting traces.
    if (n == 1000L && scenario != "fan") next
    f <- generate_scale_fixture(n, scenario)
    new <- synthetic_scale_methods(n)
    old <- synthetic_scale_methods(n, env$analyse_land_network_topology)
    network <- new$build(f$pointer, f$water, f$valid, f$grid, f$provenance, f$lake, 16L)
    stopifnot(identical(new$analyse(network), old$analyse(network)))
    checks <- checks + 1L
  }
}
stopifnot(checks > 0L)
cat(sprintf("PASS: %d complete inventory outputs identical to pinned base\n", checks))
