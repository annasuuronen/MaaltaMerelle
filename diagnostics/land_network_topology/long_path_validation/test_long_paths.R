#!/usr/bin/env Rscript
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
here <- dirname(normalizePath(script)); source(file.path(here, "common.R"))
bodies <- method_bodies(); rows <- list()
sparse <- function(label, f, start, expected, transitions, cap = 256L) {
  stopifnot(cap <= 256L, inherits(f, "synthetic_d8_fixture"))
  before <- serialize(f, NULL); read <- fixture_read(f); calls <- integer()
  callback <- function(cell) { calls <<- c(calls, cell); read(cell) }
  r <- trace_land_d8_route(start, f$grid, callback, cap, f$provenance)
  ref <- scale_reference(f, cap, starts = start)
  check(identical(r$route_status, expected) && identical(r$route_status, ref$status[1L]), label)
  check(r$n_transitions == transitions && r$n_transitions == ref$steps[1L] &&
    r$n_cell_reads == ref$reads[1L], paste(label, "accounting"))
  check(identical(as.integer(r$path$local_cell), as.integer(ref$paths[[1L]])) &&
    identical(as.integer(calls), as.integer(unique(ref$paths[[1L]]))), paste(label, "ordered reads and closing revisit"))
  check(r$n_transitions <= cap && r$n_cell_reads <= cap + 1L &&
    identical(before, serialize(f, NULL)), paste(label, "bounded immutable input"))
  check(r$hydrological_validation == "NOT_ASSESSED" && r$channel_interpretation == "NOT_ASSESSED" &&
    r$MODERATE == "REVIEW_REQUIRED" && r$NATIONAL == "LOCKED", paste(label, "scientific locks"))
  rows[[length(rows) + 1L]] <<- data.frame(label = label, n = f$n, start = start, cap = cap,
    status = r$route_status, transitions = r$n_transitions, reads = r$n_cell_reads,
    terminal = r$terminal$local_cell, result = "PASS")
  cat("PASS:", label, "\n"); flush.console()
  invisible(r)
}
f <- generate_scale_fixture(1000L, "long"); order <- serpentine_order(f)
primary <- sparse("long_chain_censored_at_256", f, order[1L], "STEP_LIMIT", 256L)
# 255 observed moves leave room to inspect the terminal's outward pointer.
sparse("exit_one_move_before_cap", f, order[1000L - 255L], "DOMAIN_EXIT_UNRESOLVED", 255L)
# Reaching that same exit-source cell with exactly 256 moves is censored:
# the original contract checks its work limit before attempting an exit.
sparse("at_exit_source_exactly_at_cap", f, order[1000L - 256L], "STEP_LIMIT", 256L)
zero <- f; target <- order[256L]; zero$pointer[zero$row[target], zero$col[target]] <- 0
zero$terminal[target] <- "D8_ZERO"
sparse("zero_one_move_before_cap", zero, order[1L], "D8_ZERO", 255L)
cycle <- f; from <- order[40L]; to <- order[39L]
# Fixed adjacent E step closes this explicit 2-cell cycle after its long prefix.
stopifnot(cycle$row[from] == cycle$row[to], cycle$col[to] == cycle$col[from] + 1L)
cycle$pointer[cycle$row[from], cycle$col[from]] <- 2
cycle$successor[from] <- to
sparse("cycle_before_cap", cycle, order[1L], "CYCLE", 40L)
serial <- serial_fixture(1000L)
r <- sparse("multiple_serial_confluences", serial, 1L, "STEP_LIMIT", 256L)
ref <- scale_reference(serial, 256L, 1L)
check(sum(unique(r$path$local_cell) %in% ref$confluences) >= 3L, "three fixed serial confluences observed")
for (w in 1:3) {
  water <- f; target <- order[128L]
  water$water[water$row[target], water$col[target]] <- w; water$kind[target] <- "WATER"
  if (w == 1L) water$lake[water$row[target], water$col[target]] <- 9001
  expected_id <- if (w == 1L) 9001 else NA_real_
  r <- sparse(paste0("first_water_class_", w), water, 1L, "FIRST_WATER_CONTACT", 127L)
  check(r$contact$water_class == w && identical(as.numeric(r$contact$lake_objectid), expected_id), "lake-only identity contract")
  if (w == 1L) for (p in c(0, 3, NA_real_)) {
    variant <- water; variant$pointer[variant$row[target], variant$col[target]] <- p
    a <- sparse(paste0("water_outgoing_pointer_", if (is.na(p)) "NA" else p), variant,
      1L, "FIRST_WATER_CONTACT", 127L)
    check(identical(a$path, r$path) && identical(a$first_water, r$first_water), "water outgoing pointer cannot change first contact")
  }
}
saved <- serialize(primary, NULL)
shorter <- sparse("shorter_source_budget_32", f, order[113L], "STEP_LIMIT", 32L, cap = 32L)
saved_shorter <- serialize(shorter, NULL)
other <- sparse("other_source_observes_beyond_primary_cap", f, order[129L], "STEP_LIMIT", 256L)
check(primary$terminal$local_cell %in% other$path$local_cell &&
  !other$terminal$local_cell %in% primary$path$local_cell, "secondary source has strictly later observed extent")
check(other$n_transitions > shorter$n_transitions && shorter$terminal$local_cell %in% other$path$local_cell &&
  !other$terminal$local_cell %in% shorter$path$local_cell &&
  identical(saved_shorter, serialize(shorter, NULL)) && shorter$route_status == "STEP_LIMIT",
  "a numerically longer secondary trace never resolves the shorter censored source")
sparse("other_source_direct_exit", f, tail(order, 1L), "DOMAIN_EXIT_UNRESOLVED", 0L)
check(identical(saved, serialize(primary, NULL)) && primary$route_status == "STEP_LIMIT" &&
  primary$continuation_unresolved, "secondary evidence never enriches the original censored trace")
# Whole inventories on a <=121-cell fixture exercise long common suffixes,
# comparing the indexed and pinned pre-optimization implementations exactly.
f <- serial_fixture(100L); serial_before <- serialize(f, NULL); methods <- synthetic_scale_methods(100L)
old <- synthetic_scale_methods(100L, reference_inventory()); prev <- prev_inv <- NULL
for (cap in c(32L, 64L, 128L)) {
  net <- methods$build(f$pointer, f$water, f$valid, f$grid, f$provenance, f$lake, cap)
  inv <- methods$analyse(net); check_inventory_compatibility(inv, old$analyse(net))
  ref <- scale_reference(f, cap)
  checks <- checks + compare_scale_result(f, net, inv, ref, cap)
  check_more_detail(f, net, inv, ref, cap)
  if (!is.null(prev)) check_monotonic(prev, net, prev_inv, inv)
  if (cap == 32L) {
    uid <- function(c) net$cells$cell_uid[c]
    m <- inv$source_confluences[inv$source_confluences$source_uid == uid(3L) &
      inv$source_confluences$confluence_uid == uid(12L), ]
    check(nrow(m) == 1L && m$reached_at_step == 16L && m$n_observed_shared_edges == 16L &&
      m$source_route_status == "STEP_LIMIT" && m$shared_extent == "PARTIAL_OBSERVED_SUFFIX", "no borrowing the confluence's longer suffix")
    check(any(inv$source_routes_per_exit$source_uid == uid(tail(serpentine_order(f), 1L))) &&
      !uid(3L) %in% inv$source_routes_per_exit$source_uid, "direct exit and censored upstream membership remain distinct")
    check(!inv$accounting_qa$n_minus_e_applicable, "incomplete source traces cannot validate N-E identity")
    saved_inv <- serialize(inv, NULL)
    fabricated <- inv
    extra <- head(fabricated$source_routes_per_exit, 1L); extra$source_uid <- uid(3L)
    fabricated$source_routes_per_exit <- rbind(fabricated$source_routes_per_exit, extra)
    error <- tryCatch(compare_scale_result(f, net, fabricated, ref, cap), error = identity)
    check(inherits(error, "error") && grepl("source to exit allocation", conditionMessage(error)), "oracle rejects a fabricated censored exit membership")
    fabricated <- inv
    at <- which(fabricated$source_confluences$source_uid == uid(3L) & fabricated$source_confluences$confluence_uid == uid(12L))
    fabricated$source_confluences$n_observed_shared_edges[at] <- 32L
    error <- tryCatch(compare_scale_result(f, net, fabricated, ref, cap), error = identity)
    check(inherits(error, "error") && grepl("censored shared suffix lengths", conditionMessage(error)), "oracle rejects a borrowed shared suffix")
    check(identical(saved_inv, serialize(inv, NULL)), "negative controls never mutate actual inventory")
  }
  if (cap == 128L) check(all(net$route_summary$route_status == "DOMAIN_EXIT_UNRESOLVED") &&
    inv$accounting_qa$n_minus_e_applicable, "complete exiting traces meet conditional accounting")
  cat(sprintf("PASS: serial inventory cap=%d baseline identical\n", cap))
  prev <- net; prev_inv <- inv
}
check(identical(bodies, method_bodies()) && identical(serial_before, serialize(f, NULL)), "all original function bodies and serial input preserved")
stopifnot(checks > 0L, length(rows) == 15L)
write.csv(do.call(rbind, rows), file.path(here, sprintf("B_sparse_results_%d_cases.csv", length(rows))), row.names = FALSE)
cat(sprintf("RESULT n=1000 scenario=sparse cap=256 sparse_cases=%d serial_inventory_cases=3 checks=%d status=PASS\n", length(rows), checks))
