# Bounded Base R observation of the existing LAND_WATER Whitebox-D8 route.
# Source l1847_trace() and first_water_contact() first; both remain unchanged.
# Branch dependency: PR12 cd9612a -> PR16 24b81af (direct base), then this work.
# A review PR belongs on codex/land-first-water-prototype, not baseline.
# Research plan: PR15 053df7c. No raster I/O, new D8, accumulation or ditch claim.
#
# Input grid, read_cell and declared provenance have the PR16 contract:
# 1-based row-major local cells; 2 m EPSG:3067; global grid origin + offsets;
# read_cell returns numeric pointer/water_class/lake_id and logical valid.
# Missing water_class means land only when valid=TRUE; validity is separate.
#
# A single call of first_water_contact() drives all reads. Observations are
# unique reads; path includes the cycle-closing revisit without another read.
# transitions includes every completed in-grid move, including into NoData;
# land_edges includes ONLY valid land-to-land moves. pointer_followed marks
# actual moves, not a terminal pointer merely inspected at the work limit.
# last_valid_land is the last reached land in path (cycle terminal included);
# last_observed_valid_land is the last newly read land (closing-edge source).
# Existing contact$last_land keeps its contact-only PR16 meaning.
# STEP_LIMIT and DOMAIN_EXIT_UNRESOLVED leave continuation unresolved; neither
# proves a physical break. D8_ZERO and cycles are computational observations.
# Declared provenance is not verified raster identity or hydrological approval.
#
# Next real LOW experiment: PROPOSAL ONLY, no data reader implemented here.
# Verify the existing 02B CSV, input identities and actual raster headers first.
# The checked Git trees contain the CSV writer/docs, not an observed 02B table.
# Select one real row in ascending (water_class, receiver_cell, source_cell,
# d8_code, record) order whose source is >=5 cells from every raster edge.
# A source-centred 9x9 core plus one-cell halo is exactly 11x11=121 positions.
# A separately approved read would sample pointer, water_class, lake_id and
# LAND_WATER at these positions only: <=484 scalar values, no whole-file scan.
# Validity: in-grid and finite LAND_WATER, separately from water_class NA.
# Within <=81 core nodes, reverse EXISTING D8 land edges to the 02B source.
# Select one upstream source at greatest reverse distance <=31 (tie: smallest
# full-raster cell ID); max_steps=32 includes the final source-to-water edge.
# No upstream source: report absence in this window; do not enlarge/replace it.
# Halo inflow/core-edge reach means censored local coverage, not a catchment.
# CSV supplies expectations only; callbacks must use real raster observations.
# The prepared DEM already exists (MML KM2 + SYKE corrections); neither its
# reconstruction nor the original sparse SYKE raster is needed for this test.
# No actual LOW row, window or raster was read/selected by this prototype.
trace_land_d8_route <- function(start, grid, read_cell, max_steps = 128L,
                               provenance) {
  if (!exists("first_water_contact", mode = "function")) {
    stop("Source the reviewed first_water_contact adapter first.", call. = FALSE)
  }
  if (!is.function(read_cell)) stop("read_cell must be a function.", call. = FALSE)
  cells <- integer()
  values <- list()
  record <- function(cell) {
    a <- read_cell(cell)
    cells <<- c(cells, cell)
    values[[length(cells)]] <<- a
    a
  }
  contact <- first_water_contact(start, grid, record, max_steps, provenance)
  # No new traversal or decoder: annotate only the observations already made.
  rows <- grid$row_offset + (cells - 1) %/% grid$ncol + 1
  cols <- grid$col_offset + (cells - 1) %% grid$ncol + 1
  kind <- vapply(values, function(a) {
    if (!a$valid) return("NO_DATA")
    if (is.na(a$water_class)) return("LAND")
    if (a$water_class %in% c(1, 2, 3)) return("WATER")
    "INVALID_WATER_CLASS"
  }, character(1))
  observations <- data.frame(
    read_order = seq_along(cells), local_cell = as.integer(cells),
    cell_uid = paste(grid$grid_id, rows, cols, sep = ":"),
    global_row = rows, global_col = cols,
    x_m = grid$xmin + (cols - 0.5) * grid$resolution_m,
    y_m = grid$ymax - (rows - 0.5) * grid$resolution_m, crs = grid$crs,
    pointer = vapply(values, function(a) a$pointer, numeric(1)),
    valid = vapply(values, function(a) a$valid, logical(1)),
    water_class = vapply(values, function(a) a$water_class, numeric(1)),
    lake_id = vapply(values, function(a) a$lake_id, numeric(1)),
    cell_kind = kind, stringsAsFactors = FALSE
  )
  index <- seq_along(cells)
  if (identical(contact$route_status, "CYCLE")) {
    index <- c(index, match(contact$terminal$local_cell, cells))
  }
  refs <- c("local_cell", "cell_uid", "global_row", "global_col", "x_m", "y_m", "crs")
  path <- observations[index, c(refs, "cell_kind"), drop = FALSE]
  row.names(path) <- NULL
  path <- data.frame(step = seq_along(index) - 1L, observation_index = index,
                     path, revisited = duplicated(index), stringsAsFactors = FALSE)
  from <- head(index, -1L)
  to <- tail(index, -1L)
  transitions <- data.frame(
    step = seq_along(from), from_cell = cells[from], to_cell = cells[to],
    from_uid = observations$cell_uid[from], to_uid = observations$cell_uid[to],
    d8_code = observations$pointer[from],
    edge_kind = if (length(to)) paste0("LAND_TO_", kind[to]) else character(),
    closes_cycle = path$revisited[-1L], stringsAsFactors = FALSE
  )
  if (anyNA(index) || anyDuplicated(cells) ||
      nrow(observations) != contact$n_cell_reads ||
      nrow(path) != contact$n_transitions + 1L ||
      nrow(transitions) != contact$n_transitions ||
      tail(path$local_cell, 1L) != contact$terminal$local_cell ||
      any(kind[from] != "LAND")) {
    stop("Route observation accounting disagrees with the reviewed trace.", call. = FALSE)
  }
  observations$pointer_followed <- seq_along(cells) %in% from
  last_ref <- function(indices) {
    if (!length(indices)) return(NULL)
    as.list(observations[tail(indices, 1L), refs, drop = FALSE])
  }
  list(
    method_version = "land-d8-continuity-prototype-v1",
    source = contact$source, terminal = contact$terminal,
    observations = observations, path = path, transitions = transitions,
    land_edges = transitions[transitions$edge_kind == "LAND_TO_LAND", , drop = FALSE],
    last_valid_land = last_ref(index[kind[index] == "LAND"]),
    last_observed_valid_land = last_ref(which(kind == "LAND")),
    first_water = contact$first_water, route_status = contact$route_status,
    n_transitions = contact$n_transitions, n_cell_reads = contact$n_cell_reads,
    continuation_unresolved = !contact$water_reached, contact = contact,
    grid = contact$grid, provenance = contact$provenance,
    provenance_verification = "DECLARED_ONLY",
    channel_interpretation = "NOT_ASSESSED", hydrological_validation = "NOT_ASSESSED",
    MODERATE = "REVIEW_REQUIRED", NATIONAL = "LOCKED"
  )
}
