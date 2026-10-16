# Lightweight base-R synthetic QA; no raster I/O and no Slurm needed.
script <- grep('^--file=', commandArgs(), value = TRUE)
stopifnot(length(script) == 1L)
source(file.path(dirname(normalizePath(sub('^--file=', '', script))),
                 'lake_to_land_d8_core.R'))
p <- matrix(NA_real_, 6L, 7L)
w <- matrix(NA_real_, 6L, 7L)
id <- matrix(NA_real_, 6L, 7L)
id[3,3] <- 3181; w[3,3] <- 1; p[3,3] <- 2   # E -> (3,4) zero
id[4,3] <- 3181; w[4,3] <- 1; p[4,3] <- 1   # NE -> same zero
p[3,4] <- 0
id[3,5] <- 1847; w[3,5] <- 1; p[3,5] <- 16 # SW -> nonzero (4,4)
p[4,4] <- 2
id[4,6] <- 1847; w[4,6] <- 1; p[4,6] <- 32 # W -> land pointer NA
id[2,5] <- 1847; w[2,5] <- 1; p[2,5] <- 8  # S -> lake (excluded)
id[6,7] <- 1847; w[6,7] <- 1; p[6,7] <- 2  # E -> tile exit (excluded)
a <- low_d8_lake_to_land_block(p[1:4,,drop=FALSE],w[1:4,,drop=FALSE],
                               id[1:4,,drop=FALSE],1L,1L,3L,6L)
b <- low_d8_lake_to_land_block(p[3:6,,drop=FALSE],w[3:6,,drop=FALSE],
                               id[3:6,,drop=FALSE],3L,4L,6L,6L)
e <- rbind(a, b)
stopifnot(nrow(e) == 4L, !anyDuplicated(e$source_cell),
          sum(e$receiver_pointer == 0, na.rm=TRUE) == 2L)
s <- low_d8_lake_to_land_summary(e, c(3181L,1847L,1898L))
stopifnot(identical(as.integer(s$lake_to_land_edges),c(2L,2L,0L)),
          identical(as.integer(s$immediate_zero_edges),c(2L,0L,0L)),
          identical(as.integer(s$distinct_zero_cells),c(1L,0L,0L)),
          identical(as.integer(s$nonzero_land_pointer_edges),c(0L,1L,0L)),
          identical(as.integer(s$na_land_pointer_edges),c(0L,1L,0L)),
          s$immediate_zero_fraction[1] == 1,
          is.na(s$immediate_zero_fraction[3]))
fails <- function(expr) inherits(tryCatch(force(expr),error=identity),'error')
stopifnot(fails(low_d8_lake_to_land_block(
  p[1:3,,drop=FALSE],w[1:3,,drop=FALSE],id[1:3,,drop=FALSE],
  1L,1L,3L,6L)))
bad <- e; bad$receiver_pointer[1] <- 999
stopifnot(fails(low_d8_lake_to_land_summary(bad)))
bad <- e; bad$source_cell[2] <- bad$source_cell[1]
stopifnot(fails(low_d8_lake_to_land_summary(bad)))
bad_id <- id; bad_id[3,3] <- 2; bad_w <- w; bad_w[3,3] <- NA_real_
stopifnot(fails(low_d8_lake_to_land_block(
  p[1:4,,drop=FALSE],bad_w[1:4,,drop=FALSE],
  bad_id[1:4,,drop=FALSE],1L,1L,3L,6L)))
cat('PASS: lake-to-land denominator, chunk halo, zero/nonzero/NA, tile exit, and fail closed\n')
