# Targeted, read-only vector gap and 02E/02F evidence for LOW lakes 1847, 1898.
# Usage: Rscript --vanilla run_mml_gap_components.R BASELINE_DIR [MML_GPKG]
args <- commandArgs(trailingOnly = TRUE)
if (!(length(args) %in% c(1L,2L))) stop('Usage: Rscript run_mml_gap_components.R BASELINE_DIR [MML_GPKG]')
script <- grep('^--file=', commandArgs(), value=TRUE)
if (length(script) != 1L) stop('Rscript --vanilla required')
scriptdir_mml_gap <- dirname(normalizePath(sub('^--file=','',script), mustWork=TRUE))
source(file.path(scriptdir_mml_gap, 'mml_gap_component_core.R'), local=TRUE)
source(file.path(scriptdir_mml_gap, 'lake_to_land_d8_core.R'), local=TRUE)
suppressPackageStartupMessages({ library(terra); library(sf) })
base <- normalizePath(args[1L], mustWork=TRUE)
tile <- basename(dirname(base))
root <- dirname(dirname(dirname(dirname(base))))
src <- file.path(root,'inputs',tile)
mml_gpkg <- if (length(args)==2L) args[2L] else
  '/dataset/project_2019680/mml/maastotietokanta/2025/gpkg/MTK-vakavesi_25-04-03.gpkg'
ranta_gpkg <- file.path(src,paste0('RANTA10_',tile,'.gpkg'))
files <- c(pointer=file.path(base,'d8_pointer_land_water_FLT8S.tif'),
           lakeid=file.path(src,'ranta10_lake_id.tif'),
           water=file.path(src,'ranta10_water_class.tif'),
           evidence=file.path(base,'02E_water_connected_candidate_evidence.csv'),
           spill_edges=file.path(base,'02E_water_connected_candidate_spill_edges.csv'),
           route=file.path(base,'02F_water_connected_route_evidence.csv'))
for (f in c(files,ranta_gpkg,mml_gpkg))
  gap_assert(file.exists(f) && !dir.exists(f) && !nzchar(Sys.readlink(f)),
             paste('MISSING_OR_LINKED_REQUIRED_INPUT',f))
for (f in files[c('evidence','spill_edges','route')])
  gap_assert(!is.na(file.info(f)$size) && file.info(f)$size <= 15000000,
             'OVERSIZED_02E_02F_CSV')
evidence <- read.csv(files[['evidence']], stringsAsFactors=FALSE)
spill_edges <- read.csv(files[['spill_edges']], stringsAsFactors=FALSE)
routes <- read.csv(files[['route']], stringsAsFactors=FALSE)
gap_validate_02e_02f(evidence, spill_edges, routes)
cat('PASS: canonical 02E/02F CSV schema (origin_lake_objectid), outlets UNASSIGNED\n')
r <- lapply(files[c('pointer','lakeid','water')], terra::rast)
p <- r$pointer
gap_assert(all(vapply(r,function(x) terra::nlyr(x)==1L &&
                terra::compareGeom(p,x,stopOnError=FALSE),logical(1))) &&
  sf::st_crs(terra::crs(p))$epsg==3067L &&
  terra::ncell(p)<.Machine$integer.max, 'RASTER_GEOMETRY_OR_CRS_MISMATCH')
gap_assert('lakes' %in% sf::st_layers(ranta_gpkg)$name &&
           'jarvi' %in% sf::st_layers(mml_gpkg)$name,
           'VECTOR_LAYERS_MISSING')
cat('========== LOW MML-ONLY GEOMETRY / ZERO CELL CLUSTERS / 02E+02F ==========', '\n')
for (lid in c(1847L,1898L)) {
  polygon <- sf::st_read(ranta_gpkg,
    query=sprintf('SELECT * FROM lakes WHERE objectid=%d',lid), quiet=TRUE)
  gap_assert(nrow(polygon)==1L && as.integer(polygon$objectid[1L])==lid &&
              sf::st_crs(polygon)$epsg==3067L && all(sf::st_is_valid(polygon)),
             'BAD_RANTA10_LAKE_POLYGON')
  bb <- sf::st_bbox(polygon)
  pixel <- terra::res(p)
  xy <- rbind(c(max(terra::xmin(p)+pixel[1L]/2,as.numeric(bb['xmin'])-30),
                min(terra::ymax(p)-pixel[2L]/2,as.numeric(bb['ymax'])+30)),
              c(min(terra::xmax(p)-pixel[1L]/2,as.numeric(bb['xmax'])+30),
                max(terra::ymin(p)+pixel[2L]/2,as.numeric(bb['ymin'])-30)))
  cells <- terra::cellFromXY(p, xy)
  gap_assert(length(cells)==2L && !anyNA(cells),'BAD_WINDOW_BOUNDS')
  rc <- terra::rowColFromCell(p,cells)
  r0<-min(rc[,1L]);r1<-max(rc[,1L]);c0<-min(rc[,2L]);c1<-max(rc[,2L])
  nr<-as.integer(r1-r0+1L); nc<-as.integer(c1-c0+1L)
  gap_assert(nr>=5L && nc>=5L && as.double(nr)*nc<=500000,
             'LOCAL_WINDOW_BUDGET_EXCEEDED')
  readmat <- function(x) {
    v <- as.numeric(terra::values(x,mat=FALSE,row=r0,nrows=nr,col=c0,ncols=nc))
    gap_assert(length(v)==nr*nc,'RASTER_WINDOW_READ_FAILED')
    matrix(v,nrow=nr,ncol=nc,byrow=TRUE)
  }
  m <- lapply(r,readmat)
  lakepixels <- which(m$lakeid==lid,arr.ind=TRUE)
  gap_assert(nrow(lakepixels)>0L &&
    all(lakepixels[,1L]>1L & lakepixels[,1L]<nr &
        lakepixels[,2L]>1L & lakepixels[,2L]<nc),
    'LAKE_ANNOTATION_TOUCHES_WINDOW_BOUNDARY')
  edges <- low_d8_lake_to_land_block(m$pointer,m$water,m$lakeid,1L,1L,nr,nr)
  edges <- edges[edges$lake_objectid==lid,,drop=FALSE]
  z <- edges[!is.na(edges$receiver_pointer) &
               edges$receiver_pointer==0L,,drop=FALSE]
  expected <- if(lid==1847L) c(198L,197L,88L) else c(189L,55L,26L)
  zero_ids_local <- sort(unique(z$receiver_cell))
  gap_assert(nrow(edges)==expected[1L] && nrow(z)==expected[2L] &&
    length(zero_ids_local)==expected[3L], 'NOT_LOCKED_LOW_D8_EVIDENCE')
  global <- function(i) as.integer(((i-1L)%/%nc + r0-1L) *
                 as.double(terra::ncol(p)) + (i-1L)%%nc + c0)
  receiver_global <- global(zero_ids_local)
  pts_xy <- terra::xyFromCell(p,receiver_global)
  pts <- sf::st_as_sf(data.frame(x=pts_xy[,1L],y=pts_xy[,2L]),
                      coords=c('x','y'),crs=3067)
  roi <- sf::st_buffer(sf::st_as_sfc(bb),40)
  mml <- sf::st_read(mml_gpkg,layer='jarvi',
         wkt_filter=as.character(sf::st_as_text(roi[[1L]])),quiet=TRUE)
  gap_assert(nrow(mml)==1L && sf::st_crs(mml)$epsg==3067L &&
               all(sf::st_is_valid(mml)), 'MML_LOCAL_MATCH_NOT_UNIQUE_OR_INVALID')
  r_geom <- sf::st_geometry(polygon); m_geom <- sf::st_geometry(mml)
  area_r <- as.numeric(sf::st_area(r_geom));area_m <- as.numeric(sf::st_area(m_geom))
  overlap <- suppressWarnings(sf::st_intersection(r_geom,m_geom))
  area_common <- sum(as.numeric(sf::st_area(overlap)))
  gap_assert(area_common>0 && area_common<=min(area_m,area_r)*(1+1e-5),
             'GEOMETRY_HAS_NO_VALID_OVERLAP')
  mml_only <- suppressWarnings(sf::st_difference(m_geom,r_geom))
  ranta_only <- suppressWarnings(sf::st_difference(r_geom,m_geom))
  area_mml_only <- sum(as.numeric(sf::st_area(mml_only)))
  area_ranta_only <- sum(as.numeric(sf::st_area(ranta_only)))
  within_mml <- lengths(sf::st_covered_by(pts,m_geom)) > 0L
  within_ranta <- lengths(sf::st_covered_by(pts,r_geom)) > 0L
  within_gap <- lengths(sf::st_covered_by(pts,mml_only)) > 0L
  gap_assert(all(!within_ranta) &&
    identical(as.integer(sum(within_mml)),if(lid==1847L)88L else 0L) &&
    identical(within_gap,within_mml & !within_ranta),
    'MML_RANTA10_ZERO_RECEIVER_RECONCILIATION_FAILED')
  d_ranta <- as.numeric(sf::st_distance(pts,sf::st_boundary(r_geom)))
  d_mml <- as.numeric(sf::st_distance(pts,sf::st_boundary(m_geom)))
  gap_assert(length(d_ranta)==length(zero_ids_local) &&
    length(d_mml)==length(zero_ids_local) &&
    all(is.finite(d_ranta)) && all(is.finite(d_mml)),
    'INVALID_VECTOR_BOUNDARY_DISTANCE')
  labels <- gap_zero_components(receiver_global,terra::nrow(p),terra::ncol(p))
  counts <- gap_component_counts(labels,global(z$receiver_cell))
  e <- evidence[evidence$lake_objectid==lid,,drop=FALSE]
  se <- spill_edges[spill_edges$lake_objectid==lid,,drop=FALSE]
  gap_assert(all(se$spill_group_id %in% e$spill_group_id) &&
               all(se$receiver_cell>=1L & se$receiver_cell<=terra::ncell(p)) &&
               !anyNA(se$receiver_cell) &&
               all(e$candidate_included[match(se$spill_group_id,e$spill_group_id)]),
               '02E_SPILL_EDGES_NOT_INCLUDED_PARALLEL_CANDIDATES')
  t <- routes[routes$origin_lake_objectid==lid,,drop=FALSE]
  cat('---------- LAKE',lid,'----------\n')
  cat('WINDOW_CELLS:',nr*nc,'\n')
  cat('ZERO_RECEIVERS:',length(receiver_global),'ZERO_EDGES:',nrow(z),'\n')
  cat('MML_ONLY_AREA_M2:',round(area_mml_only,3),'RANTA10_ONLY_AREA_M2:',round(area_ranta_only,3),'\n')
  cat('MML_OVERLAP_AREA_M2:',round(area_common,3),'\n')
  cat('ZERO_CENTERS_IN_MML_ONLY:',sum(within_gap),'\n')
  cat('ZERO_CENTERS_IN_MML_WATER:',sum(within_mml),'\n')
  cat('ZERO_TO_RANTA_BOUNDARY_MEDIAN_M:',round(median(d_ranta),4),'\n')
  cat('ZERO_TO_MML_BOUNDARY_MEDIAN_M:',round(median(d_mml),4),'\n')
  cat('ZERO_8_NEIGHBOR_COMPONENTS:',nrow(counts),'\n')
  cat('LARGEST_8_NEIGHBOR_COMPONENT_COUNTS:\n')
  print(utils::head(counts,10L),row.names=FALSE)
  cat('02E_SPILL_GROUPS:',nrow(e),'02E_INCLUDED_PARALLEL_GROUPS:',
       sum(e$candidate_included),'02E_REVIEW_FLAGGED_GROUPS:',sum(e$needs_review),'\n')
  cat('02E_OUTLET_SELECTION:',if(nrow(e))'UNASSIGNED' else 'NO_02E_ROWS', '\n')
  cat('02E_SPILL_CANDIDATE_EDGES:',nrow(se),'\n')
  if (nrow(se)) {
    xy_cand <- terra::xyFromCell(p,sort(unique(as.integer(se$receiver_cell))))
    mat_dist <- sqrt((outer(pts_xy[,1L],xy_cand[,1L],'-'))^2 +
                     (outer(pts_xy[,2L],xy_cand[,2L],'-'))^2)
    nearest <- apply(mat_dist,1L,min)
    cat('ZERO_TO_NEAREST_02E_SPILL_RECEIVER_MEDIAN_M:',
        round(median(nearest),4),'MIN_M:',round(min(nearest),4),'\n')
    cat('NOTE: 02E receiver proximity is NOT confirmation of a functioning outlet\n')
  }
  cat('02F_CANDIDATE_RECEIVER_ROUTES:',nrow(t),'\n')
  if(nrow(t)) {
    cat('02F_ROUTE_STATUS_COUNTS:\n')
    print(table(t$route_status))
  } else cat('02F_ROUTE_STATUS_COUNTS: NONE_IN_EXISTING_02F_TABLE\n')
  cat('NOTE: 8-neighbour groups are zero-cell clusters, not outlets or MML-only polygon components\n')
}
cat('PASS: LOW MML-only gap and 02E/02F evidence audited without data modifications\n')
cat('SCIENTIFIC_STATUS: REVIEW_REQUIRED; NO D8 DEM MASK OR OUTLET MODIFICATIONS\n')
cat('========== LOW MML GAP CHECK DONE ==========\n')
