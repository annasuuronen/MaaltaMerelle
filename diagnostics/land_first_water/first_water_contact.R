# Bounded synthetic prototype. Requires the unchanged LOW l1847_trace() core.
# No raster I/O, pointer changes, outlet selection or hydrological approval.
first_water_contact <- function(start, grid, read_cell, max_steps = 128L,
                                provenance) {
  require_true <- function(ok, message) {
    if (!isTRUE(ok)) stop(message, call. = FALSE)
  }
  whole <- function(x, minimum = 0, maximum = .Machine$integer.max) {
    is.numeric(x) && length(x) == 1L && is.finite(x) &&
      x >= minimum && x <= maximum && x == floor(x)
  }
  scalar_number <- function(x) is.numeric(x) && length(x) == 1L
  scalar_text <- function(x) is.character(x) && length(x) == 1L &&
    !is.na(x) && nzchar(trimws(x))
  require_true(exists("l1847_trace", mode = "function"),
               "Source the reviewed LOW l1847_trace core first.")
  required_grid <- c("grid_id", "nrow", "ncol", "row_offset", "col_offset",
                     "xmin", "ymax", "resolution_m", "crs")
  require_true(is.list(grid) && !anyDuplicated(names(grid)) &&
                 all(required_grid %in% names(grid)), "Invalid grid fields.")
  require_true(scalar_text(grid$grid_id) &&
                 grepl("^[A-Za-z0-9_.-]+$", grid$grid_id), "Invalid grid_id.")
  require_true(whole(grid$nrow, 1) && whole(grid$ncol, 1) &&
                 grid$nrow * grid$ncol <= .Machine$integer.max &&
                 whole(grid$row_offset) && whole(grid$col_offset) &&
                 grid$row_offset + grid$nrow <= .Machine$integer.max &&
                 grid$col_offset + grid$ncol <= .Machine$integer.max,
               "Invalid grid dimensions or offsets.")
  require_true(scalar_number(grid$xmin) && is.finite(grid$xmin) &&
                 scalar_number(grid$ymax) && is.finite(grid$ymax) &&
                 scalar_number(grid$resolution_m) && grid$resolution_m == 2 &&
                 identical(grid$crs, "EPSG:3067"),
               "Expected finite global origin, 2 m cells and EPSG:3067.")
  require_true(whole(start, 1, grid$nrow * grid$ncol), "Invalid land start cell.")
  require_true(whole(max_steps, 1, 256), "Expected max_steps in 1..256.")
  require_true(is.function(read_cell), "read_cell must be a function.")
  required_provenance <- c("run_id", "code_revision", "pointer_source", "water_source",
                           "lake_id_source", "validity_source", "lake_id_namespace")
  require_true(is.list(provenance) && !anyDuplicated(names(provenance)) &&
                 all(required_provenance %in% names(provenance)) &&
                 all(vapply(provenance[required_provenance], scalar_text, logical(1))),
               "Missing or invalid declared provenance.")

  cell_ref <- function(cell) {
    row <- grid$row_offset + (cell - 1) %/% grid$ncol + 1
    col <- grid$col_offset + (cell - 1) %% grid$ncol + 1
    list(local_cell = as.integer(cell),
         cell_uid = paste(grid$grid_id, row, col, sep = ":"),
         global_row = row, global_col = col,
         x_m = grid$xmin + (col - 0.5) * grid$resolution_m,
         y_m = grid$ymax - (row - 0.5) * grid$resolution_m, crs = grid$crs)
  }
  reads <- 0L
  source_observation <- NULL
  first_successor <- last_land_seen <- NULL
  contact <- NULL
  # These conditions stop the SAME trace before an unusable cell can be routed.
  # No artificial pointer or second independent traversal is substituted.
  halt <- function(status, cell) {
    stop(structure(list(message = status, call = NULL, status = status,
                        cell = cell, steps = reads - 1L),
                   class = c("first_water_halt", "error", "condition")))
  }
  observe <- function(cell) {
    reads <<- reads + 1L
    a <- read_cell(cell)
    require_true(is.list(a) && !anyDuplicated(names(a)) &&
                   all(c("pointer", "water_class", "lake_id", "valid") %in% names(a)) &&
                   scalar_number(a$pointer) && scalar_number(a$water_class) &&
                   scalar_number(a$lake_id) && is.logical(a$valid) &&
                   length(a$valid) == 1L && !is.na(a$valid),
                 "Invalid cell observation.")
    if (reads == 1L) source_observation <<- a
    if (reads == 2L) first_successor <<- cell_ref(cell)
    if (!a$valid) halt("NO_DATA", cell)
    if (!is.na(a$water_class) &&
        (!is.finite(a$water_class) || !a$water_class %in% c(1, 2, 3))) {
      halt("INVALID_WATER_CLASS", cell)
    }
    if (reads == 1L) {
      require_true(is.na(a$water_class), "Start must be a valid land cell, not water.")
    }
    if (is.na(a$water_class)) {
      last_land_seen <<- cell_ref(cell)
    } else {
      contact <<- a
    }
    a
  }
  stopped_by_adapter <- FALSE
  raw <- tryCatch(
    l1847_trace(start, grid$nrow, grid$ncol, observe, max_steps),
    first_water_halt = function(e) {
      stopped_by_adapter <<- TRUE
      list(status = e$status, cell = e$cell, steps = e$steps)
    }
  )
  reached <- identical(raw$status, "REACHES_WATER_CLASS")
  route_status <- switch(raw$status,
                         REACHES_WATER_CLASS = "FIRST_WATER_CONTACT",
                         MAX_STEPS = "STEP_LIMIT",
                         DOMAIN_EXIT = "DOMAIN_EXIT_UNRESOLVED", raw$status)
  water_class <- if (reached) as.integer(contact$water_class) else NA_integer_
  observed_lake_id <- if (reached) contact$lake_id else NA_real_
  lake_id_valid <- reached && water_class == 1L && whole(observed_lake_id, 1)
  reasons <- character()
  if (!reached) reasons <- route_status
  if (reached && water_class == 1L && !lake_id_valid) {
    reasons <- if (is.na(observed_lake_id)) "LAKE_ID_MISSING" else "INVALID_LAKE_ID"
  }
  if (reached && water_class != 1L) reasons <- "RIVER_FEATURE_ID_UNAVAILABLE"

  list(method_version = "land-first-water-prototype-v1",
       source = cell_ref(start), source_valid = source_observation$valid,
       source_water_class = source_observation$water_class,
       source_pointer = source_observation$pointer,
       first_successor = first_successor, terminal = cell_ref(raw$cell),
       route_status = route_status,
       raw_trace_status = if (stopped_by_adapter) NA_character_ else raw$status,
       n_transitions = as.integer(raw$steps), n_cell_reads = reads,
       max_steps = as.integer(max_steps),
       visit_cap_reached = identical(raw$status, "MAX_STEPS"),
       last_land = if (reached) last_land_seen else NULL,
       first_water = if (reached) cell_ref(raw$cell) else NULL,
       water_class = water_class, observed_lake_id = observed_lake_id,
       lake_objectid = if (lake_id_valid) as.integer(observed_lake_id) else NA_integer_,
       recipient_id = if (lake_id_valid) as.character(as.integer(observed_lake_id)) else NA_character_,
       recipient_namespace = if (lake_id_valid) provenance$lake_id_namespace else NA_character_,
       water_reached = reached, recipient_identified = lake_id_valid,
       hydrological_validation = "NOT_ASSESSED", uncertainty_reasons = reasons,
       grid = grid, provenance = provenance, provenance_verification = "DECLARED_ONLY",
       MODERATE = "REVIEW_REQUIRED", NATIONAL = "LOCKED")
}
