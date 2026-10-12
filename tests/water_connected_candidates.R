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
      "EXTERNAL_EVIDENCE_CANDIDATE",
      "EXTERNAL_EVIDENCE_CANDIDATE",
      "NO_EXTERNAL_EVIDENCE",
      "REVIEW_REQUIRED"
    )
  ),
  all(candidate$outlet_selection == "UNASSIGNED"),
  nrow(tables$lake_summary) == 3L,
  tables$lake_summary$n_spill_groups[
    tables$lake_summary$lake_objectid == 10L
  ] == 2L,
  sum(tables$lake_summary$n_spill_groups) == nrow(candidate),
  all(tables$qa$pass)
)

bad_evidence <- make_evidence()
bad_evidence$outlet_selection[1] <- "SELECTED"
err <- tryCatch(
  build_water_connected_candidate_tables(bad_evidence),
  error = identity
)
stopifnot(inherits(err, "error"))

cat("PASS: 02E preserves candidate groups without selecting outlets\n")
