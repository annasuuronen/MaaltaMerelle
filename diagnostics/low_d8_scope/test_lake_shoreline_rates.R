# Synthetic base-R rate tests; vector geometry test requires sf on CSC.
script_arg <- grep('^--file=', commandArgs(), value = TRUE)
stopifnot(length(script_arg) == 1L)
d <- dirname(normalizePath(sub('^--file=', '', script_arg), mustWork = TRUE))
source(file.path(d, 'lake_shoreline_rates.R'))
counts <- data.frame(lake_objectid = c(3181L, 1847L, 999L),
                     zero_cells = c(30L, 10L, 1L),
                     d8_edges = c(70L, 20L, 1L))
shore <- data.frame(lake_objectid = c(999L, 1847L, 3181L),
                    shoreline_m = c(0, 1000, 2000),
                    touches_tile_edge = c(TRUE, FALSE, TRUE),
                    excluded_tile_border_m = c(100, 0, 0))
z <- low_02c_shoreline_rates(counts, shore)
stopifnot(identical(z$lake_objectid, counts$lake_objectid),
          identical(z$zero_cells_per_shore_km[1:2], c(15, 10)),
          identical(z$d8_edges_per_shore_km[1:2], c(35, 20)),
          is.na(z$zero_cells_per_shore_km[3]),
          identical(z$touches_tile_edge, c(TRUE, FALSE, TRUE)),
          identical(z$excluded_tile_border_m, c(0, 0, 100)))
err <- function(x) inherits(tryCatch(force(x), error = identity), 'error')
stopifnot(err(low_02c_shoreline_rates(counts, shore[-1, , drop = FALSE])))
bad <- shore; bad$lake_objectid[1] <- 3181L
stopifnot(err(low_02c_shoreline_rates(counts, bad)))
bad <- shore; bad$shoreline_m[2] <- -1
stopifnot(err(low_02c_shoreline_rates(counts, bad)))
bad <- shore; bad$touches_tile_edge[2] <- NA
stopifnot(err(low_02c_shoreline_rates(counts, bad)))
bad <- shore; bad$excluded_tile_border_m[2] <- 100
stopifnot(err(low_02c_shoreline_rates(counts, bad)))
if (requireNamespace('sf', quietly = TRUE)) {
  crs <- 3067L
  tile <- c(xmin=0,ymin=0,xmax=10,ymax=10)
  # One partially clipped square: original perimeter 8m; 8m inside tile,
  # incl. a 2m segment coincident with the tile boundary at x=0.
  a <- sf::st_polygon(list(matrix(c(0,3, 2,3, 2,5, 0,5, 0,3),
                                  byrow=TRUE,ncol=2)))
  b <- sf::st_polygon(list(matrix(c(5,5, 7,5, 7,7, 5,7, 5,5),
                                  byrow=TRUE,ncol=2)))
  g <- sf::st_sf(objectid=c(1L,2L), geometry=sf::st_sfc(a,b,crs=crs))
  m <- low_02c_vector_shoreline(g,tile)
  stopifnot(abs(m$shoreline_m[1] - 6) < 1e-7,
            abs(m$excluded_tile_border_m[1] - 2) < 1e-7,
            m$touches_tile_edge[1],
            abs(m$shoreline_m[2] - 8) < 1e-7,
            !m$touches_tile_edge[2])
  cat('PASS: vector shoreline geometry incl. clipped tile border', '\n')
} else {
  cat('SKIP: sf geometry test (sf unavailable)', '\n')
}
cat('PASS: lake shoreline rate normalization, ID join and fail-closed cases', '\n')
# Regression for runner variable collision: sourced 02C QA sets d to a seven-column
# data.frame. The wrapper must retain a separate script-directory variable.
runner_lines <- readLines(file.path(d, 'run_lake_shoreline_rates.R'), warn = FALSE)
stopifnot(any(grepl('shoreline_script_dir_02c <- dirname(', runner_lines, fixed = TRUE)),
          sum(grepl('source(file.path(shoreline_script_dir_02c,', runner_lines,
                    fixed = TRUE)) == 2L,
          !any(grepl('source(file.path(d,', runner_lines, fixed = TRUE)))
cat('PASS: shoreline runner preserves source paths after D8 status loop', '\n')
