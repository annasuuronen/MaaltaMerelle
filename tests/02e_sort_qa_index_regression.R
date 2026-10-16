# Regression: 02E edge QA must use evidence indices for SORTED edge rows.
# Base-R-only synthetic fixture. No real data, raster, outlet, or CSC access.
source(file.path("R", "02E_water_connected_candidates.R"))

evidence <- data.frame(
  spill_group_id = c(501L, 502L, 503L),
  lake_objectid = c(20L, 10L, 10L),
  spill_level_m = c(31, 22, 23),
  evidence_class = rep("SYNTHETIC_ONLY", 3L),
  has_external_evidence = c(TRUE, TRUE, FALSE),
  needs_review = c(FALSE, FALSE, TRUE),
  evidence_status = c("EXTERNAL_EVIDENCE", "EXTERNAL_EVIDENCE", "REVIEW_REQUIRED"),
  outlet_selection = rep("UNASSIGNED", 3L),
  stringsAsFactors = FALSE
)
shore <- data.frame(
  spill_group_id = c(501L, 502L, 503L),
  lake_objectid = c(20L, 10L, 10L),
  source_cell = c(5L, 8L, 11L),
  receiver_cell = c(6L, 7L, 12L),
  storage_step_level_m = c(31, 22, 23),
  receiver_type = rep("LAND", 3L),
  stringsAsFactors = FALSE
)
for (order_index in list(1:3, c(3L, 1L, 2L), c(2L, 3L, 1L))) {
  groups <- build_water_connected_candidate_tables(evidence[order_index, , drop = FALSE])
  stopifnot(all(groups$qa$pass),
            sum(groups$candidate_evidence$candidate_included) == 2L)
  edge_result <- build_water_connected_candidate_edges(groups$candidate_evidence,
                                                         shore[order_index, , drop = FALSE])
  # The same two eligible groups must be retained, ordered by lake/object ID.
  stopifnot(all(edge_result$qa$pass),
            identical(edge_result$edges$spill_group_id, c(502L, 501L)),
            identical(edge_result$edges$lake_objectid, c(10L, 20L)),
            identical(edge_result$edges$candidate_spill_level_m, c(22, 31)),
            all(edge_result$edges$water_connected_candidate_status ==
                "INCLUDED_PARALLEL_CANDIDATE"),
            !any(edge_result$edges$spill_group_id == 503L))
}
# Input mismatches still fail closed; the index repair must not weaken QA.
bad_shore <- shore
bad_shore$lake_objectid[1] <- 999L
groups <- build_water_connected_candidate_tables(evidence)
stopifnot(inherits(try(build_water_connected_candidate_edges(
  groups$candidate_evidence, bad_shore), silent = TRUE), "try-error"))

cat("PASS: 02E post-sort evidence lookup QA is aligned, and invalid identities remain rejected\n")
