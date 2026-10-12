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
  candidate_evidence$water_connected_candidate_status <- ifelse(
    final_evidence$evidence_status == "REVIEW_REQUIRED",
    "REVIEW_REQUIRED",
    ifelse(
      final_evidence$evidence_status == "EXTERNAL_EVIDENCE",
      "EXTERNAL_EVIDENCE_CANDIDATE",
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
      n_external_evidence_candidates = sum(
        rows$water_connected_candidate_status == "EXTERNAL_EVIDENCE_CANDIDATE"
      ),
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
