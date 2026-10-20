#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L)
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
here <- dirname(normalizePath(script)); parent <- dirname(here)
source(file.path(parent, "..", "low_d8_scope", "lake_1847_focus_core.R"))
source(file.path(parent, "..", "land_first_water", "first_water_contact.R"))
source(file.path(parent, "..", "land_d8_continuity", "trace_land_d8_route.R"))
source(file.path(parent, "land_network_topology.R"))
source(file.path(parent, "analyse_land_network_topology.R"))
source(file.path(here, "generator.R")); source(file.path(here, "oracle.R"))
n <- as.integer(args[1]); scenario <- args[2]; max_steps <- as.integer(args[3])
stopifnot(!is.na(max_steps), max_steps %in% c(4L, 16L, 32L))
original <- serialize(list(body(build_land_d8_network), body(analyse_land_network_topology),
                           body(select_land_network_cases)), NULL)
f <- generate_scale_fixture(n, scenario); stopifnot(inherits(f, "synthetic_d8_fixture"))
methods <- synthetic_scale_methods(n)
clock <- proc.time()[["elapsed"]]
network <- methods$build(f$pointer, f$water, f$valid, f$grid, f$provenance,
                         lake_id = f$lake, max_steps = max_steps)
build_s <- proc.time()[["elapsed"]] - clock
cat(sprintf("PHASE=BUILD_COMPLETE ELAPSED_S=%.6f\n", build_s)); flush.console()
clock <- proc.time()[["elapsed"]]
inventory <- methods$analyse(network)
inventory_s <- proc.time()[["elapsed"]] - clock
cat(sprintf("PHASE=INVENTORY_COMPLETE ELAPSED_S=%.6f\n", inventory_s)); flush.console()
clock <- proc.time()[["elapsed"]]
reference <- scale_reference(f, max_steps)
checks <- compare_scale_result(f, network, inventory, reference, max_steps)
oracle_s <- proc.time()[["elapsed"]] - clock
stopifnot(identical(original, serialize(list(body(build_land_d8_network),
  body(analyse_land_network_topology), body(select_land_network_cases)), NULL)))
# Long-chain sparse probes reuse the unchanged core up to its existing 256-step
# limit without materialising 256-step traces for every large-network source.
if (scenario == "long") {
  p <- as.vector(t(f$pointer)); w <- as.vector(t(f$water)); valid <- as.vector(t(f$valid))
  read <- function(cell) list(pointer = p[cell], water_class = w[cell], lake_id = NA_real_, valid = valid[cell])
  probes <- c(1L, as.integer(n / 2)); oracle <- scale_reference(f, 256L, probes)
  for (start in probes) {
    r <- trace_land_d8_route(start, f$grid, read, 256L, f$provenance)
    i <- match(start, oracle$land)
    stopifnot(identical(r$route_status, oracle$status[i]), identical(as.integer(r$path$local_cell), as.integer(oracle$paths[[i]])))
    checks <- checks + 2L
  }
}
cat(sprintf("RESULT n=%d scenario=%s cap=%d build_s=%.6f inventory_s=%.6f oracle_s=%.6f network_mib=%.6f inventory_mib=%.6f land=%d edges=%d confluences=%d exits=%d checks=%d status=PASS\n",
  n, scenario, max_steps, build_s, inventory_s, oracle_s,
  as.numeric(object.size(network)) / 1024^2, as.numeric(object.size(inventory)) / 1024^2,
  nrow(network$land_nodes), nrow(network$edges), nrow(inventory$confluence_details), nrow(inventory$exit_edges), checks))
