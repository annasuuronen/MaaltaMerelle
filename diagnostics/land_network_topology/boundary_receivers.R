# Base R observation of a locked receiver set. No D8 traversal or raster I/O.
low_boundary_targets <- function(exits, locked_exits) {
  fields <- c("exit_id", "exit_cell_uid", "global_row", "global_col", "d8_code",
              "predicted_receiver_row", "predicted_receiver_col", "n_source_routes")
  canonical <- function(x) {
    if (!is.data.frame(x) || anyDuplicated(names(x)) ||
        !all(fields %in% names(x)) || nrow(x) != 16L) stop("EXPECTED_16_LOCKED_EXIT_ROWS")
    x <- x[, fields, drop = FALSE]
    text <- function(v) is.character(v) && !anyNA(v) && all(nzchar(v))
    if (!text(x$exit_id) || !text(x$exit_cell_uid) ||
        anyDuplicated(x$exit_id) || anyDuplicated(x$exit_cell_uid)) stop("INVALID_EXIT_IDENTITIES")
    for (key in fields[3:8]) {
      v <- x[[key]]
      if (!is.numeric(v) || any(!is.finite(v) | v != floor(v) | v < 1))
        stop("INVALID_TARGET_NUMBER: ", key)
      x[[key]] <- as.numeric(v)
    }
    prefix <- "LOW-E200000-N6900000"
    if (any(x$global_row < 2995 | x$global_row > 3005 | x$global_col < 2995 | x$global_col > 3005) ||
        any(!(x$global_row %in% c(2995, 3005) | x$global_col %in% c(2995, 3005))) ||
        any(x$predicted_receiver_row > 6000 | x$predicted_receiver_col > 6000) ||
        any(x$predicted_receiver_row >= 2995 & x$predicted_receiver_row <= 3005 &
            x$predicted_receiver_col >= 2995 & x$predicted_receiver_col <= 3005) ||
        any(abs(x$predicted_receiver_row - x$global_row) > 1 |
            abs(x$predicted_receiver_col - x$global_col) > 1) ||
        !all(x$d8_code %in% c(1, 2, 4, 8, 16, 32, 64, 128)) ||
        !identical(x$exit_cell_uid, paste(prefix, x$global_row, x$global_col, sep = ":")) ||
        !identical(x$exit_id, paste0("EXIT:", x$exit_cell_uid))) stop("INVALID_EXIT_RECEIVER_GEOMETRY")
    x <- x[order(x$global_row, x$global_col), , drop = FALSE]
    row.names(x) <- NULL
    x
  }
  expected <- canonical(locked_exits)
  x <- canonical(exits)
  if (!identical(x, expected)) stop("TARGET_SET_DIFFERS_FROM_LOCKED_REPORT")
  receiver_uid <- paste("LOW-E200000-N6900000", x$predicted_receiver_row,
                        x$predicted_receiver_col, sep = ":")
  if (length(unique(receiver_uid)) != 14L || sum(x$n_source_routes) != 121)
    stop("EXPECTED_16_TO_14_AND_121_REPORTED_SOURCE_ROUTES")
  pairs <- list(c(3000, 2994, 20), c(3006, 3002, 32))
  expected_sources <- list(c("3000:2995", "3001:2995"), c("3005:3001", "3005:3002"))
  for (i in seq_along(pairs)) {
    p <- pairs[[i]]
    keep <- x$predicted_receiver_row == p[1L] & x$predicted_receiver_col == p[2L]
    if (sum(keep) != 2L || sum(x$n_source_routes[keep]) != p[3L] ||
        !setequal(paste(x$global_row[keep], x$global_col[keep], sep = ":"), expected_sources[[i]]))
      stop("SHARED_RECEIVER_DIFFERS_FROM_APPROVED_SUMMARY")
  }
  x$receiver_uid <- receiver_uid
  receivers <- unique(x[, c("receiver_uid", "predicted_receiver_row", "predicted_receiver_col")])
  receivers <- receivers[order(receivers$predicted_receiver_row, receivers$predicted_receiver_col), ]
  row.names(receivers) <- NULL
  receivers$cell <- (receivers$predicted_receiver_row - 1) * 6000 + receivers$predicted_receiver_col
  receivers$n_exit_edges <- tabulate(match(receiver_uid, receivers$receiver_uid), nbins = 14L)
  receivers$reported_source_routes <- vapply(receivers$receiver_uid,
    function(uid) sum(x$n_source_routes[receiver_uid == uid]), numeric(1))
  list(exits = x, receivers = receivers, evidence = "LOCKED_REPORT_COORDINATES_ONLY")
}

observe_boundary_receivers <- function(targets, samples) {
  required <- c("receiver_uid", "land_water", "water_class", "lake_id", "pointer")
  if (!is.list(targets) || !is.data.frame(targets$receivers) || nrow(targets$receivers) != 14L ||
      !is.data.frame(samples) || anyDuplicated(names(samples)) ||
      !all(required %in% names(samples)) || nrow(samples) != 14L ||
      !is.character(samples$receiver_uid) || anyNA(samples$receiver_uid) ||
      anyDuplicated(samples$receiver_uid) ||
      !setequal(samples$receiver_uid, targets$receivers$receiver_uid) ||
      !all(vapply(samples[required[-1L]], is.numeric, logical(1)))) stop("INVALID_EXACT_RECEIVER_SAMPLES")
  r <- targets$receivers
  observations <- samples[match(r$receiver_uid, samples$receiver_uid), required[-1L], drop = FALSE]
  row.names(observations) <- NULL
  r <- cbind(r, observations)
  r$land_water_valid <- is.finite(r$land_water)
  r$receiver_class <- "UNCLEAR"
  r$receiver_class[!r$land_water_valid] <- "NO_DATA"
  r$receiver_class[r$land_water_valid & is.na(r$water_class)] <- "LAND"
  r$receiver_class[r$land_water_valid & r$water_class %in% 1:3] <- "WATER"
  r$pointer_status <- "INVALID_POINTER"
  r$pointer_status[is.na(r$pointer)] <- "POINTER_NA"
  r$pointer_status[!is.na(r$pointer) & r$pointer == 0] <- "D8_ZERO"
  r$pointer_status[r$pointer %in% c(1, 2, 4, 8, 16, 32, 64, 128)] <- "VALID_D8_CODE"
  lake_valid <- r$receiver_class == "WATER" & r$water_class %in% 1 &
    !is.na(r$lake_id) & is.finite(r$lake_id) & r$lake_id >= 1 &
    r$lake_id == floor(r$lake_id) & r$lake_id <= .Machine$integer.max
  r$lake_objectid <- ifelse(lake_valid, r$lake_id, NA_real_)
  r$lake_id_status <- "NOT_APPLICABLE"
  lake_water <- r$receiver_class == "WATER" & r$water_class %in% 1
  r$lake_id_status[lake_water & is.na(r$lake_id)] <- "MISSING"
  r$lake_id_status[lake_water & !is.na(r$lake_id) & !lake_valid] <- "INVALID"
  r$lake_id_status[lake_valid] <- "VALID"
  r$shared_receiver <- r$n_exit_edges > 1L
  r$hydrological_validation <- "NOT_ASSESSED"
  r$channel_interpretation <- "NOT_ASSESSED"
  links <- cbind(targets$exits, r[match(targets$exits$receiver_uid, r$receiver_uid),
    c("receiver_class", "land_water_valid", "water_class", "lake_id", "lake_objectid",
      "pointer", "pointer_status", "shared_receiver"), drop = FALSE])
  row.names(links) <- NULL
  list(receivers = r, exit_links = links, n_unique_receivers = 14L, n_exit_links = 16L,
    downstream_steps = 0L, accumulation = "NOT_COMPUTED", external_inflow = "UNKNOWN",
    hydrological_validation = "NOT_ASSESSED", channel_interpretation = "NOT_ASSESSED",
    MODERATE = "REVIEW_REQUIRED", NATIONAL = "LOCKED")
}

# Backend contract: one ordered numeric vector for exactly these unique IDs.
read_boundary_cells <- function(rasters, cells, read_cells, ncell) {
  if (!is.numeric(ncell) || length(ncell) != 1L || !is.finite(ncell) ||
      ncell != floor(ncell) || ncell < 14 ||
      !is.list(rasters) || !identical(names(rasters), c("pointer", "water", "lake", "land")) ||
      !is.numeric(cells) || length(cells) != 14L || anyDuplicated(cells) ||
      any(!is.finite(cells) | cells != floor(cells) | cells < 1 | cells > ncell) ||
      !is.function(read_cells)) stop("INVALID_EXACT_CELL_READ_REQUEST")
  values <- lapply(rasters, function(r) {
    x <- read_cells(r, cells)
    if (!is.numeric(x) || !is.null(dim(x)) || length(x) != 14L) stop("BAD_EXACT_CELL_READER_RESULT")
    x
  })
  list(values = values, read_calls = 4L, unique_cell_positions = 14L, returned_values = 56L)
}
