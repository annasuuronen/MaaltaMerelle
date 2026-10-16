# Read-only, pure base-R classification of actual lake->land D8 receiver evidence.
# Vector coverage is an independent descriptive comparison, not outlet approval.
mm_fail <- function(ok, reason) if (!isTRUE(ok)) stop(reason, call. = FALSE)

mm_shore_summary <- function(edges, src_ranta, src_mml, dst_ranta, dst_mml,
                             dest_dem, dest_raw, dest_fill, dest_land,
                             dest_storage, source_land, tol = 1e-7) {
  mm_fail(is.data.frame(edges) && all(c('source_cell','receiver_cell',
                  'receiver_pointer') %in% names(edges)) && nrow(edges)>0L,
          'BAD_EDGE_SCHEMA')
  n <- nrow(edges)
  flags <- list(src_ranta=src_ranta,src_mml=src_mml,
                dst_ranta=dst_ranta,dst_mml=dst_mml)
  mm_fail(all(vapply(flags,function(x) is.logical(x) && length(x)==n &&
                    !anyNA(x), logical(1))), 'BAD_VECTOR_CLASSIFICATION')
  zcols <- list(dest_dem=dest_dem,dest_raw=dest_raw,dest_fill=dest_fill,
                dest_land=dest_land,dest_storage=dest_storage,
                source_land=source_land)
  mm_fail(all(vapply(zcols,function(x) is.numeric(x) && length(x)==n &&
                    all(is.finite(x)), logical(1))), 'BAD_ELEVATION_VALUES')
  mm_fail(length(tol)==1L && is.finite(tol) && tol>=0L &&
            !anyNA(edges$source_cell) && !anyNA(edges$receiver_cell) &&
            !anyDuplicated(edges$source_cell) &&
            all(is.finite(edges$receiver_pointer)) &&
            all(edges$receiver_pointer %in% c(0,1,2,4,8,16,32,64,128)),
          'BAD_POINTERS_OR_TOLERANCE')
  zero <- edges$receiver_pointer==0L
  u_zero <- unique(edges$receiver_cell[zero])
  ix <- match(u_zero,edges$receiver_cell)
  mm_fail(!anyNA(ix), 'BAD_UNIQUE_RECEIVER_MAPPING')
  mm_fail(all(abs(dest_raw-dest_dem)<=tol), 'LAND_RAW_DIFFERENT_FROM_DEM')
  # All rows sharing a receiver must agree on its underlying raster values.
  for (col in c('dest_dem','dest_raw','dest_fill','dest_land','dest_storage')) {
    x <- zcols[[col]]
    mm_fail(all(abs(x-x[match(edges$receiver_cell,edges$receiver_cell)])<=tol),
            'INCONSISTENT_SHARED_RECEIVER')
  }
  dz <- source_land - dest_land
  list(
    edges=n, zero_edges=sum(zero), zero_receivers=length(u_zero),
    source_in_ranta_vector=sum(src_ranta),
    nonzero_edges=sum(!zero), source_in_mml=sum(src_mml),
    land_receivers_in_ranta_vector=sum(dst_ranta),
    land_receivers_in_mml=sum(dst_mml),
    zero_edges_to_mml_water=sum(zero & dst_mml),
    unique_zero_receivers_in_mml=sum(dst_mml[ix]),
    distinct_zero_raw_fill_unchanged=sum(abs(dest_raw[ix]-dest_fill[ix])<=tol),
    distinct_zero_storage_raised=sum(dest_storage[ix]-dest_land[ix]>tol),
    source_above_land_edges=sum(dz>tol),
    source_level_land_edges=sum(abs(dz)<=tol),
    source_below_land_edges=sum(dz< -tol),
    lake_minus_land_gap_m=range(dz),
    lake_minus_land_gap_median=median(dz)
  )
}
