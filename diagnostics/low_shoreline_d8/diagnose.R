# LOW 02F shoreline D8 terminal diagnostics. Pure base R; no raster writes.
# Evidence flags are review triggers, never instructions to change a D8 pointer.

shoreline_d8_deltas <- data.frame(
  code = c(1L, 2L, 4L, 8L, 16L, 32L, 64L, 128L),
  dr = c(-1L, 0L, 1L, 1L, 1L, 0L, -1L, -1L),
  dc = c(1L, 1L, 1L, 0L, -1L, -1L, -1L, 0L)
)

shoreline_d8_move_code <- function(dr, dc) {
  key <- paste(dr, dc, sep = ":")
  reference <- paste(shoreline_d8_deltas$dr,
                     shoreline_d8_deltas$dc, sep = ":")
  shoreline_d8_deltas$code[match(key, reference)]
}

diagnose_shoreline_d8_terminals <- function(
    terminal_cells, read_window, nrow_raster, ncol_raster, tolerance = 1e-7) {
  if (!is.function(read_window)) stop("read_window must be a function")
  if (length(nrow_raster) != 1L || length(ncol_raster) != 1L ||
      !is.numeric(nrow_raster) || !is.numeric(ncol_raster) ||
      !is.finite(nrow_raster) || !is.finite(ncol_raster) ||
      nrow_raster < 5 || ncol_raster < 5 ||
      nrow_raster != floor(nrow_raster) ||
      ncol_raster != floor(ncol_raster)) {
    stop("invalid raster dimensions")
  }
  if (length(tolerance) != 1L || !is.numeric(tolerance) ||
      !is.finite(tolerance) || tolerance < 0) stop("invalid tolerance")
  if (!is.numeric(terminal_cells) || !length(terminal_cells) ||
      length(terminal_cells) > 200L || anyNA(terminal_cells) ||
      any(!is.finite(terminal_cells)) ||
      any(terminal_cells != floor(terminal_cells)) ||
      any(terminal_cells < 1) ||
      any(terminal_cells > as.double(nrow_raster) * ncol_raster) ||
      anyDuplicated(terminal_cells)) {
    stop("expected 1..200 distinct, valid terminal cell indices")
  }

  required <- c("cell", "row", "col", "dem", "land_raw", "land_fill",
                "land_water", "storage", "water_class", "lake_id", "d8")
  summaries <- vector("list", length(terminal_cells))
  lake_incoming <- list()
  flat_escapes <- list()

  for (i in seq_along(terminal_cells)) {
    id <- terminal_cells[i]
    r <- floor((id - 1) / ncol_raster) + 1
    c <- ((id - 1) %% ncol_raster) + 1
    if (r <= 2 || c <= 2 || r >= nrow_raster - 1 ||
        c >= ncol_raster - 1) stop("terminal lacks full 5x5 interior window: ", id)
    x <- read_window(id, 2L)
    if (!is.data.frame(x) || !all(required %in% names(x)) || nrow(x) != 25L) {
      stop("read_window must return exactly 25 cells with required columns: ", id)
    }
    if (!all(vapply(x[required], is.numeric, logical(1)))) {
      stop("read_window has nonnumeric QA values: ", id)
    }
    keys <- paste(x$row, x$col, sep = ":")
    expected <- as.vector(outer(seq.int(r - 2, r + 2),
                                seq.int(c - 2, c + 2), paste, sep = ":"))
    if (anyNA(x$row) || anyNA(x$col) || anyNA(x$cell) ||
        anyDuplicated(keys) || !setequal(keys, expected) ||
        any(x$cell != (x$row - 1) * ncol_raster + x$col)) {
      stop("read_window geometry or cell-order mismatch: ", id)
    }
    center <- x[x$cell == id, , drop = FALSE]
    if (nrow(center) != 1L || !is.finite(center$d8) || center$d8 != 0 ||
        !is.finite(center$land_water) || !is.finite(center$dem) ||
        !is.finite(center$land_raw) || !is.finite(center$land_fill) ||
        !is.finite(center$storage) ||
        !is.na(center$water_class) || !is.na(center$lake_id)) {
      stop("terminal is not a finite, non-water D8 zero: ", id)
    }
    near <- x[abs(x$row - r) <= 1 & abs(x$col - c) <= 1 &
                x$cell != id, , drop = FALSE]
    if (nrow(near) != 8L) stop("invalid 3x3 neighborhood: ", id)
    adjacent_lakes <- which(!is.na(near$water_class) &
                              near$water_class == 1)
    to_center <- shoreline_d8_move_code(r - near$row, c - near$col)
    incoming <- adjacent_lakes[
      !is.na(near$d8[adjacent_lakes]) &
        near$d8[adjacent_lakes] == to_center[adjacent_lakes]
    ]
    if (length(incoming) &&
        any(!is.finite(near$lake_id[incoming]))) {
      stop("incoming lake lacks a lake ID: ", id)
    }
    lake_incoming[[i]] <- data.frame(
      terminal_cell = rep(id, length(incoming)),
      incoming_lake_cell = near$cell[incoming],
      incoming_lake_id = near$lake_id[incoming],
      lake_land_water_m = near$land_water[incoming],
      stringsAsFactors = FALSE
    )

    masked <- length(adjacent_lakes) > 0 &&
      all(is.na(near$land_raw[adjacent_lakes])) &&
      all(is.na(near$land_fill[adjacent_lakes]))
    fill_unchanged <- abs(center$land_fill - center$land_raw) <= tolerance
    source_dem_unchanged <- abs(center$dem - center$land_raw) <= tolerance
    shore_fill_flag <- masked && fill_unchanged && source_dem_unchanged

    # The flat-neighbor's actual D8 must lead to a lower LAND_WATER cell;
    # a mere equal-height neighbor does not qualify as a continuation.
    flats <- which(is.na(near$water_class) &
                     is.finite(near$land_water) &
                     abs(near$land_water - center$land_water) <= tolerance)
    valid_escapes <- integer(0)
    receivers <- numeric(0)
    for (j in flats) {
      m <- match(near$d8[j], shoreline_d8_deltas$code)
      if (is.na(m)) next
      rr <- near$row[j] + shoreline_d8_deltas$dr[m]
      cc <- near$col[j] + shoreline_d8_deltas$dc[m]
      dest <- x[x$row == rr & x$col == cc, , drop = FALSE]
      if (nrow(dest) == 1L && is.finite(dest$land_water) &&
          dest$land_water < near$land_water[j] - tolerance) {
        valid_escapes <- c(valid_escapes, j)
        receivers <- c(receivers, dest$cell)
      }
    }
    flat_escapes[[i]] <- data.frame(
      terminal_cell = rep(id, length(valid_escapes)),
      flat_neighbor_cell = near$cell[valid_escapes],
      lower_receiver_cell = receivers,
      stringsAsFactors = FALSE
    )

    lake_to_zero <- length(incoming) > 0
    summaries[[i]] <- data.frame(
      terminal_cell = id,
      adjacent_lake_cells = length(adjacent_lakes),
      incoming_lake_d8 = length(incoming),
      masked_lake_neighbors = if (length(adjacent_lakes))
        sum(is.na(near$land_raw[adjacent_lakes]) &
              is.na(near$land_fill[adjacent_lakes])) else 0L,
      flat_neighbors = length(flats),
      flat_downhill_continuations = length(valid_escapes),
      center_land_water_m = center$land_water,
      center_storage_m = center$storage,
      LAKE_D8_TO_INTERIOR_ZERO = lake_to_zero,
      MASKED_SHORE_FILL_UNCHANGED = shore_fill_flag,
      FLAT_CONTINUATION_REVIEW = length(valid_escapes) > 0,
      scientific_status = if (lake_to_zero || shore_fill_flag ||
                              length(valid_escapes))
        "REVIEW_REQUIRED" else "NO_FLAG_FROM_LOCAL_WINDOW",
      stringsAsFactors = FALSE
    )
  }
  list(
    summary = do.call(rbind, summaries),
    incoming_lake_edges = do.call(rbind, lake_incoming),
    flat_downhill_escapes = do.call(rbind, flat_escapes)
  )
}