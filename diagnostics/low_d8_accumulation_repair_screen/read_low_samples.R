#!/usr/bin/env Rscript
# Bounded read-only: three existing CSC rasters, exact numeric cell IDs.
args <- commandArgs(trailingOnly=TRUE)
if (length(args)!=2L || !requireNamespace("terra",quietly=TRUE)) stop("STOP: R_ARGS_OR_TERRA")
root <- "/scratch/project_2004707/pienvedet/csc_validation_4bbf22b"
base <- file.path(root,"hydro_01_02/runs/E200000_N6900000/02_baseline")
inp <- file.path(root,"inputs/E200000_N6900000")
files <- c(pointer=file.path(base,"d8_pointer_land_water_FLT8S.tif"),
           z=file.path(base,"routing_surface_land_water_FLT8S.tif"),
           water_class=file.path(inp,"ranta10_water_class.tif"))
if (!all(file.exists(files))) stop("STOP: REQUIRED_RASTER_MISSING")
cells <- read.csv(args[[1L]],stringsAsFactors=FALSE)
if (!identical(names(cells),"cell_id") || nrow(cells)<256L ||
    nrow(cells)>2304L || anyNA(cells$cell_id) ||
    anyDuplicated(cells$cell_id) ||
    any(cells$cell_id != floor(cells$cell_id)) ||
    any(cells$cell_id<1 | cells$cell_id>36000000))
  stop("STOP: INVALID_BOUNDED_CELL_REQUEST")
ids <- as.numeric(cells$cell_id)
rasters <- lapply(files, terra::rast)
check <- function(x) {
  bounds <- as.vector(terra::ext(x))
  isTRUE(terra::nrow(x)==6000L && terra::ncol(x)==6000L &&
         terra::nlyr(x)==1L &&
         all(abs(terra::res(x)-c(2,2))<1e-9) &&
         all(abs(bounds-c(199000,211000,6899000,6911000))<1e-7) &&
         terra::same.crs(x,"EPSG:3067"))
}
if (!all(vapply(rasters,check,logical(1)))) stop("STOP: RASTER_GEOMETRY")
read_exact <- function(x) {
  v <- terra::extract(x,ids,raw=TRUE)
  if (is.matrix(v) || is.data.frame(v)) {
    if (ncol(v)!=1L || !is.numeric(v[,1L])) stop("STOP: EXTRACT_SCHEMA")
    v <- v[,1L]
  }
  if (!is.numeric(v) || !is.null(dim(v)) || length(v)!=length(ids))
    stop("STOP: EXTRACT_BUDGET_OR_TYPE")
  v
}
v <- lapply(rasters,read_exact)
out <- data.frame(cell_id=ids,pointer=v$pointer,z=v$z,water_class=v$water_class)
write.csv(out,args[[2L]],row.names=FALSE,quote=FALSE,na="NaN")
cat("RASTER_READ_CALLS=3 UNIQUE_CELLS=",length(ids),
    " RETURNED_VALUES=",3L*length(ids),"\n",sep="")
