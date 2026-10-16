# Pure base-R, read-only analysis of 02C shoreline zero cells and their water neighbors.
# Whitebox D8 pointer direction from the WATER neighbor to the zero LAND cell.
# Do not interpret the 02C SAFE_LAKE_CONNECTOR classification as a D8 PASS.

low_d8_stop <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

low_02c_incoming <- function(zeros, neighbors, components, water_ptr,
                             nrow_raster, ncol_raster, tol = 1e-7, detail = FALSE) {
  low_d8_stop(is.logical(detail) && length(detail) == 1L && !is.na(detail),
              'BAD_DETAIL_FLAG')
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
  out <- data.frame(
    cell = zc, component_id = zcomp, connector_status = status,
    elevation_class = elev,
    n_incoming_lake_edges = lake_edges,
    n_incoming_river_edges = river_edges,
    has_incoming_lake_D8 = lake_edges > 0L,
    stringsAsFactors = FALSE
  )
  if (!detail) return(out)  # original interface remains unchanged
  # Only actual incoming water_class=1 pointers; no hypothetical shoreline links.
  li <- which(lake_in)
  edges <- data.frame(
    lake_objectid = lkid[li],
    lake_cell = water[li],
    zero_cell = src[li],
    component_id = zcomp[source_index[li]],
    connector_status = status[source_index[li]],
    elevation_class = elev[source_index[li]],
    stringsAsFactors = FALSE
  )
  low_d8_stop(nrow(edges) == sum(out$n_incoming_lake_edges) &&
                !anyDuplicated(paste(edges$zero_cell, edges$lake_cell, sep = ':')),
              'INCOMING_EDGE_RECONCILIATION_FAILED')
  list(zero_cells = out, lake_edges = edges)
}

# Zero cells receiving D8 from several lakes are counted once globally
# but once for each source lake; the overlap is reported explicitly.
low_02c_summarize_by_lake <- function(detail_result) {
  low_d8_stop(is.list(detail_result) &&
                all(c('zero_cells', 'lake_edges') %in% names(detail_result)),
              'BAD_DETAILED_RESULT')
  z <- detail_result$zero_cells
  e <- detail_result$lake_edges
  low_d8_stop(is.data.frame(z) && is.data.frame(e) &&
                all(c('cell', 'n_incoming_lake_edges') %in% names(z)) &&
                all(c('lake_objectid', 'lake_cell', 'zero_cell',
                      'connector_status', 'elevation_class') %in% names(e)),
              'BAD_LAKE_EDGE_SCHEMA')
  low_d8_stop(nrow(e) == sum(z$n_incoming_lake_edges) &&
                all(e$zero_cell %in% z$cell) &&
                !anyNA(e$lake_objectid) && all(e$lake_objectid > 0L) &&
                !anyDuplicated(paste(e$lake_cell, e$zero_cell, sep = ':')),
              'BAD_LAKE_EDGE_COUNTS')
  make_empty <- function() data.frame(
    lake_objectid = integer(), zero_cells = integer(), d8_edges = integer(),
    incoming_lake_cells = integer(), safe_zero_cells = integer(),
    below_water_min_zero_cells = integer(), stringsAsFactors = FALSE)
  if (nrow(e) == 0L) {
    return(list(lakes = make_empty(), edges = e,
                n_lakes = 0L, unique_zero_cells = 0L,
                d8_edges = 0L, zero_cells_with_multiple_lakes = 0L,
                per_lake_zero_sum = 0L))
  }
  lids <- sort(unique(e$lake_objectid))
  rows <- lapply(lids, function(id) {
    a <- e[e$lake_objectid == id, , drop = FALSE]
    data.frame(
      lake_objectid = as.integer(id),
      zero_cells = as.integer(length(unique(a$zero_cell))),
      d8_edges = as.integer(nrow(a)),
      incoming_lake_cells = as.integer(length(unique(a$lake_cell))),
      safe_zero_cells = as.integer(length(unique(a$zero_cell[
        a$connector_status == 'SAFE_LAKE_CONNECTOR']))),
      below_water_min_zero_cells = as.integer(length(unique(a$zero_cell[
        a$elevation_class == 'BELOW']))),
      stringsAsFactors = FALSE
    )
  })
  lakes <- do.call(rbind, rows)
  rownames(lakes) <- NULL
  pairs <- unique(e[, c('lake_objectid', 'zero_cell'), drop = FALSE])
  lake_count_per_zero <- table(pairs$zero_cell)
  n_multi <- sum(lake_count_per_zero > 1L)
  low_d8_stop(sum(lakes$d8_edges) == nrow(e) &&
                sum(lakes$zero_cells) == nrow(pairs) &&
                length(lake_count_per_zero) == sum(z$n_incoming_lake_edges > 0L),
              'LAKE_SUMMARY_RECONCILIATION_FAILED')
  list(lakes = lakes, edges = e,
       n_lakes = length(lids), unique_zero_cells = length(lake_count_per_zero),
       d8_edges = nrow(e), zero_cells_with_multiple_lakes = as.integer(n_multi),
       per_lake_zero_sum = nrow(pairs))
}
