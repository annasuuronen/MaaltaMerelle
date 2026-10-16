# 02E - WATER_CONNECTED candidate evidence, not a routing surface.

build_water_connected_candidate_tables <- function(final_evidence) {
  required <- c(
    "spill_group_id",
    "lake_objectid",
    "spill_level_m",
    "evidence_class",
    "has_external_evidence",
    "needs_review",
    "evidence_status",
    "outlet_selection"
  )
  missing <- setdiff(required, names(final_evidence))
  if (length(missing)) {
    stop("02E missing 02D.8 columns: ", paste(missing, collapse = ", "))
  }
  if (!nrow(final_evidence)) stop("02E cannot process empty 02D.8 evidence.")
  if (!is.numeric(final_evidence$spill_group_id) ||
      anyNA(final_evidence$spill_group_id) ||
      anyDuplicated(final_evidence$spill_group_id)) {
    stop("02E requires one non-missing row per spill group.")
  }
  if (!is.numeric(final_evidence$lake_objectid) ||
      !is.numeric(final_evidence$spill_level_m) ||
      anyNA(final_evidence$lake_objectid) ||
      anyNA(final_evidence$spill_level_m) ||
      any(!is.finite(final_evidence$spill_level_m))) {
    stop("02E requires finite lake IDs and spill levels.")
  }
  if (!is.logical(final_evidence$has_external_evidence) ||
      !is.logical(final_evidence$needs_review) ||
      anyNA(final_evidence$has_external_evidence) ||
      anyNA(final_evidence$needs_review)) {
    stop("02E requires non-missing logical 02D.8 evidence flags.")
  }
  if (anyNA(final_evidence$outlet_selection) ||
      any(final_evidence$outlet_selection != "UNASSIGNED")) {
    stop("02E requires outlet_selection to remain UNASSIGNED.")
  }

  expected_status <- ifelse(
    final_evidence$needs_review,
    "REVIEW_REQUIRED",
    ifelse(
      final_evidence$has_external_evidence,
      "EXTERNAL_EVIDENCE",
      "NO_EXTERNAL_EVIDENCE"
    )
  )
  if (anyNA(final_evidence$evidence_status) ||
      any(final_evidence$evidence_status != expected_status)) {
    stop("02E found inconsistent 02D.8 evidence status flags.")
  }

  candidate_evidence <- final_evidence
  candidate_evidence$candidate_included <- (
    final_evidence$evidence_status == "EXTERNAL_EVIDENCE" &
      !final_evidence$needs_review
  )
  candidate_evidence$water_connected_candidate_status <- ifelse(
    candidate_evidence$candidate_included,
    "INCLUDED_PARALLEL_CANDIDATE",
    ifelse(
      final_evidence$evidence_status == "REVIEW_REQUIRED",
      "REVIEW_REQUIRED",
      "NO_EXTERNAL_EVIDENCE"
    )
  )
  candidate_evidence <- candidate_evidence[
    order(candidate_evidence$lake_objectid, candidate_evidence$spill_group_id),
    ,
    drop = FALSE
  ]
  row.names(candidate_evidence) <- NULL

  lake_ids <- sort(unique(candidate_evidence$lake_objectid))
  lake_summary <- do.call(rbind, lapply(lake_ids, function(lake_id) {
    rows <- candidate_evidence[
      candidate_evidence$lake_objectid == lake_id,
      ,
      drop = FALSE
    ]
    data.frame(
      lake_objectid = lake_id,
      n_spill_groups = nrow(rows),
      n_included_parallel_candidates = sum(rows$candidate_included),
      n_review_required = sum(
        rows$water_connected_candidate_status == "REVIEW_REQUIRED"
      ),
      n_no_external_evidence = sum(
        rows$water_connected_candidate_status == "NO_EXTERNAL_EVIDENCE"
      ),
      stringsAsFactors = FALSE
    )
  }))
  row.names(lake_summary) <- NULL

  checks <- c(
    all_spill_groups_preserved =
      nrow(candidate_evidence) == nrow(final_evidence) &&
      setequal(candidate_evidence$spill_group_id, final_evidence$spill_group_id),
    spill_groups_unique =
      !anyDuplicated(candidate_evidence$spill_group_id),
    all_outlets_unassigned =
      all(candidate_evidence$outlet_selection == "UNASSIGNED"),
    review_groups_excluded =
      !any(candidate_evidence$candidate_included &
        candidate_evidence$needs_review),
    evidence_status_consistent =
      all(candidate_evidence$evidence_status == expected_status[
        match(candidate_evidence$spill_group_id, final_evidence$spill_group_id)
      ]),
    lake_group_counts_reconcile =
      sum(lake_summary$n_spill_groups) == nrow(candidate_evidence)
  )
  if (!all(checks)) {
    stop("02E QA failed: ", paste(names(checks)[!checks], collapse = ", "))
  }

  qa <- data.frame(
    check = names(checks),
    pass = unname(checks),
    stringsAsFactors = FALSE
  )

  list(
    candidate_evidence = candidate_evidence,
    lake_summary = lake_summary,
    qa = qa
  )
}

build_water_connected_candidate_edges <- function(
  candidate_evidence,
  low_shore_edges,
  level_tolerance_m = 1e-6
) {
  required_evidence <- c(
    "spill_group_id",
    "lake_objectid",
    "spill_level_m",
    "candidate_included"
  )
  missing_evidence <- setdiff(required_evidence, names(candidate_evidence))
  if (length(missing_evidence)) {
    stop(
      "02E candidate edges missing evidence columns: ",
      paste(missing_evidence, collapse = ", ")
    )
  }
  required_edges <- c(
    "spill_group_id",
    "lake_objectid",
    "source_cell",
    "receiver_cell",
    "storage_step_level_m",
    "receiver_type"
  )
  missing_edges <- setdiff(required_edges, names(low_shore_edges))
  if (length(missing_edges)) {
    stop(
      "02E candidate edges missing spill-edge columns: ",
      paste(missing_edges, collapse = ", ")
    )
  }
  if (length(level_tolerance_m) != 1L ||
      !is.finite(level_tolerance_m) ||
      level_tolerance_m < 0) {
    stop("02E spill-level tolerance must be a finite non-negative number.")
  }
  if (!nrow(low_shore_edges) ||
      anyNA(low_shore_edges$spill_group_id) ||
      anyNA(low_shore_edges$source_cell) ||
      anyNA(low_shore_edges$receiver_cell) ||
      any(!is.finite(low_shore_edges$storage_step_level_m))) {
    stop("02E requires complete lowest-spill edge records.")
  }
  if (any(!low_shore_edges$spill_group_id %in%
      candidate_evidence$spill_group_id)) {
    stop("02E spill edges contain groups absent from final evidence.")
  }

  selected_groups <- candidate_evidence$spill_group_id[
    candidate_evidence$candidate_included
  ]

  edges <- low_shore_edges[
    low_shore_edges$spill_group_id %in% selected_groups,
    ,
    drop = FALSE
  ]
  if (length(selected_groups) && !nrow(edges)) {
    stop("02E eligible spill groups have no lowest-spill shore edges.")
  }

  evidence_index <- match(edges$spill_group_id, candidate_evidence$spill_group_id)
  if (anyNA(evidence_index)) stop("02E could not match spill edges to evidence.")
  if (any(edges$lake_objectid !=
      candidate_evidence$lake_objectid[evidence_index])) {
    stop("02E spill-edge lake IDs disagree with final evidence.")
  }
  if (any(abs(
    edges$storage_step_level_m -
      candidate_evidence$spill_level_m[evidence_index]
  ) > level_tolerance_m)) {
    stop("02E spill-edge levels disagree with final evidence.")
  }

  edges$candidate_spill_level_m <-
    candidate_evidence$spill_level_m[evidence_index]
  edges$evidence_status <- rep("EXTERNAL_EVIDENCE", nrow(edges))
  edges$water_connected_candidate_status <- rep(
    "INCLUDED_PARALLEL_CANDIDATE",
    nrow(edges)
  )
  edges <- edges[
    order(edges$lake_objectid, edges$spill_group_id,
      edges$source_cell, edges$receiver_cell),
    ,
    drop = FALSE
  ]
  row.names(edges) <- NULL

  # Rebind the group lookup AFTER sorting rows. The pre-sort evidence_index
  # above correctly validates each edge on input, but cannot be reused for
  # QA comparisons after lake-based ordering changes the edge row positions.
  evidence_index <- match(edges$spill_group_id, candidate_evidence$spill_group_id)
  if (anyNA(evidence_index)) stop("02E QA cannot match sorted edges to evidence.")

  included_counts <- table(factor(
    edges$spill_group_id,
    levels = selected_groups
  ))
  expected_edge_count <- sum(
    low_shore_edges$spill_group_id %in% selected_groups
  )
  if (any(included_counts == 0L)) {
    stop("02E an eligible candidate spill group has no retained edges.")
  }
  if (nrow(edges) != expected_edge_count) {
    stop("02E did not preserve every edge from the eligible spill groups.")
  }

  list(
    edges = edges,
    source_cells = sort(unique(as.integer(edges$source_cell))),
    receiver_cells = sort(unique(as.integer(edges$receiver_cell))),
    qa = data.frame(
      check = c(
        "no_eligible_candidates_have_no_edges",
        "all_eligible_spill_groups_have_edges",
        "all_eligible_group_edges_preserved",
        "only_eligible_groups_in_edge_table",
        "lake_ids_match_evidence",
        "spill_levels_match_evidence"
      ),
      pass = c(
        length(selected_groups) > 0L || nrow(edges) == 0L,
        all(included_counts > 0L),
        nrow(edges) == expected_edge_count,
        all(edges$spill_group_id %in% selected_groups),
        all(edges$lake_objectid ==
          candidate_evidence$lake_objectid[evidence_index]),
        all(abs(edges$storage_step_level_m -
          edges$candidate_spill_level_m) <= level_tolerance_m)
      ),
      stringsAsFactors = FALSE
    )
  )
}

water_connected_candidate_cell_sets <- function(candidate_edges) {
  required <- c("source_cell", "receiver_cell")
  missing <- setdiff(required, names(candidate_edges))
  if (length(missing)) {
    stop("02E candidate mask missing edge columns: ", paste(missing, collapse = ", "))
  }
  if (!nrow(candidate_edges)) {
    return(list(source_cells = integer(0), receiver_cells = integer(0)))
  }
  if (anyNA(candidate_edges$source_cell) ||
      anyNA(candidate_edges$receiver_cell) ||
      any(!is.finite(candidate_edges$source_cell)) ||
      any(!is.finite(candidate_edges$receiver_cell)) ||
      any(candidate_edges$source_cell < 1) ||
      any(candidate_edges$receiver_cell < 1) ||
      any(candidate_edges$source_cell != as.integer(candidate_edges$source_cell)) ||
      any(candidate_edges$receiver_cell != as.integer(candidate_edges$receiver_cell))) {
    stop("02E candidate mask requires positive integer source and receiver cells.")
  }

  list(
    source_cells = sort(unique(as.integer(candidate_edges$source_cell))),
    receiver_cells = sort(unique(as.integer(candidate_edges$receiver_cell)))
  )
}

write_water_connected_candidate_mask <- function(cells, template, filename) {
  if (!length(cells)) stop("02E cannot write an empty candidate mask: ", filename)
  if (anyNA(cells) || any(cells < 1L) || any(cells > terra::ncell(template))) {
    stop("02E candidate mask contains cells outside its raster template.")
  }

  coordinates <- terra::xyFromCell(template, cells)
  points <- terra::vect(
    data.frame(
      x = coordinates[, 1],
      y = coordinates[, 2],
      mask_value = 1L
    ),
    geom = c("x", "y"),
    crs = terra::crs(template)
  )
  terra::rasterize(
    points,
    template,
    field = "mask_value",
    background = NA,
    touches = FALSE,
    filename = filename,
    overwrite = TRUE,
    wopt = list(
      datatype = "INT1U",
      gdal = c("COMPRESS=DEFLATE", "BIGTIFF=YES")
    )
  )
}

validate_water_connected_candidate_mask <- function(
  mask,
  expected_cells,
  template,
  cell_values
) {
  if (!isTRUE(terra::compareGeom(mask, template, stopOnError = FALSE))) {
    stop("02E candidate mask geometry differs from its input template.")
  }
  mask_count <- terra::global(!is.na(mask), "sum", na.rm = TRUE)[1, 1]
  invalid_count <- terra::global(mask != 1, "sum", na.rm = TRUE)[1, 1]
  expected_values <- cell_values(mask, expected_cells)
  if (is.na(mask_count) ||
      mask_count != length(expected_cells) ||
      is.na(invalid_count) ||
      invalid_count != 0 ||
      any(expected_values != 1)) {
    stop("02E candidate mask does not exactly match its expected spill-edge cells.")
  }
  TRUE
}

run_water_connected_candidate_mask_qa <- function(
  candidate_edges,
  template,
  directory,
  overwrite,
  cell_values
) {
  cells <- water_connected_candidate_cell_sets(candidate_edges)
  if (!nrow(candidate_edges)) {
    stale_masks <- file.path(
      directory,
      c(
        "02E_water_connected_candidate_source_mask.tif",
        "02E_water_connected_candidate_receiver_mask.tif"
      )
    )
    stale_masks <- stale_masks[file.exists(stale_masks)]
    if (length(stale_masks) && !overwrite) {
      stop(
        "02E found stale candidate masks with no eligible edges; ",
        "set OVERWRITE=TRUE before rerunning."
      )
    }
    if (length(stale_masks) && !all(file.remove(stale_masks))) {
      stop("02E could not remove stale candidate masks.")
    }
    return(list(
      source_path = NA_character_,
      receiver_path = NA_character_,
      source_cell_count = 0L,
      receiver_cell_count = 0L,
      qa = data.frame(
        check = c(
          "no_eligible_edges_no_masks_emitted",
          "routing_elevation_surface_not_generated"
        ),
        pass = c(TRUE, TRUE),
        stringsAsFactors = FALSE
      )
    ))
  }
  source_path <- file.path(
    directory,
    "02E_water_connected_candidate_source_mask.tif"
  )
  receiver_path <- file.path(
    directory,
    "02E_water_connected_candidate_receiver_mask.tif"
  )

  if (!file.exists(source_path) || overwrite) {
    write_water_connected_candidate_mask(
      cells$source_cells,
      template,
      source_path
    )
  }
  if (!file.exists(receiver_path) || overwrite) {
    write_water_connected_candidate_mask(
      cells$receiver_cells,
      template,
      receiver_path
    )
  }
  if (!file.exists(source_path) || !file.exists(receiver_path)) {
    stop("02E candidate spill-edge mask output is missing.")
  }

  source_mask <- terra::rast(source_path)
  receiver_mask <- terra::rast(receiver_path)
  validate_water_connected_candidate_mask(
    source_mask, cells$source_cells, template, cell_values
  )
  validate_water_connected_candidate_mask(
    receiver_mask, cells$receiver_cells, template, cell_values
  )

  qa <- data.frame(
    check = c(
      "source_mask_matches_all_candidate_edges",
      "receiver_mask_matches_all_candidate_edges",
      "routing_elevation_surface_not_generated"
    ),
    pass = c(TRUE, TRUE, TRUE),
    stringsAsFactors = FALSE
  )
  list(
    source_path = source_path,
    receiver_path = receiver_path,
    source_cell_count = length(cells$source_cells),
    receiver_cell_count = length(cells$receiver_cells),
    qa = qa
  )
}
