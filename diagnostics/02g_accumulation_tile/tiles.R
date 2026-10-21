# Rectangular synthetic tile cores with exactly one-cell in-grid halos.
g02_rectangle <- function(rows, cols, g, halo = 0L) {
  rr <- seq.int(max(1L, min(rows) - halo), min(g$nrow, max(rows) + halo))
  cc <- seq.int(max(1L, min(cols) - halo), min(g$ncol, max(cols) + halo))
  sort(as.vector(outer(rr - 1L, cc, function(r, c) r * g$ncol + c)))
}
g02_layout <- function(layout, g) {
  g02_grid(g)
  g02_assert(is.list(layout) && length(layout) > 0 && !is.null(names(layout)) &&
    !anyDuplicated(names(layout)) && all(nzchar(names(layout))), "Invalid tile layout")
  owner <- rep(NA_character_, g$nrow * g$ncol)
  for (id in names(layout)) {
    box <- layout[[id]]
    g02_assert(is.list(box) && length(box$rows) == 2L && length(box$cols) == 2L &&
      all(is.finite(c(box$rows, box$cols))) && all(c(box$rows, box$cols) == floor(c(box$rows, box$cols))) &&
      box$rows[1] <= box$rows[2] && box$cols[1] <= box$cols[2] && min(box$rows) >= 1 &&
      max(box$rows) <= g$nrow && min(box$cols) >= 1 && max(box$cols) <= g$ncol, "Invalid rectangular core")
    core <- g02_rectangle(box$rows, box$cols, g)
    g02_assert(all(is.na(owner[core])), "Duplicate core ownership")
    owner[core] <- id
  }
  g02_assert(!anyNA(owner), "Layout must describe the complete declared synthetic grid")
  setNames(owner, g02_uid(seq_along(owner), g))
}
g02_tile_accumulation <- function(tiles, layout, grid, provenance, max_steps = 32L,
                                  external_import = "UNKNOWN") {
  expected <- g02_layout(layout, grid)
  g02_assert(is.list(tiles) && length(tiles) > 0 && !anyDuplicated(names(tiles)) &&
    all(names(tiles) %in% names(layout)), "Invalid available tiles")
  all_obs <- list(); owned_obs <- list(); owner <- character()
  for (id in sort(names(tiles))) {
    tile <- tiles[[id]]; box <- layout[[id]]
    g02_assert(identical(tile$grid, grid), "Tile grid mismatch")
    observed <- g02_cells(tile$cells, grid)
    core <- g02_rectangle(box$rows, box$cols, grid)
    halo <- g02_rectangle(box$rows, box$cols, grid, 1L)
    g02_assert(identical(as.numeric(observed$cell), as.numeric(halo)), "Missing, duplicate or excessive halo observations")
    all_obs[[id]] <- observed
    owned_obs[[id]] <- observed[observed$cell %in% core, 1:5, drop = FALSE]
  }
  observed <- do.call(rbind, all_obs)
  for (cell in unique(observed$cell[duplicated(observed$cell)])) {
    x <- observed[observed$cell == cell, 1:5, drop = FALSE]
    for (j in seq_len(nrow(x))) g02_assert(identical(as.list(x[j, ]), as.list(x[1L, ])), "Conflicting halo observation")
  }
  cells <- g02_cells(do.call(rbind, owned_obs), grid)
  owner <- expected[cells$cell_uid]
  # This is a fresh, explicitly requested synthetic stitched observation;
  # previous tile/source traces are not silently resumed or enriched.
  observed_routes <- g02_observe(cells, grid, provenance, max_steps)
  result <- g02_accumulate(cells, observed_routes$routes, grid, provenance, owner, expected, external_import)
  moves <- result$observed_moves
  # One transfer per canonical cross-core edge; per-source membership records
  # only actual observed moves, not all sources that merely reached its sender.
  cross <- moves[expected[moves$from_uid] != expected[moves$to_uid], , drop = FALSE]
  ids <- unique(paste(cross$from_uid, cross$to_uid, sep = ">"))
  records <- list(); memberships <- list()
  for (j in seq_along(ids)) {
    x <- cross[paste(cross$from_uid, cross$to_uid, sep = ">") == ids[j], , drop = FALSE]
    from <- x$from_uid[1L]; to <- x$to_uid[1L]
    sender <- unname(expected[from]); receiver <- unname(expected[to])
    g02_assert(length(unique(x$d8_code)) == 1L && sender %in% names(tiles), "Conflicting transfer direction/ownership")
    members <- unique(x$source_uid)
    available <- receiver %in% names(tiles)
    at <- match(from, result$nodes$cell_uid)
    records[[j]] <- data.frame(transfer_id = ids[j], sending_tile = sender, receiving_tile = receiver,
      source_cell_uid = from, receiver_cell_uid = to, d8_code = x$d8_code[1L], d8_verified_by_core = TRUE,
      known_local_accumulation_cells = result$nodes$local_upstream_cells[at], n_transferred_sources = length(members),
      external_import = external_import, transfer_status = if (available) "OBSERVED_INTERNAL_TRANSFER" else "MISSING_NEIGHBOUR_TILE")
    memberships[[j]] <- data.frame(transfer_id = ids[j], source_uid = members,
      sending_tile = sender, receiving_tile = receiver, received = available)
  }
  transfers <- g02_bind(records, data.frame(transfer_id = character(), sending_tile = character(), receiving_tile = character(),
    source_cell_uid = character(), receiver_cell_uid = character(), d8_code = numeric(), d8_verified_by_core = logical(),
    known_local_accumulation_cells = numeric(), n_transferred_sources = integer(), external_import = character(), transfer_status = character()))
  members <- g02_bind(memberships, data.frame(transfer_id = character(), source_uid = character(), sending_tile = character(), receiving_tile = character(), received = logical()))
  receipts <- members[members$received, , drop = FALSE]
  g02_assert(!anyDuplicated(transfers$transfer_id) && !anyDuplicated(members[, c("transfer_id", "source_uid")]), "Duplicate transfer accounting")
  tile_balance <- lapply(sort(names(tiles)), function(id) {
    local <- result$source_ledger[result$source_ledger$owner_tile == id, , drop = FALSE]
    data.frame(tile_id = id, owned_sources = nrow(local), first_water_sources = sum(local$endpoint_type == "FIRST_WATER_CONTACT"),
      unresolved_sources = sum(local$endpoint_type != "FIRST_WATER_CONTACT"),
      received_memberships = sum(receipts$receiving_tile == id), sent_memberships = sum(members$sending_tile == id))
  })
  result$transfers <- transfers; result$transfer_sources <- members; result$receipts <- receipts
  result$tile_balance <- do.call(rbind, tile_balance)
  result$internal_balance <- data.frame(sent = sum(members$received), received = nrow(receipts),
    pending = sum(!members$received), cancelled = sum(members$received) == nrow(receipts))
  result$missing_core_cells <- sum(!expected %in% names(tiles))
  result$ownership <- owner
  result
}
