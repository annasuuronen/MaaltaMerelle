# Pure base-R, read-only analysis of 02C shoreline zero cells and their water neighbors.
# Whitebox D8 pointer direction from the WATER neighbor to the zero LAND cell.
# Do not interpret the 02C SAFE_LAKE_CONNECTOR classification as a D8 PASS.

low_d8_stop <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

low_02c_incoming <- function(zeros, neighbors, components, water_ptr,
                             nrow_raster, ncol_raster, tol = 1e-7) {
  required <- list(
    zeros = c('cell', 'component_id', 'z_m'),
    neighbors = c('component_id', 'source_cell', 'water_cell', 'water_class',
                  'lake_objectid', 'water_z_m'),
    components = c('component_id', 'connector_status', 'n_zero_cells')
  )
  data <- list(zeros = zeros, neighbors = neighbors, components = components)
  for (name in names(required)) {
    low_d8_stop(is.data.frame(data[[name]]) &&
                  all(required[[name]] %in% names(data[[name]])),
                paste('BAD_SCHEMA', name))
  }
  low_d8_stop(is.numeric(nrow_raster) && length(nrow_raster) == 1L &&
                is.finite(nrow_raster) && nrow_raster == floor(nrow_raster) &&
                nrow_raster >= 3L && is.numeric(ncol_raster) &&
                length(ncol_raster) == 1L && is.finite(ncol_raster) &&
                ncol_raster == floor(ncol_raster) && ncol_raster >= 3L &&
                is.finite(nrow_raster * ncol_raster) &&
                nrow_raster * ncol_raster <= .Machine$integer.max,
              'BAD_RASTER_SHAPE')
  low_d8_stop(is.numeric(tol) && length(tol) == 1L && is.finite(tol) && tol >= 0,
              'BAD_TOLERANCE')
  zc <- suppressWarnings(as.integer(as.character(zeros$cell)))
  zcomp <- suppressWarnings(as.integer(as.character(zeros$component_id)))
  nz <- nrow(zeros)
  low_d8_stop(nz > 0 && !anyNA(zc) && !anyDuplicated(zc) &&
                all(zc >= 1L & zc <= nrow_raster * ncol_raster) &&
                all(zcomp >= 1L & !is.na(zcomp)), 'BAD_ZERO_CELLS')
  zval <- suppressWarnings(as.numeric(as.character(zeros$z_m)))
  low_d8_stop(!anyNA(zval) && all(is.finite(zval)), 'BAD_ZERO_HEIGHTS')
  ci <- suppressWarnings(as.integer(as.character(components$component_id)))
  cn <- suppressWarnings(as.integer(as.character(components$n_zero_cells)))
  low_d8_stop(nrow(components) > 0 && !anyNA(ci) && !anyDuplicated(ci) &&
                !anyNA(cn) && all(cn >= 1L) &&
                !anyNA(components$connector_status) &&
                all(nzchar(as.character(components$connector_status))) &&
                setequal(ci, zcomp), 'BAD_COMPONENT_CLASSIFICATION')
  low_d8_stop(all(tabulate(match(zcomp, ci), nbins = length(ci)) == cn),
              'COMPONENT_SIZE_MISMATCH')
  src <- suppressWarnings(as.integer(as.character(neighbors$source_cell)))
  water <- suppressWarnings(as.integer(as.character(neighbors$water_cell)))
  wcomp <- suppressWarnings(as.integer(as.character(neighbors$component_id)))
  wcls <- suppressWarnings(as.integer(as.character(neighbors$water_class)))
  wz <- suppressWarnings(as.numeric(as.character(neighbors$water_z_m)))
  low_d8_stop(length(src) > 0L && !anyNA(src) && !anyNA(water) &&
                all(water >= 1L & water <= nrow_raster * ncol_raster) &&
                !anyNA(wcomp) && !anyNA(wcls) &&
                all(wcls %in% c(1L, 2L, 3L)) &&
                all(is.finite(wz)), 'BAD_WATER_NEIGHBORS')
  source_index <- match(src, zc)
  low_d8_stop(!anyNA(source_index) && all(wcomp == zcomp[source_index]) &&
                !anyDuplicated(paste(src, water, sep = ':')),
              'WATER_NEIGHBOR_SOURCE_MISMATCH_OR_DUPLICATE')
  # Rows/columns from 1-based terra cell ordering; guards avoid wraparound.
  src_row <- (src - 1L) %/% ncol_raster + 1L
  src_col <- (src - 1L) %% ncol_raster + 1L
  w_row <- (water - 1L) %/% ncol_raster + 1L
  w_col <- (water - 1L) %% ncol_raster + 1L
  dr <- src_row - w_row
  dc <- src_col - w_col
  low_d8_stop(all(abs(dr) <= 1L & abs(dc) <= 1L &
                    !(dr == 0L & dc == 0L)), 'NON_ADJACENT_WATER_EDGE')
  dirs <- matrix(c(64L, 128L, 1L, 32L, NA_integer_, 2L,
                   16L, 8L, 4L), nrow = 3L, byrow = TRUE)
  expected <- dirs[cbind(dr + 2L, dc + 2L)]
  low_d8_stop(is.numeric(water_ptr) && !is.null(names(water_ptr)) &&
                !anyDuplicated(names(water_ptr)) &&
                all(as.character(unique(water)) %in% names(water_ptr)),
              'MISSING_OR_DUPLICATE_WATER_POINTERS')
  ptr <- unname(water_ptr[as.character(water)])
  low_d8_stop(all(is.na(ptr) | (is.finite(ptr) & ptr %in%
                    c(0, 1, 2, 4, 8, 16, 32, 64, 128))),
              'INVALID_WATER_D8_VALUE')
  incoming <- !is.na(ptr) & ptr == expected
  lake_in <- incoming & wcls == 1L
  river_in <- incoming & wcls %in% c(2L, 3L)
  lkid <- suppressWarnings(as.integer(as.character(neighbors$lake_objectid)))
  low_d8_stop(all(!is.na(lkid[wcls == 1L]) & lkid[wcls == 1L] > 0L),
              'MISSING_LAKE_ID')
  lake_edges <- tabulate(source_index[lake_in], nbins = nz)
  river_edges <- tabulate(source_index[river_in], nbins = nz)
  water_min <- rep(NA_real_, nz)
  for (i in split(seq_along(src), source_index)) {
    ii <- source_index[i[1L]]
    water_min[ii] <- min(wz[i])
  }
  low_d8_stop(all(is.finite(water_min)), 'ZERO_WITHOUT_WATER_NEIGHBOR')
  dz <- zval - water_min
  elev <- ifelse(dz < -tol, 'BELOW', ifelse(dz > tol, 'ABOVE', 'SAME'))
  status <- as.character(components$connector_status[match(zcomp, ci)])
  data.frame(
    cell = zc, component_id = zcomp, connector_status = status,
    elevation_class = elev,
    n_incoming_lake_edges = lake_edges,
    n_incoming_river_edges = river_edges,
    has_incoming_lake_D8 = lake_edges > 0L,
    stringsAsFactors = FALSE
  )
}
