#!/usr/bin/env Rscript
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
here <- dirname(normalizePath(script)); source(file.path(here, "common.R"))
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) %in% c(2L, 3L))
n <- as.integer(args[1L]); scenario <- args[2L]
stopifnot(n %in% c(100L, 1000L, 10000L), scenario %in% c("fan", "long", "mixed", "random"))
caps <- if (length(args) == 3L) as.integer(args[3L]) else c(4L, 16L, 32L)
stopifnot(all(caps %in% c(4L, 16L, 32L)), n != 10000L || identical(caps, 16L) && scenario == "long")
f <- generate_scale_fixture(n, scenario); fixture_before <- serialize(f, NULL); bodies <- method_bodies()
methods <- synthetic_scale_methods(n); old <- synthetic_scale_methods(n, reference_inventory())
prev <- prev_inv <- NULL; measurements <- list()
for (cap in caps) {
  clock <- proc.time()[["elapsed"]]
  net <- methods$build(f$pointer, f$water, f$valid, f$grid, f$provenance, f$lake, cap)
  build_s <- proc.time()[["elapsed"]] - clock
  clock <- proc.time()[["elapsed"]]; inv <- methods$analyse(net)
  inventory_s <- proc.time()[["elapsed"]] - clock
  clock <- proc.time()[["elapsed"]]
  check_inventory_compatibility(inv, old$analyse(net))
  compatibility_s <- proc.time()[["elapsed"]] - clock
  clock <- proc.time()[["elapsed"]]; ref <- scale_reference(f, cap)
  checks <- checks + compare_scale_result(f, net, inv, ref, cap)
  check_more_detail(f, net, inv, ref, cap)
  if (!is.null(prev)) {
    before <- serialize(list(prev, prev_inv), NULL)
    check_monotonic(prev, net, prev_inv, inv)
    check(identical(before, serialize(list(prev, prev_inv), NULL)), "previous observations never enriched in place")
  }
  oracle_s <- proc.time()[["elapsed"]] - clock
  measurements[[length(measurements) + 1L]] <- data.frame(n = n, scenario = scenario, cap = cap,
    build_s = build_s, inventory_s = inventory_s, compatibility_s = compatibility_s, oracle_s = oracle_s,
    land = length(ref$land), transitions = sum(ref$steps), censored = sum(ref$status == "STEP_LIMIT"),
    confluences = length(ref$confluences), direct_exits = length(ref$exits),
    reached_exits = sum(ref$status == "DOMAIN_EXIT_UNRESOLVED"), water = sum(ref$status == "FIRST_WATER_CONTACT"),
    cycles = sum(ref$status == "CYCLE"), network_mib = as.numeric(object.size(net)) / 1024^2,
    inventory_mib = as.numeric(object.size(inv)) / 1024^2, baseline_identical = TRUE, status = "PASS")
  cat(sprintf("DETAIL n=%d scenario=%s cap=%d censored=%d reached_exits=%d checks=%d status=PASS\n",
    n, scenario, cap, sum(ref$status == "STEP_LIMIT"), sum(ref$status == "DOMAIN_EXIT_UNRESOLVED"), checks)); flush.console()
  prev <- net; prev_inv <- inv
}
check(identical(fixture_before, serialize(f, NULL)) && identical(bodies, method_bodies()), "immutable fixtures and routing functions")
stopifnot(checks > 0L)
m <- do.call(rbind, measurements)
write.csv(m, file.path(here, sprintf("A_%s_%d_caps_%s.csv", scenario, n, paste(caps, collapse = "-"))), row.names = FALSE)
cat(sprintf("RESULT n=%d scenario=%s cap=0 build_s=%.6f inventory_s=%.6f compatibility_s=%.6f oracle_s=%.6f comparisons=%d checks=%d status=PASS\n",
 n, scenario, sum(m$build_s), sum(m$inventory_s), sum(m$compatibility_s), sum(m$oracle_s), nrow(m), checks))
