#!/usr/bin/env Rscript
# Synthetic, isolated test of the new read-only Roihu review diagnostics.
# No CSC paths, production models, or data are modified.
suppressPackageStartupMessages(library(terra))
args <- commandArgs(trailingOnly=TRUE)
root <- if (length(args)) normalizePath(args[[1]], mustWork=TRUE) else normalizePath(".", mustWork=TRUE)
file1 <- file.path(root, "scripts", "audit_moderate_spill_d8_readonly.R")
file2 <- file.path(root, "scripts", "audit_moderate_lake_geometry_readonly.R")
stopifnot(file.exists(file1), file.exists(file2))
invisible(parse(file=file1)); invisible(parse(file=file2))
dir <- tempfile("moderate-review-test-")
dir.create(dir)
on.exit <- NULL # All temporary files are under a dedicated disposable tempdir.
baseline <- file.path(dir, "02_baseline")
dir.create(baseline)
lake <- rast(nrows=7, ncols=7, xmin=0, xmax=14, ymin=0, ymax=14, crs="EPSG:3067")
lake[] <- NA_real_
lake[cellFromRowCol(lake,4,4)] <- 101
lake[cellFromRowCol(lake,1,2)] <- 102
lake[cellFromRowCol(lake,1,3)] <- 102
w <- rast(lake); w[] <- 12
w[cellFromRowCol(lake,4,4)] <- 10
w[cellFromRowCol(lake,4,5)] <- NA_real_
w[cellFromRowCol(lake,1,2)] <- 9
w[cellFromRowCol(lake,1,3)] <- 9.5
s <- w
pointer <- rast(lake); pointer[] <- 0
# 101's spill receiver 3,4 is westbound into lake 101.
receiver101 <- cellFromRowCol(lake,4,3)
pointer[receiver101] <- 2
# 102's spill receiver 2,2 is pointer zero and must be terminal.
receiver102 <- cellFromRowCol(lake,2,2)
writeRaster(lake,file.path(dir,"lake_id.tif"),overwrite=FALSE)
writeRaster(w,file.path(baseline,"routing_surface_land_water_FLT8S.tif"),overwrite=FALSE)
writeRaster(s,file.path(baseline,"routing_surface_water_storage_FLT8S.tif"),overwrite=FALSE)
writeRaster(pointer,file.path(baseline,"d8_pointer_land_water_FLT8S.tif"),overwrite=FALSE)
summary <- data.frame(lake_objectid=c(101,102),
  depression_status=rep("SPILL_RAISED_NO_COMPONENT",2),
  spill_raised=c(TRUE,TRUE), n_depression_components=c(0,0),
  n_raised_lake_cells=c(0,0), max_storage_raise_m=c(0,0))
spill <- data.frame(lake_objectid=c(101,102),
  spill_raise_m=c(2,3),raise_mismatch=c(TRUE,TRUE))
edges <- data.frame(lake_objectid=c(101,102),
  source_cell=c(cellFromRowCol(lake,4,4),cellFromRowCol(lake,1,2)),
  receiver_cell=c(receiver101,receiver102))
zc <- data.frame(cell=integer())
write.csv(summary,file.path(baseline,"02D_lake_depression_component_summary.csv"),row.names=FALSE)
write.csv(spill,file.path(baseline,"02D_spill_group_diagnostic.csv"),row.names=FALSE)
write.csv(edges,file.path(baseline,"02D_lowest_spill_shore_edges.csv"),row.names=FALSE)
write.csv(zc,file.path(baseline,"02C_zero_pointer_cells.csv"),row.names=FALSE)
run <- function(script) {
  output <- suppressWarnings(system2(file.path(R.home("bin"),"Rscript"),
    c("--vanilla",shQuote(script),shQuote(baseline),shQuote(file.path(dir,"lake_id.tif"))),
    stdout=TRUE,stderr=TRUE))
  rc <- attr(output,"status")
  if (!is.null(rc) && rc != 0L) stop(paste("FAILED",script,paste(output,collapse="\n")))
  paste(output,collapse="\n")
}
d8 <- run(file1)
stopifnot(grepl("MISMATCH_CLASS 2", d8, fixed=TRUE),
          grepl("RETURN_TO_SOURCE_LAKE",d8,fixed=TRUE),
          grepl("TERMINAL_0",d8,fixed=TRUE),
          grepl("PRODUCTION_02D5_GATE_PASS FALSE",d8,fixed=TRUE),
          grepl("NATIONAL_LOCKED TRUE",d8,fixed=TRUE))
geom <- run(file2)
stopifnot(grepl("TARGET_LAKES 2",geom,fixed=TRUE),
          grepl("TOUCHES_DOMAIN_EDGE 1",geom,fixed=TRUE),
          grepl("HAS_NODATA_OUTSIDE_SHORE 1",geom,fixed=TRUE),
          grepl("NONCONSTANT_LAKE_Z 1",geom,fixed=TRUE),
          grepl("HAS_CHANGED_SOURCE_STORAGE 0",geom,fixed=TRUE),
          grepl("SCIENTIFIC_STATUS REVIEW_REQUIRED",geom,fixed=TRUE),
          grepl("NATIONAL_LOCKED TRUE",geom,fixed=TRUE))
unlink(dir,recursive=TRUE)
cat("PASS: BOTH MODERATE REVIEW DIAGNOSTICS (synthetic only)\n")
cat("PASS: BOTH SCIENTIFIC LOCKS REMAIN IN FORCE\n")
