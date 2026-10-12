# Base-R tests for outlet-independent 02E candidate evidence.
source(file.path("R", "02E_water_connected_candidates.R"))

make_evidence <- function() {
  data.frame(
    spill_group_id = c(1L, 2L, 3L, 4L),
    lake_objectid = c(10L, 10L, 20L, 30L),
    spill_level_m = c(1.1, 1.2, 2.0, 3.0),
    evidence_class = c("RIVER_CONTACT", "LAND_ONLY", "LAND_ONLY", "EDGE_CASE"),
    has_external_evidence = c(TRUE, TRUE, FALSE, TRUE),
    needs_review = c(FALSE, FALSE, FALSE, TRUE),
    evidence_status = c(
      "EXTERNAL_EVIDENCE",
      "EXTERNAL_EVIDENCE",
      "NO_EXTERNAL_EVIDENCE",
      "REVIEW_REQUIRED"
    ),
    outlet_selection = rep("UNASSIGNED", 4L),
    stringsAsFactors = FALSE
  )
}

tables <- build_water_connected_candidate_tables(make_evidence())
candidate <- tables$candidate_evidence
stopifnot(
  nrow(candidate) == 4L,
  !anyDuplicated(candidate$spill_group_id),
  identical(candidate$spill_group_id, 1:4),
  identical(
    candidate$water_connected_candidate_status,
    c(
      "INCLUDED_PARALLEL_CANDIDATE",
      "INCLUDED_PARALLEL_CANDIDATE",
      "NO_EXTERNAL_EVIDENCE",
      "REVIEW_REQUIRED"
    )
  ),
  identical(candidate$candidate_included, c(TRUE, TRUE, FALSE, FALSE)),
  all(candidate$outlet_selection == "UNASSIGNED"),
  nrow(tables$lake_summary) == 3L,
  tables$lake_summary$n_included_parallel_candidates[
    tables$lake_summary$lake_objectid == 10L
  ] == 2L,
  sum(tables$lake_summary$n_spill_groups) == nrow(candidate),
  all(tables$qa$pass)
)

edge_rows <- data.frame(
  spill_group_id = c(1L, 1L, 2L, 4L),
  lake_objectid = c(10L, 10L, 10L, 30L),
  source_cell = c(100L, 101L, 200L, 400L),
  receiver_cell = c(110L, 111L, 210L, 410L),
  storage_step_level_m = c(1.1, 1.1, 1.2, 3.0),
  receiver_type = c("RIVER_LINE", "LAND", "LAND", "LAND"),
  stringsAsFactors = FALSE
)
candidate_edges <- build_water_connected_candidate_edges(
  candidate,
  edge_rows
)
stopifnot(
  nrow(candidate_edges$edges) == 3L,
  setequal(candidate_edges$edges$spill_group_id, c(1L, 2L)),
  !any(candidate_edges$edges$spill_group_id == 4L),
  all(candidate_edges$qa$pass),
  identical(candidate_edges$source_cells, c(100L, 101L, 200L)),
  identical(candidate_edges$receiver_cells, c(110L, 111L, 210L))
)
cell_sets <- water_connected_candidate_cell_sets(candidate_edges$edges)
stopifnot(
  identical(cell_sets$source_cells, c(100L, 101L, 200L)),
  identical(cell_sets$receiver_cells, c(110L, 111L, 210L))
)

no_eligible_candidates <- candidate
no_eligible_candidates$candidate_included <- FALSE
empty_edges <- build_water_connected_candidate_edges(
  no_eligible_candidates,
  edge_rows
)
stopifnot(
  nrow(empty_edges$edges) == 0L,
  all(empty_edges$qa$pass),
  identical(
    water_connected_candidate_cell_sets(empty_edges$edges)$source_cells,
    integer(0)
  )
)

bad_edges <- edge_rows
bad_edges$storage_step_level_m[1] <- 1.5
err <- tryCatch(
  build_water_connected_candidate_edges(candidate, bad_edges),
  error = identity
)
stopifnot(inherits(err, "error"))

bad_cells <- candidate_edges$edges
bad_cells$source_cell[1] <- 1.5
err <- tryCatch(
  water_connected_candidate_cell_sets(bad_cells),
  error = identity
)
stopifnot(inherits(err, "error"))

bad_evidence <- make_evidence()
bad_evidence$outlet_selection[1] <- "SELECTED"
err <- tryCatch(
  build_water_connected_candidate_tables(bad_evidence),
  error = identity
)
stopifnot(inherits(err, "error"))

cat("PASS: 02E preserves parallel spill candidates and diagnostic edge masks\n")
