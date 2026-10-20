# Postprocess only the bounded, already-observed graph and stored routes.
# No D8 decoder, new route traversal, cell callback, raster or file I/O.
analyse_land_network_topology <- function(network, full_grid = NULL) {
  require_true <- function(ok, message) {
    if (!isTRUE(ok)) stop(message, call. = FALSE)
  }
  whole <- function(x, minimum = 0) is.numeric(x) && length(x) == 1L &&
    is.finite(x) && x == floor(x) && x >= minimum && x <= .Machine$integer.max
  table_has <- function(x, fields) is.data.frame(x) && !anyDuplicated(names(x)) &&
    all(fields %in% names(x))
  text_col <- function(x) is.character(x) && !anyNA(x) && all(nzchar(x))
  flag_col <- function(x) is.logical(x) && !anyNA(x)
  statuses <- c("D8_ZERO", "POINTER_NA", "INVALID_POINTER", "NO_DATA",
                "INVALID_WATER_CLASS", "CYCLE", "DOMAIN_EXIT_UNRESOLVED",
                "STEP_LIMIT", "FIRST_WATER_CONTACT")
  require_true(is.list(network) && identical(network$method_version, "land-network-topology-v1"),
               "Expected an observed land-network-topology-v1 result.")
  g <- network$grid
  require_true(is.list(g) && whole(g$nrow, 1) && whole(g$ncol, 1) &&
    g$nrow * as.double(g$ncol) <= 121 && whole(g$row_offset) && whole(g$col_offset) &&
    identical(g$crs, "EPSG:3067") && isTRUE(g$resolution_m == 2), "Invalid bounded grid.")
  cells <- network$cells; nodes <- network$land_nodes
  edges <- network$edges; land_edges <- network$land_edges
  summaries <- network$route_summary; routes <- network$routes
  require_true(table_has(cells, c("local_cell", "cell_uid", "global_row", "global_col",
    "x_m", "y_m", "pointer", "cell_kind", "is_core", "is_halo")) &&
    nrow(cells) == g$nrow * g$ncol &&
    identical(as.numeric(cells$local_cell), as.numeric(seq_len(nrow(cells)))) &&
    text_col(cells$cell_uid) && !anyDuplicated(cells$cell_uid) &&
    all(is.finite(cells$global_row)) && all(is.finite(cells$global_col)) &&
    flag_col(cells$is_core) && flag_col(cells$is_halo) &&
    all(cells$is_core != cells$is_halo), "Invalid cell identities or core/halo flags.")
  expected_row <- g$row_offset + (cells$local_cell - 1) %/% g$ncol + 1
  expected_col <- g$col_offset + (cells$local_cell - 1) %% g$ncol + 1
  expected_core <- (cells$local_cell - 1) %/% g$ncol > 0 &
    (cells$local_cell - 1) %/% g$ncol < g$nrow - 1 &
    (cells$local_cell - 1) %% g$ncol > 0 & (cells$local_cell - 1) %% g$ncol < g$ncol - 1
  require_true(all(cells$global_row == expected_row) && all(cells$global_col == expected_col) &&
    identical(cells$is_core, expected_core) &&
    identical(cells$cell_uid, paste(g$grid_id, expected_row, expected_col, sep = ":")),
    "Cell coordinates or core/halo labels disagree with the window.")
  land <- which(cells$cell_kind == "LAND")
  require_true(table_has(nodes, c("local_cell", "cell_uid", "land_indegree_in_window",
    "outgoing_kind", "outgoing_to_uid", "is_core", "is_halo", "route_status")) &&
    identical(as.numeric(nodes$local_cell), as.numeric(land)) &&
    identical(nodes$cell_uid, cells$cell_uid[land]) &&
    identical(nodes$is_core, cells$is_core[land]) && identical(nodes$is_halo, cells$is_halo[land]),
    "Land nodes disagree with the observed cells.")
  require_true(table_has(edges, c("edge_id", "from_cell", "to_cell", "from_uid", "to_uid",
    "d8_code", "edge_kind", "from_is_core", "zone_transition")) && nrow(edges) <= length(land) &&
    !anyDuplicated(edges$edge_id) && !anyDuplicated(edges$from_uid) &&
    !anyNA(match(edges$from_cell, land)) && !anyNA(match(edges$to_cell, cells$local_cell)) &&
    all(edges$from_uid == cells$cell_uid[edges$from_cell]) &&
    all(edges$to_uid == cells$cell_uid[edges$to_cell]) &&
    all(is.finite(edges$d8_code)) && all(edges$d8_code == cells$pointer[edges$from_cell]),
    "Invalid, duplicate or unobserved canonical edges.")
  from <- match(edges$from_uid, cells$cell_uid); to <- match(edges$to_uid, cells$cell_uid)
  dr <- cells$global_row[to] - cells$global_row[from]
  dc <- cells$global_col[to] - cells$global_col[from]
  require_true(all(abs(dr) <= 1 & abs(dc) <= 1 & (abs(dr) + abs(dc)) >= 1),
    "Canonical edges must be observed adjacent cells.")
  lengths <- 2 * sqrt(dr^2 + dc^2)
  li <- which(edges$edge_kind == "LAND_TO_LAND")
  require_true(table_has(land_edges, names(edges)) &&
    identical(land_edges, edges[li, , drop = FALSE]) &&
    !anyNA(match(edges$to_cell[li], land)) &&
    all(nodes$land_indegree_in_window == tabulate(match(edges$to_cell[li], land), nbins = length(land))),
    "Canonical land edges or local indegrees disagree.")
  require_true(table_has(summaries, c("source_cell", "source_uid", "route_status", "terminal_cell",
    "n_transitions", "n_cell_reads")) && nrow(summaries) == length(land) &&
    identical(summaries$source_uid, nodes$cell_uid) &&
    is.list(routes) && length(routes) == length(land) &&
    identical(names(routes), nodes$cell_uid) && all(summaries$route_status %in% statuses) &&
    identical(nodes$route_status, summaries$route_status), "Mismatched stored route inventory.")
  edge_ids_by_route <- vector("list", length(routes))
  for (i in seq_along(routes)) {
    r <- routes[[i]]
    require_true(is.list(r) && table_has(r$path, c("step", "local_cell", "cell_uid", "cell_kind", "revisited")) &&
      table_has(r$transitions, c("from_uid", "to_uid", "d8_code", "edge_kind", "closes_cycle")) &&
      nrow(r$path) == nrow(r$transitions) + 1L && nrow(r$path) <= 257L &&
      r$path$cell_uid[1L] == nodes$cell_uid[i] && !anyNA(match(r$path$cell_uid, cells$cell_uid)) &&
      identical(r$route_status, summaries$route_status[i]) &&
      r$n_transitions == nrow(r$transitions) && r$n_transitions == summaries$n_transitions[i] &&
      tail(r$path$local_cell, 1L) == summaries$terminal_cell[i], "Invalid stored route path.")
    k <- match(r$transitions$from_uid, edges$from_uid)
    require_true(!anyNA(k) && all(r$transitions$to_uid == edges$to_uid[k]) &&
      all(r$transitions$d8_code == edges$d8_code[k]) &&
      all(r$transitions$edge_kind == edges$edge_kind[k]) &&
      identical(r$transitions$from_uid, head(r$path$cell_uid, -1L)) &&
      identical(r$transitions$to_uid, tail(r$path$cell_uid, -1L)),
      "Stored route transitions disagree with canonical edges.")
    edge_ids_by_route[[i]] <- edges$edge_id[k]
    outgoing <- match(nodes$cell_uid[i], edges$from_uid)
    require_true(if (is.na(outgoing)) {
      nrow(r$transitions) == 0L && nodes$outgoing_kind[i] == r$route_status &&
        is.na(nodes$outgoing_to_uid[i])
    } else {
      nrow(r$transitions) >= 1L && nodes$outgoing_kind[i] == edges$edge_kind[outgoing] &&
        nodes$outgoing_to_uid[i] == edges$to_uid[outgoing]
    }, "Source outgoing edge and its stored trace disagree.")
  }
  if (!is.null(full_grid)) {
    require_true(is.list(full_grid) && whole(full_grid$nrow, 1) && whole(full_grid$ncol, 1) &&
      g$row_offset + g$nrow <= full_grid$nrow && g$col_offset + g$ncol <= full_grid$ncol,
      "Full grid does not contain the declared window.")
  }
  bind <- function(rows, prototype) {
    if (!length(rows)) return(prototype)
    x <- do.call(rbind, rows); row.names(x) <- NULL; x
  }
  empty <- function(...) data.frame(..., stringsAsFactors = FALSE)
  confl_idx <- which(nodes$land_indegree_in_window >= 2L)
  confluence_details <- empty(confluence_uid = nodes$cell_uid[confl_idx],
    local_cell = nodes$local_cell[confl_idx], global_row = cells$global_row[land[confl_idx]],
    global_col = cells$global_col[land[confl_idx]], is_core = nodes$is_core[confl_idx],
    is_halo = nodes$is_halo[confl_idx], land_indegree_in_window = nodes$land_indegree_in_window[confl_idx],
    pointer = cells$pointer[land[confl_idx]], outgoing_kind = nodes$outgoing_kind[confl_idx],
    outgoing_to_uid = nodes$outgoing_to_uid[confl_idx], route_status = nodes$route_status[confl_idx],
    external_inflow = rep("UNKNOWN", length(confl_idx)))
  incoming <- segments <- segment_cells <- segment_edges <- associations <- list()
  for (j in seq_along(confl_idx)) {
    i <- confl_idx[j]; uid <- nodes$cell_uid[i]; segment <- paste0("SEGMENT:", uid)
    r <- routes[[i]]; ids <- edge_ids_by_route[[i]]; k <- match(ids, edges$edge_id)
    a <- which(edges$edge_kind == "LAND_TO_LAND" & edges$to_uid == uid)
    incoming[[j]] <- empty(confluence_uid = rep(uid, length(a)), edge_id = edges$edge_id[a],
      from_uid = edges$from_uid[a], d8_code = edges$d8_code[a],
      from_is_core = edges$from_is_core[a], zone_transition = edges$zone_transition[a])
    segments[[j]] <- empty(segment_id = segment, confluence_uid = uid,
      n_observed_edges = length(ids), n_unique_edges = length(unique(ids)),
      n_observed_land_edges = sum(edges$edge_kind[k] == "LAND_TO_LAND"),
      n_unique_cells = length(unique(r$path$cell_uid)), observed_length_m = sum(lengths[k]),
      route_status = r$route_status, external_inflow = "UNKNOWN")
    cp <- match(r$path$cell_uid, cells$cell_uid)
    segment_cells[[j]] <- empty(segment_id = rep(segment, length(cp)), order = seq_along(cp),
      step = r$path$step, local_cell = r$path$local_cell, cell_uid = r$path$cell_uid,
      global_row = cells$global_row[cp], global_col = cells$global_col[cp],
      cell_kind = cells$cell_kind[cp], is_core = cells$is_core[cp], is_halo = cells$is_halo[cp],
      revisited = r$path$revisited)
    segment_edges[[j]] <- empty(segment_id = rep(segment, length(k)), order = seq_along(k),
      edge_id = ids, from_uid = edges$from_uid[k], to_uid = edges$to_uid[k],
      d8_code = edges$d8_code[k], edge_kind = edges$edge_kind[k], step_length_m = lengths[k],
      closes_cycle = r$transitions$closes_cycle)
    for (s in seq_along(routes)) {
      pos <- match(uid, routes[[s]]$path$cell_uid)
      if (is.na(pos)) next
      observed <- edge_ids_by_route[[s]]
      suffix <- observed[seq_along(observed) >= pos]
      common <- min(length(ids), length(suffix))
      if (common) {
        require_true(all(ids[seq_len(common)] == suffix[seq_len(common)]),
                     "Observed common suffix disagrees with the confluence segment.")
      }
      associations[[length(associations) + 1L]] <- empty(source_uid = nodes$cell_uid[s],
        confluence_uid = uid, reached_at_step = routes[[s]]$path$step[pos],
        n_observed_shared_edges = common, n_unique_shared_edges = length(unique(head(ids, common))),
        observed_shared_length_m = sum(lengths[match(head(ids, common), edges$edge_id)]),
        source_route_status = routes[[s]]$route_status,
        shared_extent = if (common == length(ids)) "FULL_CONFLUENCE_SEGMENT_OBSERVED" else "PARTIAL_OBSERVED_SUFFIX")
    }
  }
  confluence_incoming <- bind(incoming, empty(confluence_uid = character(), edge_id = integer(),
    from_uid = character(), d8_code = numeric(), from_is_core = logical(), zone_transition = character()))
  shared_segments <- bind(segments, empty(segment_id = character(), confluence_uid = character(),
    n_observed_edges = integer(), n_unique_edges = integer(), n_observed_land_edges = integer(),
    n_unique_cells = integer(), observed_length_m = numeric(), route_status = character(), external_inflow = character()))
  segment_cells <- bind(segment_cells, empty(segment_id = character(), order = integer(), step = integer(),
    local_cell = integer(), cell_uid = character(), global_row = numeric(), global_col = numeric(),
    cell_kind = character(), is_core = logical(), is_halo = logical(), revisited = logical()))
  segment_edges <- bind(segment_edges, empty(segment_id = character(), order = integer(), edge_id = integer(),
    from_uid = character(), to_uid = character(), d8_code = numeric(), edge_kind = character(),
    step_length_m = numeric(), closes_cycle = logical()))
  source_confluences <- bind(associations, empty(source_uid = character(), confluence_uid = character(),
    reached_at_step = numeric(), n_observed_shared_edges = integer(), n_unique_shared_edges = integer(),
    observed_shared_length_m = numeric(), source_route_status = character(), shared_extent = character()))

  exit_idx <- which(nodes$outgoing_kind == "DOMAIN_EXIT_UNRESOLVED")
  exit_rows <- list()
  # Direction is learned ONLY from a same-code step already observed by the
  # reviewed core. Its private decoder is not copied or evaluated here.
  for (j in seq_along(exit_idx)) {
    i <- exit_idx[j]; cell <- land[i]; code <- cells$pointer[cell]
    require_true(nodes$is_halo[i] && is.finite(code) && code != 0, "Invalid direct exit source.")
    samples <- which(edges$d8_code == code)
    predicted_row <- predicted_col <- NA_real_; predicted_uid <- NA_character_
    direction <- "UNKNOWN"; origin <- "ENCAPSULATED_D8_DIRECTION_NOT_OBSERVED"
    receiver_status <- "RECEIVER_UNKNOWN"
    if (length(samples)) {
      require_true(length(unique(dr[samples])) == 1L && length(unique(dc[samples])) == 1L,
                   "Inconsistent observed direction for one D8 code.")
      rr <- dr[samples[1L]]; cc <- dc[samples[1L]]
      direction <- paste0(if (rr < 0) "N" else if (rr > 0) "S" else "",
                          if (cc < 0) "W" else if (cc > 0) "E" else "")
      origin <- "OBSERVED_INTERNAL_STEP_FROM_REVIEWED_CORE"
      predicted_row <- cells$global_row[cell] + rr; predicted_col <- cells$global_col[cell] + cc
      outside_window <- predicted_row <= g$row_offset || predicted_row > g$row_offset + g$nrow ||
        predicted_col <= g$col_offset || predicted_col > g$col_offset + g$ncol
      require_true(outside_window, "A direct exit prediction must leave the window.")
      receiver_status <- if (is.null(full_grid)) "FULL_GRID_SCOPE_UNKNOWN" else if (
        predicted_row < 1 || predicted_row > full_grid$nrow ||
        predicted_col < 1 || predicted_col > full_grid$ncol) "FULL_GRID_EXIT" else "WINDOW_EXIT_INSIDE_FULL_GRID"
      # An outside-grid coordinate is a predicted step, not a valid grid cell.
      if (predicted_row >= 1 && predicted_col >= 1 && receiver_status != "FULL_GRID_EXIT")
        predicted_uid <- paste(g$grid_id, predicted_row, predicted_col, sep = ":")
    }
    exit_rows[[j]] <- empty(exit_id = paste0("EXIT:", nodes$cell_uid[i]), local_cell = nodes$local_cell[i],
      exit_cell_uid = nodes$cell_uid[i], global_row = cells$global_row[cell], global_col = cells$global_col[cell],
      is_core = nodes$is_core[i], is_halo = nodes$is_halo[i], d8_code = code, direction = direction,
      direction_source = origin, predicted_receiver_row = predicted_row, predicted_receiver_col = predicted_col,
      predicted_receiver_uid = predicted_uid, receiver_status = receiver_status, receiver_raster_read = FALSE,
      route_status = "DOMAIN_EXIT_UNRESOLVED", n_source_routes = 0L)
  }
  exit_edges <- bind(exit_rows, empty(exit_id = character(), local_cell = integer(), exit_cell_uid = character(),
    global_row = numeric(), global_col = numeric(), is_core = logical(), is_halo = logical(),
    d8_code = numeric(), direction = character(), direction_source = character(),
    predicted_receiver_row = numeric(), predicted_receiver_col = numeric(), predicted_receiver_uid = character(),
    receiver_status = character(), receiver_raster_read = logical(), route_status = character(), n_source_routes = integer()))
  allocated <- list()
  exit_routes <- which(summaries$route_status == "DOMAIN_EXIT_UNRESOLVED")
  for (i in exit_routes) {
    uid <- tail(routes[[i]]$path$cell_uid, 1L)
    j <- match(uid, exit_edges$exit_cell_uid)
    require_true(!is.na(j), "Exit-terminating route lacks a direct exit event.")
    allocated[[length(allocated) + 1L]] <- empty(exit_id = exit_edges$exit_id[j],
      source_uid = nodes$cell_uid[i], exit_cell_uid = uid,
      n_transitions = summaries$n_transitions[i], source_is_core = nodes$is_core[i])
  }
  source_routes_per_exit <- bind(allocated, empty(exit_id = character(), source_uid = character(),
    exit_cell_uid = character(), n_transitions = numeric(), source_is_core = logical()))
  exit_edges$n_source_routes <- tabulate(match(source_routes_per_exit$exit_id, exit_edges$exit_id),
                                         nbins = nrow(exit_edges))
  no_edge <- is.na(match(nodes$cell_uid, edges$from_uid))
  nonexit_terminal <- sum(no_edge & nodes$outgoing_kind != "DOMAIN_EXIT_UNRESOLVED")
  all_land <- nrow(cells) == nrow(nodes)
  all_exit <- length(land) > 0L && length(exit_routes) == length(land)
  applicable <- all_land && all_exit
  partition <- length(land) == nrow(land_edges) + (nrow(edges) - nrow(land_edges)) + nrow(exit_edges) + nonexit_terminal
  allocation <- nrow(source_routes_per_exit) == length(exit_routes) &&
    !anyDuplicated(source_routes_per_exit$source_uid) &&
    sum(exit_edges$n_source_routes) == length(exit_routes)
  difference <- length(land) - nrow(land_edges) - nrow(exit_edges)
  require_true(partition && allocation && (!applicable || difference == 0L), "Topology accounting failed.")
  accounting_qa <- empty(n_land_nodes = length(land), n_internal_land_edges = nrow(land_edges),
    n_other_internal_edges = nrow(edges) - nrow(land_edges), n_exit_events = nrow(exit_edges),
    n_exit_terminating_routes = length(exit_routes), n_nonexit_terminal_sources = nonexit_terminal,
    n_nonexit_routes = length(land) - length(exit_routes), n_minus_internal_edges = length(land) - nrow(land_edges),
    n_exit_difference = difference, direct_partition_ok = partition, route_allocation_ok = allocation,
    all_cells_valid_land = all_land, all_source_routes_exit = all_exit,
    n_minus_e_applicable = applicable, n_minus_e_check = if (applicable) "PASS" else "NOT_APPLICABLE")
  route_status_counts <- empty(route_status = statuses,
    n_routes = as.integer(table(factor(summaries$route_status, levels = statuses))))
  list(method_version = "land-network-inventories-v1", confluence_details = confluence_details,
    confluence_incoming = confluence_incoming, shared_segments = shared_segments,
    segment_cells = segment_cells, segment_edges = segment_edges, source_confluences = source_confluences,
    exit_edges = exit_edges, source_routes_per_exit = source_routes_per_exit,
    accounting_qa = accounting_qa, route_status_counts = route_status_counts,
    full_grid = full_grid, extra_raster_reads = 0L, extra_route_traces = 0L,
    accumulation = "NOT_COMPUTED", external_inflow = "UNKNOWN", upstream_coverage = "WINDOW_ONLY",
    hydrological_validation = "NOT_ASSESSED", channel_interpretation = "NOT_ASSESSED",
    MODERATE = "REVIEW_REQUIRED", NATIONAL = "LOCKED")
}
