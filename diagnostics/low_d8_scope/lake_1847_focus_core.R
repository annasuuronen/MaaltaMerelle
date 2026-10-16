# Read-only core for LOW RANTA10 lake 1847. Whitebox D8, not ESRI.
# No sampling or outlet substitution; failures are explicit.
l1847_assert <- function(x, msg) if (!isTRUE(x)) stop(msg, call. = FALSE)

l1847_global_cell <- function(local, first_row, first_col, window_cols, grid_cols) {
  l1847_assert(all(is.finite(local)) && all(local >= 1L) &&
                 all(local == floor(local)) && window_cols > 0 && grid_cols > 0,
               'BAD_LOCAL_CELLS')
  as.integer((first_row - 1L + (local - 1L) %/% window_cols) *
               as.double(grid_cols) + first_col + (local - 1L) %% window_cols)
}

l1847_mat_values <- function(m, local) {
  rr <- (local - 1L) %/% ncol(m) + 1L
  cc <- (local - 1L) %% ncol(m) + 1L
  m[cbind(rr, cc)]
}

l1847_summary <- function(edges, p, w, land, storage, raw, filled, expected=TRUE) {
  req <- c('lake_objectid','source_cell','receiver_cell','receiver_pointer')
  l1847_assert(is.data.frame(edges) && all(req %in% names(edges)), 'BAD_EDGES')
  l1847_assert(all(vapply(list(p,w,land,storage,raw,filled),is.matrix,logical(1))) &&
                 all(vapply(list(w,land,storage,raw,filled),function(x) identical(dim(x),dim(p)),logical(1))),
               'BAD_WINDOW_SHAPE')
  n <- nrow(p)*ncol(p)
  l1847_assert(nrow(edges)>0L && !anyNA(edges$source_cell) &&
                 !anyNA(edges$receiver_cell) &&
                 all(edges$lake_objectid == 1847L) &&
                 all(edges$source_cell >= 1L & edges$source_cell <= n) &&
                 all(edges$receiver_cell >= 1L & edges$receiver_cell <= n) &&
                 !anyDuplicated(edges$source_cell), 'BAD_LAKE_1847_EDGES')
  target <- edges$receiver_cell
  source <- edges$source_cell
  l1847_assert(all(l1847_mat_values(w,source)==1L & is.na(l1847_mat_values(w,target))), 'BAD_LAKE_TO_LAND_CLASSES')
  l1847_assert(all(is.na(l1847_mat_values(raw,source)) & is.na(l1847_mat_values(filled,source))), 'LAKE_MASK_NOT_APPLIED')
  l1847_assert(all(is.finite(l1847_mat_values(land,source)) & is.finite(l1847_mat_values(land,target)) &
                   is.finite(l1847_mat_values(raw,target)) & is.finite(l1847_mat_values(filled,target)) &
                   is.finite(l1847_mat_values(storage,target))), 'NONFINITE_1847_ELEVATIONS')
  lp <- l1847_mat_values(p,target)
  l1847_assert(all(!is.na(lp) & lp == edges$receiver_pointer), 'BAD_RECEIVER_POINTER')
  z <- which(lp == 0L)
  keep <- which(lp != 0L)
  n_distinct <- length(unique(target[z]))
  if (expected) l1847_assert(nrow(edges)==198L && length(z)==197L &&
                               length(keep)==1L && n_distinct==88L,
                             'WRONG_LAKE_1847_SNAPSHOT_OR_WINDOW')
  l1847_assert(length(z)>0L && length(keep)>0L, 'MISSING_ZERO_OR_CONTINUING_EDGES')
  unique_z <- unique(target[z])
  zraw <- l1847_mat_values(raw,unique_z); zfill <- l1847_mat_values(filled,unique_z)
  gap <- as.numeric(l1847_mat_values(land,source) - l1847_mat_values(land,target))
  change <- as.numeric(l1847_mat_values(storage,unique_z) - l1847_mat_values(land,unique_z))
  list(total=nrow(edges), zero_edges=length(z), continuing_edges=length(keep),
       unique_zero=n_distinct,
       distinct_zero_raw_fill_unchanged=sum(abs(zfill-zraw)<=1e-7),
       distinct_zero_raw_fill_changed=sum(abs(zfill-zraw)>1e-7),
       distinct_zero_storage_raised=sum(change>1e-7),
       distinct_zero_storage_equal=sum(abs(change)<=1e-7),
       source_above_receiver=sum(gap>1e-7), source_same_receiver=sum(abs(gap)<=1e-7),
       source_below_receiver=sum(gap< -1e-7),
       gap_range=range(gap), gap_median=median(gap),
       continuing_source=as.integer(source[keep]),
       continuing_receiver=as.integer(target[keep]),
       continuing_pointer=as.integer(lp[keep]),
       continuing_source_z=as.numeric(l1847_mat_values(land,source[keep])),
       continuing_receiver_z=as.numeric(l1847_mat_values(land,target[keep])))
}

# Follow only the single nonzero-receiver path. Bounded sparse lookups outside
# the lake window. A water hit or domain exit is evidence, not an approved outlet.
l1847_trace <- function(start, nr, nc, read_cell, max_steps=128L) {
  l1847_assert(length(start)==1L && is.finite(start) && start>=1L &&
                 start<=nr*nc && max_steps>=1L && max_steps<=256L &&
                 is.function(read_cell), 'BAD_TRACE_ARGUMENTS')
  codes <- c(1L,2L,4L,8L,16L,32L,64L,128L)
  dr <- c(-1L,0L,1L,1L,1L,0L,-1L,-1L)
  dc <- c(1L,1L,1L,0L,-1L,-1L,-1L,0L)
  current <- as.integer(start)
  seen <- integer(0)
  for (steps in 0:max_steps) {
    if (current %in% seen) return(list(status='CYCLE',cell=current,steps=steps,lake_id=NA_integer_))
    seen <- c(seen,current)
    a <- read_cell(current)
    l1847_assert(length(a$pointer)==1L && length(a$water_class)==1L &&
                   length(a$lake_id)==1L, 'BAD_TRACE_CELL_READ')
    if (!is.na(a$water_class)) return(list(status='REACHES_WATER_CLASS',
                                           cell=current,steps=steps,lake_id=a$lake_id))
    p <- a$pointer
    if (is.na(p)) return(list(status='POINTER_NA',cell=current,steps=steps,lake_id=NA_integer_))
    if (p==0) return(list(status='D8_ZERO',cell=current,steps=steps,lake_id=NA_integer_))
    k <- match(p,codes)
    if (is.na(k)) return(list(status='INVALID_POINTER',cell=current,steps=steps,lake_id=NA_integer_))
    if (steps==max_steps) return(list(status='MAX_STEPS',cell=current,steps=steps,lake_id=NA_integer_))
    row <- (current-1L)%/%nc+1L; col <- (current-1L)%%nc+1L
    row <- row+dr[k]; col <- col+dc[k]
    if (row<1L || row>nr || col<1L || col>nc)
      return(list(status='DOMAIN_EXIT',cell=current,steps=steps,lake_id=NA_integer_))
    current <- as.integer((row-1L)*nc+col)
  }
  stop('UNEXPECTED_TRACE_EXIT')
}
