# Independent graph calculations: no pointer decoding or calls into the SUT.
scale_reference <- function(f, max_steps, starts = NULL) {
  land <- which(f$kind == "LAND")
  from <- land[f$terminal[land] == "" & f$successor[land] != 0]
  to <- f$successor[from]
  land_from <- from[f$kind[to] == "LAND"]; land_to <- f$successor[land_from]
  indegree <- tabulate(land_to, nbins = f$n)
  exits <- land[f$terminal[land] == "" & f$successor[land] == 0]
  if (!is.null(starts)) land <- starts
  paths <- vector("list", length(land)); status <- character(length(land))
  steps <- reads <- terminal <- integer(length(land))
  for (i in seq_along(land)) {
    p <- integer(); cell <- land[i]; moved <- 0L; observed <- 0L
    repeat {
      if (cell %in% p) { p <- c(p, cell); reason <- "CYCLE"; break }
      p <- c(p, cell); observed <- observed + 1L
      if (f$kind[cell] != "LAND") {
        reason <- switch(f$kind[cell], WATER = "FIRST_WATER_CONTACT", f$kind[cell]); break
      }
      if (nzchar(f$terminal[cell])) { reason <- f$terminal[cell]; break }
      if (moved == max_steps) { reason <- "STEP_LIMIT"; break }
      if (f$successor[cell] == 0L) { reason <- "DOMAIN_EXIT_UNRESOLVED"; break }
      cell <- f$successor[cell]; moved <- moved + 1L
    }
    paths[[i]] <- p; status[i] <- reason; terminal[i] <- cell
    steps[i] <- moved; reads[i] <- observed
  }
  list(land = land, from = from, to = to, land_from = land_from,
    indegree = indegree, confluences = which(indegree >= 2L), exits = exits,
    paths = paths, status = status, terminal = terminal, steps = steps, reads = reads)
}

compare_scale_result <- function(f, network, inventory, ref, max_steps) {
  checks <- 0L
  check <- function(ok, label) {
    checks <<- checks + 1L
    if (!isTRUE(ok)) stop("ORACLE_MISMATCH: ", label, call. = FALSE)
  }
  uid <- function(cell) paste(f$grid$grid_id, f$grid$row_offset + f$row[cell],
                             f$grid$col_offset + f$col[cell], sep = ":")
  check(identical(as.integer(network$edges$from_cell), as.integer(ref$from)) &&
        identical(as.integer(network$edges$to_cell), as.integer(ref$to)), "canonical graph")
  check(all(network$edges$d8_code == as.vector(t(f$pointer))[ref$from]), "observed D8 values")
  check(identical(network$cells$cell_kind, f$kind) &&
    identical(network$cells$water_class, as.vector(t(f$water))) &&
    identical(network$cells$lake_id, as.vector(t(f$lake))), "independent input identities")
  check(all(network$cells$x_m == f$grid$xmin + (f$grid$col_offset + f$col - 0.5) * 2) &&
    all(network$cells$y_m == f$grid$ymax - (f$grid$row_offset + f$row - 0.5) * 2), "2 m global cell centres")
  check(!anyDuplicated(network$edges$from_cell) && !anyDuplicated(network$edges$edge_id), "unique edges")
  check(identical(network$edges$from_uid, uid(ref$from)) && identical(network$edges$to_uid, uid(ref$to)), "global IDs")
  check(all(network$land_nodes$land_indegree_in_window == ref$indegree[ref$land]), "indegrees")
  check(identical(as.integer(inventory$confluence_details$local_cell), as.integer(ref$confluences)), "confluences")
  check(identical(as.integer(inventory$exit_edges$local_cell), as.integer(ref$exits)), "direct exit events")
  check(identical(network$route_summary$route_status, ref$status), "all route statuses")
  check(all(network$route_summary$n_transitions == ref$steps) &&
        all(network$route_summary$n_cell_reads == ref$reads), "route budgets and cycle closure")
  check(all(network$route_summary$terminal_cell == ref$terminal), "terminal cells")
  for (i in seq_along(ref$land)) {
    check(identical(as.integer(network$routes[[i]]$path$local_cell), as.integer(ref$paths[[i]])), "ordered route path")
  }
  exited <- which(ref$status == "DOMAIN_EXIT_UNRESOLVED")
  check(identical(inventory$source_routes_per_exit$source_uid, uid(ref$land[exited])) &&
        identical(inventory$source_routes_per_exit$exit_cell_uid, uid(ref$terminal[exited])), "source to exit allocation")
  check(!anyDuplicated(inventory$source_routes_per_exit$source_uid), "no double counted exit sources")
  check(all(inventory$exit_edges$n_source_routes ==
    tabulate(match(ref$terminal[exited], ref$exits), nbins = length(ref$exits))), "exit group sizes")
  edge_index <- integer(f$n); edge_index[ref$from] <- seq_along(ref$from)
  members <- lapply(seq_along(ref$land), function(i) {
    p <- ref$paths[[i]]; k <- which(!duplicated(p) & p %in% ref$confluences)
    if (!length(k)) return(NULL)
    data.frame(source = i, confluence = p[k], pos = k)
  })
  members <- do.call(rbind, members)
  if (is.null(members)) members <- data.frame(source = integer(), confluence = integer(), pos = integer())
  members <- members[order(members$confluence, members$source), , drop = FALSE]
  check(nrow(members) == nrow(inventory$source_confluences), "confluence membership cardinality")
  if (nrow(members)) {
    own <- match(members$confluence, ref$land)
    expected_shared <- pmin(ref$steps[own], ref$steps[members$source] - members$pos + 1L)
    check(identical(inventory$source_confluences$source_uid, uid(ref$land[members$source])) &&
      identical(inventory$source_confluences$confluence_uid, uid(members$confluence)), "membership identities")
    check(all(inventory$source_confluences$n_observed_shared_edges == expected_shared), "censored shared suffix lengths")
  }
  for (c in ref$confluences) {
    p <- ref$paths[[match(c, ref$land)]]
    got <- inventory$segment_edges[inventory$segment_edges$segment_id == paste0("SEGMENT:", uid(c)), , drop = FALSE]
    expected_ids <- edge_index[head(p, -1L)]
    check(identical(as.integer(got$edge_id), as.integer(expected_ids)), "canonical shared edge references")
    check(!anyDuplicated(got$edge_id), "shared cycle edges appear once per segment")
    incoming <- inventory$confluence_incoming[inventory$confluence_incoming$confluence_uid == uid(c), ]
    check(setequal(incoming$from_uid, uid(ref$land_from[f$successor[ref$land_from] == c])), "incoming confluence sources")
  }
  q <- inventory$accounting_qa
  nonland_edges <- sum(f$kind[ref$to] != "LAND")
  stops <- sum(nzchar(f$terminal[ref$land]))
  check(q$n_land_nodes == length(ref$land) && q$n_internal_land_edges == length(ref$land_from) &&
    q$n_other_internal_edges == nonland_edges && q$n_exit_events == length(ref$exits) &&
    q$n_nonexit_terminal_sources == stops, "partition counts")
  check(q$direct_partition_ok && q$route_allocation_ok &&
    length(ref$land) == length(ref$land_from) + nonland_edges + length(ref$exits) + stops, "independent conservation")
  applicable <- length(ref$land) == f$n && all(ref$status == "DOMAIN_EXIT_UNRESOLVED")
  check(identical(q$n_minus_e_applicable, applicable), "N-E applicability")
  check(inventory$accumulation == "NOT_COMPUTED" && inventory$external_inflow == "UNKNOWN" &&
    inventory$hydrological_validation == "NOT_ASSESSED" && inventory$NATIONAL == "LOCKED" && inventory$MODERATE == "REVIEW_REQUIRED" &&
    inventory$channel_interpretation == "NOT_ASSESSED", "scientific locks")
  check(sum(network$route_summary$n_transitions) <= length(ref$land) * max_steps, "bounded work")
  checks
}
