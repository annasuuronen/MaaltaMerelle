# Pure report classifier. No raster access, routing, component creation or approval.
classify_02d5_readiness <- function(x, tolerance_m = 1e-7) {
  if (!is.data.frame(x) || anyDuplicated(names(x))) stop("Expected uniquely named table columns.")
  if (length(tolerance_m) != 1L || !is.numeric(tolerance_m) ||
      !is.finite(tolerance_m) || tolerance_m != 1e-7) stop("Use the production 1e-7 m tolerance.")
  required <- c("lake_objectid", "n_lake_cells", "n_raised_lake_cells",
                "raised_fraction", "n_depression_components", "depression_component_ids",
                "spill_raised", "spill_raise_m", "storage_raised", "max_storage_raise_m")
  missing_columns <- setdiff(required, names(x))
  for (name in missing_columns) x[[name]] <- rep(NA, nrow(x))
  number <- function(value) {
    if (length(value) != 1L || is.logical(value) || is.factor(value)) return(NA_real_)
    value <- suppressWarnings(as.numeric(value))
    if (is.finite(value)) value else NA_real_
  }
  boolean <- function(value) {
    if (length(value) != 1L || is.na(value)) return(NA)
    if (is.logical(value)) return(value)
    if (is.character(value) && value %in% c("TRUE", "FALSE")) return(value == "TRUE")
    NA
  }
  whole <- function(value, minimum = 0) is.finite(value) && value >= minimum &&
    value <= .Machine$integer.max && value == floor(value)
  ids <- vapply(x$lake_objectid, number, 0.0)
  duplicate_ids <- duplicated(ids) | duplicated(ids, fromLast = TRUE)
  rows <- vector("list", nrow(x))
  for (i in seq_len(nrow(x))) {
    reasons <- character()
    add <- function(reason) reasons <<- unique(c(reasons, reason))
    if (length(missing_columns)) add(paste0("MISSING_COLUMN:", missing_columns))
    id <- ids[i]
    count <- number(x$n_lake_cells[i])
    raised <- number(x$n_raised_lake_cells[i])
    components <- number(x$n_depression_components[i])
    fraction <- number(x$raised_fraction[i])
    threshold <- number(x$spill_raise_m[i])
    shore_raise <- number(x$max_storage_raise_m[i])
    spill_flag <- boolean(x$spill_raised[i])
    storage_flag <- boolean(x$storage_raised[i])
    if (!whole(id, 1)) add("INVALID_OR_MISSING_LAKE_ID")
    if (duplicate_ids[i]) add("DUPLICATE_LAKE_ID")
    if (!whole(count, 1)) add("INVALID_OR_MISSING_LAKE_CELL_COUNT")
    if (!whole(raised)) add("INVALID_OR_MISSING_RAISED_CELL_COUNT")
    if (!whole(components)) add("INVALID_OR_MISSING_COMPONENT_COUNT")
    if (!is.finite(fraction) || fraction < 0 || fraction > 1) add("INVALID_OR_MISSING_RAISED_FRACTION")
    if (!is.finite(threshold)) add("INVALID_OR_MISSING_SHORE_THRESHOLD")
    if (!is.finite(shore_raise)) add("INVALID_OR_MISSING_SHORE_RAISE")
    if (is.na(spill_flag)) add("INVALID_OR_MISSING_SPILL_FLAG")
    if (is.na(storage_flag)) add("INVALID_OR_MISSING_STORAGE_FLAG")
    component_text <- x$depression_component_ids[i]
    references <- numeric()
    if (length(component_text) != 1L || is.na(component_text)) {
      add("MISSING_COMPONENT_REFERENCES")
    } else {
      component_text <- trimws(as.character(component_text))
      if (nzchar(component_text)) {
        if (!grepl("^[1-9][0-9]*(;[1-9][0-9]*)*$", component_text)) {
          add("INVALID_COMPONENT_REFERENCES")
        } else {
          references <- suppressWarnings(as.numeric(strsplit(component_text, ";", fixed = TRUE)[[1L]]))
          if (any(!is.finite(references)) || any(references > .Machine$integer.max) ||
              anyDuplicated(references)) add("INVALID_OR_DUPLICATE_COMPONENT_REFERENCES")
        }
      }
    }
    if (whole(components) && length(references) != components) add("COMPONENT_REFERENCE_COUNT_MISMATCH")
    if (whole(raised) && whole(count, 1) && raised > count) add("RAISED_CELLS_EXCEED_LAKE_CELLS")
    if (whole(raised) && whole(components) &&
        ((raised == 0) != (components == 0) || components > raised)) add("CELL_COMPONENT_COUNT_MISMATCH")
    if (whole(raised) && whole(count, 1) && is.finite(fraction) &&
        abs(fraction - raised / count) > 1e-10) add("RAISED_FRACTION_MISMATCH")
    if (is.finite(threshold) && !is.na(spill_flag) &&
        spill_flag != (threshold > tolerance_m)) add("SHORE_THRESHOLD_FLAG_MISMATCH")
    if (is.finite(shore_raise) && !is.na(storage_flag) &&
        storage_flag != (shore_raise > tolerance_m)) add("SHORE_RAISE_FLAG_MISMATCH")
    if (is.finite(shore_raise) && shore_raise < -tolerance_m) add("NEGATIVE_SHORE_CHANGE")
    if (is.finite(threshold) && threshold < -tolerance_m) add("NEGATIVE_SHORE_THRESHOLD")
    if (whole(raised) && raised == 0 && is.finite(shore_raise) &&
        shore_raise > tolerance_m) add("SHORE_RAISE_WITHOUT_RAISED_LAKE_CELLS")

    eligible <- FALSE
    class <- "NEEDS_REVIEW"
    interpretation <- "INCONSISTENT_OR_INCOMPLETE_EVIDENCE"
    if (!length(reasons)) {
      if (raised > 0 && components > 0) {
        if (spill_flag) {
          class <- "OBSERVED_COMPONENT_ELIGIBLE_FOR_GATE_REVIEW"
          eligible <- TRUE
          interpretation <- if (components == 1) "ONE_REPORTED_OBSERVED_COMPONENT" else
            "MULTIPLE_REPORTED_OBSERVED_COMPONENTS"
        } else {
          class <- "OBSERVED_RAISE_WITHOUT_POSITIVE_THRESHOLD"
          interpretation <- "OBSERVED_COMPONENT_NOT_A_SPILL_TARGET"
        }
        # This is valid partial/interior evidence; the shore-only maximum is not
        # an all-lake-cell maximum and must NOT be used to reject this case.
        if (!storage_flag) interpretation <- paste(interpretation, "RAISE_NOT_DETECTED_BY_SHORE_MAX", sep = ";")
      } else if (spill_flag) {
        class <- "POSITIVE_THRESHOLD_NO_OBSERVED_RAISE"
        interpretation <- "POSITIVE_SHORE_THRESHOLD_NO_OBSERVED_RAISE"
      } else {
        class <- "NO_OBSERVED_COMPONENT"
        interpretation <- "NO_POSITIVE_THRESHOLD_OR_REPORTED_RAISED_COMPONENT"
      }
    }
    rows[[i]] <- data.frame(lake_objectid = id, technical_class = class,
      evidence_consistent = !length(reasons), gate_component_evidence_present = eligible,
      reported_spill_raised = spill_flag, reported_raised_cells = raised,
      reported_components = components, interpretation = interpretation,
      review_reasons = paste(reasons, collapse = ";"), continuation_authorized = FALSE,
      scientific_status = "REVIEW_REQUIRED", national_status = "LOCKED",
      stringsAsFactors = FALSE)
  }
  # Keep a typed, empty report when input has zero rows; never vacuously accept.
  if (length(rows)) {
    per_lake <- do.call(rbind, rows)
  } else {
    per_lake <- data.frame(lake_objectid = numeric(), technical_class = character(),
      evidence_consistent = logical(), gate_component_evidence_present = logical(),
      reported_spill_raised = logical(), reported_raised_cells = numeric(),
      reported_components = numeric(), interpretation = character(), review_reasons = character(),
      continuation_authorized = logical(), scientific_status = character(), national_status = character())
  }
  target <- !is.na(per_lake$reported_spill_raised) & per_lake$reported_spill_raised
  complete <- nrow(per_lake) > 0 && !length(missing_columns) &&
    all(per_lake$evidence_consistent) && any(target) &&
    all(per_lake$gate_component_evidence_present[target])
  list(per_lake = per_lake, summary = data.frame(
    lakes = nrow(per_lake), positive_threshold_targets = sum(target),
    incomplete_or_inconsistent_lakes = sum(!per_lake$evidence_consistent),
    eligible_for_component_gate_review = sum(per_lake$gate_component_evidence_present),
    component_evidence_complete = complete,
    technical_status = if (complete) "COMPONENT_EVIDENCE_COMPLETE_REVIEW_PENDING" else "NEEDS_REVIEW",
    continuation_authorized = FALSE, scientific_status = "REVIEW_REQUIRED",
    national_status = "LOCKED", stringsAsFactors = FALSE))
}
