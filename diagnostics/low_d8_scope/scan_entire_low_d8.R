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
script_arg <- grep('^--file=', commandArgs(), value = TRUE)
stopifnot(length(script_arg) == 1L)
helper_path <- file.path(dirname(normalizePath(sub('^--file=', '', script_arg))),
                         'lake_to_land_d8_core.R')
source(helper_path, local = TRUE)
base <- normalizePath(args[1], mustWork=TRUE)
src <- normalizePath(args[2], mustWork=TRUE)
pfile <- file.path(base, 'd8_pointer_land_water_FLT8S.tif')
wfile <- file.path(src, 'ranta10_water_class.tif')
ifile <- file.path(src, 'ranta10_lake_id.tif')
stopifnot(file.exists(pfile), file.exists(wfile), file.exists(ifile),
          !nzchar(Sys.readlink(pfile)), !nzchar(Sys.readlink(wfile)),
          !nzchar(Sys.readlink(ifile)))
p <- rast(pfile)
w <- rast(wfile)
id_raster <- rast(ifile)
stopifnot(nlyr(p)==1L, nlyr(w)==1L, nlyr(id_raster)==1L,
          compareGeom(p,w,stopOnError=FALSE),
          compareGeom(p,id_raster,stopOnError=FALSE),
          nrow(p)>2, ncol(p)>2, ncell(p) < .Machine$integer.max)

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
lake_land_chunks <- vector('list', length(seq.int(1L, nrow(p), by = 64L)))
lake_land_edge_budget <- 2000000L
lake_land_edge_count <- 0L

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
  iv <- as.numeric(values(id_raster,mat=FALSE,row=read0,nrows=nr,
                          col=1,ncols=ncol(p)))
  stopifnot(length(pv)==nr*ncol(p),length(wv)==length(pv),
            length(iv)==length(pv))
  pm <- matrix(pv,nrow=nr,ncol=ncol(p),byrow=TRUE)
  wm <- matrix(wv,nrow=nr,ncol=ncol(p),byrow=TRUE)
  im <- matrix(iv,nrow=nr,ncol=ncol(p),byrow=TRUE)
  # Same raster pass and halo also produce the INDEPENDENT denominator:
  # every mapped-lake D8 pointer whose receiver is a non-water cell.
  chunk_i <- as.integer((r0 - 1L) %/% block + 1L)
  lake_land_chunks[[chunk_i]] <-
    low_d8_lake_to_land_block(pm, wm, im, read0, r0, r1, nrow(p))
  lake_land_edge_count <- lake_land_edge_count + nrow(lake_land_chunks[[chunk_i]])
  if (lake_land_edge_count > lake_land_edge_budget)
    stop('TOO_MANY_LAKE_TO_LAND_EDGES: inspect before raising budget')
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

# A lake may have multiple shoreline pointers, but each source cell has
# exactly one Whitebox D8 pointer. Never treat a nonzero land destination
# as a successful downstream hydrologic route.
all_land_edges <- do.call(rbind, lake_land_chunks)
if (is.null(all_land_edges)) {
  all_land_edges <- data.frame(lake_objectid=integer(),source_cell=integer(),
                               receiver_cell=integer(),receiver_pointer=numeric())
}
if (anyDuplicated(all_land_edges$source_cell))
  stop('DUPLICATE_SOURCE_ACROSS_BLOCK_BOUNDARIES', call. = FALSE)
all_lake_rates <- low_d8_lake_to_land_summary(all_land_edges)
# Exactly the 22 source lakes observed with incoming lake-D8 -> zero
# in the earlier sparse 02C QA; this list is an independent reconciliation
# of the earlier 1,273 zero pointers, NOT a filter on the raster read.
known_lake_ids <- c(3181L,1847L,1898L,1832L,1889L,1894L,1849L,
                    1884L,1887L,1851L,212435L,1905L,212437L,
                    1945L,1921L,1892L,1943L,1891L,1920L,1895L,
                    212436L,1853L)
stopifnot(length(known_lake_ids) == 22L, !anyDuplicated(known_lake_ids))
known_rates <- low_d8_lake_to_land_summary(all_land_edges, known_lake_ids)
known_zero <- sum(known_rates$immediate_zero_edges)
known_receivers <- unique(all_land_edges$receiver_cell[
  all_land_edges$lake_objectid %in% known_lake_ids &
  !is.na(all_land_edges$receiver_pointer) &
  all_land_edges$receiver_pointer == 0])
cat('========== COMPLETE LOW LAKE TO LAND D8 DENOMINATOR ==========', '\n')
cat('ALL_LAKES_WITH_OUTGOING_LAND_D8:', nrow(all_lake_rates), '\n')
cat('ALL_LAKE_TO_LAND_D8_EDGES:', nrow(all_land_edges), '\n')
cat('ALL_IMMEDIATE_ZERO_EDGES:', sum(all_lake_rates$immediate_zero_edges), '\n')
cat('KNOWN_22_LAKE_TO_LAND_D8_EDGES:', sum(known_rates$lake_to_land_edges), '\n')
cat('KNOWN_22_IMMEDIATE_ZERO_EDGES:', known_zero, '\n')
cat('KNOWN_22_DISTINCT_ZERO_RECEIVERS:', length(known_receivers), '\n')
cat('KNOWN_22_NONZERO_LAND_POINTER_EDGES:',
    sum(known_rates$nonzero_land_pointer_edges), '\n')
cat('KNOWN_22_NA_LAND_POINTER_EDGES:',
    sum(known_rates$na_land_pointer_edges), '\n')
cat('========== KNOWN 22 LAKES: COUNTS AND FRACTIONS ==========', '\n')
print(known_rates[order(-known_rates$immediate_zero_edges,
                        known_rates$lake_objectid), , drop=FALSE],
      row.names=FALSE)
cat('========== ALL SOURCE LAKES: FRACTION RANKING (DENOM >= 20) ==========', '\n')
eligible <- all_lake_rates[
  all_lake_rates$lake_to_land_edges >= 20L, , drop=FALSE]
print(eligible[order(-eligible$immediate_zero_fraction,
                     -eligible$lake_to_land_edges), , drop=FALSE],
      row.names=FALSE)
if (known_zero != 1273L || length(known_receivers) != 535L)
  stop('KNOWN_02C_LAKE_TO_ZERO_RECONCILIATION_FAILED: inspect raster outputs',
       call. = FALSE)
if (n_interior_incoming_lake != length(unique(all_land_edges$receiver_cell[
        !is.na(all_land_edges$receiver_pointer) &
        all_land_edges$receiver_pointer == 0])))
  warning('FULL_INTERIOR_ZERO_VS_LAKE_EDGE_MISMATCH: inspect edge/domain cases')
cat('PASS: COMPLETE-LAKE-DENOMINATOR RECONCILED WITH 02C 1273/535', '\n')
cat('LIMITATION: IMMEDIATE D8=0 FRACTION, NOT DOWNSTREAM ROUTE SUCCESS RATE', '\n')
cat('SCIENTIFIC_STATUS: REVIEW_REQUIRED; ALL RASTERS READ ONLY', '\n')

