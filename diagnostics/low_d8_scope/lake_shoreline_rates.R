# Read-only derived statistics for vector shoreline length within a LOW tile.
# The denominator is an observed RANTA10-vector shoreline length (km), NOT
# number of valid raster D8 lake cells, a true hydrological error probability,
# or a count of independent watersheds.
low_02c_shoreline_rates <- function(lake_counts, shore_metrics) {
  req_counts <- c('lake_objectid', 'zero_cells', 'd8_edges')
  req_shore <- c('lake_objectid', 'shoreline_m', 'touches_tile_edge',
                 'excluded_tile_border_m')
  if (!is.data.frame(lake_counts) || !is.data.frame(shore_metrics) ||
      !all(req_counts %in% names(lake_counts)) ||
      !all(req_shore %in% names(shore_metrics))) {
    stop('BAD_SHORELINE_SCHEMA', call. = FALSE)
  }
  id <- as.integer(as.character(lake_counts$lake_objectid))
  gid <- as.integer(as.character(shore_metrics$lake_objectid))
  nzero <- suppressWarnings(as.numeric(as.character(lake_counts$zero_cells)))
  edges <- suppressWarnings(as.numeric(as.character(lake_counts$d8_edges)))
  m <- suppressWarnings(as.numeric(as.character(shore_metrics$shoreline_m)))
  border <- suppressWarnings(as.numeric(as.character(shore_metrics$excluded_tile_border_m)))
  touch <- shore_metrics$touches_tile_edge
  if (length(id) == 0L || anyNA(id) || any(id <= 0L) || anyDuplicated(id) ||
      anyNA(gid) || any(gid <= 0L) || anyDuplicated(gid) ||
      !setequal(id, gid) || anyNA(nzero) || any(!is.finite(nzero)) ||
      any(nzero < 1 | nzero != floor(nzero)) ||
      anyNA(edges) || any(!is.finite(edges)) ||
      any(edges < nzero | edges != floor(edges)) ||
      anyNA(m) || any(!is.finite(m)) || any(m < 0) ||
      anyNA(border) || any(!is.finite(border)) || any(border < 0) ||
      !is.logical(touch) || anyNA(touch) ||
      any(border > 1e-7 & !touch)) {
    stop('INVALID_SHORELINE_METRICS', call. = FALSE)
  }
  ix <- match(id, gid)
  km <- m[ix] / 1000
  per_zero <- rep(NA_real_, length(id))
  per_edge <- rep(NA_real_, length(id))
  valid <- km > 0
  per_zero[valid] <- nzero[valid] / km[valid]
  per_edge[valid] <- edges[valid] / km[valid]
  lake_counts$shoreline_km <- km
  lake_counts$touches_tile_edge <- touch[ix]
  lake_counts$excluded_tile_border_m <- border[ix]
  lake_counts$zero_cells_per_shore_km <- per_zero
  lake_counts$d8_edges_per_shore_km <- per_edge
  lake_counts$shoreline_length_status <- ifelse(valid, 'VECTOR_LENGTH_WITHIN_TILE',
                                               'NO_INTERIOR_VECTOR_SHORELINE')
  lake_counts
}

# Independent vector-lake shoreline geometry inside a raster tile.
# Source lakes MUST be the same RANTA10 objectids already validated in 02C.
# Crucially, boundary(original lake polygon) intersect tile, rather than
# boundary(clipped lake polygon); subtract border-coincident artificial lines.
low_02c_vector_shoreline <- function(lakes_sf, extent, epsg = 3067L) {
  if (!inherits(lakes_sf, 'sf') || !'objectid' %in% names(lakes_sf) ||
      nrow(lakes_sf) == 0L ||
      !is.numeric(extent) || length(extent) != 4L ||
      !all(c('xmin', 'ymin', 'xmax', 'ymax') %in% names(extent)) ||
      !all(is.finite(extent)) || extent['xmax'] <= extent['xmin'] ||
      extent['ymax'] <= extent['ymin'] ||
      is.na(sf::st_crs(lakes_sf)) || sf::st_crs(lakes_sf)$epsg != epsg) {
    stop('INVALID_VECTOR_OR_TILE_GEOMETRY', call. = FALSE)
  }
  ids <- suppressWarnings(as.integer(as.character(lakes_sf$objectid)))
  if (anyNA(ids) || any(ids <= 0L) || anyDuplicated(ids) ||
      any(!sf::st_is_valid(lakes_sf)) || any(sf::st_is_empty(lakes_sf))) {
    stop('INVALID_LAKE_POLYGON', call. = FALSE)
  }
  bb <- sf::st_bbox(c(xmin = extent[['xmin']], ymin = extent[['ymin']],
                      xmax = extent[['xmax']], ymax = extent[['ymax']]),
                    crs = sf::st_crs(lakes_sf))
  tile <- sf::st_as_sfc(bb)
  border <- sf::st_boundary(tile)
  original_boundaries <- sf::st_boundary(sf::st_geometry(lakes_sf))
  # st_intersection() handles only the original shoreline segments within tile.
  within <- suppressWarnings(sf::st_intersection(original_boundaries, tile))
  # Per-feature intersections are essential: a group-level intersection
  # drops non-overlapping geometries, silently misaligning lake IDs and rates.
  excluded <- vapply(seq_along(within), function(i) {
    overlap <- suppressWarnings(sf::st_intersection(within[i], border))
    if (length(overlap) == 0L) return(0)
    sum(as.numeric(sf::st_length(overlap)))
  }, numeric(1))
  inner <- suppressWarnings(sf::st_difference(within, border))
  len <- as.numeric(sf::st_length(inner))
  touching <- lengths(sf::st_intersects(original_boundaries, border)) > 0L
  if (length(len) != nrow(lakes_sf) || length(excluded) != nrow(lakes_sf) ||
      anyNA(len) || any(!is.finite(len)) || any(len < 0) ||
      anyNA(excluded) || any(!is.finite(excluded)) || any(excluded < 0)) {
    stop('INVALID_VECTOR_LENGTHS', call. = FALSE)
  }
  data.frame(lake_objectid = ids, shoreline_m = len,
             touches_tile_edge = touching,
             excluded_tile_border_m = excluded,
             stringsAsFactors = FALSE)
}
