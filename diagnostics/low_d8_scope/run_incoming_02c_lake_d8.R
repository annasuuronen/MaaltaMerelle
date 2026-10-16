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
result <- low_02c_incoming(zeros, neighbors, components, ptr, nrow(p), ncol(p))
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
cat('SCOPE: 02C WATER-ADJACENT ZEROS ONLY; NOT A FULL LOW D8 SCAN', '\n')
cat('SCIENTIFIC_STATUS: REVIEW_REQUIRED; NO DEM D8 OUTLET MODIFICATIONS', '\n')
cat('========== READ-ONLY D8 SCOPE DONE ==========', '\n')
