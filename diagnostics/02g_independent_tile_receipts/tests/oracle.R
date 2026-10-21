# Independent fixtures and explicit-successor reference. No SUT route,
# accumulation, tile ownership helper or D8 decoder is called by the oracle.
r_fixture <- function(nr = 3L, nc = 9L, land = c(2L, 5L, 8L, 10:17),
                      edges = rbind(c(2,11), c(5,14), c(8,17), cbind(10:17,11:18)), water = 18L) {
  n <- nr * nc; ids <- seq_len(n)
  successor <- integer(n); if (length(edges)) successor[edges[,1L]] <- edges[,2L]
  kind <- rep("NO_DATA", n); kind[land] <- "LAND"; kind[water] <- "WATER"
  terminal <- rep("D8_ZERO", n); terminal[successor > 0] <- ""
  cells <- data.frame(cell = ids, pointer = rep(0, n), water_class = rep(NA_real_, n),
    lake_id = rep(NA_real_, n), valid = kind != "NO_DATA")
  for (from in which(successor > 0)) {
    to <- successor[from]
    dr <- (to-1L) %/% nc - (from-1L) %/% nc; dc <- (to-1L) %% nc - (from-1L) %% nc
    code <- c("-1:1"=1, "0:1"=2, "1:1"=4, "1:0"=8, "1:-1"=16, "0:-1"=32, "-1:-1"=64, "-1:0"=128)[paste(dr,dc,sep=":")]
    stopifnot(!is.na(code)); cells$pointer[from] <- code
  }
  cells$water_class[water] <- 1; cells$lake_id[water] <- 9001
  grid <- list(grid_id="SYNTHETIC-02G2", nrow=nr, ncol=nc, row_offset=100L, col_offset=200L,
    xmin=200000, ymax=6900000, resolution_m=2, crs="EPSG:3067")
  provenance <- list(run_id="synthetic-02g2", code_revision="02g2-fixture-v1", pointer_source="generated",
    water_source="generated", lake_id_source="generated", validity_source="generated",
    lake_id_namespace="SYNTHETIC_ONLY", synthetic=TRUE)
  list(cells=cells, successor=successor, kind=kind, terminal=terminal, grid=grid, provenance=provenance)
}
r_uid <- function(cells, f) {
  if (!length(cells)) return(character())
  paste(f$grid$grid_id,100L+(cells-1L)%/%f$grid$ncol+1L,200L+(cells-1L)%%f$grid$ncol+1L,sep=":")
}
r_reference <- function(f, owner, available, cap) {
  present <- owner %in% available; seeds <- which(present & f$kind=="LAND")
  sets <- setNames(rep(list(integer()),length(seeds)),as.character(seeds))
  waters <- which(present & f$kind=="WATER")
  wsets <- setNames(rep(list(integer()),length(waters)),as.character(waters))
  status <- character(); endpoints <- integer(); cycles <- integer(); transfers <- character()
  for (source in seeds) {
    current<-source; seen<-integer(); steps<-0L
    repeat {
      if (!present[current]) { end<-"MISSING_NEIGHBOUR_TILE"; break }
      if (current %in% seen) { end<-"CYCLE"; cycles<-union(cycles,seen[match(current,seen):length(seen)]); break }
      seen<-c(seen,current)
      if (f$kind[current]!="LAND") {
        end<-if(f$kind[current]=="WATER") "FIRST_WATER_CONTACT" else f$kind[current]
        if(end=="FIRST_WATER_CONTACT") wsets[[as.character(current)]]<-union(wsets[[as.character(current)]],source)
        break
      }
      sets[[as.character(current)]]<-union(sets[[as.character(current)]],source)
      if (nzchar(f$terminal[current]) && f$terminal[current]!="DOMAIN_EXIT_UNRESOLVED") { end<-f$terminal[current]; break }
      if (steps>=cap) { end<-"STEP_LIMIT"; break }
      if (f$terminal[current]=="DOMAIN_EXIT_UNRESOLVED") { end<-f$terminal[current]; break }
      to<-f$successor[current]; stopifnot(to>0)
      if (owner[current]!=owner[to]) transfers<-c(transfers,paste(source,current,to,steps+1L,sep="|"))
      current<-to;steps<-steps+1L
    }
    status<-c(status,end);endpoints<-c(endpoints,current)
  }
  list(seeds=seeds,sets=sets,water_sets=wsets,status=status,endpoints=endpoints,cycles=cycles,transfers=transfers)
}
