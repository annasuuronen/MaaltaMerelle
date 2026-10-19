#!/usr/bin/env Rscript
# Read-only, batched scientific audit for MODERATE 02D.1–02D.5.
# No outputs written, no Whitebox run, no pointer or model changes.
# Usage: Rscript scripts/audit_moderate_spill_d8_readonly.R RUN_02_BASELINE RANTA10_LAKE_ID_TIF
suppressPackageStartupMessages(library(terra))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Supply RUN_02_BASELINE and RANTA10_LAKE_ID_TIF")
b <- normalizePath(args[1], mustWork = TRUE)
lake_path <- normalizePath(args[2], mustWork = TRUE)
read_table <- function(name) read.csv(file.path(b, name), stringsAsFactors = FALSE)
q <- read_table("02D_lake_depression_component_summary.csv")
s <- read_table("02D_spill_group_diagnostic.csv")
e <- read_table("02D_lowest_spill_shore_edges.csv")
zc <- read_table("02C_zero_pointer_cells.csv")
needed <- c("lake_objectid", "spill_raised", "n_depression_components",
            "n_raised_lake_cells", "max_storage_raise_m")
stopifnot(all(needed %in% names(q)),
          all(c("lake_objectid", "spill_raise_m", "raise_mismatch") %in% names(s)),
          all(c("lake_objectid", "receiver_cell", "source_cell") %in% names(e)),
          "cell" %in% names(zc),
          !anyDuplicated(q$lake_objectid), !anyDuplicated(s$lake_objectid),
          setequal(q$lake_objectid, s$lake_objectid))
ids <- q$lake_objectid[q$depression_status == "SPILL_RAISED_NO_COMPONENT"]
a <- e[e$lake_objectid %in% ids, , drop = FALSE]
stopifnot(setequal(ids, a$lake_objectid))
cat("=== MODERATE 02D SUMMARY ===\n")
cat("LAKES", nrow(q), "SPILL_RAISED", sum(q$spill_raised),
    "MISMATCH_CLASS", length(ids), "SPILL_EDGES", nrow(a), "\n")
cat("MISMATCH_RAISED_CELLS", sum(q$n_raised_lake_cells[q$lake_objectid %in% ids]),
    "WITH_COMPONENT", sum(q$n_depression_components[q$lake_objectid %in% ids] >= 1),
    "MAX_OBSERVED_STORAGE_RAISE",
    max(q$max_storage_raise_m[q$lake_objectid %in% ids]), "\n")
cat("SPILL_RAISE_RANGE_M",
    paste(range(s$spill_raise_m[s$lake_objectid %in% ids]), collapse = " .. "), "\n")
cat("PRODUCTION_02D5_GATE_PASS",
    all(q$n_depression_components[q$spill_raised] >= 1), "\n")
p <- rast(file.path(b, "d8_pointer_land_water_FLT8S.tif"))
l <- rast(lake_path)
stopifnot(compareGeom(p, l, stopOnError = FALSE))
dirs <- list("1" = c(-1L, 1L), "2" = c(0L, 1L), "4" = c(1L, 1L),
             "8" = c(1L, 0L), "16" = c(1L, -1L), "32" = c(0L, -1L),
             "64" = c(-1L, -1L), "128" = c(-1L, 0L))
# Read only the requested raster cells. This does not scan all 36 million cells.
one_value <- function(r, cell) terra::extract(r, as.integer(cell))[[1]][1]
trace <- function(start, source_id, cap = 100L) {
  cell <- as.integer(start)
  seen <- integer()
  for (step in seq_len(cap)) {
    if (cell %in% seen) return(c("CYCLE", as.character(cell), as.character(step)))
    seen <- c(seen, cell)
    water_id <- one_value(l, cell)
    if (is.finite(water_id) && water_id == source_id)
      return(c("RETURN_TO_SOURCE_LAKE", as.character(cell), as.character(step)))
    code <- one_value(p, cell)
    k <- as.character(code)
    if (!is.finite(code) || !k %in% names(dirs))
      return(c(paste0("TERMINAL_", code), as.character(cell), as.character(step)))
    rc <- rowColFromCell(p, cell)
    nr <- rc[1, 1] + dirs[[k]][1]
    nc <- rc[1, 2] + dirs[[k]][2]
    if (nr < 1L || nr > nrow(p) || nc < 1L || nc > ncol(p))
      return(c("DOMAIN_EXIT", as.character(cell), as.character(step)))
    cell <- cellFromRowCol(p, nr, nc)
  }
  c("STEP_LIMIT", as.character(cell), as.character(cap))
}
out <- lapply(seq_len(nrow(a)), function(i) trace(a$receiver_cell[i], a$lake_objectid[i]))
res <- data.frame(lake_objectid = a$lake_objectid,
                  source_cell = a$source_cell, receiver_cell = a$receiver_cell,
                  status = vapply(out, `[[`, "", 1),
                  end_cell = as.integer(vapply(out, `[[`, "", 2)),
                  steps = as.integer(vapply(out, `[[`, "", 3)))
cat("=== ROUTE TERMINALS ===\n")
print(table(res$status))
cat("=== NONRETURN ROUTES ===\n")
print(res[res$status != "RETURN_TO_SOURCE_LAKE", , drop = FALSE], row.names = FALSE)
terminals <- unique(res$end_cell[res$status == "TERMINAL_0"])
cat("TERMINAL_0_DISTINCT", length(terminals),
    "IN_02C_CANDIDATE_TABLE", sum(terminals %in% zc$cell), "\n")
cat("NOTE: 02C is only an adjacent-land candidate table, not every D8 zero cell.\n")
cat("NOTE: classification, routing, and provenance remain REVIEW_REQUIRED; no acceptance inferred.\n")
cat("NATIONAL_LOCKED TRUE\n")
