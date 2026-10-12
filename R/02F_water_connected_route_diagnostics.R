# 02F - trace candidate spill receivers through the existing land-water D8.
# Diagnostic only: does not modify elevations, pointers, or outlet assignments.

trace_water_connected_candidate_routes <- function(
  candidate_edges,
  ptr_land_water,
  water_class,
  lake_id,
  nrow_raster,
  ncol_raster,
  cell_values,
  max_steps
) {
  required <- c(
    "spill_group_id",
    "lake_objectid",
    "source_cell",
    "receiver_cell"
  )
  missing <- setdiff(required, names(candidate_edges))
  if (length(missing)) {
    stop("02F candidate edges missing columns: ", paste(missing, collapse = ", "))
  }
  if (!is.function(cell_values)) stop("02F cell_values must be a function.")
  if (length(max_steps) != 1L || !is.numeric(max_steps) ||
      is.na(max_steps) || !is.finite(max_steps) ||
      max_steps < 1L || max_steps != as.integer(max_steps)) {
    stop("02F max_steps must be a positive integer.")
  }
  if (length(nrow_raster) != 1L || !is.numeric(nrow_raster) ||
      is.na(nrow_raster) || !is.finite(nrow_raster) ||
      nrow_raster < 1L || nrow_raster != as.integer(nrow_raster) ||
      length(ncol_raster) != 1L || !is.numeric(ncol_raster) ||
      is.na(ncol_raster) || !is.finite(ncol_raster) ||
      ncol_raster < 1L || ncol_raster != as.integer(ncol_raster)) {
    stop("02F raster dimensions must be positive integers.")
  }
  if (nrow(candidate_edges) &&
      (!is.numeric(candidate_edges$spill_group_id) ||
       !is.numeric(candidate_edges$lake_objectid) ||
       !is.numeric(candidate_edges$source_cell) ||
       !is.numeric(candidate_edges$receiver_cell) ||
       anyNA(candidate_edges$spill_group_id) ||
       anyNA(candidate_edges$lake_objectid) ||
       anyNA(candidate_edges$source_cell) ||
       anyNA(candidate_edges$receiver_cell) ||
       any(!is.finite(candidate_edges$spill_group_id)) ||
       any(!is.finite(candidate_edges$lake_objectid)) ||
       any(!is.finite(candidate_edges$source_cell)) ||
       any(!is.finite(candidate_edges$receiver_cell)) ||
       any(candidate_edges$spill_group_id != as.integer(candidate_edges$spill_group_id)) ||
       any(candidate_edges$lake_objectid != as.integer(candidate_edges$lake_objectid)) ||
       any(candidate_edges$source_cell < 1) ||
       any(candidate_edges$receiver_cell < 1) ||
       any(candidate_edges$source_cell != as.integer(candidate_edges$source_cell)) ||
       any(candidate_edges$receiver_cell != as.integer(candidate_edges$receiver_cell)))) {
    stop("02F candidate edge IDs and raster cells must be non-missing integers.")
  }

  empty_routes <- data.frame(
    route_id = integer(0),
    start_receiver_cell = integer(0),
    origin_lake_objectid = integer(0),
    terminal_cell = integer(0),
    terminal_water_class = integer(0),
    terminal_lake_objectid = integer(0),
    route_steps = integer(0),
    route_status = character(0),
    stringsAsFactors = FALSE
  )
  if (!nrow(candidate_edges)) {
    return(list(
      routes = empty_routes,
      edge_routes = candidate_edges,
      group_summary = data.frame(
        spill_group_id = numeric(0),
        lake_objectid = numeric(0),
        route_status = character(0),
        n_candidate_edges = integer(0),
        stringsAsFactors = FALSE
      ),
      qa = data.frame(
        check = c(
          "empty_candidate_edge_set_classified",
          "existing_routing_surfaces_only"
        ),
        pass = c(TRUE, TRUE),
        stringsAsFactors = FALSE
      )
    ))
  }

  route_starts <- unique(candidate_edges[
    ,
    c("receiver_cell", "lake_objectid"),
    drop = FALSE
  ])
  route_starts <- route_starts[
    order(route_starts$lake_objectid, route_starts$receiver_cell),
    ,
    drop = FALSE
  ]
  row.names(route_starts) <- NULL
  route_starts$route_id <- seq_len(nrow(route_starts))
  route_starts$route_key <- paste(
    route_starts$receiver_cell,
    route_starts$lake_objectid,
    sep = ":"
  )

  current_cell <- as.integer(route_starts$receiver_cell)
  route_steps <- integer(nrow(route_starts))
  terminal_cell <- rep(NA_integer_, nrow(route_starts))
  terminal_water_class <- rep(NA_integer_, nrow(route_starts))
  terminal_lake_objectid <- rep(NA_integer_, nrow(route_starts))
  route_status <- rep(NA_character_, nrow(route_starts))
  visited <- new.env(hash = TRUE, parent = emptyenv())
  for (i in seq_along(current_cell)) {
    if (current_cell[i] > as.double(nrow_raster) * ncol_raster) {
      route_status[i] <- "START_OUTSIDE_RASTER"
    } else {
      assign(
        paste(i, current_cell[i], sep = ":"),
        TRUE,
        envir = visited
      )
    }
  }

  pointer_codes <- c(1L, 2L, 4L, 8L, 16L, 32L, 64L, 128L)
  delta_row <- c(
    "1" = -1L, "2" = 0L, "4" = 1L, "8" = 1L,
    "16" = 1L, "32" = 0L, "64" = -1L, "128" = -1L
  )
  delta_col <- c(
    "1" = 1L, "2" = 1L, "4" = 1L, "8" = 0L,
    "16" = -1L, "32" = -1L, "64" = -1L, "128" = 0L
  )
  for (step in seq_len(as.integer(max_steps))) {
    active <- which(is.na(route_status))
    if (!length(active)) break

    cells <- current_cell[active]
    classes <- cell_values(water_class, cells)
    lakes <- cell_values(lake_id, cells)
    pointers <- cell_values(ptr_land_water, cells)
    if (length(classes) != length(active) ||
        length(lakes) != length(active) ||
        length(pointers) != length(active)) {
      stop("02F cell_values returned an incomplete raster read.")
    }

    has_class <- !is.na(classes)
    water <- which(has_class)
    if (length(water)) {
      class_values <- classes[water]
      lake_values <- lakes[water]
      valid_water <- is.finite(class_values) & class_values %in% c(1, 2, 3)
      invalid <- water[!valid_water]
      if (length(invalid)) {
        route_status[active[invalid]] <- "INVALID_WATER_CLASS"
      }

      valid <- water[valid_water]
      if (length(valid)) {
        valid_classes <- classes[valid]
        valid_lakes <- lakes[valid]
        valid_routes <- active[valid]
        terminal_cell[valid_routes] <- as.integer(cells[valid])
        terminal_water_class[valid_routes] <- as.integer(valid_classes)
        terminal_lake_objectid[valid_routes] <- ifelse(
          valid_classes == 1 & is.finite(valid_lakes),
          as.integer(valid_lakes),
          NA_integer_
        )

        status <- ifelse(
          valid_classes == 1 & !is.finite(valid_lakes),
          "LAKE_ID_MISSING",
          ifelse(
            valid_classes == 1 & valid_lakes ==
              route_starts$lake_objectid[valid_routes],
            "RETURNS_TO_ORIGIN_LAKE",
            ifelse(
              valid_classes == 1,
              "REACHES_OTHER_LAKE",
              ifelse(valid_classes == 2, "REACHES_RIVER_AREA", "REACHES_RIVER_LINE")
            )
          )
        )
        route_status[valid_routes] <- status
      }
    }

    land <- which(!has_class)
    if (!length(land)) next
    land_routes <- active[land]
    land_cells <- cells[land]
    land_pointers <- pointers[land]
    row <- ((land_cells - 1) %/% ncol_raster) + 1
    col <- ((land_cells - 1) %% ncol_raster) + 1
    at_edge <- row == 1 | row == nrow_raster |
      col == 1 | col == ncol_raster

    pointer_na <- is.na(land_pointers)
    route_status[land_routes[pointer_na]] <- "D8_POINTER_NA"
    zero <- !pointer_na & is.finite(land_pointers) & land_pointers == 0
    if (any(zero)) {
      route_status[land_routes[zero]] <- ifelse(
        at_edge[zero],
        "D8_ZERO_AT_RASTER_EDGE",
        "D8_ZERO_INTERIOR"
      )
    }
    valid_pointer <- !pointer_na & is.finite(land_pointers) &
      land_pointers %in% pointer_codes
    invalid_pointer <- !pointer_na & !zero & !valid_pointer
    route_status[land_routes[invalid_pointer]] <- "D8_POINTER_INVALID"

    follow <- which(valid_pointer)
    if (!length(follow)) next
    codes <- as.character(as.integer(land_pointers[follow]))
    next_row <- row[follow] + unname(delta_row[codes])
    next_col <- col[follow] + unname(delta_col[codes])
    outside <- next_row < 1 | next_row > nrow_raster |
      next_col < 1 | next_col > ncol_raster
    if (any(outside)) {
      exiting <- land_routes[follow[outside]]
      route_status[exiting] <- "D8_DOMAIN_EXIT"
      terminal_cell[exiting] <- as.integer(land_cells[follow[outside]])
    }

    inside <- which(!outside)
    if (!length(inside)) next
    next_cells <- as.integer(
      (next_row[inside] - 1) * ncol_raster + next_col[inside]
    )
    advancing_routes <- land_routes[follow[inside]]
    keys <- paste(advancing_routes, next_cells, sep = ":")
    cycle <- vapply(
      keys,
      exists,
      logical(1),
      envir = visited,
      inherits = FALSE
    )
    if (any(cycle)) {
      cycling <- advancing_routes[cycle]
      route_status[cycling] <- "D8_CYCLE"
      terminal_cell[cycling] <- next_cells[cycle]
    }
    advancing <- which(!cycle)
    if (length(advancing)) {
      advancing_routes <- advancing_routes[advancing]
      next_cells <- next_cells[advancing]
      for (i in seq_along(advancing_routes)) {
        assign(
          paste(advancing_routes[i], next_cells[i], sep = ":"),
          TRUE,
          envir = visited
        )
      }
      current_cell[advancing_routes] <- next_cells
      route_steps[advancing_routes] <- route_steps[advancing_routes] + 1L
    }
  }

  unresolved <- which(is.na(route_status))
  if (length(unresolved)) {
    route_status[unresolved] <- "STEP_LIMIT"
    terminal_cell[unresolved] <- current_cell[unresolved]
  }
  terminal_cell[is.na(terminal_cell)] <- current_cell[is.na(terminal_cell)]

  routes <- data.frame(
    route_id = route_starts$route_id,
    start_receiver_cell = as.integer(route_starts$receiver_cell),
    origin_lake_objectid = as.integer(route_starts$lake_objectid),
    terminal_cell = terminal_cell,
    terminal_water_class = terminal_water_class,
    terminal_lake_objectid = terminal_lake_objectid,
    route_steps = route_steps,
    route_status = route_status,
    stringsAsFactors = FALSE
  )

  route_index <- match(
    paste(candidate_edges$receiver_cell, candidate_edges$lake_objectid, sep = ":"),
    route_starts$route_key
  )
  if (anyNA(route_index)) stop("02F failed to link a candidate edge to its route.")
  edge_routes <- candidate_edges
  edge_routes$route_id <- routes$route_id[route_index]
  edge_routes$route_start_receiver_cell <- routes$start_receiver_cell[route_index]
  edge_routes$route_terminal_cell <- routes$terminal_cell[route_index]
  edge_routes$terminal_water_class <- routes$terminal_water_class[route_index]
  edge_routes$terminal_lake_objectid <- routes$terminal_lake_objectid[route_index]
  edge_routes$route_steps <- routes$route_steps[route_index]
  edge_routes$route_status <- routes$route_status[route_index]

  group_summary <- aggregate(
    rep.int(1L, nrow(edge_routes)),
    by = edge_routes[
      ,
      c("spill_group_id", "lake_objectid", "route_status"),
      drop = FALSE
    ],
    FUN = sum
  )
  names(group_summary)[names(group_summary) == "x"] <- "n_candidate_edges"
  row.names(group_summary) <- NULL

  connected_status <- routes$route_status %in% c(
    "REACHES_OTHER_LAKE",
    "REACHES_RIVER_AREA",
    "REACHES_RIVER_LINE"
  )
  other_lake_status <- routes$route_status == "REACHES_OTHER_LAKE"
  qa <- data.frame(
    check = c(
      "one_classified_outcome_per_receiver_and_origin",
      "route_ends_on_water_or_explicit_d8_terminal",
      "all_candidate_edges_link_to_a_route",
      "all_candidate_edges_have_a_classified_status",
      "connected_routes_end_on_ranta10_water",
      "other_lake_routes_have_lake_ids",
      "group_summary_reconciles_candidate_edges",
      "existing_routing_surfaces_only"
    ),
    pass = c(
      nrow(routes) == nrow(route_starts) &&
        !anyDuplicated(route_starts$route_key) &&
        !anyNA(routes$route_status),
      all(!is.na(routes$terminal_cell)),
      !anyNA(edge_routes$route_id),
      !anyNA(edge_routes$route_status),
      all(routes$terminal_water_class[connected_status] %in% c(1L, 2L, 3L)),
      all(is.finite(routes$terminal_lake_objectid[other_lake_status])),
      sum(group_summary$n_candidate_edges) == nrow(edge_routes),
      TRUE
    ),
    stringsAsFactors = FALSE
  )
  if (!all(qa$pass)) {
    stop("02F route diagnostic QA failed: ", paste(qa$check[!qa$pass], collapse = ", "))
  }

  list(
    routes = routes,
    edge_routes = edge_routes,
    group_summary = group_summary,
    qa = qa
  )
}
