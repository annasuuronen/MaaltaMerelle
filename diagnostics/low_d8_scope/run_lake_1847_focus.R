# Targeted read-only LOW lake 1847 diagnostic, no Slurm / full raster scan.
# Usage: Rscript --vanilla run_lake_1847_focus.R BASELINE_DIR
args <- commandArgs(trailingOnly=TRUE)
if (length(args)!=1L) stop('Usage: Rscript run_lake_1847_focus.R BASELINE_DIR')
sarg <- grep('^--file=',commandArgs(),value=TRUE)
if(length(sarg)!=1L) stop('Rscript --vanilla required')
script_dir_1847 <- dirname(normalizePath(sub('^--file=','',sarg),mustWork=TRUE))
source(file.path(script_dir_1847,'lake_1847_focus_core.R'),local=TRUE)
source(file.path(script_dir_1847,'lake_to_land_d8_core.R'),local=TRUE)
suppressPackageStartupMessages({library(terra);library(sf)})
base <- normalizePath(args[1L],mustWork=TRUE)
tile_id <- basename(dirname(base))
root <- dirname(dirname(dirname(dirname(base))))
src <- file.path(root,'inputs',tile_id)
gpkg <- file.path(src,paste0('RANTA10_',tile_id,'.gpkg'))
paths <- c(pointer=file.path(base,'d8_pointer_land_water_FLT8S.tif'),
           water=file.path(src,'ranta10_water_class.tif'),
           lake=file.path(src,'ranta10_lake_id.tif'),
           land=file.path(base,'routing_surface_land_water_FLT8S.tif'),
           storage=file.path(base,'routing_surface_water_storage_FLT8S.tif'),
           raw=file.path(base,'land_dem_raw_FLT8S.tif'),
           filled=file.path(base,'land_dem_filled_FLT8S.tif'))
l1847_assert(all(file.exists(paths) & !nzchar(Sys.readlink(paths))) &&
               file.exists(gpkg) && !nzchar(Sys.readlink(gpkg)),
             'SOURCE_RASTERS_OR_RANTA10_VECTOR_MISSING')
rr <- lapply(paths,terra::rast)
p <- rr$pointer
l1847_assert(all(vapply(rr,function(x) terra::nlyr(x)==1L &&
                  terra::compareGeom(p,x,stopOnError=FALSE),logical(1))),
             'LOW_RASTER_GEOMETRY_MISMATCH')
l1847_assert(terra::nrow(p)>10L && terra::ncol(p)>10L &&
               terra::ncell(p)<.Machine$integer.max,'BAD_LOW_RASTER_GRID')
l1847_assert('lakes' %in% sf::st_layers(gpkg)$name,'NO_RANTA10_LAKES_LAYER')
lake <- sf::st_read(gpkg,query='SELECT * FROM lakes WHERE objectid = 1847',quiet=TRUE)
l1847_assert(nrow(lake)==1L && 'objectid' %in% names(lake) &&
               as.integer(lake$objectid[1L])==1847L &&
               sf::st_crs(lake)$epsg==3067L,'LAKE_1847_VECTOR_ID_OR_CRS_FAILURE')
# Bounding window plus 20-m buffer; all lake-ID pixels must be interior.
bbox <- sf::st_bbox(lake)
margin <- 20
rx <- terra::res(p)[1L]; ry <- terra::res(p)[2L]
xlo <- max(terra::xmin(p)+rx/2,as.numeric(bbox['xmin'])-margin)
xhi <- min(terra::xmax(p)-rx/2,as.numeric(bbox['xmax'])+margin)
ylo <- max(terra::ymin(p)+ry/2,as.numeric(bbox['ymin'])-margin)
yhi <- min(terra::ymax(p)-ry/2,as.numeric(bbox['ymax'])+margin)
cells <- terra::cellFromXY(p,rbind(c(xlo,yhi),c(xhi,ylo)))
l1847_assert(length(cells)==2L && !anyNA(cells),'INVALID_LOCAL_BOUNDS')
rc <- terra::rowColFromCell(p,cells)
r0 <- min(rc[,1L]); r1 <- max(rc[,1L]); c0 <- min(rc[,2L]); c1 <- max(rc[,2L])
nr <- as.integer(r1-r0+1L); nc <- as.integer(c1-c0+1L)
l1847_assert(nr>=5L && nc>=5L && as.double(nr)*nc<=500000,
             'LOCAL_WINDOW_TOO_SMALL_OR_LARGE_FOR_LOGIN_NODE')
read_local <- function(x) {
  v <- as.numeric(terra::values(x,mat=FALSE,row=r0,nrows=nr,col=c0,ncols=nc))
  l1847_assert(length(v)==nr*nc,'RASTER_WINDOW_READ_FAILURE')
  matrix(v,nrow=nr,ncol=nc,byrow=TRUE)
}
mat <- lapply(rr,read_local)
source_idx <- which(mat$lake==1847L,arr.ind=TRUE)
l1847_assert(nrow(source_idx)>0L &&
               all(source_idx[,1L]>1L & source_idx[,1L]<nr &
                   source_idx[,2L]>1L & source_idx[,2L]<nc),
             'LAKE_1847_ID_TOUCHES_LOCAL_WINDOW_BORDER: no incomplete scan')
edges <- low_d8_lake_to_land_block(mat$pointer,mat$water,mat$lake,1L,1L,nr,nr)
edges <- edges[edges$lake_objectid==1847L,,drop=FALSE]
summary1847 <- l1847_summary(edges,mat$pointer,mat$water,mat$land,
                             mat$storage,mat$raw,mat$filled,expected=TRUE)
local_to_global <- function(i) l1847_global_cell(i,r0,c0,nc,terra::ncol(p))
source_g <- local_to_global(summary1847$continuing_source)
receiver_g <- local_to_global(summary1847$continuing_receiver)
# Read the *single* continuing connection, with strict 128-step sparse tracing.
# In local window use already loaded matrices; outside only 1-cell sparse reads.
read_global <- function(cell) {
  cr <- (cell-1L)%/%terra::ncol(p)+1L
  cc <- (cell-1L)%%terra::ncol(p)+1L
  if (cr>=r0 && cr<=r1 && cc>=c0 && cc<=c1) {
    ij <- cbind(cr-r0+1L,cc-c0+1L)
    return(list(pointer=mat$pointer[ij],water_class=mat$water[ij],
                lake_id=mat$lake[ij]))
  }
  get <- function(x) as.numeric(terra::values(x,mat=FALSE,row=cr,nrows=1L,
                                               col=cc,ncols=1L))
  list(pointer=get(rr$pointer),water_class=get(rr$water),lake_id=get(rr$lake))
}
trace <- l1847_trace(receiver_g,terra::nrow(p),terra::ncol(p),read_global,128L)
cat('========== LOW: RANTA10 LAKE 1847 FOCUSED D8 QA (READ ONLY) ==========', '\n')
cat('WINDOW_ROWS',nr,'WINDOW_COLS',nc,'WINDOW_CELLS',nr*nc,'\n')
cat('LAKE_1847_RASTER_PIXELS_IN_WINDOW',nrow(source_idx),'\n')
cat('LAKE_1847_TO_LAND_EDGES',summary1847$total,'\n')
cat('LAKE_1847_IMMEDIATE_ZERO_EDGES',summary1847$zero_edges,'\n')
cat('LAKE_1847_UNIQUE_ZERO_RECEIVERS',summary1847$unique_zero,'\n')
cat('LAKE_1847_CONTINUING_LAND_EDGES',summary1847$continuing_edges,'\n')
cat('ZERO_RECEIVERS_RAW_FILL_UNCHANGED',summary1847$distinct_zero_raw_fill_unchanged,'\n')
cat('ZERO_RECEIVERS_RAW_FILL_CHANGED',summary1847$distinct_zero_raw_fill_changed,'\n')
cat('ZERO_RECEIVERS_STORAGE_RAISED',summary1847$distinct_zero_storage_raised,'\n')
cat('ZERO_RECEIVERS_STORAGE_UNCHANGED',summary1847$distinct_zero_storage_equal,'\n')
cat('LAKE_MINUS_LAND_HEIGHT_M_RANGE',paste(signif(summary1847$gap_range,8),collapse=' '),'\n')
cat('LAKE_MINUS_LAND_HEIGHT_M_MEDIAN',signif(summary1847$gap_median,8),'\n')
cat('LAKE_ABOVE_LAND_EDGES',summary1847$source_above_receiver,'\n')
cat('LAKE_LEVEL_WITH_LAND_EDGES',summary1847$source_same_receiver,'\n')
cat('LAKE_BELOW_LAND_EDGES',summary1847$source_below_receiver,'\n')
cat('SOLE_CONTINUING_SOURCE_CELL',source_g,'RECEIVER_CELL',receiver_g,
    'RECEIVER_D8',summary1847$continuing_pointer,'\n')
cat('SOLE_CONTINUING_LAKE_Z',summary1847$continuing_source_z,
    'LAND_Z',summary1847$continuing_receiver_z,'\n')
cat('SOLE_CONTINUING_TRACE_STATUS',trace$status,'TRACE_STEPS',trace$steps,
    'LAST_CELL',trace$cell,'LAST_LAKE_ID',trace$lake_id,'\n')
cat('PASS: LAKE 1847 RECONCILES WITH FULL LOW 198/197/88 SNAPSHOT', '\n')
cat('LIMITATION: BOUNDED TRACE IS NOT HYDROLOGICAL OUTLET APPROVAL', '\n')
cat('SCIENTIFIC_STATUS: REVIEW_REQUIRED; NO DEM D8 OUTLET MODIFICATIONS', '\n')
cat('========== LAKE 1847 REVIEW DONE ==========', '\n')
