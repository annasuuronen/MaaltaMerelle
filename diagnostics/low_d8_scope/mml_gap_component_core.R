# LOW MML/RANTA10 gap: read-only, pure base-R 8-neighbour components of
# DISTINCT zero receivers. This is not a polygon component or a flow path.
gap_assert <- function(ok, msg) {
  if (!isTRUE(ok)) stop(msg, call. = FALSE)
}

gap_zero_components <- function(cells, raster_nrow, raster_ncol) {
  gap_assert(length(raster_nrow) == 1L && length(raster_ncol) == 1L &&
    all(is.finite(c(raster_nrow, raster_ncol))) &&
    raster_nrow > 2L && raster_ncol > 2L &&
    raster_nrow * as.double(raster_ncol) < .Machine$integer.max,
    'INVALID_RASTER_SHAPE')
  gap_assert(is.numeric(cells) && length(cells) >= 1L &&
    !anyNA(cells) && all(is.finite(cells)) &&
    all(cells == floor(cells)) &&
    all(cells >= 1L & cells <= raster_nrow * as.double(raster_ncol)) &&
    !anyDuplicated(cells), 'INVALID_ZERO_RECEIVER_SET')
  cells <- sort(as.integer(cells))
  row <- (cells - 1L) %/% raster_ncol + 1L
  col <- (cells - 1L) %% raster_ncol + 1L
  index <- setNames(seq_along(cells), as.character(cells))
  component <- integer(length(cells))
  dr <- rep(-1L:1L, each = 3L)
  dc <- rep(-1L:1L, times = 3L)
  valid <- dr != 0L | dc != 0L
  dr <- dr[valid]; dc <- dc[valid]
  group <- 0L
  for (start in seq_along(cells)) {
    if (component[start] != 0L) next
    group <- group + 1L
    component[start] <- group
    q <- start; head <- 1L
    while (head <= length(q)) {
      i <- q[head]; head <- head + 1L
      nr <- row[i] + dr; nc <- col[i] + dc
      mask <- nr >= 1L & nr <= raster_nrow & nc >= 1L & nc <= raster_ncol
      if (!any(mask)) next
      candidate <- as.character(as.integer((nr[mask] - 1L) * raster_ncol + nc[mask]))
      j <- unname(index[candidate]); j <- j[!is.na(j)]
      j <- j[component[j] == 0L]
      if (length(j)) {
        component[j] <- group
        q <- c(q, j)
      }
    }
  }
  gap_assert(all(component > 0L), 'UNLABELLED_ZERO_RECEIVER')
  data.frame(cell = cells, row = row, col = col, component = component)
}

gap_component_counts <- function(labelled, edge_receivers) {
  gap_assert(is.data.frame(labelled) && all(c('cell','component') %in% names(labelled)) &&
    nrow(labelled) >= 1L && !anyDuplicated(labelled$cell) &&
    all(labelled$component > 0L) && is.numeric(edge_receivers) &&
    length(edge_receivers) >= nrow(labelled) && !anyNA(edge_receivers) &&
    all(edge_receivers %in% labelled$cell), 'BAD_COMPONENT_EDGES')
  mapping <- match(edge_receivers, labelled$cell)
  ids <- sort(unique(labelled$component))
  out <- data.frame(component = ids,
    zero_cells = tabulate(match(labelled$component, ids), nbins = length(ids)),
    incoming_zero_edges = tabulate(match(labelled$component[mapping], ids),
                                   nbins = length(ids)))
  gap_assert(sum(out$zero_cells) == nrow(labelled) &&
    sum(out$incoming_zero_edges) == length(edge_receivers), 'COMPONENT_RECONCILIATION_FAILED')
  out[order(-out$zero_cells, -out$incoming_zero_edges, out$component), , drop = FALSE]
}

# Validate the *actual* frozen 02E + 02F CSV schemas before any raster access.
# 02F route records use origin_lake_objectid, not lake_objectid.
gap_validate_02e_02f <- function(evidence, spill_edges, routes) {
  gap_assert(is.data.frame(evidence) && is.data.frame(spill_edges) &&
               is.data.frame(routes), '02E_02F_NOT_DATA_FRAMES')
  req_e <- c('lake_objectid','spill_group_id','candidate_included',
             'needs_review','outlet_selection')
  req_s <- c('lake_objectid','spill_group_id','source_cell','receiver_cell')
  req_f <- c('origin_lake_objectid','route_status','start_receiver_cell',
             'terminal_cell')
  gap_assert(all(req_e %in% names(evidence)),
             paste('02E_EVIDENCE_MISSING_COLUMNS:',
                   paste(setdiff(req_e, names(evidence)), collapse=',')))
  gap_assert(all(req_s %in% names(spill_edges)),
             paste('02E_SPILL_MISSING_COLUMNS:',
                   paste(setdiff(req_s, names(spill_edges)), collapse=',')))
  gap_assert(all(req_f %in% names(routes)),
             paste('02F_ROUTES_MISSING_COLUMNS:',
                   paste(setdiff(req_f, names(routes)), collapse=',')))
  gap_assert(is.logical(evidence$candidate_included) &&
               is.logical(evidence$needs_review) &&
               !anyNA(evidence$candidate_included) &&
               !anyNA(evidence$needs_review),
             '02E_BOOLEAN_FLAGS_INVALID')
  gap_assert(is.character(evidence$outlet_selection) &&
               !anyNA(evidence$outlet_selection) &&
               all(evidence$outlet_selection == 'UNASSIGNED'),
             '02E_OUTLET_SELECTION_NOT_UNASSIGNED')
  gap_assert(is.numeric(evidence$lake_objectid) &&
               is.numeric(evidence$spill_group_id) &&
               !anyNA(evidence$lake_objectid) &&
               !anyNA(evidence$spill_group_id) &&
               !anyDuplicated(evidence$spill_group_id),
             '02E_EVIDENCE_ID_INVALID')
  if (nrow(spill_edges)) {
    gap_assert(is.numeric(spill_edges$lake_objectid) &&
                 is.numeric(spill_edges$spill_group_id) &&
                 is.numeric(spill_edges$source_cell) &&
                 is.numeric(spill_edges$receiver_cell) &&
                 !anyNA(spill_edges[,req_s,drop=FALSE]),
               '02E_SPILL_ID_OR_CELLS_INVALID')
    matched <- match(spill_edges$spill_group_id,evidence$spill_group_id)
    gap_assert(!anyNA(matched) &&
               all(spill_edges$lake_objectid == evidence$lake_objectid[matched]) &&
               all(evidence$candidate_included[matched]),
               '02E_SPILL_EDGE_NOT_INCLUDED_OR_LAKE_MISMATCH')
  }
  if (nrow(routes)) {
    gap_assert(is.numeric(routes$origin_lake_objectid) &&
                 is.numeric(routes$start_receiver_cell) &&
                 is.numeric(routes$terminal_cell) &&
                 !anyNA(routes[,req_f,drop=FALSE]) &&
                 all(nzchar(routes$route_status)),
               '02F_ROUTE_VALUES_INVALID')
    gap_assert(nrow(spill_edges)>0L &&
                 all(paste(routes$origin_lake_objectid,
                           routes$start_receiver_cell) %in%
                     paste(spill_edges$lake_objectid,
                           spill_edges$receiver_cell)),
               '02F_ROUTES_NOT_LINKED_TO_02E_RECEIVERS')
  }
  invisible(TRUE)
}
