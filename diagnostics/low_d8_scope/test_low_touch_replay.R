# Small synthetic test, no original raster access. Uses sf/terra locally.
sa <- grep('^--file=',commandArgs(),value=TRUE)
stopifnot(length(sa)==1L)
script_home <- dirname(normalizePath(sub('^--file=','',sa)))
source(file.path(script_home,'low_touch_replay_core.R'))
suppressPackageStartupMessages({library(sf);library(terra)})
r <- terra::rast(nrows=4L,ncols=4L,xmin=0,xmax=4,ymin=0,ymax=4,crs='EPSG:3067')
# Small polygon in a single lower-left pixel: touched != center.
g <- sf::st_sfc(sf::st_polygon(list(matrix(c(0.1,0.1,0.3,0.1,
  0.3,0.3,0.1,0.3,0.1,0.1),ncol=2,byrow=TRUE))),crs=3067)
f <- sf::st_sf(objectid=1847L,geometry=g)
a <- terra::rasterize(terra::vect(f),r,field='objectid',touches=TRUE)
b <- terra::rasterize(terra::vect(f),r,field='objectid',touches=FALSE)
stopifnot(sum(!is.na(terra::values(a)))==1L,
          sum(!is.na(terra::values(b)))==0L)
# Pixel 13 (lower left) is a touched lake and points into pixel 14 (land).
id <- matrix(NA_integer_,4L,4L)
id[4,1] <- 1847L
ap <- matrix(as.integer(terra::values(a)),4L,4L,byrow=TRUE)
bp <- matrix(as.integer(terra::values(b)),4L,4L,byrow=TRUE)
ed <- data.frame(lake_objectid=1847L,source_cell=13L,receiver_cell=14L,
                 receiver_pointer=0L)
s <- low_touch_replay_summary(id,ap,bp,ed,1847L,c(1L,1L,1L))
stopifnot(s[['original_pixels_not_touched_by_polygon']]==0,
          s[['source_centers_inside_vector']]==0,
          s[['source_footprints_touch_vector']]==1,
          s[['land_receiver_footprints_touch_vector']]==0)
error <- function(expr) inherits(tryCatch(force(expr),error=identity),'error')
wrong <- bp; wrong[4,1] <- 1847L
stopifnot(error(low_touch_replay_summary(id,bp,wrong,ed,1847L,c(1L,1L,1L))))
stopifnot(error(low_touch_replay_summary(id,ap,bp,ed,1847L,c(2L,1L,1L))))
stopifnot(error(low_touch_replay_summary(id,ap,bp,ed,1898L,c(1L,1L,1L))))
cat('PASS: touch-vs-center replay, original mask comparison, fail-closed cases\n')
