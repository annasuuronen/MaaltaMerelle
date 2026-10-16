#!/usr/bin/env Rscript
# Targeted 52-lake geometry and NoData diagnostics, read only.
# Does not compute new STORAGE, redirect D8, or approve a lake outlet.
# Usage: Rscript scripts/audit_moderate_lake_geometry_readonly.R BASELINE_DIR LAKE_ID_TIF
suppressPackageStartupMessages(library(terra))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Expected: BASELINE_DIR LAKE_ID_TIF")
b <- normalizePath(args[[1]], mustWork = TRUE)
lpath <- normalizePath(args[[2]], mustWork = TRUE)
lake <- rast(lpath)
w <- rast(file.path(b, "routing_surface_land_water_FLT8S.tif"))
s <- rast(file.path(b, "routing_surface_water_storage_FLT8S.tif"))
stopifnot(compareGeom(lake, w, stopOnError = FALSE),
          compareGeom(w, s, stopOnError = FALSE))
q <- read.csv(file.path(b, "02D_lake_depression_component_summary.csv"))
ids <- as.integer(q$lake_objectid[q$depression_status == "SPILL_RAISED_NO_COMPONENT"])
stopifnot(length(ids) > 0L, !anyNA(ids), !anyDuplicated(ids))
# A single bounded-in-memory scan identifies the lake cells; not repeated per lake.
# 6000x6000 doubles are approximately 288 MB, run under Slurm rather than login.
all_ids <- values(lake, mat = FALSE)
source_cells <- which(!is.na(all_ids) & all_ids %in% ids)
tab <- table(as.integer(all_ids[source_cells]))
stopifnot(setequal(ids, as.integer(names(tab))))
rm(all_ids)
gc(verbose = FALSE)
# Obtain each cell ID in the actual raster cell order (not table-sort order).
source_ids <- as.integer(extract(lake, source_cells)[[2]])
stopifnot(length(source_cells) == length(source_ids), all(source_ids %in% ids),
          identical(as.integer(table(factor(source_ids, levels=ids))),\n                    as.integer(tab[as.character(ids)])))
# Each cell's neighboring cells, with 8-connectivity. At most 8 neighbours per
# selected lake cell, avoiding 36 million cells x 8 materialisation.
pairs <- adjacent(lake, cells = source_cells, directions = 8,
                  pairs = TRUE, include = FALSE)
stopifnot(ncol(pairs) == 2L)
pair_id <- source_ids[match(pairs[,1], source_cells)]
stopifnot(!anyNA(pair_id))
neighbor_id <- as.integer(extract(lake, pairs[,2])[[2]])
outside <- is.na(neighbor_id) | neighbor_id != pair_id
rim <- pairs[outside,,drop = FALSE]
rim_id <- pair_id[outside]
rm(pairs, pair_id, neighbor_id, outside)
gc(verbose = FALSE)
# Query the original and stored surfaces only at rim and target lake cells.
rim_w <- extract(w, rim[,2])[[2]]
rim_s <- extract(s, rim[,2])[[2]]
source_w <- extract(w, source_cells)[[2]]
source_s <- extract(s, source_cells)[[2]]
rc <- rowColFromCell(lake, source_cells)
edge <- rc[,1] == 1L | rc[,1] == nrow(lake) |
        rc[,2] == 1L | rc[,2] == ncol(lake)
cat("=== TARGETED MODERATE 52-LAKE GEOMETRY AUDIT ===\n")
cat("TARGET_LAKES", length(ids), "TARGET_CELLS", length(source_cells),
    "SHORE_PAIRS", nrow(rim), "\n")
cat("LAKE_ID_GEOMETRY", nrow(lake), "rows", ncol(lake), "cols", "\n")
report <- lapply(ids, function(id) {
  ix <- which(source_ids == id)
  jx <- which(rim_id == id)
  iz <- source_w[ix]
  is <- source_s[ix]
  rw <- rim_w[jx]
  rs <- rim_s[jx]
  nvalid <- sum(is.finite(iz) & is.finite(is))
  changed <- sum(is.finite(iz) & is.finite(is) & abs(is-iz) > 1e-7)
  data.frame(lake_objectid = id,
             lake_cells = length(ix), edge_lake_cells = sum(edge[ix]),
             external_shore_pairs = length(jx),
             shore_land_water_NA = sum(!is.finite(rw)),
             shore_storage_NA = sum(!is.finite(rs)),
             source_land_water_NA = sum(!is.finite(iz)),
             source_storage_NA = sum(!is.finite(is)),
             source_changed_gt_1e_7 = changed,
             lake_z_min = if (any(is.finite(iz))) min(iz[is.finite(iz)]) else NA_real_,
             lake_z_max = if (any(is.finite(iz))) max(iz[is.finite(iz)]) else NA_real_,
             shore_z_min = if (any(is.finite(rw))) min(rw[is.finite(rw)]) else NA_real_,
             shore_z_max = if (any(is.finite(rw))) max(rw[is.finite(rw)]) else NA_real_,
             finite_source_pair_count = nvalid)
})
result <- do.call(rbind, report)
stopifnot(nrow(result) == length(ids))
print(result, row.names = FALSE, digits = 10)
cat("=== CLASS COUNTS ===\n")
cat("TOUCHES_DOMAIN_EDGE", sum(result$edge_lake_cells > 0), "\n")
cat("HAS_NODATA_OUTSIDE_SHORE", sum(result$shore_land_water_NA > 0), "\n")
cat("NONCONSTANT_LAKE_Z", sum(result$lake_z_max - result$lake_z_min > 1e-7, na.rm=TRUE), "\n")
cat("HAS_CHANGED_SOURCE_STORAGE", sum(result$source_changed_gt_1e_7 > 0), "\n")
cat("NOTE: exterior-shore pair count includes possible repeated receiver cells.\n")
cat("NOTE: these are geometry diagnostics, not an exhaustive reachability or Whitebox fill validation.\n")
cat("SCIENTIFIC_STATUS REVIEW_REQUIRED\nNATIONAL_LOCKED TRUE\n")
