# Test-only support. The caller declares `here` as this script directory.
parent <- dirname(here)
source(file.path(parent, "..", "low_d8_scope", "lake_1847_focus_core.R"))
source(file.path(parent, "..", "land_first_water", "first_water_contact.R"))
source(file.path(parent, "..", "land_d8_continuity", "trace_land_d8_route.R"))
source(file.path(parent, "land_network_topology.R"))
source(file.path(parent, "analyse_land_network_topology.R"))
source(file.path(parent, "synthetic_scale", "generator.R"))
source(file.path(parent, "synthetic_scale", "oracle.R"))
checks <- 0L
check <- function(ok, label) {
  checks <<- checks + 1L
  if (!isTRUE(ok)) stop("LONG_PATH_MISMATCH: ", label, call. = FALSE)
}
reference_inventory <- function() {
  pinned <- "effab29aa4d44ecc897efc0c91c96f3bfc1b4db6:diagnostics/land_network_topology/analyse_land_network_topology.R"
  text <- system2("git", c("show", pinned), stdout = TRUE)
  stopifnot(is.null(attr(text, "status")), length(text) > 0L)
  env <- new.env(parent = .GlobalEnv); eval(parse(text = text), envir = env)
  env$analyse_land_network_topology
}
check_inventory_compatibility <- function(current, previous) {
  if (!identical(current, previous)) stop("STOP_BASELINE_MISMATCH: typed inventories differ", call. = FALSE)
  check(TRUE, "complete typed inventory equality")
}
method_bodies <- function() serialize(list(body(build_land_d8_network),
  body(analyse_land_network_topology), body(select_land_network_cases),
  body(trace_land_d8_route), body(first_water_contact), body(l1847_trace)), NULL)
fixture_read <- function(f) {
  pointer <- as.vector(t(f$pointer)); water <- as.vector(t(f$water))
  lake <- as.vector(t(f$lake)); valid <- as.vector(t(f$valid))
  function(cell) list(pointer = pointer[cell], water_class = water[cell],
                      lake_id = lake[cell], valid = valid[cell])
}
serpentine_order <- function(f) unlist(lapply(seq_len(f$grid$nrow), function(r)
  (r - 1L) * f$grid$ncol + if (r %% 2L) seq_len(f$grid$ncol) else rev(seq_len(f$grid$ncol))), use.names = FALSE)
# Two or three fixed shortcuts add serial confluences without any flow split.
# The original successor graph and encoded pointer are changed together only
# in a newly generated synthetic fixture, never in an observed input.
serial_fixture <- function(n) {
  f <- generate_scale_fixture(n, "long")
  rows <- if (n == 100L) c(1L, 5L) else c(1L, 11L, 21L)
  sources <- (rows - 1L) * 10L + 2L
  f$successor[sources] <- sources + 10L
  f$pointer[cbind(rows, 2L)] <- 8
  f$scenario <- "serial"; f$provenance$run_id <- paste0("synthetic:serial:", n)
  f
}
check_more_detail <- function(f, net, inv, ref, cap) {
  check(sum(net$route_summary$route_status == "STEP_LIMIT") == sum(ref$status == "STEP_LIMIT"), "censor counts")
  pointer <- as.vector(t(f$pointer))
  for (i in seq_along(ref$land)) {
    r <- net$routes[[i]]; p <- ref$paths[[i]]
    check(identical(as.integer(r$transitions$from_cell), as.integer(head(p, -1L))) &&
      identical(as.integer(r$transitions$to_cell), as.integer(tail(p, -1L))) &&
      identical(as.numeric(r$transitions$d8_code), as.numeric(pointer[head(p, -1L)])), "every observed transition")
    check(!anyDuplicated(p[seq_along(p) < length(p)]) &&
      sum(r$path$revisited) == as.integer(ref$status[i] == "CYCLE"), "only documented closing revisit")
    check(r$n_transitions <= cap && identical(r$continuation_unresolved,
      ref$status[i] != "FIRST_WATER_CONTACT"), "budget and unresolved continuation")
    if (ref$status[i] == "STEP_LIMIT") check(!net$route_summary$source_uid[i] %in%
      inv$source_routes_per_exit$source_uid, "no borrowed exit membership")
  }
  uid <- function(c) paste(f$grid$grid_id, f$grid$row_offset + f$row[c], f$grid$col_offset + f$col[c], sep = ":")
  for (c in ref$confluences) {
    j <- match(c, ref$land); p <- ref$paths[[j]]
    distance <- 2 * sqrt(diff(f$row[p])^2 + diff(f$col[p])^2)
    got <- inv$shared_segments[inv$shared_segments$confluence_uid == uid(c), ]
    check(nrow(got) == 1L && got$n_unique_cells == length(unique(p)) &&
      got$n_unique_edges == length(p) - 1L &&
      abs(got$observed_length_m - sum(distance)) < 1e-8, "unique shared geometry and physical length")
    members <- inv$source_confluences[inv$source_confluences$confluence_uid == uid(c), ]
    for (s in seq_len(nrow(members))) {
      source <- match(members$source_uid[s], net$land_nodes$cell_uid)
      pos <- match(c, ref$paths[[source]])
      common <- min(ref$steps[j], ref$steps[source] - pos + 1L)
      expected <- sum(head(distance, common))
      check(abs(members$observed_shared_length_m[s] - expected) < 1e-8 &&
        members$n_unique_shared_edges[s] == common, "source-specific common extent, not a borrowed suffix")
    }
  }
  check(inv$extra_raster_reads == 0L && inv$extra_route_traces == 0L &&
    inv$external_inflow == "UNKNOWN" && inv$accumulation == "NOT_COMPUTED", "no inferred continuation or accumulation")
}
check_monotonic <- function(short, long, old_inv, new_inv) {
  check(identical(short$cells, long$cells) && identical(short$edges, long$edges) &&
    identical(short$land_edges, long$land_edges), "unchanged pointer graph across budgets")
  check(identical(old_inv$confluence_incoming, new_inv$confluence_incoming), "unchanged direct incoming edges")
  for (i in seq_along(short$routes)) {
    a <- short$routes[[i]]; b <- long$routes[[i]]
    check(identical(a$path, head(b$path, nrow(a$path))) &&
      identical(a$transitions, head(b$transitions, nrow(a$transitions))) &&
      identical(a$observations[, setdiff(names(a$observations), "pointer_followed")],
        head(b$observations, nrow(a$observations))[, setdiff(names(b$observations), "pointer_followed")]) &&
      all(!a$observations$pointer_followed | head(b$observations$pointer_followed, nrow(a$observations))) &&
      a$n_transitions <= b$n_transitions, "original observation is an unchanged prefix")
    if (a$route_status != "STEP_LIMIT") check(identical(a$route_status, b$route_status) &&
      identical(a$path, b$path), "resolved terminal remains resolved")
  }
  keys <- function(x) paste(x$source_uid, x$confluence_uid, sep = "|")
  k <- match(keys(old_inv$source_confluences), keys(new_inv$source_confluences))
  check(!anyNA(k) && all(new_inv$source_confluences$n_observed_shared_edges[k] >=
    old_inv$source_confluences$n_observed_shared_edges), "monotonic observed membership")
  k <- match(old_inv$source_routes_per_exit$source_uid, new_inv$source_routes_per_exit$source_uid)
  check(!anyNA(k) && identical(old_inv$source_routes_per_exit$exit_cell_uid,
    new_inv$source_routes_per_exit$exit_cell_uid[k]), "confirmed exits preserved without inventing exits")
}
