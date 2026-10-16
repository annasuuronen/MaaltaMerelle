# Inventory of all non-water D8_ZERO_INTERIOR cells in an existing LOW D8 raster.
# This is a complete raster-cell inventory, NOT a full downstream-route or cycle QA.
# Never modify DEM, D8, water classes, or any other raster.
# Must run on a Slurm compute node (never on a login node).
if (!nzchar(Sys.getenv('SLURM_JOB_ID', ''))) {
  stop('COMPUTE_NODE_REQUIRED: submit a reviewed Slurm batch job; do not run on login node.')
}
args <- commandArgs(trailingOnly=TRUE)
if (length(args) != 2L) stop('Usage: Rscript scan_entire_low_d8.R BASELINE_DIR SOURCE_DIR')
suppressPackageStartupMessages(library(terra))
base <- normalizePath(args[1], mustWork=TRUE)
src <- normalizePath(args[2], mustWork=TRUE)
pfile <- file.path(base, 'd8_pointer_land_water_FLT8S.tif')
wfile <- file.path(src, 'ranta10_water_class.tif')
stopifnot(file.exists(pfile), file.exists(wfile))
p <- rast(pfile)
w <- rast(wfile)
stopifnot(nlyr(p)==1L, nlyr(w)==1L,
          compareGeom(p,w,stopOnError=FALSE), nrow(p)>2, ncol(p)>2)

# Whitebox pointer code from neighbour at (dr, dc) into center.
dr <- c(-1L,-1L,-1L, 0L, 0L, 1L, 1L, 1L)
dc <- c(-1L, 0L, 1L,-1L, 1L,-1L, 0L, 1L)
into <- c(4L,8L,16L,2L,32L,1L,128L,64L)

block <- 64L
n_all_nonwater_zeros <- 0L
n_all_interior_zeros <- 0L
n_interior_adjacent_lake <- 0L
n_interior_incoming_lake <- 0L
n_incoming_lake_edges <- 0L
sample <- integer(0)

cat('MODE: READ_ONLY BLOCK SCAN OF NON-WATER D8 ZERO VALUES\n')
cat('INPUT_D8:',pfile,'\nINPUT_WATER_CLASS:',wfile,'\n')
cat('GRID:',nrow(p),'rows x',ncol(p),'cols\n')

for (r0 in seq.int(1L,nrow(p),by=block)) {
  r1 <- min(nrow(p),r0+block-1L)
  read0 <- max(1L,r0-1L)
  read1 <- min(nrow(p),r1+1L)
  nr <- read1-read0+1L
  pv <- as.numeric(values(p,mat=FALSE,row=read0,nrows=nr,col=1,ncols=ncol(p)))
  wv <- as.numeric(values(w,mat=FALSE,row=read0,nrows=nr,col=1,ncols=ncol(p)))
  stopifnot(length(pv)==nr*ncol(p),length(wv)==length(pv))
  pm <- matrix(pv,nrow=nr,ncol=ncol(p),byrow=TRUE)
  wm <- matrix(wv,nrow=nr,ncol=ncol(p),byrow=TRUE)
  core <- seq.int(r0-read0+1L,length.out=r1-r0+1L)
  candidates <- which(!is.na(pm[core,,drop=FALSE]) &
                      pm[core,,drop=FALSE]==0 &
                      is.na(wm[core,,drop=FALSE]),arr.ind=TRUE)
  if (!nrow(candidates)) next
  n_all_nonwater_zeros <- n_all_nonwater_zeros+nrow(candidates)
  global_row <- r0+candidates[,1]-1L
  global_col <- candidates[,2]
  is_interior <- global_row>1L & global_row<nrow(p) &
                 global_col>1L & global_col<ncol(p)
  n_all_interior_zeros <- n_all_interior_zeros+sum(is_interior)
  if (!any(is_interior)) next
  rr <- global_row[is_interior]-read0+1L
  cc <- global_col[is_interior]
  stopifnot(all(rr>1L & rr<nr),all(cc>1L & cc<ncol(p)))
  adjacent <- rep(FALSE,length(rr))
  incoming <- rep(FALSE,length(rr))
  for (i in seq_along(dr)) {
    ij <- cbind(rr+dr[i],cc+dc[i])
    is_lake <- !is.na(wm[ij]) & wm[ij]==1
    is_in <- is_lake & !is.na(pm[ij]) & pm[ij]==into[i]
    adjacent <- adjacent | is_lake
    incoming <- incoming | is_in
    n_incoming_lake_edges <- n_incoming_lake_edges+sum(is_in)
  }
  n_interior_adjacent_lake <- n_interior_adjacent_lake+sum(adjacent)
  n_interior_incoming_lake <- n_interior_incoming_lake+sum(incoming)
  if (length(sample)<20L && any(incoming)) {
    cells <- as.double(global_row[is_interior][incoming]-1L)*ncol(p)+
             global_col[is_interior][incoming]
    sample <- c(sample,head(as.integer(cells),20L-length(sample)))
  }
}

stopifnot(n_interior_incoming_lake<=n_interior_adjacent_lake,
          n_interior_adjacent_lake<=n_all_interior_zeros,
          n_all_interior_zeros<=n_all_nonwater_zeros,
          n_incoming_lake_edges>=n_interior_incoming_lake)
cat('========== COMPLETE LOW D8 ZERO CELL INVENTORY ==========' ,'\n')
cat('ALL_NONWATER_D8_ZEROS:',n_all_nonwater_zeros,'\n')
cat('INTERIOR_NONWATER_D8_ZEROS:',n_all_interior_zeros,'\n')
cat('INTERIOR_ZERO_ADJACENT_TO_RANTA10_LAKE:',n_interior_adjacent_lake,'\n')
cat('INTERIOR_ZERO_WITH_INCOMING_LAKE_D8:',n_interior_incoming_lake,'\n')
cat('INCOMING_LAKE_D8_EDGES:',n_incoming_lake_edges,'\n')
cat('SAMPLE_LAKE_TO_ZERO_TERMINALS:',paste(sample,collapse=','),'\n')
cat('LIMITATION: This is not a full trace of all routes/cycles/other terminal types.\n')
cat('SCIENTIFIC_STATUS: REVIEW_REQUIRED; NO POINTER OR OUTLET CHANGES\n')
cat('========== INVENTORY FINISHED ==========' ,'\n')
