# Base-R regressions only. All IDs and evidence rows below are SYNTHETIC.
local({
  source("scripts/lib/classify_02d5_readiness.R", local = TRUE)
  checks <- 0L
  check <- function(label, condition) {
    stopifnot(isTRUE(condition))
    checks <<- checks + 1L
    cat("PASS 02D.5 readiness:", label, "\n")
  }
  row <- function() data.frame(lake_objectid = 101, n_lake_cells = 10,
    n_raised_lake_cells = 0, raised_fraction = 0, n_depression_components = 0,
    depression_component_ids = "", spill_raised = TRUE, spill_raise_m = 0.2,
    storage_raised = FALSE, max_storage_raise_m = 0, stringsAsFactors = FALSE)
  observed <- function() {
    x <- row()
    x$n_raised_lake_cells <- 4
    x$raised_fraction <- 0.4
    x$n_depression_components <- 1
    x$depression_component_ids <- "7"
    x$storage_raised <- TRUE
    x$max_storage_raise_m <- 0.2
    x
  }
  denied <- function(x) {
    r <- classify_02d5_readiness(x)
    !r$summary$component_evidence_complete && !r$summary$continuation_authorized &&
      all(!r$per_lake$continuation_authorized) &&
      r$summary$scientific_status == "REVIEW_REQUIRED" && r$summary$national_status == "LOCKED"
  }
  # Known counts are simulated, not a newly imported CSC report.
  x <- row()[rep(1L, 158), ]
  x$lake_objectid <- seq_len(158)
  x$spill_raised[53:158] <- FALSE
  x$spill_raise_m[53:158] <- 0
  r <- classify_02d5_readiness(x)
  check("52 targets never authorize continuation", denied(x) &&
    sum(r$per_lake$technical_class == "POSITIVE_THRESHOLD_NO_OBSERVED_RAISE") == 52 &&
    sum(r$per_lake$technical_class == "NO_OBSERVED_COMPONENT") == 106 &&
    r$summary$positive_threshold_targets == 52 && r$summary$eligible_for_component_gate_review == 0)
  r <- classify_02d5_readiness(observed())
  check("one observed component is only eligible for review", r$summary$component_evidence_complete &&
    r$per_lake$gate_component_evidence_present && !r$summary$continuation_authorized)
  x <- observed()
  x$n_depression_components <- 2
  x$depression_component_ids <- "7;9"
  r <- classify_02d5_readiness(x)
  check("multiple observed components preserved, not merged", r$per_lake$evidence_consistent &&
    r$per_lake$reported_components == 2 && r$summary$component_evidence_complete)
  x <- row()
  x$spill_raise_m <- 0
  x$spill_raised <- FALSE
  check("empty spill target set is not vacuous acceptance", denied(x) &&
    classify_02d5_readiness(x)$per_lake$technical_class == "NO_OBSERVED_COMPONENT")
  x <- observed()
  x$storage_raised <- FALSE
  x$max_storage_raise_m <- 0
  r <- classify_02d5_readiness(x)
  check("interior-only raise is consistent with zero shore maximum",
    r$per_lake$evidence_consistent && r$summary$component_evidence_complete &&
      grepl("RAISE_NOT_DETECTED_BY_SHORE_MAX", r$per_lake$interpretation, fixed = TRUE))
  x$spill_raise_m <- 0
  x$spill_raised <- FALSE
  r <- classify_02d5_readiness(x)
  check("partial non-target raise retained without inventing a spill target", denied(x) &&
    r$per_lake$evidence_consistent && r$per_lake$technical_class == "OBSERVED_RAISE_WITHOUT_POSITIVE_THRESHOLD")
  mutations <- list(
    lake_objectid = c(NA, 0, 1.5), n_lake_cells = c(NA, 0, 1.1),
    n_raised_lake_cells = c(NA, -1, 0.5, 11), n_depression_components = c(NA, -1, 1, 0.5),
    raised_fraction = c(NA, -1, 1.1, 0.5), spill_raise_m = c(NA, Inf, -1, 0),
    max_storage_raise_m = c(NA, Inf, -1, 0.2),
    spill_raised = c(NA, FALSE), storage_raised = c(NA, TRUE),
    depression_component_ids = c(NA, "7", "0", "1;;2", "7;7", "1.0", "2147483648"))
  for (name in names(mutations)) for (value in mutations[[name]]) {
    x <- row()
    x[[name]] <- value
    r <- classify_02d5_readiness(x)
    check(paste("reject invalid or contradictory", name, value), denied(x) &&
      r$per_lake$technical_class == "NEEDS_REVIEW" && nzchar(r$per_lake$review_reasons))
  }
  x <- observed()
  for (text in c("", "7;7", "7;9", "7;", "7.5", NA)) {
    x$depression_component_ids <- text
    check(paste("component references fail closed", text), denied(x) &&
      !classify_02d5_readiness(x)$per_lake$evidence_consistent)
  }
  for (column in names(row())) {
    x <- row()
    x[[column]] <- NULL
    check(paste("missing column", column), denied(x) &&
      classify_02d5_readiness(x)$per_lake$technical_class == "NEEDS_REVIEW")
  }
  x <- rbind(observed(), observed())
  r <- classify_02d5_readiness(x)
  check("all duplicate IDs flagged and dataset denied", denied(x) &&
    all(grepl("DUPLICATE_LAKE_ID", r$per_lake$review_reasons, fixed = TRUE)))
  check("zero rows fail closed", denied(row()[FALSE, ]) &&
    classify_02d5_readiness(row()[FALSE, ])$summary$lakes == 0)
  x <- observed()
  x$n_depression_components <- 5
  x$depression_component_ids <- "1;2;3;4;5"
  check("components cannot outnumber raised cells", denied(x))
  # Original production guard is evaluated unchanged on the synthetic 52 rows.
  code <- readLines("R/02_build_baseline_hydrology.R", warn = FALSE)
  a <- grep("# 109. SPILL-RAISED LAKES -> DEPRESSION COMPONENT", code, fixed = TRUE)
  b <- grep("# TEST_SULKU_11 has one raised depression component", code, fixed = TRUE)
  stopifnot(length(a) == 1, length(b) == 1)
  e <- new.env()
  e$lake_depression_summary <- row()[rep(1L, 52), ]
  e$lake_depression_summary$lake_objectid <- seq_len(52)
  failure <- tryCatch({eval(parse(text = code[seq.int(a + 1, b - 1)]), e); NULL}, error = identity)
  check("unchanged production 02D.5 guard still rejects 52 no-component lakes", inherits(failure, "error"))
  # CLI is a report-only reader. Verify its summary and preserve input bytes.
  d <- tempfile("readiness-cli-")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  f <- file.path(d, "synthetic.csv")
  write.csv(row(), f, row.names = FALSE)
  before <- readBin(f, "raw", file.info(f)$size)
  out <- system2(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", "scripts/classify_02d5_readiness.R", shQuote(f), "summary"), stdout = TRUE, stderr = TRUE)
  check("CLI produces denied summary and leaves input unchanged", is.null(attr(out, "status")) &&
    grepl("NEEDS_REVIEW", paste(out, collapse = "\n"), fixed = TRUE) &&
    identical(before, readBin(f, "raw", file.info(f)$size)))
  stopifnot(checks >= 60)
  cat("Completed", checks, "02D.5 readiness checks; MODERATE=REVIEW_REQUIRED; NATIONAL=LOCKED.\n")
})
