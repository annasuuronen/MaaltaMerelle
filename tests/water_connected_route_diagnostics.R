source(file.path("R", "02F_water_connected_route_diagnostics.R"))

pointer <- rep(0, 16L)
water_class <- rep(NA_real_, 16L)
lake_id <- rep(NA_real_, 16L)

water_class[c(1L, 2L, 3L, 8L)] <- c(2, 1, 1, 3)
lake_id[c(2L, 3L)] <- c(20, 10)
pointer[c(4L, 6L, 7L, 9L, 10L, 11L, 12L, 14L, 15L)] <-
  c(8, 0, 3, 16, 8, 8, NA, 128, 128)

candidate_edges <- data.frame(
  spill_group_id = c(1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L, 9L, 10L, 11L, 12L),
  lake_objectid = c(10L, 10L, 10L, 10L, 10L, 10L, 10L, 10L, 10L, 10L, 20L, 10L),
  source_cell = c(20L, 21L, 22L, 23L, 24L, 25L, 26L, 27L, 28L, 29L, 30L, 31L),
  receiver_cell = c(1L, 2L, 3L, 4L, 6L, 7L, 12L, 9L, 10L, 15L, 3L, 1L),
  stringsAsFactors = FALSE
)

values <- function(raster, cells) raster[cells]
routes <- trace_water_connected_candidate_routes(
  candidate_edges = candidate_edges,
  ptr_land_water = pointer,
  water_class = water_class,
  lake_id = lake_id,
  nrow_raster = 4L,
  ncol_raster = 4L,
  cell_values = values,
  max_steps = 16L
)

route_for <- function(cell, origin = 10L) {
  routes$routes[
    routes$routes$start_receiver_cell == cell &
      routes$routes$origin_lake_objectid == origin,
    ,
    drop = FALSE
  ]
}

stopifnot(
  route_for(1L)$route_status == "REACHES_RIVER_AREA",
  route_for(2L)$route_status == "REACHES_OTHER_LAKE",
  route_for(3L, 10L)$route_status == "RETURNS_TO_ORIGIN_LAKE",
  route_for(3L, 20L)$route_status == "REACHES_OTHER_LAKE",
  route_for(4L)$route_status == "REACHES_RIVER_LINE",
  route_for(4L)$route_steps == 1L,
  route_for(6L)$route_status == "D8_ZERO_INTERIOR",
  route_for(7L)$route_status == "D8_POINTER_INVALID",
  route_for(12L)$route_status == "D8_POINTER_NA",
  route_for(9L)$route_status == "D8_DOMAIN_EXIT",
  route_for(10L)$route_status == "D8_CYCLE",
  route_for(15L)$route_status == "D8_CYCLE",
  nrow(routes$routes) == 11L,
  nrow(routes$edge_routes) == nrow(candidate_edges),
  nrow(routes$group_summary) == nrow(candidate_edges),
  all(routes$qa$pass)
)

limited <- trace_water_connected_candidate_routes(
  candidate_edges = candidate_edges[10L, , drop = FALSE],
  ptr_land_water = pointer,
  water_class = water_class,
  lake_id = lake_id,
  nrow_raster = 4L,
  ncol_raster = 4L,
  cell_values = values,
  max_steps = 1L
)
stopifnot(limited$routes$route_status == "STEP_LIMIT")

empty <- trace_water_connected_candidate_routes(
  candidate_edges = candidate_edges[FALSE, , drop = FALSE],
  ptr_land_water = pointer,
  water_class = water_class,
  lake_id = lake_id,
  nrow_raster = 4L,
  ncol_raster = 4L,
  cell_values = values,
  max_steps = 16L
)
stopifnot(nrow(empty$routes) == 0L, all(empty$qa$pass))

cat("PASS: 02F classifies downstream D8 route terminals without changing pointers\n")
