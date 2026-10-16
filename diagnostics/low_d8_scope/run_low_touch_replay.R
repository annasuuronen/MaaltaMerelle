# READ ONLY. Two local LOW RANTA10 rasterization replays (touches TRUE vs FALSE).
# Usage: Rscript --vanilla run_low_touch_replay.R BASELINE_DIR [MML_2025_GPKG]
args <- commandArgs(trailingOnly=TRUE)
if (!(length(args) %in% c(1L,2L))) stop('Usage: Rscript run_low_touch_replay.R BASELINE_DIR [MML_2025_GPKG]')
sa <- grep('^--file=',commandArgs(),value=TRUE)
if (length(sa)!=1L) stop('Rscript --vanilla required')
script_dir_touch <- dirname(normalizePath(sub('^--file=','',sa),mustWork=TRUE))
source(file.path(script_dir_touch,'low_touch_replay_core.R'),local=TRUE)
source(file.path(script_dir_touch,'lake_to_land_d8_core.R'),local=TRUE)
suppressPackageStartupMessages({library(sf);library(terra)})
base <- normalizePath(args[1],mustWork=TRUE)
tile <- basename(dirname(base))
study <- dirname(dirname(dirname(dirname(base))))
src <- file.path(study,'inputs',tile)
ranta_gpkg <- file.path(src,paste0('RANTA10_',tile,'.gpkg'))
mml_gpkg <- if(length(args)==2L) args[2L] else
  '/dataset/project_2019680/mml/maastotietokanta/2025/gpkg/MTK-vakavesi_25-04-03.gpkg'
paths <- c(ptr=file.path(base,'d8_pointer_land_water_FLT8S.tif'),
           class=file.path(src,'ranta10_water_class.tif'),
           id=file.path(src,'ranta10_lake_id.tif'))
for (f in c(paths,ranta_gpkg,mml_gpkg))
  low_touch_require(file.exists(f) && !dir.exists(f) && !nzchar(Sys.readlink(f)),
                    paste('MISSING_OR_LINKED_INPUT',f))
rr <- lapply(paths,terra::rast)
p <- rr$ptr
low_touch_require(all(vapply(rr,function(x) terra::nlyr(x)==1L &&
                     terra::compareGeom(x,p,stopOnError=FALSE),logical(1))) &&
                    sf::st_crs(terra::crs(p))$epsg==3067L &&
                    terra::nrow(p)>3L && terra::ncol(p)>3L &&
                    terra::ncell(p)<.Machine$integer.max,'GRID_OR_CRS_MISMATCH')
low_touch_require('lakes' %in% sf::st_layers(ranta_gpkg)$name &&
                  'jarvi' %in% sf::st_layers(mml_gpkg)$name,
                  'REQUIRED_VECTOR_LAYER_MISSING')
# The source-side QA receipt is optional; its presence supports provenance,
# while its absence must NOT be silently treated as proven raster provenance.
qa_path <- file.path(src,'00A_validation_fixture_QA.csv')
if (file.exists(qa_path) && !nzchar(Sys.readlink(qa_path)) &&
    !is.na(file.info(qa_path)$size) && file.info(qa_path)$size<1000000) {
  receipt <- read.csv(qa_path,stringsAsFactors=FALSE)
  low_touch_require(all(c('item','value') %in% names(receipt)),
                    'BAD_VALIDATION_FIXTURE_RECEIPT')
  vals <- as.character(receipt$value[receipt$item=='rasterization_touches'])
  low_touch_require(length(vals)==1L && vals %in% c('TRUE','FALSE'),
                    'BAD_RASTERIZATION_RECEIPT_VALUE')
  cat('SOURCE_00A_RECEIPT_RASTERIZATION_TOUCHES:',vals,'\n')
} else {
  cat('SOURCE_00A_RECEIPT_RASTERIZATION_TOUCHES: NOT_VERIFIED_NO_RECEIPT\n')
}

cat('========== LOW: RANTA10 TOUCH RASTER REPLAY AND MML GEOMETRY MATCH ==========', '\n')
for (lid in c(1847L,1898L)) {
  ranta <- sf::st_read(ranta_gpkg,query=sprintf(
      'SELECT * FROM lakes WHERE objectid = %d',lid),quiet=TRUE)
  low_touch_require(nrow(ranta)==1L && 'objectid' %in% names(ranta) &&
                    as.integer(ranta$objectid[1L])==lid &&
                    sf::st_crs(ranta)$epsg==3067L &&
                    all(sf::st_is_valid(ranta)),'RANTA10_ID_OR_GEOMETRY_INVALID')
  bb <- sf::st_bbox(ranta)
  cellsize <- terra::res(p)
  xy <- rbind(c(max(terra::xmin(p)+cellsize[1L]/2,as.numeric(bb['xmin'])-30),
                min(terra::ymax(p)-cellsize[2L]/2,as.numeric(bb['ymax'])+30)),
              c(min(terra::xmax(p)-cellsize[1L]/2,as.numeric(bb['xmax'])+30),
                max(terra::ymin(p)+cellsize[2L]/2,as.numeric(bb['ymin'])-30)))
  bounds <- terra::cellFromXY(p,xy)
  low_touch_require(length(bounds)==2L && !anyNA(bounds), 'BAD_LOCAL_WINDOW_COORDS')
  rc <- terra::rowColFromCell(p,bounds)
  r0 <- min(rc[,1L]); r1<-max(rc[,1L]); c0<-min(rc[,2L]); c1<-max(rc[,2L])
  nr<-as.integer(r1-r0+1L); nc<-as.integer(c1-c0+1L)
  low_touch_require(nr>=5L && nc>=5L && as.double(nr)*nc<=500000,
                    'WINDOW_EXCEEDS_LOGIN_NODE_SCOPE')
  readm <- function(x) {
    a <- as.numeric(terra::values(x,mat=FALSE,row=r0,nrows=nr,
                                  col=c0,ncols=nc))
    low_touch_require(length(a)==nr*nc,'RASTER_WINDOW_READ_FAILED')
    matrix(a,nrow=nr,ncol=nc,byrow=TRUE)
  }
  m <- lapply(rr,readm)
  pixels <- which(m$id==lid,arr.ind=TRUE)
  low_touch_require(nrow(pixels)>0L &&
       all(pixels[,1L]>1L & pixels[,1L]<nr &
           pixels[,2L]>1L & pixels[,2L]<nc),
                    'TARGET_LAKE_TOUCHES_WINDOW_BORDER')
  ed <- low_d8_lake_to_land_block(m$ptr,m$class,m$id,1L,1L,nr,nr)
  ed <- ed[ed$lake_objectid==lid,,drop=FALSE]
  expect <- if(lid==1847L) c(198L,197L,88L) else c(189L,55L,26L)
  # Strict grid alignment: identical origin/resolution as the locked existing raster.
  template <- terra::rast(nrows=nr,ncols=nc,
    xmin=terra::xmin(p)+(c0-1L)*cellsize[1L],
    xmax=terra::xmin(p)+c1*cellsize[1L],
    ymin=terra::ymax(p)-r1*cellsize[2L],
    ymax=terra::ymax(p)-(r0-1L)*cellsize[2L],
    crs=terra::crs(p))
  replay_t <- terra::rasterize(terra::vect(ranta),template,
                        field='objectid',background=NA,touches=TRUE)
  replay_c <- terra::rasterize(terra::vect(ranta),template,
                        field='objectid',background=NA,touches=FALSE)
  summary <- low_touch_replay_summary(m$id,matrix(
    as.numeric(terra::values(replay_t)),nr,nc,byrow=TRUE),
    matrix(as.numeric(terra::values(replay_c)),nr,nc,byrow=TRUE),
    ed,lid,expect)
  # Check actual MML polygon is an overlapping geometric counterpart, not merely nearby.
  roi <- sf::st_buffer(sf::st_as_sfc(bb),40)
  mml <- sf::st_read(mml_gpkg,layer='jarvi',
      wkt_filter=as.character(sf::st_as_text(roi[[1L]])),quiet=TRUE)
  low_touch_require(nrow(mml)>0L && nrow(mml)<=3000L &&
    sf::st_crs(mml)$epsg==3067L && all(sf::st_is_valid(mml)),
    'NO_VALID_MML_LOCAL_POLYGON')
  area_ranta <- as.numeric(sf::st_area(ranta))[1L]
  area_mml <- as.numeric(sf::st_area(mml))
  overlaps <- vapply(seq_len(nrow(mml)),function(i) {
    suppressWarnings(x <- sf::st_intersection(sf::st_geometry(ranta),
                                               sf::st_geometry(mml)[i]))
    if(!length(x)) return(0)
    sum(as.numeric(sf::st_area(x)))
  },numeric(1))
  low_touch_require(is.finite(area_ranta) && area_ranta>0 &&
     all(is.finite(area_mml) & area_mml>0) &&
     all(is.finite(overlaps)) && all(overlaps>=0),
     'INVALID_VECTOR_AREAS')
  match_idx<-which.max(overlaps)
  ov <- overlaps[match_idx]
  iou <- ov/(area_ranta+area_mml[match_idx]-ov)
  low_touch_require(is.finite(iou) && iou>=0 && iou<=1+1e-5,
                    'INVALID_VECTOR_OVERLAP')
  cat('---------- LAKE',lid,'----------\n')
  cat('WINDOW_CELLS:',nr*nc,'\n')
  for (key in names(summary)) cat(toupper(key),':',summary[[key]],'\n')
  cat('NEARBY_MML_POLYGONS:',nrow(mml),'\n')
  cat('MAX_OVERLAP_MML_RANTA10_AREA_M2:',round(ov,3),'\n')
  cat('MML_MAX_OVERLAP_OF_RANTA10_POLYGON_PCT:',round(100*ov/area_ranta,3),'\n')
  cat('RANTA10_MAX_OVERLAP_OF_MML_POLYGON_PCT:',round(100*ov/area_mml[match_idx],3),'\n')
  cat('MAX_OVERLAP_MML_RANTA10_IOU:',round(iou,6),'\n')
  cat('NOTE: overlap measures geometry, not semantic lake identity or outlet\n')
}
cat('PASS: LOW 1847/1898 RANTA10 touches-vs-centers replay and MML geometry QA\n')
cat('LIMITATION: local single-lake replay is not a bytewise reproduction of whole-layer rasterization\n')
cat('SCIENTIFIC_STATUS: REVIEW_REQUIRED; NO RASTER D8 DEM OR OUTLET MODIFICATIONS\n')
cat('========== LOW TOUCH RULE REVIEW DONE ==========\n')
