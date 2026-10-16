# READ-ONLY: RANTA10 vs MML jarvi 2025 vector coverage at actual LOW D8 shoreline edge centers.
# Focus: 1847; control: 1898. Does NOT identify or modify a hydrological outlet.
# Usage: Rscript --vanilla run_compare_mml_shore.R BASELINE_DIR [MML_VAKAVESI_GPKG]
args <- commandArgs(trailingOnly=TRUE)
if (!(length(args) %in% c(1L,2L))) stop('Usage: Rscript run_compare_mml_shore.R BASELINE_DIR [MML_GPKG]')
sarg <- grep('^--file=',commandArgs(),value=TRUE)
if (length(sarg)!=1L) stop('Run via Rscript --vanilla')
diagnostic_dir_mml <- dirname(normalizePath(sub('^--file=','',sarg),mustWork=TRUE))
source(file.path(diagnostic_dir_mml,'compare_mml_shore_core.R'),local=TRUE)
source(file.path(diagnostic_dir_mml,'lake_to_land_d8_core.R'),local=TRUE)
suppressPackageStartupMessages({library(sf); library(terra)})
base <- normalizePath(args[1],mustWork=TRUE)
tile <- basename(dirname(base))
study_root <- dirname(dirname(dirname(dirname(base))))
source_dir <- file.path(study_root,'inputs',tile)
ranta_gpkg <- file.path(source_dir,paste0('RANTA10_',tile,'.gpkg'))
mml_gpkg <- if(length(args)==2L) args[2L] else
  '/dataset/project_2019680/mml/maastotietokanta/2025/gpkg/MTK-vakavesi_25-04-03.gpkg'
paths <- c(ptr=file.path(base,'d8_pointer_land_water_FLT8S.tif'),
           class=file.path(source_dir,'ranta10_water_class.tif'),
           id=file.path(source_dir,'ranta10_lake_id.tif'),
           dem=file.path(source_dir,'dem_12km_rumpukorjattu.tif'),
           land=file.path(base,'routing_surface_land_water_FLT8S.tif'),
           storage=file.path(base,'routing_surface_water_storage_FLT8S.tif'),
           raw=file.path(base,'land_dem_raw_FLT8S.tif'),
           fill=file.path(base,'land_dem_filled_FLT8S.tif'))
for (path in c(paths,ranta_gpkg,mml_gpkg)) {
  mm_fail(file.exists(path) && !dir.exists(path) && !nzchar(Sys.readlink(path)),
          paste('MISSING_OR_LINKED_INPUT',path))
}
rs <- lapply(paths,terra::rast)
p <- rs$ptr
mm_fail(all(vapply(rs,function(x)terra::nlyr(x)==1L &&
                    terra::compareGeom(x,p,stopOnError=FALSE),logical(1))) &&
          terra::nrow(p)>10L && terra::ncol(p)>10L &&
          terra::ncell(p)<.Machine$integer.max,
        'RASTER_GEOMETRY_MISMATCH')
mm_fail('lakes' %in% sf::st_layers(ranta_gpkg)$name &&
          'jarvi' %in% sf::st_layers(mml_gpkg)$name,
        'RANTA10_OR_MML_LAYER_MISSING')
mm_fail(sf::st_crs(terra::crs(p))$epsg==3067L,
        'RASTER_MUST_BE_EPSG3067')
point_set <- function(global) {
  xy <- terra::xyFromCell(p,global)
  sf::st_as_sf(data.frame(x=xy[,1L],y=xy[,2L]),
               coords=c('x','y'),crs=3067L)
}
inside <- function(points,polygons) {
  if (!nrow(polygons)) return(rep(FALSE,nrow(points)))
  lengths(sf::st_covered_by(points,polygons))>0L
}

cat('========== LOW: 1847 VS 1898 INDEPENDENT MML RANTA10 SHORELINE QA ==========', '\n')
cat('MML_SOURCE: MTK-vakavesi_25-04-03, layer jarvi (2025)', '\n')
for (lid in c(1847L,1898L)) {
  ranta <- sf::st_read(ranta_gpkg,
         query=sprintf('SELECT * FROM lakes WHERE objectid = %d',lid),quiet=TRUE)
  mm_fail(nrow(ranta)==1L && 'objectid' %in% names(ranta) &&
            as.integer(ranta$objectid[1L])==lid &&
            sf::st_crs(ranta)$epsg==3067L &&
            all(sf::st_is_valid(ranta)),'BAD_RANTA10_POLYGON')
  bbox <- sf::st_bbox(ranta)
  roi <- sf::st_buffer(sf::st_as_sfc(bbox),40)
  mml <- sf::st_read(mml_gpkg,layer='jarvi',
                wkt_filter=as.character(sf::st_as_text(roi[[1L]])),quiet=TRUE)
  mm_fail(nrow(mml)>0L && nrow(mml)<=3000L &&
            sf::st_crs(mml)$epsg==3067L &&
            all(sf::st_is_valid(mml)),
          paste('MML_NO_LOCAL_POLYGONS_OR_BAD_GEOMETRY',lid))
  # A local 30m margin ensures each selected lake-ID pixel is interior.
  res <- terra::res(p)
  coords <- rbind(c(max(terra::xmin(p)+res[1L]/2,as.numeric(bbox['xmin'])-30),
                    min(terra::ymax(p)-res[2L]/2,as.numeric(bbox['ymax'])+30)),
                  c(min(terra::xmax(p)-res[1L]/2,as.numeric(bbox['xmax'])+30),
                    max(terra::ymin(p)+res[2L]/2,as.numeric(bbox['ymin'])-30)))
  cs <- terra::cellFromXY(p,coords)
  mm_fail(length(cs)==2L && !anyNA(cs),'BAD_LOCAL_WINDOW_BOUNDS')
  rc <- terra::rowColFromCell(p,cs)
  r0<-min(rc[,1L]); r1<-max(rc[,1L]); c0<-min(rc[,2L]); c1<-max(rc[,2L])
  nr<-as.integer(r1-r0+1L); nc<-as.integer(c1-c0+1L)
  mm_fail(nr>=5L && nc>=5L && as.double(nr)*nc <= 500000,
          'LOCAL_WINDOW_SIZE_LIMIT')
  readm <- function(x) {
    v<-as.numeric(terra::values(x,mat=FALSE,row=r0,nrows=nr,col=c0,ncols=nc))
    mm_fail(length(v)==nr*nc,'LOCAL_RASTER_READ_ERROR')
    matrix(v,nrow=nr,ncol=nc,byrow=TRUE)
  }
  mat <- lapply(rs,readm)
  pixels <- which(mat$id==lid,arr.ind=TRUE)
  mm_fail(nrow(pixels)>0L &&
            all(pixels[,1L]>1L & pixels[,1L]<nr &
                pixels[,2L]>1L & pixels[,2L]<nc),
          'LAKE_RASTER_TOUCHES_LOCAL_WINDOW_BORDER')
  ed <- low_d8_lake_to_land_block(mat$ptr,mat$class,mat$id,
                                  1L,1L,nr,nr)
  ed <- ed[ed$lake_objectid==lid,,drop=FALSE]
  expected <- if(lid==1847L) c(198L,197L,88L) else c(189L,55L,26L)
  z <- which(ed$receiver_pointer==0L)
  mm_fail(nrow(ed)==expected[1L] && length(z)==expected[2L] &&
            length(unique(ed$receiver_cell[z]))==expected[3L],
          paste('FAILED_FULL_LOW_RECONCILIATION',lid))
  to_global <- function(cells) as.integer(((cells-1L)%/%nc+r0-1L)*
                                     as.double(terra::ncol(p))+
                                     (cells-1L)%%nc+c0)
  src_pts<-point_set(to_global(ed$source_cell))
  dst_pts<-point_set(to_global(ed$receiver_cell))
  local_value <- function(m,cells) {
    m[cbind((cells-1L)%/%nc+1L,(cells-1L)%%nc+1L)]
  }
  ix_src<-ed$source_cell; ix_dst<-ed$receiver_cell
  mm_fail(all(is.na(local_value(mat$raw,ix_src)) &
              is.na(local_value(mat$fill,ix_src))),
          'LAND_RAW_FILL_NOT_MASKED_AT_SOURCE_LAKE')
  result <- mm_shore_summary(ed,
    inside(src_pts,ranta),inside(src_pts,mml),
    inside(dst_pts,ranta),inside(dst_pts,mml),
    local_value(mat$dem,ix_dst),local_value(mat$raw,ix_dst),
    local_value(mat$fill,ix_dst),local_value(mat$land,ix_dst),
    local_value(mat$storage,ix_dst),local_value(mat$land,ix_src))
  u<-unique(ed$receiver_cell[z]); z_pts<-point_set(to_global(u))
  # Distance to the nearest MML jarvi polygon boundary, regardless of lake ID.
  bound<-sf::st_boundary(sf::st_union(sf::st_geometry(mml)))
  dist<-as.numeric(sf::st_distance(z_pts,bound))
  mm_fail(length(dist)==length(u) && all(is.finite(dist)),
          'MML_BOUNDARY_DISTANCE_FAILED')
  vals <- c(LAKE_ID=lid,MML_POLYGONS_NEARBY=nrow(mml),
      RANTA10_PIXELS=nrow(pixels),WINDOW_CELLS=nr*nc,
      LAKE_TO_LAND_EDGES=result$edges,
      IMMEDIATE_D8_ZERO_EDGES=result$zero_edges,
      UNIQUE_ZERO_RECEIVERS=result$zero_receivers,
      NONZERO_LAND_D8_EDGES=result$nonzero_edges,
      SOURCE_CENTERS_INSIDE_RANTA10_VECTOR=result$source_in_ranta_vector,
      SOURCE_CENTERS_INSIDE_MML_JARVI=result$source_in_mml,
      LAND_RECEIVER_CENTERS_INSIDE_RANTA10_VECTOR=result$land_receivers_in_ranta_vector,
      LAND_RECEIVER_CENTERS_INSIDE_MML_JARVI=result$land_receivers_in_mml,
      ZERO_EDGES_RECEIVER_INSIDE_MML_JARVI=result$zero_edges_to_mml_water,
      UNIQUE_ZERO_RECEIVERS_INSIDE_MML_JARVI=result$unique_zero_receivers_in_mml,
      ZERO_RECEIVERS_RAW_FILL_UNCHANGED=result$distinct_zero_raw_fill_unchanged,
      ZERO_RECEIVERS_STORAGE_RAISED=result$distinct_zero_storage_raised,
      SOURCE_LAKE_ABOVE_LAND=result$source_above_land_edges,
      SOURCE_LAKE_LEVEL_LAND=result$source_level_land_edges,
      SOURCE_LAKE_BELOW_LAND=result$source_below_land_edges,
      MML_BOUNDARY_DIST_ZERO_MEDIAN_M=median(dist),
      MML_BOUNDARY_DIST_ZERO_LE_2M=sum(dist<=2),
      MML_BOUNDARY_DIST_ZERO_LE_5M=sum(dist<=5),
      LAKE_MINUS_LAND_MEDIAN_M=result$lake_minus_land_gap_median)
  cat('---------- LAKE',lid,'----------\n')
  for(k in names(vals)) cat(k,format(vals[[k]],digits=9,scientific=FALSE),'\n')
  cat('LAKE_MINUS_LAND_HEIGHT_RANGE_M',
      paste(format(result$lake_minus_land_gap_m,digits=9),collapse=' '),'\n')
}
cat('PASS: RANTA10/MML TARGETED 1847 AND 1898 EDGE COUNTS RECONCILED\n')
cat('LIMITATION: VECTOR CENTRE COVERAGE/BOUNDARY PROXIMITY DOES NOT PROVE NATURAL OUTLET\n')
cat('SCIENTIFIC_STATUS: REVIEW_REQUIRED; NO D8 DEM OUTLET MODIFICATIONS\n')
cat('========== SHORELINE VECTOR COMPARISON DONE ==========\n')
