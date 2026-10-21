#!/usr/bin/env Rscript
here <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))))
source(file.path(here,"support.R"))
f <- fixture(3L,9L,land=c(2,5,8,10:17),arcs=matrix(c(2,11,5,14,8,17,as.vector(rbind(10:17,11:18))),ncol=2,byrow=TRUE),water=18L)
layout3 <- list(A=list(rows=c(1,3),cols=c(1,3)),B=list(rows=c(1,3),cols=c(4,6)),C=list(rows=c(1,3),cols=c(7,9)))
layout2 <- list(A=list(rows=c(1,3),cols=c(1,4)),B=list(rows=c(1,3),cols=c(5,9)))
make_tiles <- function(layout) lapply(layout,function(b) list(grid=f$grid,
  cells=f$cells[f$cells$cell %in% g02_rectangle(b$rows,b$cols,f$grid,1L),]))
compare <- function(a,b) {
  fields <- setdiff(names(a$nodes),"owner_tile")
  g02_assert(identical(a$nodes[,fields],b$nodes[,fields]) && identical(a$water,b$water) &&
    identical(a$source_sets,b$source_sets) && identical(a$water_source_sets,b$water_source_sets) &&
    identical(a$source_ledger[,setdiff(names(a$source_ledger),"owner_tile")],
      b$source_ledger[,setdiff(names(b$source_ledger),"owner_tile")]), "STOP_TILE_MONOLITH_MISMATCH")
  check(TRUE,"tile/monolith exact numerical and source-set equality")
}
for (layout in list(layout2,layout3)) for (cap in c(2L,32L)) {
  tiles <- make_tiles(layout)
  r <- g02_tile_accumulation(tiles,layout,f$grid,f$provenance,cap)
  mono <- run_fixture(f,cap); compare(r,mono); verify(f,r,cap)
  check(r$balance$n_sources == 11 && sum(r$tile_balance$owned_sources)==11,"halo contributes no new sources")
  check(all(r$tile_balance$owned_sources == r$tile_balance$first_water_sources+r$tile_balance$unresolved_sources))
  check(r$internal_balance$cancelled && r$internal_balance$pending==0)
  check(all(r$transfers$d8_verified_by_core) && !anyDuplicated(r$transfers$transfer_id))
  # Independent ownership from known column cuts, not the tile builder.
  col <- (f$cells$cell-1L) %% 9L + 1L
  owner <- if (length(layout)==3L) ifelse(col<=3,"A",ifelse(col<=6,"B","C")) else ifelse(col<=4,"A","B")
  expected <- character()
  for (s in which(f$kind=="LAND")) {
    cell<-s; seen<-integer(); steps<-0L
    while(f$kind[cell]=="LAND" && !cell %in% seen && steps<cap && f$successor[cell]>0) {
      seen<-c(seen,cell); to<-f$successor[cell]
      if(owner[cell]!=owner[to]) expected<-c(expected,paste(g02_uid(cell,f$grid),g02_uid(to,f$grid),g02_uid(s,f$grid),sep="|"))
      cell<-to; steps<-steps+1L
    }
  }
  actual <- paste(r$transfers$source_cell_uid[match(r$transfer_sources$transfer_id,r$transfers$transfer_id)],
    r$transfers$receiver_cell_uid[match(r$transfer_sources$transfer_id,r$transfers$transfer_id)],r$transfer_sources$source_uid,sep="|")
  check(setequal(actual,expected) && !anyDuplicated(actual),"independent cross-tile source accounting")
  if(length(layout)==3L) {
    at<-match(paste(g02_uid(12,f$grid),g02_uid(13,f$grid),sep=">"),r$transfers$transfer_id)
    check(r$transfers$n_transferred_sources[at]==if(cap==2L) 2 else 4)
    check(r$transfers$known_local_accumulation_cells[at]==4,"capped source at sender is not silently transferred")
  }
  reverse<-rev(tiles);reverse<-lapply(reverse,function(t){t$cells<-t$cells[nrow(t$cells):1L,];t})
  shuffled<-g02_tile_accumulation(reverse,layout,f$grid,f$provenance,cap)
  check(identical(r,shuffled),"tile and observation order invariance")
  if(length(layout)==3L && cap==32L) {
    write.csv(r$nodes,file.path(root,"example_nodes.csv"),row.names=FALSE)
    write.csv(r$water,file.path(root,"example_water.csv"),row.names=FALSE)
    write.csv(r$source_ledger,file.path(root,"example_source_ledger.csv"),row.names=FALSE)
    write.csv(r$transfers,file.path(root,"example_transfers.csv"),row.names=FALSE)
    write.csv(r$transfer_sources,file.path(root,"example_transfer_sources.csv"),row.names=FALSE)
    write.csv(r$tile_balance,file.path(root,"example_tile_balance.csv"),row.names=FALSE)
  }
  cat(sprintf("PASS: %d tiles cap=%d equal monolith\n",length(layout),cap))
}
tiles<-make_tiles(layout3); available<-tiles[c("A","C")]
r<-g02_tile_accumulation(available,layout3,f$grid,f$provenance,32L)
ids<-sort(unique(unlist(lapply(c("A","C"),function(id)g02_rectangle(layout3[[id]]$rows,layout3[[id]]$cols,f$grid)))))
verify(f,r,32L,ids)
check(r$missing_core_cells==9 && r$balance$n_sources==7 && r$balance$n_first_water==3 && r$balance$n_unresolved==4)
check(all(r$source_ledger$endpoint_type[r$source_ledger$owner_tile=="A"]=="MISSING_NEIGHBOUR_TILE"))
check(r$internal_balance$pending==4 && all(r$transfers$transfer_status=="MISSING_NEIGHBOUR_TILE"))
check(all(is.na(r$nodes$total_upstream_cells)) && r$coverage_status=="PARTIAL_OBSERVATION")
reject(g02_tile_accumulation(available,layout3,f$grid,f$provenance,32L,"KNOWN_ZERO_SYNTHETIC"))
bad<-tiles;bad$B$cells$pointer[bad$B$cells$cell==12]<-4
reject(g02_tile_accumulation(bad,layout3,f$grid,f$provenance))
bad<-layout2;bad$A$cols<-c(1,5)
reject(g02_tile_accumulation(make_tiles(layout2),bad,f$grid,f$provenance))
bad<-tiles;bad$A$cells<-bad$A$cells[-1,]
reject(g02_tile_accumulation(bad,layout3,f$grid,f$provenance))
bad<-tiles;bad$C$grid$resolution_m<-3
reject(g02_tile_accumulation(bad,layout3,f$grid,f$provenance))
check(checks>0L)
cat(sprintf("RESULT n=27 scenario=tiles cap=32 comparisons=4 checks=%d status=PASS\n",checks))
