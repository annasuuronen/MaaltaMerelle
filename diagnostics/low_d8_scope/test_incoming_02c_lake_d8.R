# Base-R regression for all 8 Whitebox directions, reporting and fail-closed inputs.
script <- sub('^--file=', '', grep('^--file=', commandArgs(), value = TRUE)[1L])
source(file.path(dirname(normalizePath(script, mustWork = TRUE)), 'incoming_02c_lake_d8.R'))
# 8x8 grid; 02C D8=0 land terminal is row4,col4 (cell28).
zeros <- data.frame(cell = 28L, component_id = 5L, z_m = 0.3)
components <- data.frame(component_id = 5L,
                         connector_status = 'SAFE_LAKE_CONNECTOR', n_zero_cells = 1L)
# Neighbor locations NW, N, NE, W, E, SW, S, SE.
# Whitebox pointer codes INTO center are SE=4, S=8, SW=16, E=2,
# W=32, NE=1, N=128, NW=64, respectively.
water_cells <- c(19L, 20L, 21L, 27L, 29L, 35L, 36L, 37L)
codes <- c(4, 8, 16, 2, 32, 1, 128, 64)
water <- data.frame(component_id = rep(5L, 8L),
                    source_cell = rep(28L, 8L), water_cell = water_cells,
                    water_class = c(rep(1L, 6L), 3L, 1L),
                    lake_objectid = c(rep(101L, 6L), NA_integer_, 101L),
                    water_z_m = rep(0.4, 8L))
pointers <- stats::setNames(codes, as.character(water_cells))
y <- low_02c_incoming(zeros, water, components, pointers, 8L, 8L)
stopifnot(nrow(y) == 1L, y$has_incoming_lake_D8,
          y$n_incoming_lake_edges == 7L, y$n_incoming_river_edges == 1L,
          y$elevation_class == 'BELOW')
pointers[] <- 0
z <- low_02c_incoming(zeros, water, components, pointers, 8L, 8L)
stopifnot(!z$has_incoming_lake_D8, z$n_incoming_lake_edges == 0L,
          z$n_incoming_river_edges == 0L)
err <- function(expression) inherits(tryCatch(force(expression), error = identity), 'error')
stopifnot(err(low_02c_incoming(zeros, water, components, pointers[-1L], 8L, 8L)))
bad <- water; bad$water_cell[1L] <- 17L # row3,col1 -> nonadjacent to 28
stopifnot(err(low_02c_incoming(zeros, bad, components, pointers, 8L, 8L)))
bad <- water; bad$water_cell[2L] <- 19L # duplicate source-water pair
stopifnot(err(low_02c_incoming(zeros, bad, components, pointers, 8L, 8L)))
bad <- water; bad$lake_objectid[1L] <- NA_integer_
stopifnot(err(low_02c_incoming(zeros, bad, components, pointers, 8L, 8L)))
bad <- zeros; bad$cell[1L] <- 29L
stopifnot(err(low_02c_incoming(bad, water, components, pointers, 8L, 8L)))
badptr <- pointers; badptr['20'] <- 999
stopifnot(err(low_02c_incoming(zeros, water, components, badptr, 8L, 8L)))
cat('PASS: all 8 Whitebox D8 directions; no-incoming and invalid inputs fail closed\n')
