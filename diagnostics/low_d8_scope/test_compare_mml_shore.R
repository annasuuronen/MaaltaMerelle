# Base-R regression. No sf, terra, or remote data required.
a <- grep('^--file=',commandArgs(),value=TRUE)
stopifnot(length(a)==1L)
source(file.path(dirname(normalizePath(sub('^--file=','',a))),
                 'compare_mml_shore_core.R'))
e <- data.frame(source_cell=c(1L,2L,3L), receiver_cell=c(5L,5L,6L),
                receiver_pointer=c(0L,0L,2L))
flags <- c(TRUE,TRUE,TRUE)
r <- mm_shore_summary(e,flags,c(TRUE,FALSE,TRUE),
   c(FALSE,FALSE,FALSE),c(TRUE,TRUE,FALSE),
   c(0.999,0.999,0.999),c(0.999,0.999,0.999),
   c(0.999,0.999,0.999),c(0.999,0.999,0.999),
   c(1.000,1.000,0.999),c(1.000,1.000,1.000))
stopifnot(r$edges==3L,r$zero_edges==2L,r$zero_receivers==1L,
          r$nonzero_edges==1L,r$unique_zero_receivers_in_mml==1L,
          r$zero_edges_to_mml_water==2L,
          r$distinct_zero_storage_raised==1L,r$source_above_land_edges==3L)
err <- function(q) inherits(tryCatch(force(q),error=identity),'error')
stopifnot(err(mm_shore_summary(e,flags,NA,flags,flags,rep(1,3),rep(1,3),
                  rep(1,3),rep(1,3),rep(1,3),rep(1,3))))
bad <- e; bad$source_cell[2] <- 1L
stopifnot(err(mm_shore_summary(bad,flags,flags,flags,flags,rep(1,3),rep(1,3),
                  rep(1,3),rep(1,3),rep(1,3),rep(1,3))))
bad <- e; bad$receiver_pointer[3] <- 999
stopifnot(err(mm_shore_summary(bad,flags,flags,flags,flags,rep(1,3),rep(1,3),
                  rep(1,3),rep(1,3),rep(1,3))))
cat('PASS: MML/RANTA10 shoreline center classification, shared receivers, elevations, fail closed\n')
# In-memory sf geometry semantics used in the independent vector comparison.
suppressPackageStartupMessages(library(sf))
poly <- sf::st_sfc(sf::st_polygon(list(matrix(c(0,0,4,0,4,4,0,4,0,0),
                                             ncol=2,byrow=TRUE))),crs=3067)
points <- sf::st_as_sf(data.frame(x=c(1,5),y=c(1,1)),
                      coords=c('x','y'),crs=3067)
stopifnot(identical(lengths(sf::st_covered_by(points,poly))>0L,c(TRUE,FALSE)))
d <- as.numeric(sf::st_distance(points,sf::st_boundary(poly)))
stopifnot(length(d)==2L, all(abs(d-1)<1e-8))
cat('PASS: sf shoreline water/land coverage and nearest-boundary distances\n')
