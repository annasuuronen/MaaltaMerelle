#!/usr/bin/env Rscript
# New, tiny compatibility subset only; no historical campaign or real raster.
here <- dirname(normalizePath(sub('^--file=', '', grep('^--file=', commandArgs(), value=TRUE))))
old <- file.path(dirname(here), 'land_network_topology')
source(file.path(old, 'run_one_low_network_window.R'))
source(file.path(old, 'run_low_boundary_receivers.R'))
source(file.path(old, 'boundary_receivers.R'))
stopifnot(requireNamespace('terra', quietly=TRUE))
work <- tempfile('pr22-tiny-'); dir.create(work)
cases <- 0L; failed <- 0L
assert <- function(x) if (!isTRUE(x)) stop('ASSERTION_FAILED')
reject <- function(expr) { e <- tryCatch({force(expr); NULL}, error=identity); assert(inherits(e,'error')) }
case <- function(label, expr) {
  cases <<- cases + 1L
  tryCatch({ force(expr); cat('PASS:',label,'\n') }, error=function(e) {
    failed <<- failed+1L; cat('FAIL:',label,conditionMessage(e),'\n')
  })
}
main <- function() {
  on.exit(unlink(work, recursive=TRUE))
  cat('R_VERSION=',as.character(getRversion()),' TERRA_VERSION=',as.character(packageVersion('terra')),'\n',sep='')
  # Non-square, row-major numeric cell IDs, unsorted request, first/last cells.
  r <- terra::rast(nrows=12,ncols=13,xmin=200000,xmax=200026,ymin=6900000,ymax=6900024,crs='EPSG:3067')
  values <- seq_len(156)*10; values[50] <- NA_real_
  path <- file.path(work,'tiny.tif'); terra::writeRaster(terra::setValues(r,values),path,datatype='FLT8S')
  r <- terra::rast(path); reader <- low_boundary_terra_backend()$read_cells
  ids <- c(156,1,50,13,14,27,39,91,82,63,101,107,131,144)
  case('numeric-ID extraction preserves exact request order and NoData', {
    sampled <- as.numeric(reader(r,ids)); expected <- as.numeric(values[ids])
    # GeoTIFF NoData may come back as NaN rather than R's NA_real_. Both
    # must stay missing; compare every nonmissing numeric value exactly.
    assert(identical(is.na(sampled),is.na(expected)))
    assert(identical(sampled[!is.na(sampled)],expected[!is.na(expected)]))
    xy <- terra::xyFromCell(r,ids)
    rows <- (ids-1)%/%13+1; cols <- (ids-1)%%13+1
    assert(all(xy[,1]==200000+(cols-0.5)*2))
    assert(all(xy[,2]==6900024-(rows-0.5)*2))
  })
  case('malformed IDs are rejected before extraction', {
    for (bad in list(ids[-1],c(ids,2),replace(ids,1,ids[2]),replace(ids,1,1.5),
                     replace(ids,1,0),replace(ids,1,157),replace(ids,1,NA_real_),as.character(ids)))
      reject(reader(r,bad))
  })
  case('four-raster adapter returns only fourteen values per requested raster', {
    seen <- list(); rasters <- setNames(rep(list(r),4),c('pointer','water','lake','land'))
    exact <- function(x, cells) {seen[[length(seen)+1L]] <<- cells;reader(x,cells)}
    out <- read_boundary_cells(rasters,ids,exact,156)
    assert(length(seen)==4L && all(vapply(seen,identical,logical(1),ids)))
    assert(out$returned_values==56L && out$unique_cell_positions==14L)
  })
  # Existing metadata validator against temporary tiny synthetic rasters only.
  base <- file.path(work,'E200000_N6900000','02_baseline')
  input <- file.path(dirname(base),'01_inputs'); waterdir <- file.path(work,'water')
  dir.create(base,recursive=TRUE);dir.create(input);dir.create(waterdir)
  files <- c(pointer=file.path(base,'d8_pointer_land_water_FLT8S.tif'),
    water=file.path(waterdir,'ranta10_water_class.tif'),lake=file.path(waterdir,'ranta10_lake_id.tif'),
    land=file.path(base,'routing_surface_land_water_FLT8S.tif'))
  for (p in files) assert(file.copy(path,p))
  write.csv(data.frame(key=c('pointer_scheme','test_id','cell_size_m','water_class_raster','lake_id_raster'),
    value=c('whitebox','E200000_N6900000','2',files['water'],files['lake'])),file.path(input,'01_input_manifest.csv'),row.names=FALSE)
  write.csv(data.frame(item=c('dem_rows','dem_cols','dem_res_x','dem_res_y','xmin','xmax','ymin','ymax'),
    value=c(12,13,2,2,200000,200026,6900000,6900024)),file.path(input,'01_input_QA.csv'),row.names=FALSE)
  case('compatible four-raster geometry is accepted without a sample read', {
    backend <- low_network_terra_backend();backend$read_window <- function(...)stop('FORBIDDEN')
    x <- low_network_open_inputs(base,backend=backend,expected_full_grid=list(nrow=12,ncol=13))
    assert(all(vapply(x$headers,function(h)h$crs_ok,logical(1))))
  })
  case('shifted CRS resolution layer and full-grid conflicts stop at headers', {
    backend <- low_network_terra_backend(); original <- backend$header
    for (kind in c('shift','crs','resolution','layers')) {
      backend$header <- function(x) {
        h <- original(x)
        if (kind=='shift') {h$xmin<-h$xmin+2;h$xmax<-h$xmax+2}
        if (kind=='crs') h$crs_ok <- FALSE
        if (kind=='resolution') h$resolution <- c(1,1)
        if (kind=='layers') h$nlyr <- 2
        h
      }
      reject(low_network_open_inputs(base,backend=backend))
    }
    reject(low_network_open_inputs(base,expected_full_grid=list(nrow=6000,ncol=6000)))
  })
  case('a single shifted raster is rejected independently of common-grid checks', {
    shifted <- terra::rast(nrows=12,ncols=13,xmin=200002,xmax=200028,ymin=6900000,ymax=6900024,crs='EPSG:3067')
    terra::writeRaster(terra::setValues(shifted,1),files['water'],overwrite=TRUE)
    reject(low_network_open_inputs(base))
  })
  cat(sprintf('SUITE_RESULT cases=%d pass=%d fail=%d not_run=0\n',cases,cases-failed,failed))
  if (cases==0L || failed) quit(status=1L)
}
main()
