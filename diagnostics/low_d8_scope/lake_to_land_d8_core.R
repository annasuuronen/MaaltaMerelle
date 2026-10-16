# Read-only Whitebox D8: enumerate LAKE -> LAND pointers in row chunks.
# This kernel uses base R, receives matrices with one-row halos, and writes nothing.
low_d8_lake_to_land_block <- function(p, w, id, read0, r0, r1, grid_rows) {
  stopifnot(is.matrix(p), is.matrix(w), is.matrix(id),
            identical(dim(p), dim(w)), identical(dim(p), dim(id)),
            length(read0) == 1L, length(r0) == 1L, length(r1) == 1L,
            length(grid_rows) == 1L,
            all(is.finite(c(read0, r0, r1, grid_rows))),
            all(c(read0, r0, r1, grid_rows) == floor(c(read0, r0, r1, grid_rows))),
            read0 >= 1L, r0 >= read0, r1 >= r0,
            r1 <= grid_rows, read0 + nrow(p) - 1L <= grid_rows,
            r1 <= read0 + nrow(p) - 1L, ncol(p) >= 3L)
  nc <- ncol(p)
  core <- seq.int(r0 - read0 + 1L, r1 - read0 + 1L)
  mids <- id[core, , drop = FALSE]
  mp <- p[core, , drop = FALSE]
  # Whitebox (not ESRI) codes: NE,E,SE,S,SW,W,NW,N.
  codes <- c(1L, 2L, 4L, 8L, 16L, 32L, 64L, 128L)
  dr <- c(-1L, 0L, 1L, 1L, 1L, 0L, -1L, -1L)
  dc <- c(1L, 1L, 1L, 0L, -1L, -1L, -1L, 0L)
  empty <- data.frame(lake_objectid = integer(), source_cell = integer(),
                      receiver_cell = integer(), receiver_pointer = numeric())
  ix <- which(!is.na(mids) & is.finite(mids) & mids > 0 &
                !is.na(mp) & mp %in% codes, arr.ind = TRUE)
  if (!nrow(ix)) return(empty)
  sr <- core[ix[, 1L]]; sc <- ix[, 2L]
  sl <- id[cbind(sr, sc)]; sp <- p[cbind(sr, sc)]
  wc <- w[cbind(sr, sc)]
  if (any(is.na(wc) | wc != 1L) ||
      any(sl != floor(sl) | sl > .Machine$integer.max))
    stop('INVALID_SOURCE_LAKE_WATER_CLASS_OR_ID', call. = FALSE)
  pieces <- vector('list', 8L)
  for (k in seq_along(codes)) {
    j <- which(sp == codes[k])
    if (!length(j)) next
    tr <- sr[j] + dr[k]; tc <- sc[j] + dc[k]
    gr <- tr + read0 - 1L
    inside <- gr >= 1L & gr <= grid_rows & tc >= 1L & tc <= nc
    if (!any(inside)) next
    j <- j[inside]; tr <- tr[inside]; tc <- tc[inside]
    if (any(tr < 1L | tr > nrow(p)))
      stop('MISSING_RECEIVER_HALO', call. = FALSE)
    at <- cbind(tr, tc)
    target_water <- w[at]
    if (any(is.na(target_water) & !is.na(id[at])))
      stop('LAND_TARGET_HAS_LAKE_ID', call. = FALSE)
    land <- is.na(target_water)
    if (!any(land)) next
    j <- j[land]; tr <- tr[land]; tc <- tc[land]
    src_global <- sr[j] + read0 - 1L
    target_global <- tr + read0 - 1L
    pieces[[k]] <- data.frame(
      lake_objectid = as.integer(sl[j]),
      source_cell = as.integer((as.double(src_global) - 1) * nc + sc[j]),
      receiver_cell = as.integer((as.double(target_global) - 1) * nc + tc),
      receiver_pointer = as.numeric(p[cbind(tr, tc)]))
  }
  parts <- Filter(Negate(is.null), pieces)
  if (!length(parts)) return(empty)
  out <- do.call(rbind, parts); rownames(out) <- NULL
  if (anyDuplicated(out$source_cell))
    stop('DUPLICATE_LAKE_SOURCE', call. = FALSE)
  out
}

low_d8_lake_to_land_summary <- function(edges, ids = NULL) {
  stopifnot(is.data.frame(edges),
            all(c('lake_objectid','source_cell','receiver_cell','receiver_pointer') %in%
                  names(edges)))
  if (nrow(edges) &&
      (anyNA(edges$lake_objectid) || any(edges$lake_objectid <= 0) ||
       anyNA(edges$source_cell) || anyNA(edges$receiver_cell) ||
       anyDuplicated(edges$source_cell) ||
       any(!is.na(edges$receiver_pointer) &
             (!is.finite(edges$receiver_pointer) |
                !edges$receiver_pointer %in% c(0, 1, 2, 4, 8, 16, 32, 64, 128)))))
    stop('BAD_LAKE_LAND_EDGES', call. = FALSE)
  if (is.null(ids)) ids <- sort(unique(edges$lake_objectid))
  ids <- as.integer(ids)
  stopifnot(!anyNA(ids), !anyDuplicated(ids), all(ids > 0L))
  columns <- lapply(ids, function(lid) {
    e <- edges[edges$lake_objectid == lid, , drop = FALSE]
    zero <- !is.na(e$receiver_pointer) & e$receiver_pointer == 0L
    n <- nrow(e)
    data.frame(lake_objectid = lid, lake_to_land_edges = n,
               immediate_zero_edges = sum(zero),
               nonzero_land_pointer_edges =
                 sum(!is.na(e$receiver_pointer) & e$receiver_pointer != 0L),
               na_land_pointer_edges = sum(is.na(e$receiver_pointer)),
               distinct_zero_cells = length(unique(e$receiver_cell[zero])),
               immediate_zero_fraction = if (n) sum(zero)/n else NA_real_)
  })
  if (!length(columns)) return(data.frame(
    lake_objectid = integer(), lake_to_land_edges = integer(),
    immediate_zero_edges = integer(), nonzero_land_pointer_edges = integer(),
    na_land_pointer_edges = integer(), distinct_zero_cells = integer(),
    immediate_zero_fraction = numeric()))
  out <- do.call(rbind, columns)
  rownames(out) <- NULL
  out
}
