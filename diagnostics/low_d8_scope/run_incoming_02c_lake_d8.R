# Read-only sparse (not full-raster) D8 validation for the 643 LOW 02C shoreline zero cells.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop('Usage: Rscript run_incoming_02c_lake_d8.R BASELINE_DIR')
source(file.path(dirname(normalizePath(sub('^--file=', '',
  grep('^--file=', commandArgs(), value = TRUE)[1L]), mustWork = TRUE)),
  'incoming_02c_lake_d8.R'))
suppressPackageStartupMessages(library(terra))
base <- normalizePath(args[1], mustWork = TRUE)
read_csv <- function(filename, required) {
  path <- file.path(base, filename)
  low_d8_stop(file.exists(path) && !dir.exists(path) &&
                !nzchar(Sys.readlink(path)) && file.info(path)$size <= 10000000L,
              paste('MISSING_OR_OVERSIZED_CSV', filename))
  x <- read.csv(path, stringsAsFactors = FALSE,
                na.strings = c('', 'NA'), check.names = FALSE)
  low_d8_stop(all(required %in% names(x)), paste('BAD_SCHEMA', filename))
  x
}
zeros <- read_csv('02C_zero_pointer_cells.csv', c('cell', 'component_id', 'z_m'))
neighbors <- read_csv('02C_zero_pointer_water_neighbors.csv',
                      c('component_id', 'source_cell', 'water_cell', 'water_class', 'lake_objectid', 'water_z_m'))
components <- read_csv('02C_shore_component_classification.csv',
                       c('component_id', 'connector_status', 'n_zero_cells'))
route <- read_csv('02F_water_connected_route_evidence.csv',
                  c('route_status', 'terminal_cell'))
zero_routes <- route[route$route_status == 'D8_ZERO_INTERIOR', , drop = FALSE]
known <- c(10007129L, 10031127L, 15389414L, 15401414L,
           23211319L, 23355315L, 23373314L)
low_d8_stop(nrow(zeros) == 643L && nrow(components) == 340L &&
              nrow(route) == 101L && nrow(zero_routes) == 41L &&
              setequal(unique(zero_routes$terminal_cell), known) &&
              all(known %in% zeros$cell), 'WRONG_LOW_EVIDENCE_SNAPSHOT')
pfile <- file.path(base, 'd8_pointer_land_water_FLT8S.tif')
low_d8_stop(file.exists(pfile) && !nzchar(Sys.readlink(pfile)), 'D8_RASTER_MISSING')
p <- rast(pfile)
low_d8_stop(nlyr(p) == 1L && nrow(p) > 10L && ncol(p) > 10L &&
              ncell(p) < .Machine$integer.max, 'WRONG_D8_GRID')
unique_water <- sort(unique(as.integer(neighbors$water_cell)))
low_d8_stop(!anyNA(unique_water) && length(unique_water) <= 12000L &&
              all(unique_water >= 1L & unique_water <= ncell(p)),
              'WATER_READ_SET_TOO_LARGE_OR_INVALID')
# Sparse raster cell reads. Group near-by columns in each row, never full raster.
read_sparse <- function(p, cells, gap = 16L) {
  nr <- nrow(p); nc <- ncol(p)
  row <- (cells - 1L) %/% nc + 1L
  col <- (cells - 1L) %% nc + 1L
  out <- numeric(length(cells))
  spans <- split(seq_along(cells), row)
  total_cells_read <- 0L
  calls <- 0L
  for (indices in spans) {
    ix <- indices[order(col[indices])]
    groups <- cumsum(c(1L, as.integer(diff(col[ix]) > gap)))
    for (part in split(ix, groups)) {
      lo <- min(col[part]); hi <- max(col[part]); count <- hi - lo + 1L
      total_cells_read <- total_cells_read + count
      calls <- calls + 1L
      low_d8_stop(total_cells_read <= 500000L && calls <= 5000L,
                  'RASTER_READ_BUDGET_EXCEEDED')
      data <- as.numeric(values(p, mat = FALSE, row = row[part[1L]],
                                nrows = 1L, col = lo, ncols = count))
      low_d8_stop(length(data) == count, 'RASTER_READ_LENGTH_MISMATCH')
      out[part] <- data[col[part] - lo + 1L]
    }
  }
  cat('SPARSE_RASTER_CELLS_READ:', total_cells_read, 'RASTER_WINDOWS:', calls, '\n')
  stats::setNames(out, as.character(cells))
}
ptr <- read_sparse(p, unique_water)
detail <- low_02c_incoming(zeros, neighbors, components, ptr, nrow(p), ncol(p),
                           detail = TRUE)
result <- detail$zero_cells
per_lake <- low_02c_summarize_by_lake(detail)
by_status <- split(result, result$connector_status)
cat('========== LOW: 643 SHORELINE ZERO CELLS / INCOMING WATER D8 ==========', '\n')
for (status in sort(names(by_status))) {
  d <- by_status[[status]]
  cat('CLASS', status,
      'ZERO_CELLS', nrow(d),
      'BELOW_WATER_MIN', sum(d$elevation_class == 'BELOW'),
      'SAME_LEVEL', sum(d$elevation_class == 'SAME'),
      'ABOVE', sum(d$elevation_class == 'ABOVE'),
      'CELLS_WITH_INCOMING_LAKE_D8', sum(d$has_incoming_lake_D8),
      'INCOMING_LAKE_D8_EDGES', sum(d$n_incoming_lake_edges),
      'CELLS_WITH_INCOMING_RIVER_D8', sum(d$n_incoming_river_edges > 0L), '\n')
}
cat('TOTAL_ZERO_CELLS:', nrow(result), '\n')
cat('ALL_INCOMING_LAKE_ZERO_CELLS:', sum(result$has_incoming_lake_D8), '\n')
cat('ALL_INCOMING_LAKE_D8_EDGES:', sum(result$n_incoming_lake_edges), '\n')
for (id in known) {
  z <- result[result$cell == id, , drop = FALSE]
  low_d8_stop(nrow(z) == 1L, 'MISSING_KNOWN_TERMINAL')
  cat('KNOWN_02F_ZERO', id, 'LAKE_EDGES', z$n_incoming_lake_edges,
      'COMPONENT_CLASS', z$connector_status, '\n')
}
actual <- result$n_incoming_lake_edges[match(known, result$cell)]
low_d8_stop(identical(as.integer(actual), c(1L, 1L, 3L, 1L, 2L, 1L, 1L)),
            'KNOWN_SEVEN_D8_EDGES_NOT_REPRODUCED')
cat('PASS: ALL 7 KNOWN 02F TERMINALS REPRODUCED; 10 INCOMING LAKE D8 POINTERS', '\n')
cat('========== LOW: SOURCE LAKE BREAKDOWN (READ ONLY) ==========', '\n')
cat('DISTINCT_SOURCE_LAKE_IDS:', per_lake$n_lakes, '\n')
cat('UNIQUE_LAKE_TO_ZERO_TERMINALS:', per_lake$unique_zero_cells, '\n')
cat('LAKE_TO_ZERO_D8_EDGES:', per_lake$d8_edges, '\n')
cat('PER_LAKE_ZERO_COUNT_SUM:', per_lake$per_lake_zero_sum, '\n')
cat('ZERO_CELLS_REACHED_FROM_MULTIPLE_LAKES:',
    per_lake$zero_cells_with_multiple_lakes, '\n')
low_d8_stop(per_lake$unique_zero_cells == 535L &&
              per_lake$d8_edges == 1273L &&
              sum(per_lake$lakes$d8_edges) == 1273L,
            'LOW_LAKE_TOTALS_DIFFER_FROM_VALIDATED_02C')
# The seven previously observed 02F terminal cells and their source lake IDs.
# This does not impose expected lake-wide totals for any lake.
expected_known_lake <- c(3181L, 3181L, 3181L, 3181L,
                         1892L, 1894L, 1894L)
for (i in seq_along(known)) {
  a <- per_lake$edges[per_lake$edges$zero_cell == known[i], , drop = FALSE]
  low_d8_stop(nrow(a) > 0L && all(a$lake_objectid == expected_known_lake[i]),
              'KNOWN_02F_LAKE_ID_NOT_REPRODUCED')
}
count_bins <- c('ONE' = sum(per_lake$lakes$zero_cells == 1L),
                'TWO_TO_FOUR' = sum(per_lake$lakes$zero_cells >= 2L &
                                    per_lake$lakes$zero_cells <= 4L),
                'FIVE_TO_NINE' = sum(per_lake$lakes$zero_cells >= 5L &
                                    per_lake$lakes$zero_cells <= 9L),
                'TEN_OR_MORE' = sum(per_lake$lakes$zero_cells >= 10L))
for (bin in names(count_bins)) cat('LAKES_WITH_ZERO_CELLS', bin, count_bins[[bin]], '\n')
ranking <- per_lake$lakes[order(-per_lake$lakes$zero_cells,
                                -per_lake$lakes$d8_edges,
                                per_lake$lakes$lake_objectid), , drop = FALSE]
cat('========== TOP SOURCE LAKES: distinct zero cells, then D8 edges ==========', '\n')
print(utils::head(ranking, 20L), row.names = FALSE)
cat('========== KNOWN LOW 02F ORIGIN LAKES ==========', '\n')
print(per_lake$lakes[per_lake$lakes$lake_objectid %in%
                       c(3181L, 1892L, 1894L), , drop = FALSE], row.names = FALSE)
cat('PASS: LAKE-BY-LAKE TOTALS AND 7 KNOWN TERMINAL SOURCE LAKES RECONCILED', '\n')
cat('SCOPE: 02C WATER-ADJACENT ZEROS ONLY; NOT A FULL LOW D8 SCAN', '\n')
cat('SCIENTIFIC_STATUS: REVIEW_REQUIRED; NO DEM D8 OUTLET MODIFICATIONS', '\n')
cat('========== READ-ONLY D8 SCOPE DONE ==========', '\n')
