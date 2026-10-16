# Requires the read-only LOW 02C source-lake QA previously tested on CSC.
# Usage: Rscript --vanilla run_lake_shoreline_rates.R BASELINE_DIR
# No Slurm, raster changes, CSV writes, or replacement lake perimeter assumptions.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop('Usage: Rscript run_lake_shoreline_rates.R BASELINE_DIR')
script_arg <- grep('^--file=', commandArgs(), value = TRUE)
if (length(script_arg) != 1L) stop('Run using Rscript --vanilla')
d <- dirname(normalizePath(sub('^--file=', '', script_arg), mustWork = TRUE))
# Re-use the actual sparse D8 classification, edges and per-lake aggregation;
# source() in this environment retains per_lake, p, and base variables.
source(file.path(d, 'run_incoming_02c_lake_d8.R'), local = TRUE)
source(file.path(d, 'lake_shoreline_rates.R'), local = TRUE)
suppressPackageStartupMessages(library(sf))
# The locked study structure is root/hydro_01_02/runs/TILE/02_baseline.
tile_id <- basename(dirname(base))
root <- dirname(dirname(dirname(dirname(base))))
gpkg <- file.path(root, 'inputs', tile_id, paste0('RANTA10_', tile_id, '.gpkg'))
low_d8_stop(file.exists(gpkg) && !dir.exists(gpkg) && !nzchar(Sys.readlink(gpkg)),
            'RANTA10_GPKG_NOT_FOUND: no geometry-based rate calculated')
low_d8_stop('lakes' %in% sf::st_layers(gpkg)$name, 'RANTA10_LAKES_LAYER_MISSING')
ids <- sort(as.integer(per_lake$lakes$lake_objectid))
low_d8_stop(length(ids) == 22L && all(is.finite(ids) & ids > 0L),
            'WRONG_02C_SOURCE_LAKE_SET')
sql <- sprintf('SELECT * FROM lakes WHERE objectid IN (%s)',
               paste(ids, collapse = ','))
lakes <- sf::st_read(gpkg, query = sql, quiet = TRUE)
low_d8_stop(nrow(lakes) == length(ids) && 'objectid' %in% names(lakes) &&
              setequal(as.integer(lakes$objectid), ids),
            'MISSING_OR_DUPLICATE_RANTA10_LAKE_POLYGONS')
low_d8_stop(sf::st_crs(lakes)$epsg == 3067L &&
              sf::st_crs(terra::crs(p))$epsg == 3067L,
            'RANTA10_RASTER_VECTOR_CRS_MISMATCH')
rect <- c(xmin = terra::xmin(p), ymin = terra::ymin(p),
          xmax = terra::xmax(p), ymax = terra::ymax(p))
metrics <- low_02c_vector_shoreline(lakes, rect)
rates <- low_02c_shoreline_rates(per_lake$lakes, metrics)
low_d8_stop(nrow(rates) == 22L &&
              sum(rates$zero_cells) == 535L &&
              sum(rates$d8_edges) == 1273L &&
              sum(rates$touches_tile_edge) == sum(metrics$touches_tile_edge),
            'VECTOR_SOURCE_RECONCILIATION_FAILED')
cat('========== LOW: VECTOR SHORELINE NORMALIZATION (READ ONLY) ==========', '\n')
cat('LAKE_POLYGONS_CHECKED:', nrow(lakes), '\n')
cat('LAKES_TOUCHING_TILE_EDGE:', sum(rates$touches_tile_edge), '\n')
cat('LAKES_WITHOUT_INTERIOR_SHORELINE:', sum(is.na(rates$zero_cells_per_shore_km)), '\n')
cat('RATES_ARE_COUNTS_PER_RANTA10_VECTOR_SHORE_KM_WITHIN_TILE; NOT_ERROR_PROBABILITIES', '\n')
cat('TILE_EDGE_BORDER_SEGMENTS_EXCLUDED_FROM_LENGTH', '\n')
print(rates[order(-rates$zero_cells, -rates$d8_edges),
            c('lake_objectid', 'zero_cells', 'd8_edges', 'shoreline_km',
              'zero_cells_per_shore_km', 'd8_edges_per_shore_km',
              'touches_tile_edge', 'excluded_tile_border_m')],
      row.names = FALSE, digits = 5)
cat('SCIENTIFIC_STATUS: REVIEW_REQUIRED; NO D8 DEM OUTLET MODIFICATIONS', '\n')
cat('========== VECTOR SHORELINE CHECK DONE ==========', '\n')
