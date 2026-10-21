# 02G.3: bounded synthetic complete-local-DAG counts. No file/raster I/O.
complete_local_dag_counts <- function(graph, evidence = NULL) {
  identity_fields <- c("run_id", "graph_version", "grid_version", "pointer_version", "water_version", "ownership_version")
  safe_identity <- function(x) {
    out <- setNames(rep(list(NA_character_), length(identity_fields)), identity_fields)
    if (is.list(x)) for (key in identity_fields) {
      v <- x[[key]]
      if (is.character(v) && length(v) == 1L && !is.na(v) && nchar(v) <= 128L) out[[key]] <- v
    }
    out
  }
  fail <- function(code, detail) {
    ownership <- NULL
    if (is.list(graph) && is.data.frame(graph$cores) && nrow(graph$cores) <= 27L)
      ownership <- graph$cores[, intersect(names(graph$cores), c("core_id", "row_min", "row_max", "col_min", "col_max")), drop = FALSE]
    stop(structure(list(message = paste("STOP", code, detail, sep = ": "), call = NULL,
      status = "STOP", reason_code = code, result_kind = "NO_NUMERIC_RESULT",
      identity = safe_identity(if (is.list(graph)) graph$identity else NULL),
      evidence_identity = safe_identity(if (is.list(evidence)) evidence$identity else NULL), ownership = ownership,
      hydrological_validation = "NOT_ASSESSED", channel_interpretation = "NOT_ASSESSED",
      MODERATE = "REVIEW_REQUIRED", NATIONAL = "LOCKED"), class = c("local_dag_stop", "error", "condition")))
  }
  need <- function(ok, code, detail) if (!isTRUE(ok)) fail(code, detail)
  fields <- function(x, keys, code) need(is.list(x) && !is.null(names(x)) &&
    !anyDuplicated(names(x)) && length(x) == length(keys) && setequal(names(x), keys), code, "Unknown, missing or duplicate fields")
  table <- function(x, keys, limit, code) {
    need(identical(class(x), "data.frame") && nrow(x) <= limit, code, "Expected a bounded plain data.frame")
    fields(x, keys, code)
  }
  text <- function(x) is.character(x) && !anyNA(x) && all(nchar(x) > 0L & nchar(x) <= 128L)
  real <- function(x) (is.integer(x) || is.double(x)) && !is.object(x)
  whole <- function(x, low, high) real(x) && all(is.finite(x) & x == floor(x) & x >= low & x <= high)
  scalar <- function(x, low, high) length(x) == 1L && whole(x, low, high)
  fields(graph, c("schema", "input_kind", "identity", "grid", "cores", "nodes", "edges", "external_import"), "GRAPH_FIELDS")
  need(identical(graph$schema, "02g.3-graph-v1") && identical(graph$input_kind, "EXPLICIT_SYNTHETIC_CELL_GRAPH"),
    "GRAPH_ORIGIN", "Only an explicit synthetic cell graph is supported")
  need(!is.null(evidence), "MISSING_EVIDENCE", "Independent complete cell census required")
  fields(evidence, c("schema", "input_kind", "scope_contract", "observation_status", "identity", "producer_id",
    "available_cores", "observations", "source_inventory"), "EVIDENCE_FIELDS")
  need(text(evidence$observation_status) && length(evidence$observation_status) == 1L,
    "CENSUS_CONTRACT", "Observation status must be one explicit value")
  need(!any(evidence$observation_status %in% c("STEP_LIMIT", "PARTIAL", "CENSORED")),
    "CENSORED_EVIDENCE", "Source-censored observations cannot be promoted to a complete graph")
  need(identical(evidence$schema, "02g.3-census-v1") &&
    identical(evidence$input_kind, "INDEPENDENT_SYNTHETIC_CELL_CENSUS") &&
    identical(evidence$scope_contract, "COMPLETE_DECLARED_LOCAL_DAG") &&
    identical(evidence$observation_status, "COMPLETE_CELL_CENSUS"), "CENSUS_CONTRACT", "Complete independent observation contract required")
  fields(graph$identity, identity_fields, "GRAPH_IDENTITY")
  fields(evidence$identity, identity_fields, "EVIDENCE_IDENTITY")
  for (key in identity_fields) need(text(graph$identity[[key]]) && length(graph$identity[[key]]) == 1L &&
    identical(graph$identity[[key]], evidence$identity[[key]]), "IDENTITY_CONFLICT", key)
  need(text(evidence$producer_id) && length(evidence$producer_id) == 1L, "CENSUS_PRODUCER", "Declare the census producer")
  need(identical(graph$external_import, "UNKNOWN"), "EXTERNAL_IMPORT", "Only unknown external import is supported")

  g <- graph$grid
  fields(g, c("grid_id", "nrow", "ncol", "row_offset", "col_offset", "xmin", "ymax", "resolution_m", "crs"), "GRID_FIELDS")
  g <- g[c("grid_id", "nrow", "ncol", "row_offset", "col_offset", "xmin", "ymax", "resolution_m", "crs")]
  need(text(g$grid_id) && length(g$grid_id) == 1L && grepl("^[A-Za-z0-9_.-]+$", g$grid_id), "GRID_ID", "Invalid global grid identifier")
  need(scalar(g$nrow, 1, 27) && scalar(g$ncol, 1, 27) && g$nrow * g$ncol <= 27, "GRID_LIMIT", "At most 27 grid positions")
  need(scalar(g$row_offset, 0, .Machine$integer.max - g$nrow) &&
    scalar(g$col_offset, 0, .Machine$integer.max - g$ncol) &&
    scalar(g$xmin, -2^52, 2^52) && scalar(g$ymax, -2^52, 2^52) &&
    identical(g$crs, "EPSG:3067") && scalar(g$resolution_m, 2, 2), "GRID_NUMERIC", "Exact bounded integer origin/offsets and 2 m EPSG:3067 required")
  n <- as.integer(g$nrow * g$ncol); seqs <- seq_len(n)
  rr <- g$row_offset + (seqs - 1L) %/% g$ncol + 1L
  cc <- g$col_offset + (seqs - 1L) %% g$ncol + 1L
  uid <- paste(g$grid_id, rr, cc, sep = ":")

  cores <- graph$cores
  table(cores, c("core_id", "row_min", "row_max", "col_min", "col_max"), 27L, "CORE_FIELDS")
  need(nrow(cores) > 0L && text(cores$core_id) && all(grepl("^[A-Za-z0-9_.-]+$", cores$core_id)) &&
    !anyDuplicated(cores$core_id), "CORE_IDENTITY", "Unique cores required")
  for (key in c("row_min", "row_max")) need(whole(cores[[key]], min(rr), max(rr)), "CORE_GEOMETRY", key)
  for (key in c("col_min", "col_max")) need(whole(cores[[key]], min(cc), max(cc)), "CORE_GEOMETRY", key)
  need(all(cores$row_min <= cores$row_max & cores$col_min <= cores$col_max), "CORE_GEOMETRY", "Inverted rectangle")
  cores <- cores[order(cores$core_id), c("core_id", "row_min", "row_max", "col_min", "col_max"), drop = FALSE]
  row.names(cores) <- NULL
  owner <- rep(NA_character_, n); expected <- character(); core_pairs <- character()
  for (i in seq_len(nrow(cores))) {
    id <- cores$core_id[i]
    inside <- rr >= cores$row_min[i] & rr <= cores$row_max[i] & cc >= cores$col_min[i] & cc <= cores$col_max[i]
    need(all(is.na(owner[inside])), "DUPLICATE_OWNER", "A cell belongs to two cores")
    owner[inside] <- id
    halo <- rr >= cores$row_min[i] - 1 & rr <= cores$row_max[i] + 1 & cc >= cores$col_min[i] - 1 & cc <= cores$col_max[i] + 1
    expected <- c(expected, paste(id, uid[halo], sep = "|"))
    core_pairs <- c(core_pairs, paste(id, uid[inside], sep = "|"))
  }
  need(!anyNA(owner), "MISSING_CORE", "Core rectangles must cover the entire declared grid")
  need(text(evidence$available_cores) && !anyDuplicated(evidence$available_cores) &&
    setequal(evidence$available_cores, cores$core_id), "MISSING_CORE", "Every declared owner must be available")

  nodes <- graph$nodes
  node_fields <- c("cell_uid", "global_row", "global_col", "owner_core", "kind", "water_class", "pointer", "valid", "source_uid")
  table(nodes, node_fields, 27L, "NODE_FIELDS")
  need(text(nodes$cell_uid) && !anyDuplicated(nodes$cell_uid), "DUPLICATE_CELL", "Unique cell rows required")
  need(nrow(nodes) == n && setequal(nodes$cell_uid, uid), "NODE_COVERAGE", "Every declared grid position needs an explicit node")
  nodes <- nodes[match(uid, nodes$cell_uid), node_fields, drop = FALSE]; row.names(nodes) <- NULL
  need(whole(nodes$global_row, min(rr), max(rr)) && whole(nodes$global_col, min(cc), max(cc)) &&
    identical(as.numeric(nodes$global_row), as.numeric(rr)) && identical(as.numeric(nodes$global_col), as.numeric(cc)), "CELL_IDENTITY", "Coordinates disagree with global UID")
  need(text(nodes$owner_core) && identical(nodes$owner_core, owner), "OWNER_CONFLICT", "Node owner disagrees with core census")
  need(is.logical(nodes$valid) && !anyNA(nodes$valid) && all(nodes$valid), "NODATA", "NoData is not a complete local node")
  need(real(nodes$water_class) && !any(is.nan(nodes$water_class)) &&
    all(is.na(nodes$water_class) | nodes$water_class %in% 1:3), "WATER_CLASS", "Only NA-land or known classes 1/2/3")
  land <- is.na(nodes$water_class); water <- !land; v <- sum(land)
  need(text(nodes$kind) && identical(nodes$kind, ifelse(land, "LAND", "WATER")), "CELL_KIND", "Class/land identity conflict")
  need(v <= 11L, "SOURCE_LIMIT", "At most 11 owned land sources")
  need(is.character(nodes$source_uid) && identical(nodes$source_uid[land], uid[land]) &&
    all(is.na(nodes$source_uid[water])), "SOURCE_IDENTITY", "Only owned land cells have one source UID")
  codes <- c(1, 2, 4, 8, 16, 32, 64, 128)
  need(real(nodes$pointer) && !any(is.nan(nodes$pointer)) &&
    all(is.na(nodes$pointer) | (is.finite(nodes$pointer) & nodes$pointer == floor(nodes$pointer) & abs(nodes$pointer) <= 2^53 - 1)),
    "POINTER_VALUE", "Inexact or oversized pointer metadata")
  need(all(nodes$pointer[land] %in% codes), "LAND_POINTER", "Every land source needs one valid nonzero Whitebox pointer")

  obs <- evidence$observations
  table(obs, c("observer_core", "cell_uid", "pointer", "water_class", "valid"), 9L * n, "CENSUS_FIELDS")
  need(text(obs$observer_core) && text(obs$cell_uid), "CENSUS_IDENTITY", "Missing observation identity")
  pairs <- paste(obs$observer_core, obs$cell_uid, sep = "|")
  need(!anyDuplicated(pairs), "DUPLICATE_OBSERVATION", "An observer/cell pair occurs twice")
  need(all(core_pairs %in% pairs), "MISSING_CORE_OBSERVATION", "Independent owned-cell census is incomplete")
  need(all(expected %in% pairs), "MISSING_REQUIRED_HALO", "One-cell halo observation missing")
  need(setequal(pairs, expected), "CENSUS_COVERAGE", "Unexpected core/halo observation")
  oi <- match(obs$cell_uid, uid)
  need(is.logical(obs$valid) && !anyNA(obs$valid) && all(obs$valid), "NODATA_OBSERVATION", "Independent census has NoData")
  need(real(obs$pointer) && real(obs$water_class) &&
    identical(as.numeric(obs$pointer), as.numeric(nodes$pointer[oi])) &&
    identical(as.numeric(obs$water_class), as.numeric(nodes$water_class[oi])), "OBSERVATION_CONFLICT", "Core/halo values disagree with the graph")
  inventory <- evidence$source_inventory
  table(inventory, c("source_uid", "cell_uid", "owner_core", "source_units"), 27L, "INVENTORY_FIELDS")
  need(text(inventory$source_uid) && text(inventory$cell_uid) && text(inventory$owner_core) &&
    !anyDuplicated(inventory$source_uid) && !anyDuplicated(inventory$cell_uid), "DUPLICATE_SOURCE", "Independent source inventory must be unique")
  need(nrow(inventory) == v && setequal(inventory$cell_uid, uid[land]), "SOURCE_COVERAGE", "Independent land-source census disagrees")
  ii <- match(inventory$cell_uid, uid)
  need(identical(inventory$source_uid, inventory$cell_uid) &&
    identical(inventory$owner_core, owner[ii]) && whole(inventory$source_units, 1, 1),
    "SOURCE_UNITS", "One exact source unit per core land cell, none in halo/water")

  edges <- graph$edges
  table(edges, c("from_uid", "to_uid", "d8_code"), 27L, "EDGE_FIELDS")
  need(text(edges$from_uid) && text(edges$to_uid), "EDGE_IDENTITY", "Edge UID missing")
  need(!anyDuplicated(edges$from_uid), "DUPLICATE_SUCCESSOR", "Repeated edge or multiple successors")
  need(nrow(edges) == v && setequal(edges$from_uid, uid[land]), "EDGE_COVERAGE", "Exactly one outgoing edge per land source, none from water")
  from <- match(edges$from_uid, uid); to <- match(edges$to_uid, uid)
  need(!anyNA(to), "MISSING_TARGET", "A successor is absent from the declared grid")
  need(real(edges$d8_code) && all(edges$d8_code %in% codes) &&
    identical(as.numeric(edges$d8_code), as.numeric(nodes$pointer[from])), "D8_POINTER_CONFLICT", "Edge code differs from the observed pointer")
  k <- match(edges$d8_code, codes)
  need(all(rr[to] - rr[from] == c(-1, 0, 1, 1, 1, 0, -1, -1)[k] &
    cc[to] - cc[from] == c(1, 1, 1, 0, -1, -1, -1, 0)[k]), "D8_GEOMETRY", "Whitebox direction does not reach the declared target")

  # Index once. Prove acyclicity and first-water closure BEFORE count allocation.
  successor <- integer(n); successor[from] <- to
  indegree <- tabulate(to, nbins = n); queue <- integer(n); topo <- integer(n)
  ready <- which(indegree == 0L); queue_end <- length(ready); queue[seq_along(ready)] <- ready
  queue_head <- 1L; used <- 0L
  while (queue_head <= queue_end) {
    at <- queue[queue_head]; queue_head <- queue_head + 1L; used <- used + 1L; topo[used] <- at
    target <- successor[at]
    if (target > 0L) {
      indegree[target] <- indegree[target] - 1L
      if (indegree[target] == 0L) { queue_end <- queue_end + 1L; queue[queue_end] <- target }
    }
  }
  need(used == n, "CYCLE", "Topological validation could not close every node")
  first_water <- integer(n)
  for (at in rev(topo)) {
    if (water[at]) first_water[at] <- at else first_water[at] <- first_water[successor[at]]
  }
  need(all(first_water > 0L) && all(water[first_water]), "INCOMPLETE_ENDPOINT", "Every source must terminate at known first water")

  # Only the fully validated DAG reaches this numeric pass; no source-ID sets.
  counts <- as.numeric(land)
  for (at in topo) if (successor[at] > 0L) {
    target <- successor[at]; next_count <- counts[target] + counts[at]
    need(scalar(next_count, 0, v) && scalar(4 * next_count, 0, 4 * v), "NUMERIC_RANGE", "Count/area must be exact integers")
    counts[target] <- next_count
  }
  need(sum(counts[water]) == v, "SOURCE_BALANCE", "First-water counts do not partition local sources")
  result_nodes <- nodes[, c("cell_uid", "owner_core", "kind", "water_class", "source_uid"), drop = FALSE]
  result_nodes$local_upstream_cells <- counts; result_nodes$local_upstream_area_m2 <- 4 * counts
  result_nodes$first_water_uid <- uid[first_water]
  result_nodes$external_import <- rep("UNKNOWN", n)
  result_nodes$total_upstream_cells <- rep(NA_real_, n); result_nodes$total_upstream_area_m2 <- rep(NA_real_, n)
  list(method_version = "02g.3-complete-local-dag-v1", result_kind = "LOCAL_COMPLETE_DAG_NUMERIC",
    membership_mode = "NOT_MATERIALIZED", scope_contract = "COMPLETE_DECLARED_LOCAL_DAG",
    scope_validation = "CONTRACT_AND_STRUCTURE_VALID", external_import = "UNKNOWN",
    nodes = result_nodes, first_water = result_nodes[water, , drop = FALSE],
    balance = data.frame(n_owned_land_sources = v, n_first_water_sources = sum(counts[water]),
      local_source_area_m2 = 4 * v, n_unresolved = 0L, n_approved_exports = 0L),
    identity = graph$identity[identity_fields], evidence_identity = evidence$identity[identity_fields],
    census_producer = evidence$producer_id, ownership = cores[order(cores$core_id), , drop = FALSE], grid = g,
    channel_threshold_cells = 10000L, channel_threshold_area_m2 = 40000,
    hydrological_validation = "NOT_ASSESSED", channel_interpretation = "NOT_ASSESSED",
    MODERATE = "REVIEW_REQUIRED", NATIONAL = "LOCKED")
}
