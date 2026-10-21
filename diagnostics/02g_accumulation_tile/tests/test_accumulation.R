#!/usr/bin/env Rscript
here <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))))
source(file.path(here, "support.R"))
cases <- 0L
case <- function(name, expr) { force(expr); cases <<- cases + 1L; cat("PASS:", name, "\n") }
arcs <- function(...) matrix(c(...), ncol = 2L, byrow = TRUE)
two <- fixture(land = c(1L, 6:9), arcs = arcs(1,7,6,7,7,8,8,9,9,10), water = 10L)
serial <- fixture(land = c(1:3, 6:9), arcs = arcs(1,7,2,8,3,9,6,7,7,8,8,9,9,10), water = 10L)
case("two branches share downstream edges without duplicated sources", {
  r <- run_fixture(two, external = "KNOWN_ZERO_SYNTHETIC"); verify(two, r, 32L)
  check(r$nodes$local_upstream_cells[match(g02_uid(7, two$grid), r$nodes$cell_uid)] == 3)
  check(r$water$local_source_cells == 5 && r$balance$area_m2 == 20)
  check(all(r$nodes$total_upstream_cells == r$nodes$local_upstream_cells))
  check(r$balance$local_recurrence == "PASS")
})
case("three serial tributaries preserve exact source sets", {
  r <- run_fixture(serial); verify(serial, r, 32L)
  check(identical(as.numeric(r$nodes$local_upstream_cells[match(g02_uid(c(7,8,9),serial$grid),r$nodes$cell_uid)]),c(3,5,7)))
  check(r$water$local_source_cells == 7 && all(is.na(r$nodes$total_upstream_cells)))
  check(all(r$nodes$external_import == "UNKNOWN"))
})
for (w in 1:3) case(paste("first contact class",w,"keeps every sub-threshold source"), {
  f <- two; f$cells$water_class[10] <- w; f$cells$lake_id[10] <- if (w==1) 9001 else NA_real_
  r <- run_fixture(f); verify(f,r,32L)
  check(r$water$water_class == w && r$water$local_source_cells == 5)
  check(if (w==1) r$water$lake_objectid == 9001 else is.na(r$water$lake_objectid))
  for (p in c(0,3,NA_real_)) {
    variant <- f; variant$cells$pointer[10] <- p; a <- run_fixture(variant)
    check(identical(a$source_ledger, r$source_ledger) && identical(a$water,r$water), "water outgoing pointer irrelevant")
  }
})
for (kind in c("zero","nodata","cycle","step","boundary","pointer_na","invalid")) case(paste("unresolved",kind), {
  f <- fixture(land = 6:9, arcs = arcs(6,7,7,8,8,9))
  cap <- 32L
  if (kind == "nodata") { f$cells$valid[9] <- FALSE; f$kind[9] <- "NO_DATA" }
  if (kind == "cycle") { f$successor[9] <- 8L; f$cells$pointer[9] <- 32; f$terminal[9] <- "" }
  if (kind == "step") { f <- two; cap <- 2L }
  if (kind == "boundary") { f <- fixture(land=6:10, arcs=arcs(6,7,7,8,8,9,9,10),boundary=10L) }
  if (kind == "pointer_na") { f$cells$pointer[9] <- NA_real_; f$terminal[9] <- "POINTER_NA" }
  if (kind == "invalid") { f$cells$pointer[9] <- 3; f$terminal[9] <- "INVALID_POINTER" }
  r <- run_fixture(f,cap); verify(f,r,cap)
  check(r$balance$n_unresolved > 0 && r$balance$n_approved_exports == 0 && r$coverage_status != "COMPLETE_DECLARED_LOCAL_DOMAIN")
  if (kind == "cycle") check(all(is.na(r$nodes$local_upstream_cells[r$nodes$cell_uid %in% r$cycle_cells])))
  if (kind == "step") check(r$water$local_source_cells == 2 && r$balance$local_recurrence == "NOT_APPLICABLE")
})
case("existing bounded network adapter never extends censored traces", {
  source(file.path(repo,"diagnostics/land_network_topology/land_network_topology.R"))
  f <- two; g <- f$grid
  net <- build_land_d8_network(matrix(f$cells$pointer,g$nrow,g$ncol,byrow=TRUE),
    matrix(f$cells$water_class,g$nrow,g$ncol,byrow=TRUE),matrix(f$cells$valid,g$nrow,g$ncol,byrow=TRUE),
    g,f$provenance,matrix(f$cells$lake_id,g$nrow,g$ncol,byrow=TRUE),max_steps=2L)
  snapshot <- serialize(net,NULL); r <- g02_from_network(net,f$provenance)
  verify(f,r,2L); check(identical(snapshot,serialize(net,NULL)))
  forged <- net; forged$routes[[1]]$transitions$d8_code[1] <- 128
  reject(g02_from_network(forged,f$provenance))
})
case("invalid grids observations and non-synthetic inputs rejected", {
  f <- two; p <- f$provenance; p$synthetic <- FALSE
  reject(g02_observe(f$cells,f$grid,p)); bad <- f$grid; bad$resolution_m <- 3
  reject(g02_observe(f$cells,bad,f$provenance)); bad <- f$cells; bad <- rbind(bad,bad[1,])
  reject(g02_observe(bad,f$grid,f$provenance))
})
case("empty land and empty water products keep typed zero-source balance", {
  for (water in list(integer(),10L)) {
    f <- fixture(land=integer(),arcs=matrix(integer(),ncol=2),water=water)
    r <- run_fixture(f); verify(f,r,32L)
    check(nrow(r$nodes)==0 && r$balance$n_sources==0 && r$balance$local_recurrence=="NOT_APPLICABLE")
  }
})
check(cases > 0L && checks > 0L)
cat(sprintf("RESULT n=15 scenario=small cap=32 cases=%d checks=%d status=PASS\n",cases,checks))
