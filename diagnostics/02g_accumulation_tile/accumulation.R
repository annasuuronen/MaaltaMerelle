# Bounded in-memory research only. No raster I/O, new D8 decoder or outlets.
g02_assert <- function(ok, message) if (!isTRUE(ok)) stop(message, call. = FALSE)
g02_grid <- function(g) {
  g02_assert(is.list(g) && identical(g$crs, "EPSG:3067") && isTRUE(g$resolution_m == 2) &&
    all(vapply(g[c("nrow", "ncol", "row_offset", "col_offset")], function(x)
      is.numeric(x) && length(x) == 1L && is.finite(x) && x == floor(x) && x >= 0, logical(1))) &&
    g$nrow >= 1 && g$ncol >= 1 && g$nrow * g$ncol <= 1000,
    "Expected a <=1000-cell synthetic 2 m EPSG:3067 grid")
  g
}
g02_uid <- function(cell, g) { if (!length(cell)) return(character()); paste(g$grid_id, g$row_offset + (cell - 1L) %/% g$ncol + 1L,
  g$col_offset + (cell - 1L) %% g$ncol + 1L, sep = ":") }
g02_cells <- function(cells, g) {
  g02_grid(g)
  g02_assert(is.data.frame(cells) && all(c("cell", "pointer", "water_class", "lake_id", "valid") %in% names(cells)) &&
    !anyDuplicated(cells$cell) && all(is.finite(cells$cell) & cells$cell == floor(cells$cell) &
      cells$cell >= 1 & cells$cell <= g$nrow * g$ncol) && is.logical(cells$valid) && !anyNA(cells$valid) &&
    all(vapply(cells[c("pointer", "water_class", "lake_id")], is.numeric, logical(1))), "Invalid cell observations")
  cells <- cells[order(cells$cell), c("cell", "pointer", "water_class", "lake_id", "valid"), drop = FALSE]
  row.names(cells) <- NULL
  cells$cell_uid <- g02_uid(cells$cell, g)
  cells$kind <- ifelse(!cells$valid, "NO_DATA", ifelse(is.na(cells$water_class), "LAND",
    ifelse(cells$water_class %in% 1:3, "WATER", "INVALID_WATER_CLASS")))
  cells
}
g02_bind <- function(rows, empty) {
  if (!length(rows)) return(empty)
  x <- do.call(rbind, rows); row.names(x) <- NULL; x
}
# New observations on a declared synthetic graph. Budget applies to the entire
# source path, including all tile crossings; it is never reset at a tile edge.
g02_observe <- function(cells, grid, provenance, max_steps = 32L) {
  g02_assert(isTRUE(provenance$synthetic), "Synthetic provenance required")
  cells <- g02_cells(cells, grid)
  g02_assert(exists("trace_land_d8_route", mode = "function"), "Source the reviewed route core")
  index <- integer(grid$nrow * grid$ncol); index[cells$cell] <- seq_len(nrow(cells))
  read <- function(cell) {
    i <- index[cell]
    if (!i) return(list(pointer = NA_real_, water_class = NA_real_, lake_id = NA_real_, valid = FALSE))
    list(pointer = cells$pointer[i], water_class = cells$water_class[i], lake_id = cells$lake_id[i], valid = cells$valid[i])
  }
  land <- cells$cell[cells$kind == "LAND"]
  routes <- lapply(land, function(s) trace_land_d8_route(s, grid, read, max_steps, provenance))
  names(routes) <- g02_uid(land, grid)
  list(cells = cells, routes = routes, grid = grid, provenance = provenance)
}
# Compatibility entry: use already-stored source observations, never extend a
# censored route by walking the union of other sources' canonical edges.
g02_from_network <- function(network, provenance, external_import = "UNKNOWN") {
  c <- network$cells
  cells <- data.frame(cell = c$local_cell, pointer = c$pointer, water_class = c$water_class,
    lake_id = c$lake_id, valid = c$valid)
  g02_accumulate(cells, network$routes, network$grid, provenance, external_import = external_import)
}
g02_accumulate <- function(cells, routes, grid, provenance, owners = NULL,
                           expected_owners = NULL, external_import = "UNKNOWN") {
  cells <- g02_cells(cells, grid)
  g02_assert(isTRUE(provenance$synthetic) && external_import %in% c("UNKNOWN", "KNOWN_ZERO_SYNTHETIC"), "Invalid synthetic/external contract")
  if (external_import == "KNOWN_ZERO_SYNTHETIC") g02_assert(nrow(cells) == grid$nrow * grid$ncol,
    "Known-zero synthetic boundary needs complete declared domain")
  land <- which(cells$kind == "LAND"); sources <- cells$cell_uid[land]
  g02_assert(is.list(routes) && ((length(routes) == 0L && length(sources) == 0L) || identical(names(routes), sources)), "One ordered route per owned land source required")
  if (is.null(owners)) owners <- setNames(rep("MONOLITH", nrow(cells)), cells$cell_uid)
  g02_assert(identical(names(owners), cells$cell_uid) && !anyNA(owners) && all(nzchar(owners)), "Invalid core ownership")
  sets <- setNames(rep(list(character()), nrow(cells)), cells$cell_uid)
  water_sets <- sets[cells$kind == "WATER"]; cycle_cells <- character(); ledger <- list(); moves <- list()
  for (i in seq_along(routes)) {
    r <- routes[[i]]; s <- sources[i]
    g02_assert(is.list(r) && identical(r$source$cell_uid, s) &&
      nrow(r$path) == r$n_transitions + 1L && r$n_transitions <= r$contact$max_steps &&
      !anyDuplicated(r$observations$cell_uid), "Malformed source trace")
    g02_assert(identical(r$grid, grid) &&
      identical(r$path$cell_uid, g02_uid(r$path$local_cell, grid)) &&
      identical(r$transitions$from_uid, head(r$path$cell_uid, -1L)) &&
      identical(r$transitions$to_uid, tail(r$path$cell_uid, -1L)), "Trace identity disagreement")
    at <- match(r$observations$cell_uid, cells$cell_uid); known <- which(!is.na(at))
    for (field in c("pointer", "water_class", "lake_id", "valid"))
      g02_assert(identical(as.numeric(r$observations[[field]][known]), as.numeric(cells[[field]][at[known]])),
        "Trace values disagree with input observations")
    seen_land <- unique(r$path$cell_uid[r$path$cell_kind == "LAND"])
    g02_assert(all(seen_land %in% cells$cell_uid[cells$kind == "LAND"]), "Unowned land contribution")
    for (v in seen_land) sets[[v]] <- c(sets[[v]], s)
    status <- r$route_status; terminal <- r$terminal$cell_uid
    if (!terminal %in% cells$cell_uid) status <- "MISSING_NEIGHBOUR_TILE"
    if (r$route_status == "CYCLE") {
      first <- match(terminal, r$path$cell_uid)
      cycle_cells <- union(cycle_cells, r$path$cell_uid[first:nrow(r$path)])
    }
    first_water <- if (r$route_status == "FIRST_WATER_CONTACT") r$first_water$cell_uid else NA_character_
    if (!is.na(first_water)) {
      g02_assert(first_water %in% names(water_sets), "Unowned first water contact")
      water_sets[[first_water]] <- c(water_sets[[first_water]], s)
    }
    ledger[[i]] <- data.frame(source_uid = s, owner_tile = unname(owners[s]), endpoint_type = status,
      terminal_uid = terminal, first_water_uid = first_water,
      water_class = r$contact$water_class, lake_objectid = r$contact$lake_objectid,
      source_area_m2 = 4, hydrological_validation = "NOT_ASSESSED")
    if (nrow(r$transitions)) {
      t <- r$transitions
      moves[[i]] <- data.frame(source_uid = s, from_uid = t$from_uid, to_uid = t$to_uid,
        d8_code = t$d8_code, stringsAsFactors = FALSE)
    }
  }
  sets <- lapply(sets, unique); water_sets <- lapply(water_sets, unique)
  ledger <- g02_bind(ledger, data.frame(source_uid = character(), owner_tile = character(), endpoint_type = character(),
    terminal_uid = character(), first_water_uid = character(), water_class = numeric(), lake_objectid = numeric(),
    source_area_m2 = numeric(), hydrological_validation = character()))
  moves <- g02_bind(moves, data.frame(source_uid = character(), from_uid = character(), to_uid = character(), d8_code = numeric()))
  canonical <- unique(moves[, c("from_uid", "to_uid", "d8_code")])
  g02_assert(!anyDuplicated(canonical$from_uid), "More than one outgoing D8 edge")
  for (j in seq_len(nrow(canonical))) {
    from <- match(canonical$from_uid[j], cells$cell_uid)
    target <- match(canonical$to_uid[j], g02_uid(seq_len(grid$nrow * grid$ncol), grid))
    code <- canonical$d8_code[j]
    g02_assert(!is.na(from) && cells$kind[from] == "LAND" && !is.na(target) &&
      isTRUE(code == cells$pointer[from]), "Unobserved canonical pointer")
    # Geometric QA only, on virtual values; does not resume any source trace.
    probe <- l1847_trace(cells$cell[from], grid$nrow, grid$ncol,
      function(cell) list(pointer = if (cell == cells$cell[from]) code else 0,
        water_class = NA_real_, lake_id = NA_real_), 1L)
    g02_assert(probe$cell == target, "Canonical edge disagrees with reviewed D8 direction")
  }
  partial <- any(ledger$endpoint_type %in% c("STEP_LIMIT", "CYCLE", "MISSING_NEIGHBOUR_TILE"))
  missing <- !is.null(expected_owners) && any(!names(expected_owners) %in% cells$cell_uid)
  counts <- vapply(sets[land], length, integer(1))
  undefined <- sources %in% cycle_cells
  local <- as.numeric(counts); local[undefined] <- NA_real_
  unresolved <- any(ledger$endpoint_type != "FIRST_WATER_CONTACT")
  coverage <- if (partial || missing) "PARTIAL_OBSERVATION" else if (unresolved) "LOCAL_GRAPH_ONLY_UNRESOLVED_TERMINALS" else "COMPLETE_DECLARED_LOCAL_DOMAIN"
  nodes <- data.frame(cell_uid = sources, owner_tile = unname(owners[sources]),
    observed_source_count = counts, local_upstream_cells = local, local_upstream_area_m2 = 4 * local,
    external_import = rep(external_import, length(sources)), total_upstream_cells = if (external_import == "UNKNOWN" || partial || missing) rep(NA_real_, length(sources)) else local,
    coverage_status = ifelse(undefined, "UNDEFINED_CYCLE", coverage),
    endpoint_type = ledger$endpoint_type, first_water_uid = ledger$first_water_uid,
    uncertainty = rep(if (partial || missing) "CENSORED_OR_UNRESOLVED_GRAPH" else if (unresolved) "DOWNSTREAM_TERMINALS_UNRESOLVED" else if (external_import == "UNKNOWN") "EXTERNAL_IMPORT_UNKNOWN" else "SYNTHETIC_DOMAIN_ONLY", length(sources)),
    independent_feature_id = rep(NA_character_, length(sources)), independent_dataset_version = rep(NA_character_, length(sources)),
    independent_evidence_provider = rep(NA_character_, length(sources)), independent_evidence_grade = rep("NOT_ASSESSED", length(sources)), row.names = NULL)
  water <- data.frame(cell_uid = names(water_sets), local_source_cells = vapply(water_sets, length, integer(1)),
    external_import = rep(external_import, length(water_sets)), coverage_status = rep(coverage, length(water_sets)), row.names = NULL)
  wi <- match(water$cell_uid, cells$cell_uid)
  water$water_class <- cells$water_class[wi]
  lake <- cells$lake_id[wi]
  water$lake_objectid <- ifelse(water$water_class == 1 & is.finite(lake) & lake > 0 & lake == floor(lake), lake, NA_real_)
  water$local_source_area_m2 <- 4 * water$local_source_cells
  water$total_source_cells <- if (external_import == "UNKNOWN" || partial || missing) rep(NA_real_, nrow(water)) else water$local_source_cells
  g02_assert(!anyDuplicated(ledger$source_uid) && nrow(ledger) == length(sources), "Source balance duplicates/loss")
  reached <- sum(ledger$endpoint_type == "FIRST_WATER_CONTACT")
  g02_assert(sum(water$local_source_cells) == reached, "Water source balance failed")
  # Check A=1+sum(A(parent)) only when every local source trace is complete and
  # acyclic. Unknown external import is not included in this LOCAL equation.
  recurrence <- "NOT_APPLICABLE"
  if (!partial && !missing && length(sources) > 0L) {
    first_edges <- unique(moves[, c("from_uid", "to_uid")])
    for (v in sources) {
      parents <- first_edges$from_uid[first_edges$to_uid == v & first_edges$from_uid %in% sources]
      g02_assert(nodes$local_upstream_cells[match(v, sources)] == 1 +
        sum(nodes$local_upstream_cells[match(parents, sources)]), "Local recurrence failed")
    }
    recurrence <- "PASS"
  }
  list(method_version = "02g-observed-accumulation-research-v1", nodes = nodes, water = water,
    source_sets = sets[land], water_source_sets = water_sets, source_ledger = ledger, observed_moves = moves,
    cycle_cells = cycle_cells, balance = data.frame(n_sources = length(sources), n_first_water = reached,
      n_unresolved = length(sources) - reached, n_approved_exports = 0L,
      area_m2 = 4 * length(sources), local_recurrence = recurrence),
    provenance = provenance, trace_provenance = lapply(routes, function(r) r$provenance), grid = grid, coverage_status = coverage,
    channel_threshold_cells = 10000L, channel_threshold_area_m2 = 40000,
    hydrological_validation = "NOT_ASSESSED", channel_interpretation = "NOT_ASSESSED",
    MODERATE = "REVIEW_REQUIRED", NATIONAL = "LOCKED")
}
