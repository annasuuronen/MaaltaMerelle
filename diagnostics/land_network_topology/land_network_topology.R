# Base R research on an already-read window: no raster I/O or new D8 decoder.
# Source PR12 l1847_trace, PR16 first_water_contact and PR17 trace_land_d8_route.
build_land_d8_network <- function(pointer, water_class, valid, grid, provenance,
                                  lake_id = NULL, max_steps = 32L) {
  require_true <- function(ok, message) {
    if (!isTRUE(ok)) stop(message, call. = FALSE)
  }
  whole <- function(x, minimum = 0) {
    is.numeric(x) && length(x) == 1L && is.finite(x) &&
      x >= minimum && x <= .Machine$integer.max && x == floor(x)
  }
  text <- function(x) is.character(x) && length(x) == 1L &&
    !is.na(x) && nzchar(trimws(x))
  number <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)
  required_grid <- c("grid_id", "nrow", "ncol", "row_offset", "col_offset",
                     "xmin", "ymax", "resolution_m", "crs")
  require_true(is.list(grid) && !anyDuplicated(names(grid)) &&
                 all(required_grid %in% names(grid)), "Invalid grid fields.")
  require_true(text(grid$grid_id) && grepl("^[A-Za-z0-9_.-]+$", grid$grid_id) &&
                 whole(grid$nrow, 1) && whole(grid$ncol, 1) &&
                 as.double(grid$nrow) * grid$ncol <= 121 &&
                 whole(grid$row_offset) && whole(grid$col_offset) &&
                 as.double(grid$row_offset) + grid$nrow <= .Machine$integer.max &&
                 as.double(grid$col_offset) + grid$ncol <= .Machine$integer.max &&
                 number(grid$xmin) && number(grid$ymax) &&
                 number(grid$resolution_m) && grid$resolution_m == 2 &&
                 identical(grid$crs, "EPSG:3067"),
               "Expected a <=121-cell window on a declared 2 m EPSG:3067 grid.")
  require_true(whole(max_steps, 1) && max_steps <= 256,
               "Expected max_steps in 1..256.")
  fields <- c("run_id", "code_revision", "pointer_source", "water_source",
              "lake_id_source", "validity_source", "lake_id_namespace")
  require_true(is.list(provenance) && !anyDuplicated(names(provenance)) &&
                 all(fields %in% names(provenance)) &&
                 all(vapply(provenance[fields], text, logical(1))),
               "Missing or invalid declared provenance.")
  shape <- function(m) is.matrix(m) &&
    all(dim(m) == c(grid$nrow, grid$ncol))
  require_true(shape(pointer) && is.numeric(pointer) &&
                 shape(water_class) && is.numeric(water_class) &&
                 shape(valid) && is.logical(valid) && !anyNA(valid),
               "Expected matching numeric pointer/water matrices and logical valid without NA.")
  if (is.null(lake_id)) {
    lake_id <- matrix(NA_real_, nrow = grid$nrow, ncol = grid$ncol)
  }
  require_true(shape(lake_id) && is.numeric(lake_id),
               "lake_id must be a matching numeric matrix or NULL.")
  require_true(all(vapply(c("l1847_trace", "first_water_contact", "trace_land_d8_route"),
                          exists, logical(1), mode = "function")),
               "Source the reviewed LOW, contact and land-route functions first.")

  # R matrices are column-major; raster cells and the callback are row-major.
  flatten <- function(m) as.vector(t(m))
  n <- length(pointer)
  local <- seq_len(n)
  row <- grid$row_offset + (local - 1) %/% grid$ncol + 1
  col <- grid$col_offset + (local - 1) %% grid$ncol + 1
  v <- flatten(valid)
  w <- flatten(water_class)
  kind <- rep("INVALID_WATER_CLASS", n)
  kind[!v] <- "NO_DATA"
  kind[v & is.na(w)] <- "LAND"
  kind[v & !is.na(w) & w %in% c(1, 2, 3)] <- "WATER"
  cells <- data.frame(
    local_cell = local, cell_uid = paste(grid$grid_id, row, col, sep = ":"),
    global_row = row, global_col = col,
    x_m = grid$xmin + (col - 0.5) * grid$resolution_m,
    y_m = grid$ymax - (row - 0.5) * grid$resolution_m, crs = grid$crs,
    pointer = flatten(pointer), water_class = w, lake_id = flatten(lake_id),
    valid = v, cell_kind = kind,
    on_window_boundary = (local - 1) %/% grid$ncol %in% c(0, grid$nrow - 1) |
      (local - 1) %% grid$ncol %in% c(0, grid$ncol - 1),
    stringsAsFactors = FALSE
  )
  starts <- which(kind == "LAND")
  read <- function(cell) {
    r <- (cell - 1L) %/% grid$ncol + 1L
    c <- (cell - 1L) %% grid$ncol + 1L
    list(pointer = pointer[r, c], water_class = water_class[r, c],
         lake_id = lake_id[r, c], valid = valid[r, c])
  }
  # Exactly one existing trace per land start. Each source contributes ONLY
  # its first completed move to the graph; route suffixes are not unioned.
  routes <- lapply(starts, function(s)
    trace_land_d8_route(s, grid, read, max_steps, provenance))
  names(routes) <- cells$cell_uid[starts]
  edge_fields <- c("from_cell", "to_cell", "from_uid", "to_uid", "d8_code", "edge_kind")
  edges <- data.frame(from_cell = integer(), to_cell = integer(),
                      from_uid = character(), to_uid = character(),
                      d8_code = numeric(), edge_kind = character(), stringsAsFactors = FALSE)
  if (length(routes)) {
    edges <- do.call(rbind, lapply(routes, function(r) {
      r$transitions[seq_len(min(1L, nrow(r$transitions))), edge_fields, drop = FALSE]
    }))
  }
  row.names(edges) <- NULL
  edges$edge_id <- seq_len(nrow(edges))
  edges <- edges[, c("edge_id", edge_fields), drop = FALSE]
  land_edges <- edges[edges$edge_kind == "LAND_TO_LAND", , drop = FALSE]
  if (anyDuplicated(edges$from_cell) || anyNA(match(land_edges$to_cell, starts))) {
    stop("Graph edge identity or land target accounting failed.", call. = FALSE)
  }
  route_summary <- data.frame(
    source_cell = starts, source_uid = cells$cell_uid[starts],
    route_status = vapply(routes, function(r) r$route_status, character(1)),
    terminal_cell = vapply(routes, function(r) r$terminal$local_cell, numeric(1)),
    n_transitions = vapply(routes, function(r) r$n_transitions, numeric(1)),
    n_land_edges = vapply(routes, function(r) nrow(r$land_edges), numeric(1)),
    n_cell_reads = vapply(routes, function(r) r$n_cell_reads, numeric(1)),
    water_class = vapply(routes, function(r) r$contact$water_class, numeric(1)),
    lake_objectid = vapply(routes, function(r) r$contact$lake_objectid, numeric(1)),
    stringsAsFactors = FALSE, row.names = NULL
  )
  land_nodes <- cells[starts, , drop = FALSE]
  land_nodes$land_indegree_in_window <- tabulate(match(land_edges$to_cell, starts),
                                                nbins = length(starts))
  # A->B with B's zero pointer is A's LAND_TO_LAND edge, not A's own zero.
  land_nodes$outgoing_kind <- vapply(routes, function(r) {
    if (nrow(r$transitions)) r$transitions$edge_kind[1L] else r$route_status
  }, character(1))
  land_nodes$outgoing_to_cell <- vapply(routes, function(r) {
    if (nrow(r$transitions)) r$transitions$to_cell[1L] else NA_real_
  }, numeric(1))
  land_nodes$outgoing_to_uid <- vapply(routes, function(r) {
    if (nrow(r$transitions)) r$transitions$to_uid[1L] else NA_character_
  }, character(1))
  land_nodes$route_status <- route_summary$route_status
  land_nodes$is_confluence <- land_nodes$land_indegree_in_window >= 2L
  max_transitions <- length(starts) * as.double(max_steps)
  max_reads <- length(starts) * (as.double(max_steps) + 1)
  require_true(sum(route_summary$n_transitions) <= max_transitions &&
                 sum(route_summary$n_cell_reads) <= max_reads,
               "In-memory route work exceeded the declared bound.")
  list(
    method_version = "land-network-topology-v1", cells = cells,
    land_nodes = land_nodes, edges = edges, land_edges = land_edges,
    confluences = land_nodes[land_nodes$is_confluence, , drop = FALSE],
    routes = routes, route_summary = route_summary,
    work_budget = list(max_cells = 121L, max_steps = as.integer(max_steps),
      n_land_starts = length(starts), max_transitions = max_transitions,
      max_cell_reads = max_reads, n_transitions = sum(route_summary$n_transitions),
      n_cell_reads = sum(route_summary$n_cell_reads)),
    external_inflow = "UNKNOWN", upstream_coverage = "WINDOW_ONLY",
    accumulation = "NOT_COMPUTED", grid = grid, provenance = provenance,
    provenance_verification = "DECLARED_ONLY",
    hydrological_validation = "NOT_ASSESSED", channel_interpretation = "NOT_ASSESSED",
    MODERATE = "REVIEW_REQUIRED", NATIONAL = "LOCKED"
  )
}

# Fixed categories, fixed numeric global-cell ordering. Never rank by route
# length or water success. A missing category is local/budget-limited evidence.
select_land_network_cases <- function(network) {
  if (!is.list(network) || !identical(network$method_version, "land-network-topology-v1") ||
      !is.data.frame(network$land_nodes) || !is.data.frame(network$route_summary)) {
    stop("Expected a matching land-network-topology-v1 result.", call. = FALSE)
  }
  nodes <- network$land_nodes
  r <- network$route_summary
  required_nodes <- c("local_cell", "cell_uid", "global_row", "global_col",
                       "land_indegree_in_window")
  required_routes <- c("source_uid", "route_status", "n_land_edges")
  n <- nrow(nodes)
  numeric_column <- function(x, minimum) is.numeric(x) && length(x) == n &&
    all(is.finite(x) & x >= minimum & x == floor(x))
  text_column <- function(x) is.character(x) && length(x) == n &&
    !anyNA(x) && all(nzchar(trimws(x)))
  if (n > 121L || nrow(r) != n || anyDuplicated(names(nodes)) ||
      anyDuplicated(names(r)) || !all(required_nodes %in% names(nodes)) ||
      !all(required_routes %in% names(r)) ||
      !numeric_column(nodes$local_cell, 1) || anyDuplicated(nodes$local_cell) ||
      !numeric_column(nodes$global_row, 1) || !numeric_column(nodes$global_col, 1) ||
      !numeric_column(nodes$land_indegree_in_window, 0) ||
      !numeric_column(r$n_land_edges, 0) || !text_column(nodes$cell_uid) ||
      anyDuplicated(nodes$cell_uid) || !text_column(r$source_uid) ||
      !identical(nodes$cell_uid, r$source_uid) || !text_column(r$route_status) ||
      !all(r$route_status %in% c("D8_ZERO", "POINTER_NA", "INVALID_POINTER",
        "NO_DATA", "INVALID_WATER_CLASS", "CYCLE", "DOMAIN_EXIT_UNRESOLVED",
        "STEP_LIMIT", "FIRST_WATER_CONTACT"))) {
    stop("Invalid or mismatched network selection tables.", call. = FALSE)
  }
  candidates <- list(
    CONFLUENCE = which(nodes$land_indegree_in_window >= 2L),
    LAND_CHAIN = which(r$n_land_edges >= 2L),
    ZERO_CHAIN = which(r$n_land_edges >= 1L & r$route_status == "D8_ZERO"),
    BOUNDARY_CHAIN = which(r$n_land_edges >= 1L & r$route_status == "DOMAIN_EXIT_UNRESOLVED")
  )
  cases <- data.frame(category = names(candidates), status = "NOT_OBSERVED",
                       source_cell = NA_integer_, source_uid = NA_character_,
                       route_status = NA_character_,
                       n_matches = vapply(candidates, length, numeric(1)),
                       stringsAsFactors = FALSE, row.names = NULL)
  for (i in seq_along(candidates)) {
    ids <- candidates[[i]]
    if (!length(ids)) next
    k <- ids[order(nodes$global_row[ids], nodes$global_col[ids])[1L]]
    cases$status[i] <- "SELECTED"
    cases$source_cell[i] <- nodes$local_cell[k]
    cases$source_uid[i] <- nodes$cell_uid[k]
    cases$route_status[i] <- r$route_status[k]
  }
  cases
}
