# Fresh explicit synthetic truth. Neither builder nor oracle calls the SUT.
truth_fixture <- function(nr = 3L, nc = 9L, land = c(2L, 5L, 8L, 10:17),
                          arcs = rbind(c(2,11,8), c(5,14,8), c(8,17,8), cbind(10:17,11:18,2))) {
  n <- nr * nc; source <- seq_len(n) %in% land
  pointer <- rep(0, n); next_cell <- integer(n)
  if (length(arcs)) { pointer[arcs[,1L]] <- arcs[,3L]; next_cell[arcs[,1L]] <- arcs[,2L] }
  list(nr=nr,nc=nc,land=as.integer(land),arcs=arcs,pointer=pointer,next_cell=next_cell,
    water_class=ifelse(source,NA_real_,1),valid=rep(TRUE,n),
    grid=list(grid_id="SYNTHETIC-02G3",nrow=nr,ncol=nc,row_offset=100L,col_offset=200L,
      xmin=200000,ymax=6900000,resolution_m=2,crs="EPSG:3067"),
    identity=list(run_id="synthetic-02g3",graph_version="fixture-v1",grid_version="grid-v1",
      pointer_version="explicit-arcs-v1",water_version="explicit-classes-v1",ownership_version="rectangles-v1"))
}
truth_uid <- function(cells,f) {
  if(!length(cells))return(character())
  paste("SYNTHETIC-02G3",100L+(cells-1L)%/%f$nc+1L,200L+(cells-1L)%%f$nc+1L,sep=":")
}
truth_cores <- function(f,cuts=c(1L,f$nc+1L)) {
  data.frame(core_id=LETTERS[seq_len(length(cuts)-1L)],row_min=rep(101,length(cuts)-1L),
    row_max=rep(100+f$nr,length(cuts)-1L),col_min=200+head(cuts,-1L),col_max=200+tail(cuts,-1L)-1)
}
truth_owner <- function(f,cores) {
  rr<-101L+(seq_len(f$nr*f$nc)-1L)%/%f$nc;cc<-201L+(seq_len(f$nr*f$nc)-1L)%%f$nc
  owner<-rep(NA_character_,length(rr))
  for(i in seq_len(nrow(cores))) {
    hit<-rr>=cores$row_min[i]&rr<=cores$row_max[i]&cc>=cores$col_min[i]&cc<=cores$col_max[i]
    stopifnot(all(is.na(owner[hit])));owner[hit]<-cores$core_id[i]
  }
  stopifnot(!anyNA(owner));owner
}
graph_from_truth <- function(f,cores) {
  cells<-seq_len(f$nr*f$nc);uids<-truth_uid(cells,f);owner<-truth_owner(f,cores);land<-cells%in%f$land
  list(schema="02g.3-graph-v1",input_kind="EXPLICIT_SYNTHETIC_CELL_GRAPH",identity=f$identity,grid=f$grid,cores=cores,
    nodes=data.frame(cell_uid=uids,global_row=100L+(cells-1L)%/%f$nc+1L,global_col=200L+(cells-1L)%%f$nc+1L,
      owner_core=owner,kind=ifelse(land,"LAND","WATER"),water_class=f$water_class,pointer=f$pointer,
      valid=f$valid,source_uid=ifelse(land,uids,NA_character_)),
    edges=data.frame(from_uid=truth_uid(f$arcs[,1L],f),to_uid=truth_uid(f$arcs[,2L],f),d8_code=as.numeric(f$arcs[,3L])),
    external_import="UNKNOWN")
}
census_from_truth <- function(f,cores) {
  # Construct observations directly from the independently declared fixture,
  # not from graph nodes, edges or a graph count/trace result.
  cells<-seq_len(f$nr*f$nc);rows<-(cells-1L)%/%f$nc+101L;cols<-(cells-1L)%%f$nc+201L
  observations<-lapply(seq_len(nrow(cores)),function(i) {
    hit<-rows>=cores$row_min[i]-1 & rows<=cores$row_max[i]+1 & cols>=cores$col_min[i]-1 & cols<=cores$col_max[i]+1
    data.frame(observer_core=rep(cores$core_id[i],sum(hit)),cell_uid=truth_uid(cells[hit],f),
      pointer=f$pointer[hit],water_class=f$water_class[hit],valid=f$valid[hit])
  })
  list(schema="02g.3-census-v1",input_kind="INDEPENDENT_SYNTHETIC_CELL_CENSUS",
    scope_contract="COMPLETE_DECLARED_LOCAL_DAG",observation_status="COMPLETE_CELL_CENSUS",identity=f$identity,
    producer_id="independent-explicit-fixture-census-v1",available_cores=cores$core_id,
    observations=do.call(rbind,observations),source_inventory=data.frame(source_uid=truth_uid(f$land,f),
      cell_uid=truth_uid(f$land,f),owner_core=truth_owner(f,cores)[f$land],source_units=rep(1,length(f$land))))
}
inputs <- function(f=truth_fixture(),cores=truth_cores(f,c(1,4,7,10)))
  list(graph=graph_from_truth(f,cores),evidence=census_from_truth(f,cores))
explicit_source_oracle <- function(f) {
  # Different algorithm: walk explicit successor IDs from each source, and
  # retain actual source sets ONLY IN THE TEST ORACLE. No pointer decoder,
  # topological ordering, SUT index, old accumulation or g2r functions.
  sets<-setNames(rep(list(character()),f$nr*f$nc),truth_uid(seq_len(f$nr*f$nc),f))
  endings<-setNames(character(length(f$land)),truth_uid(f$land,f))
  for(source in f$land) {
    cell<-source;seen<-integer()
    repeat {
      stopifnot(cell>=1L,cell<=f$nr*f$nc,!cell%in%seen,length(seen)<f$nr*f$nc)
      seen<-c(seen,cell);id<-truth_uid(cell,f)
      sets[[id]]<-union(sets[[id]],truth_uid(source,f))
      if(!is.na(f$water_class[cell])) { endings[[truth_uid(source,f)]]<-id;break }
      cell<-f$next_cell[cell];stopifnot(cell>0L)
    }
  }
  list(sets=sets,endings=endings)
}
