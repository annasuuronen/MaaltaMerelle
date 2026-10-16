# Bounded, isolated single-pit search model; NOT Whitebox, a fill, or routing.
# Matrix windows are observations. Their boundaries are ALWAYS censoring limits.
probe_fill_hypotheses <- function(surface, lake_ids, targets, max_visits = 10000L) {
  if (!is.matrix(surface) || !is.numeric(surface) || !is.matrix(lake_ids) ||
      !is.numeric(lake_ids) || !identical(dim(surface), dim(lake_ids)) ||
      length(surface) > 250000L || min(dim(surface)) < 3L) stop("Invalid bounded matrix window.")
  if (length(max_visits) != 1L || !is.finite(max_visits) || max_visits < 1 ||
      max_visits > 20000 || max_visits != floor(max_visits)) stop("Invalid search budget.")
  if (!is.data.frame(targets) || !all(c("lake_objectid", "n_lake_cells") %in% names(targets)) ||
      nrow(targets) < 1L || nrow(targets) > 158L || anyDuplicated(targets$lake_objectid) ||
      any(!is.finite(targets$lake_objectid)) || any(targets$lake_objectid <= 0) ||
      any(targets$lake_objectid != floor(targets$lake_objectid)) ||
      any(!is.finite(targets$n_lake_cells)) || any(targets$n_lake_cells < 1) ||
      any(targets$n_lake_cells != floor(targets$n_lake_cells))) stop("Invalid target coverage contract.")
  nr <- nrow(surface)
  nc <- ncol(surface)
  z <- as.vector(surface)
  ids <- as.vector(lake_ids)
  # Whitebox neighbour order, in matrix coordinates.
  dr <- c(-1, 0, 1, 1, 1, 0, -1, -1)
  dc <- c(1, 1, 1, 0, -1, -1, -1, 0)
  rc <- function(cell) c((cell - 1L) %% nr + 1L, (cell - 1L) %/% nr + 1L)
  neighbours <- function(cell) {
    p <- rc(cell)
    rr <- p[1] + dr
    cc <- p[2] + dc
    ok <- rr >= 1 & rr <= nr & cc >= 1 & cc <= nc
    as.integer(rr[ok] + (cc[ok] - 1L) * nr)
  }
  edge <- function(cell) {
    p <- rc(cell)
    p[1] %in% c(1L, nr) || p[2] %in% c(1L, nc)
  }
  remaining <- as.integer(max_visits)
  report <- list()
  for (id in targets$lake_objectid) {
    cells <- which(is.finite(ids) & ids == id)
    coverage <- length(cells) == targets$n_lake_cells[targets$lake_objectid == id]
    # Find every 8-connected part of this ID, never joining separated pieces.
    labels <- integer(length(z))
    parts <- list()
    for (start in cells) {
      if (labels[start] != 0L) next
      if (length(parts) >= 100L || length(report) + length(parts) >= 1000L) stop("Component report cap exceeded.")
      queue <- integer(length(cells))
      head <- 1L
      tail <- 1L
      queue[tail] <- start
      label <- length(parts) + 1L
      labels[start] <- label
      while (head <= tail) {
        cell <- queue[head]
        head <- head + 1L
        nb <- neighbours(cell)
        fresh <- nb[is.finite(ids[nb]) & ids[nb] == id & labels[nb] == 0L]
        if (length(fresh)) {
          labels[fresh] <- label
          queue[seq.int(tail + 1L, tail + length(fresh))] <- fresh
          tail <- tail + length(fresh)
        }
      }
      parts[[label]] <- queue[seq_len(tail)]
    }
    if (!length(parts)) parts <- list(integer())
    # Bound output cardinality for pathological checkerboard masks.
    if (length(parts) > 100L || length(report) + length(parts) > 1000L) stop("Component report cap exceeded.")
    for (part in seq_along(parts)) {
      piece <- parts[[part]]
      pits <- piece[vapply(piece, function(cell) {
        nb <- neighbours(cell)
        !edge(cell) && is.finite(z[cell]) && length(nb) == 8L &&
          all(is.finite(z[nb])) && all(z[nb] >= z[cell])
      }, FALSE)]
      found <- FALSE
      touched_edge <- any(vapply(piece, edge, FALSE))
      touched_nodata <- FALSE
      visited_count <- 0L
      capped <- FALSE
      witness_from <- witness_to <- NA_integer_
      seed <- if (length(pits)) pits[which.min(z[pits])] else NA_integer_
      if (coverage && length(pits) && all(is.finite(z[piece]))) {
        visited <- rep(FALSE, length(z))
        frontier <- seed
        visited[seed] <- TRUE
        while (length(frontier)) {
          if (remaining == 0L || visited_count >= 2000L) {
            capped <- TRUE
            break
          }
          pos <- which.min(z[frontier])
          cell <- frontier[pos]
          frontier <- frontier[-pos]
          visited_count <- visited_count + 1L
          remaining <- remaining - 1L
          touched_edge <- touched_edge || edge(cell)
          nb <- neighbours(cell)
          touched_nodata <- touched_nodata || any(!is.finite(z[nb]))
          for (next_cell in nb) {
            if (visited[next_cell] || !is.finite(z[next_cell])) next
            if (z[next_cell] < z[cell]) {
              found <- TRUE
              witness_from <- cell
              witness_to <- next_cell
              break
            }
            visited[next_cell] <- TRUE
            frontier <- c(frontier, next_cell)
          }
          if (found) break
        }
      }
      status <- if (!coverage || !length(piece)) "INCOMPLETE_TARGET_WINDOW" else
        if (any(!is.finite(z[piece]))) "NONFINITE_SOURCE_EVIDENCE" else
        if (!length(pits) && touched_edge) "CENSORED_NO_INTERIOR_PIT_CANDIDATE" else
        if (!length(pits)) "NO_EXACT_LOCAL_PIT_CANDIDATE" else
        if (capped || touched_edge) "CENSORED_LOCAL_SEARCH" else
        if (found) "LOWER_NEIGHBOUR_WITNESS_IN_ISOLATED_SEARCH" else
        "NO_LOWER_WITNESS_IN_EXPLORED_FINITE_COMPONENT"
      from <- if (found) rc(witness_from) else c(NA, NA)
      to <- if (found) rc(witness_to) else c(NA, NA)
      report[[length(report) + 1L]] <- data.frame(lake_objectid = id,
        window_mask_components = if (length(cells)) length(parts) else 0L,
        component_index = if (length(piece)) part else NA_integer_, component_cells = length(piece),
        full_id_cell_count_matches_report = coverage, exact_local_pit_candidates = length(pits),
        seed_row = if (length(pits)) rc(seed)[1] else NA,
        seed_col = if (length(pits)) rc(seed)[2] else NA,
        visited_cells = visited_count, visit_cap_reached = capped,
        search_touched_window_edge = touched_edge, search_contacted_nodata = touched_nodata,
        lower_neighbour_witness_found = found, witness_from_row = from[1], witness_from_col = from[2],
        witness_to_row = to[1], witness_to_col = to[2],
        witness_from_z = if (found) z[witness_from] else NA,
        witness_to_z = if (found) z[witness_to] else NA,
        witness_to_same_lake_id = if (found) is.finite(ids[witness_to]) && ids[witness_to] == id else NA,
        diagnostic_status = status, actual_whitebox_behaviour_verified = FALSE,
        natural_outlet_verified = FALSE, scientific_status = "REVIEW_REQUIRED",
        national_status = "LOCKED", stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, report)
}
