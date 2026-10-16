# LOW 1847 / 1898: pure base-R checks for original raster vs vector replay.
# Classification only; no hydrology changes or raster writes.
low_touch_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(message, call. = FALSE)
}
low_touch_replay_summary <- function(raster_id, replay_touch, replay_center,
                                     edges, lake_id, expected) {
  low_touch_require(is.matrix(raster_id) && is.matrix(replay_touch) &&
    is.matrix(replay_center) && identical(dim(raster_id), dim(replay_touch)) &&
    identical(dim(raster_id), dim(replay_center)), 'BAD_REPLAY_MATRIX_GEOMETRY')
  low_touch_require(is.data.frame(edges) &&
    all(c('lake_objectid','source_cell','receiver_cell','receiver_pointer') %in%
      names(edges)), 'BAD_REPLAY_EDGE_SCHEMA')
  low_touch_require(length(lake_id)==1L && lake_id %in% c(1847L,1898L) &&
    length(expected)==3L && all(expected >= 0L), 'BAD_REPLAY_EXPECTATIONS')
  n <- length(raster_id)
  low_touch_require(!anyNA(edges$source_cell) &&
    !anyNA(edges$receiver_cell) && !anyNA(edges$lake_objectid) &&
    all(edges$lake_objectid==lake_id) &&
    !anyDuplicated(edges$source_cell) &&
    all(edges$source_cell >= 1L & edges$source_cell <= n) &&
    all(edges$receiver_cell >= 1L & edges$receiver_cell <= n),
    'INVALID_LAKE_TO_LAND_SOURCE_OR_RECEIVER')
  orig <- as.vector(t(raster_id)) == lake_id
  touch <- as.vector(t(replay_touch)) == lake_id
  center <- as.vector(t(replay_center)) == lake_id
  orig[is.na(orig)] <- FALSE
  touch[is.na(touch)] <- FALSE
  center[is.na(center)] <- FALSE
  # Replay with touches=FALSE must be a subset of touches=TRUE.
  low_touch_require(all(!center | touch), 'CENTER_NOT_SUBSET_OF_ALL_TOUCHED')
  zero <- !is.na(edges$receiver_pointer) & edges$receiver_pointer==0L
  low_touch_require(nrow(edges)==expected[1L] && sum(zero)==expected[2L] &&
    length(unique(edges$receiver_cell[zero]))==expected[3L],
    'WRONG_LOCKED_LOW_D8_COUNTS')
  low_touch_require(all(orig[edges$source_cell]) &&
    all(!orig[edges$receiver_cell]), 'SOURCE_RECEIVER_RASTER_CLASSES_INVALID')
  stopifnot(!anyNA(edges$receiver_pointer))
  z_rec <- unique(edges$receiver_cell[zero])
  c(lake_id=lake_id,
    raster_id_pixels=sum(orig),
    touch_replay_pixels=sum(touch),
    center_replay_pixels=sum(center),
    original_pixels_not_touched_by_polygon=sum(orig & !touch),
    original_pixels_not_centered_in_polygon=sum(orig & !center),
    touched_polygon_pixels_not_target_raster=sum(touch & !orig),
    source_edge_count=nrow(edges),
    source_centers_inside_vector=sum(center[edges$source_cell]),
    source_footprints_touch_vector=sum(touch[edges$source_cell]),
    land_receiver_centers_inside_vector=sum(center[edges$receiver_cell]),
    land_receiver_footprints_touch_vector=sum(touch[edges$receiver_cell]),
    unique_zero_receivers=length(z_rec),
    zero_receiver_footprints_touch_vector=sum(touch[z_rec]))
}
