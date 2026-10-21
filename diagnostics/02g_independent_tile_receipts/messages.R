# Synthetic, bounded, functional tile actors. No raster/network/file I/O.
# Source the reviewed LOW route core and 02G accumulation.R / tiles.R first.
g2r_contract <- function(grid, layout, provenance, max_steps = 32L) {
  g02_grid(grid)
  g02_assert(grid$nrow * grid$ncol <= 121, "02G.2 supports at most 121 synthetic positions")
  g02_assert(isTRUE(provenance$synthetic) && is.character(provenance$run_id) &&
    length(provenance$run_id) == 1L && grepl("^[A-Za-z0-9_.-]+$", provenance$run_id), "Invalid synthetic run")
  g02_assert(all(grepl("^[A-Za-z0-9_.-]+$", names(layout))), "Invalid tile identifiers")
  # Reuse the reviewed grid, provenance and global work-budget contract on
  # virtual values. This validates metadata; it does not observe any input.
  first_water_contact(1L, grid, function(cell) list(pointer = 0, water_class = NA_real_,
    lake_id = NA_real_, valid = TRUE), max_steps, provenance)
  layout <- layout[sort(names(layout))]
  list(protocol = "02g.2-source-token-v1", grid = grid, layout = layout,
    owners = g02_layout(layout, grid), provenance = provenance, max_steps = as.integer(max_steps))
}
g2r_actor <- function(id, tile, contract) {
  g02_assert(id %in% names(contract$layout) && identical(tile$grid, contract$grid), "Actor identity/grid mismatch")
  box <- contract$layout[[id]]; c <- g02_cells(tile$cells, contract$grid)
  g02_assert(identical(as.numeric(c$cell), as.numeric(g02_rectangle(box$rows, box$cols, contract$grid, 1L))),
    "Actor needs exactly its own core and one-cell halo")
  core <- c$cell_uid[contract$owners[c$cell_uid] == id]
  land <- c$cell_uid[c$cell_uid %in% core & c$kind == "LAND"]
  water <- c$cell_uid[c$cell_uid %in% core & c$kind == "WATER"]
  list(id = id, contract = contract, cells = c, core = core, native_sources = land,
    source_sets = setNames(rep(list(character()), length(land)), land),
    water_sets = setNames(rep(list(character()), length(water)), water),
    inbox = list(), outbox = list(), confirmations = list(), terminals = list(), seeded = FALSE)
}
g2r_values <- function(state, cell) {
  i <- match(cell, state$cells$cell)
  g02_assert(!is.na(i), "Unobserved actor cell")
  as.list(state$cells[i, c("cell", "pointer", "water_class", "lake_id", "valid"), drop = FALSE])
}
g2r_next <- function(cell, code, grid) {
  l1847_trace(cell, grid$nrow, grid$ncol, function(at) list(pointer = if (at == cell) code else 0,
    water_class = NA_real_, lake_id = NA_real_), 1L)
}
g2r_id <- function(contract, source, path) paste(contract$provenance$run_id, source,
  g02_uid(tail(path, 2L)[1L], contract$grid), g02_uid(tail(path, 1L), contract$grid),
  length(path) - 1L, sep = "|")
g2r_message <- function(state, token) {
  path <- token$path; from <- tail(path, 2L)[1L]; to <- tail(path, 1L); c <- state$contract
  list(message_id = g2r_id(c, token$source_uid, path), contract = c, source_uid = token$source_uid,
    source_cell = token$source_cell, sending_tile = state$id,
    receiving_tile = unname(c$owners[g02_uid(to, c$grid)]),
    from_cell = from, receiver_cell = to, path = path, codes = token$codes)
}
g2r_terminal <- function(state, token, status) {
  g02_assert(is.null(state$terminals[[token$source_uid]]), "Source already terminated at this actor")
  state$terminals[[token$source_uid]] <- list(source_uid = token$source_uid,
    terminal_cell = tail(token$path, 1L), status = status, path = token$path)
  state
}
g2r_advance <- function(state, token) {
  c <- state$contract; g <- c$grid
  repeat {
    cell <- tail(token$path, 1L); uid <- g02_uid(cell, g)
    g02_assert(uid %in% state$core, "Only the current core owner may advance a token")
    if (cell %in% head(token$path, -1L)) return(g2r_terminal(state, token, "CYCLE"))
    a <- g2r_values(state, cell)
    if (!a$valid) return(g2r_terminal(state, token, "NO_DATA"))
    if (!is.na(a$water_class)) {
      if (!a$water_class %in% 1:3) return(g2r_terminal(state, token, "INVALID_WATER_CLASS"))
      state$water_sets[[uid]] <- union(state$water_sets[[uid]], token$source_uid)
      return(g2r_terminal(state, token, "FIRST_WATER_CONTACT"))
    }
    state$source_sets[[uid]] <- union(state$source_sets[[uid]], token$source_uid)
    if (is.na(a$pointer)) return(g2r_terminal(state, token, "POINTER_NA"))
    if (a$pointer == 0) return(g2r_terminal(state, token, "D8_ZERO"))
    if (!a$pointer %in% c(1, 2, 4, 8, 16, 32, 64, 128)) return(g2r_terminal(state, token, "INVALID_POINTER"))
    if (length(token$codes) >= c$max_steps) return(g2r_terminal(state, token, "STEP_LIMIT"))
    step <- g2r_next(cell, a$pointer, g)
    if (step$status == "DOMAIN_EXIT") return(g2r_terminal(state, token, "DOMAIN_EXIT_UNRESOLVED"))
    token$path <- c(token$path, step$cell); token$codes <- c(token$codes, a$pointer)
    if (c$owners[g02_uid(step$cell, g)] != state$id) {
      message <- g2r_message(state, token)
      g02_assert(is.null(state$outbox[[message$message_id]]), "Duplicate logical send")
      state$outbox[[message$message_id]] <- message
      return(state)
    }
  }
}
g2r_seed <- function(state) {
  g02_assert(!state$seeded, "Actor already seeded; source units cannot be recreated")
  state$seeded <- TRUE
  for (uid in state$native_sources) {
    cell <- state$cells$cell[match(uid, state$cells$cell_uid)]
    state <- g2r_advance(state, list(source_uid = uid, source_cell = cell, path = cell, codes = numeric()))
  }
  state
}
g2r_validate_message <- function(state, message) {
  fields <- c("message_id", "contract", "source_uid", "source_cell", "sending_tile", "receiving_tile",
    "from_cell", "receiver_cell", "path", "codes")
  g02_assert(is.list(message) && identical(names(message), fields), "Unknown/missing message fields")
  c <- state$contract; g <- c$grid; m <- message
  g02_assert(identical(m$contract, c), "Stale/different run, grid, provenance or budget")
  for (field in c("message_id", "source_uid", "sending_tile", "receiving_tile"))
    g02_assert(is.character(m[[field]]) && length(m[[field]]) == 1L && !is.na(m[[field]]), "Invalid message identity")
  g02_assert(m$receiving_tile == state$id && m$sending_tile != state$id && m$sending_tile %in% names(c$layout),
    "Wrong receiving/sending tile")
  g02_assert(is.numeric(m$path) && length(m$path) >= 2L && length(m$path) <= c$max_steps + 1L &&
    all(is.finite(m$path) & m$path == floor(m$path) & m$path >= 1 & m$path <= g$nrow * g$ncol) &&
    !anyDuplicated(head(m$path, -1L)) && is.numeric(m$codes) && length(m$codes) == length(m$path) - 1L &&
    all(m$codes %in% c(1, 2, 4, 8, 16, 32, 64, 128)), "Invalid path/budget/directions")
  g02_assert(identical(m$source_cell, m$path[1L]) && identical(m$source_uid, g02_uid(m$source_cell, g)) &&
    identical(m$from_cell, tail(m$path, 2L)[1L]) && identical(m$receiver_cell, tail(m$path, 1L)) &&
    identical(m$message_id, g2r_id(c, m$source_uid, m$path)), "Message/path identity conflict")
  g02_assert(c$owners[g02_uid(m$from_cell, g)] == m$sending_tile &&
    g02_uid(m$receiver_cell, g) %in% state$core, "Boundary ownership conflict")
  for (j in seq_along(m$codes)) {
    step <- g2r_next(m$path[j], m$codes[j], g)
    g02_assert(step$status != "DOMAIN_EXIT" && step$cell == m$path[j + 1L], "Path geometry conflict")
    # Validate every path edge whose source was independently observed by this
    # receiver (core OR halo). Foreign history outside the halo stays declared.
    if (m$path[j] %in% state$cells$cell) {
      a <- g2r_values(state, m$path[j])
      g02_assert(a$valid && is.na(a$water_class) && isTRUE(a$pointer == m$codes[j]), "Receiver observation disagrees with path")
    }
  }
  for (old in state$inbox) if (old$message$source_uid == m$source_uid) {
    n <- min(length(old$message$path), length(m$path))
    g02_assert(identical(head(old$message$path, n), head(m$path, n)) &&
      identical(head(old$message$codes, n - 1L), head(m$codes, n - 1L)), "Conflicting source histories")
  }
  invisible(TRUE)
}
g2r_receive <- function(state, message) {
  g02_assert(state$seeded, "Seed the receiver once before receiving messages")
  g2r_validate_message(state, message)
  prior <- state$inbox[[message$message_id]]
  if (!is.null(prior)) {
    g02_assert(identical(prior$message, message), "Conflicting replay payload")
    return(list(state = state, receipt = prior$receipt, delivery_status = "REPLAY"))
  }
  # No sender counts, sender result object or global observations are used.
  receipt <- list(message_id = message$message_id, contract = state$contract,
    source_uid = message$source_uid, sending_tile = message$sending_tile, receiving_tile = state$id,
    receiver_cell = message$receiver_cell, receiver_observation = g2r_values(state, message$receiver_cell),
    status = "OBSERVED_RECEIPT", hydrological_validation = "NOT_ASSESSED")
  state$inbox[[message$message_id]] <- list(message = message, receipt = receipt)
  state <- g2r_advance(state, message[c("source_uid", "source_cell", "path", "codes")])
  list(state = state, receipt = receipt, delivery_status = "ACCEPTED")
}
g2r_confirm <- function(state, receipt) {
  fields <- c("message_id", "contract", "source_uid", "sending_tile", "receiving_tile", "receiver_cell",
    "receiver_observation", "status", "hydrological_validation")
  g02_assert(is.list(receipt) && identical(names(receipt), fields) &&
    identical(receipt$contract, state$contract), "Invalid receipt contract")
  sent <- state$outbox[[receipt$message_id]]
  g02_assert(!is.null(sent) && identical(receipt$source_uid, sent$source_uid) &&
    identical(receipt$sending_tile, state$id) && identical(receipt$receiving_tile, sent$receiving_tile) &&
    identical(receipt$receiver_cell, sent$receiver_cell) && receipt$status == "OBSERVED_RECEIPT" &&
    receipt$hydrological_validation == "NOT_ASSESSED" &&
    identical(receipt$receiver_observation, g2r_values(state, sent$receiver_cell)), "Receipt disagrees with sent edge or halo")
  prior <- state$confirmations[[receipt$message_id]]
  g02_assert(is.null(prior) || identical(prior, receipt), "Conflicting receipt replay")
  state$confirmations[[receipt$message_id]] <- receipt
  state
}
g2r_collect <- function(actors) {
  g02_assert(is.list(actors) && length(actors) > 0L && !is.null(names(actors)) &&
    !anyDuplicated(names(actors)), "Invalid actor collection")
  actors <- actors[sort(names(actors))]; c <- actors[[1L]]$contract; g <- c$grid
  for (id in names(actors)) g02_assert(identical(actors[[id]]$id, id) &&
    identical(actors[[id]]$contract, c) && actors[[id]]$seeded, "Actor contracts/seeds disagree")
  # Reconciliation observes independently stored ledgers. It neither creates
  # receiver entries nor manufactures confirmations for an available tile.
  sent <- unlist(lapply(actors, function(a) unname(a$outbox)), recursive = FALSE)
  received <- unlist(lapply(actors, function(a) unname(a$inbox)), recursive = FALSE)
  for (entry in received) {
    m <- entry$message; sender <- actors[[m$sending_tile]]
    g02_assert(!is.null(sender) && identical(sender$outbox[[m$message_id]], m), "Orphan/conflicting received message")
  }
  confirmed <- 0L
  for (a in actors) for (ack in a$confirmations) {
    receiver <- actors[[ack$receiving_tile]]
    g02_assert(!is.null(receiver) && identical(receiver$inbox[[ack$message_id]]$receipt, ack), "Receipt has no independent receiver entry")
    confirmed <- confirmed + 1L
  }
  sources <- sort(as.character(unlist(lapply(actors, function(a) a$native_sources), use.names = FALSE)))
  g02_assert(!anyDuplicated(sources), "Duplicate core source ownership")
  terminals <- unlist(lapply(actors, function(a) unname(a$terminals)), recursive = FALSE)
  term_sources <- vapply(terminals, function(t) t$source_uid, character(1))
  g02_assert(!anyDuplicated(term_sources) && all(term_sources %in% sources), "Duplicate/unknown terminal sources")
  ledger <- list(); cycles <- integer()
  for (uid in sources) {
    i <- match(uid, term_sources)
    if (!is.na(i)) {
      t <- terminals[[i]]; status <- t$status; endpoint <- t$terminal_cell
      if (status == "CYCLE") cycles <- union(cycles, t$path[match(endpoint, t$path):(length(t$path) - 1L)])
    } else {
      pending <- Filter(function(m) m$source_uid == uid &&
        is.null(actors[[m$sending_tile]]$confirmations[[m$message_id]]), sent)
      g02_assert(length(pending) > 0L, "Source lost without terminal or pending transfer")
      m <- pending[[which.max(vapply(pending, function(x) length(x$codes), integer(1)))]]
      status <- if (m$receiving_tile %in% names(actors)) "PENDING_DELIVERY" else "MISSING_NEIGHBOUR_TILE"
      endpoint <- m$receiver_cell
    }
    ledger[[length(ledger) + 1L]] <- data.frame(source_uid = uid, owner_tile = unname(c$owners[uid]),
      endpoint_type = status, terminal_uid = g02_uid(endpoint, g),
      first_water_uid = if (status == "FIRST_WATER_CONTACT") g02_uid(endpoint, g) else NA_character_)
  }
  ledger <- g02_bind(ledger, data.frame(source_uid = character(), owner_tile = character(),
    endpoint_type = character(), terminal_uid = character(), first_water_uid = character()))
  sets <- unlist(unname(lapply(actors, function(a) a$source_sets)), recursive = FALSE, use.names = TRUE)
  water <- unlist(unname(lapply(actors, function(a) a$water_sets)), recursive = FALSE, use.names = TRUE)
  if (is.null(sets)) sets <- setNames(list(), character())
  if (is.null(water)) water <- setNames(list(), character())
  sets <- lapply(sets[sort(names(sets))], sort); water <- lapply(water[sort(names(water))], sort)
  for (s in c(sets, water)) g02_assert(!anyDuplicated(s) && all(s %in% sources), "Duplicate/unowned source membership")
  g02_assert(identical(sort(as.character(names(sets))), sources), "Core source inventory mismatch")
  count <- vapply(sets, length, integer(1)); local <- as.numeric(count)
  local[names(sets) %in% g02_uid(cycles, g)] <- NA_real_
  nodes <- data.frame(cell_uid = as.character(names(sets)), observed_source_count = count,
    local_upstream_cells = local, local_upstream_area_m2 = 4 * local,
    external_import = rep("UNKNOWN", length(sets)), total_upstream_cells = rep(NA_real_, length(sets)), row.names = NULL)
  water_ids <- as.character(names(water))
  water_values <- lapply(water_ids, function(uid) {
    owner <- unname(c$owners[uid]); a <- actors[[owner]]
    g2r_values(a, a$cells$cell[match(uid, a$cells$cell_uid)])
  })
  wc <- vapply(water_values, function(a) a$water_class, numeric(1))
  lake <- vapply(water_values, function(a) a$lake_id, numeric(1))
  water_table <- data.frame(cell_uid = water_ids, water_class = wc,
    lake_objectid = ifelse(wc == 1 & is.finite(lake) & lake > 0 & lake == floor(lake), lake, NA_real_),
    local_source_cells = vapply(water, length, integer(1)),
    external_import = rep("UNKNOWN", length(water_ids)), total_source_cells = rep(NA_real_, length(water_ids)), row.names = NULL)
  water_table$local_source_area_m2 <- 4 * water_table$local_source_cells
  wi <- match(ledger$first_water_uid, water_table$cell_uid)
  ledger$water_class <- water_table$water_class[wi]
  ledger$lake_objectid <- water_table$lake_objectid[wi]
  nodes$endpoint_type <- ledger$endpoint_type[match(nodes$cell_uid, ledger$source_uid)]
  reached <- sum(ledger$endpoint_type == "FIRST_WATER_CONTACT")
  g02_assert(sum(vapply(water, length, integer(1))) == reached, "First-water source balance mismatch")
  list(protocol = c$protocol, nodes = nodes, water = water_table, source_sets = sets, water_source_sets = water,
    source_ledger = ledger, cycle_cells = sort(g02_uid(cycles, g)),
    balance = data.frame(n_sources = length(sources), n_first_water = reached,
      n_unresolved = length(sources) - reached, n_approved_exports = 0L,
      sent = length(sent), independently_received = length(received), confirmed = confirmed,
      unconfirmed = length(sent) - confirmed),
    missing_tiles = setdiff(names(c$layout), names(actors)),
    coverage_status = if (length(sources) > 0 && all(ledger$endpoint_type == "FIRST_WATER_CONTACT"))
      "OBSERVED_LOCAL_SOURCES_ONLY" else "PARTIAL_OR_UNRESOLVED",
    external_import = "UNKNOWN", provenance = c$provenance, provenance_verification = "DECLARED_ONLY",
    channel_threshold_cells = 10000L, channel_threshold_area_m2 = 40000,
    hydrological_validation = "NOT_ASSESSED", channel_interpretation = "NOT_ASSESSED",
    MODERATE = "REVIEW_REQUIRED", NATIONAL = "LOCKED")
}
