# Small regression. Does not read CSC data or any raster.
script <- grep('^--file=', commandArgs(), value = TRUE)
stopifnot(length(script) == 1L)
source(file.path(dirname(normalizePath(sub('^--file=', '', script))),
                 'mml_gap_component_core.R'))
# 5x6: zero receivers (2,2), (2,3) connect; (5,6) isolated.
ids <- as.integer(c((2-1)*6+2, (2-1)*6+3, (5-1)*6+6))
a <- gap_zero_components(ids, 5L, 6L)
counts <- gap_component_counts(a, as.integer(c(ids[1],ids[1],ids[2],ids[3])))
stopifnot(nrow(counts)==2L, identical(sort(counts$zero_cells), c(1L,2L)),
          identical(sort(counts$incoming_zero_edges), c(1L,3L)),
          sum(counts$zero_cells)==3L, sum(counts$incoming_zero_edges)==4L)
# No wrapping from last column to first column in the next row.
b <- gap_zero_components(as.integer(c(6L,7L)), 5L, 6L)
stopifnot(length(unique(b$component)) == 2L)
fails <- function(x) inherits(tryCatch(force(x), error=identity), 'error')
stopifnot(fails(gap_zero_components(c(2L,2L),5L,6L)),
          fails(gap_zero_components(c(1L,99L),5L,6L)),
          fails(gap_component_counts(a, as.integer(c(1L,99L,2L)))))
suppressPackageStartupMessages(library(sf))
g1 <- sf::st_sfc(sf::st_polygon(list(matrix(c(0,0,4,0,4,4,0,4,0,0),
                                        ncol=2,byrow=TRUE))), crs=3067)
g2 <- sf::st_sfc(sf::st_polygon(list(matrix(c(1,0,5,0,5,4,1,4,1,0),
                                        ncol=2,byrow=TRUE))), crs=3067)
diff <- suppressWarnings(sf::st_difference(g2,g1))
pts <- sf::st_as_sf(data.frame(x=c(4.5,2,0.5),y=c(2,2,2)),
                    coords=c('x','y'),crs=3067)
stopifnot(identical(lengths(sf::st_covered_by(pts, diff))>0L,
                    c(TRUE,FALSE,FALSE)),
          abs(as.numeric(sf::st_area(diff))-4)<1e-7)
cat('PASS: MML-only geometry difference and 8-neighbour distinct-zero clustering\n')

# Regression for the real 02F route CSV schema. The origin lake field is
# origin_lake_objectid, NOT lake_objectid. Reject wrong/selected-outlet data.
ev <- data.frame(lake_objectid=c(1847L,1898L),
                 spill_group_id=c(12L,13L),
                 candidate_included=c(TRUE,FALSE),
                 needs_review=c(FALSE,TRUE),
                 outlet_selection=c('UNASSIGNED','UNASSIGNED'))
se <- data.frame(lake_objectid=1847L,spill_group_id=12L,
                 source_cell=13L,receiver_cell=14L)
rt <- data.frame(origin_lake_objectid=1847L,
                 start_receiver_cell=14L,terminal_cell=15L,
                 route_status='D8_ZERO_INTERIOR')
stopifnot(isTRUE(gap_validate_02e_02f(ev,se,rt)))
wrong <- rt; names(wrong)[names(wrong)=='origin_lake_objectid'] <- 'lake_objectid'
stopifnot(fails(gap_validate_02e_02f(ev,se,wrong)))
wrong <- ev; wrong$outlet_selection[1L] <- 'SELECTED'
stopifnot(fails(gap_validate_02e_02f(wrong,se,rt)))
wrong <- rt; wrong$start_receiver_cell[1L] <- 999L
stopifnot(fails(gap_validate_02e_02f(ev,se,wrong)))
wrong <- se; wrong$lake_objectid[1L] <- 1898L
stopifnot(fails(gap_validate_02e_02f(ev,wrong,rt)))
cat('PASS: actual 02E/02F CSV origin_lake_objectid schema and UNASSIGNED invariants\n')
