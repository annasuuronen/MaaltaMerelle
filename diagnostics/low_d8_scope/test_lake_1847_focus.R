# Base R synthetic QA. No I/O, no model modifications.
s <- grep('^--file=',commandArgs(),value=TRUE)
stopifnot(length(s)==1L)
source(file.path(dirname(normalizePath(sub('^--file=','',s))), 'lake_1847_focus_core.R'))
p <- matrix(NA_real_,5,5); w <- matrix(NA_real_,5,5)
land <- matrix(1,5,5); storage <- land; raw <- land; filled <- land
# Cell 12 lake → cell 13 zero; cell 17 lake → cell 18 nonzero.
w[3,2] <- 1L; w[4,2] <- 1L
p[3,2] <- 2L; p[3,3] <- 0L; p[4,2] <- 2L; p[4,3] <- 2L
raw[3,2] <- NA_real_; raw[4,2] <- NA_real_
filled[3,2] <- NA_real_; filled[4,2] <- NA_real_
land[3,2] <- 1.2; land[4,2] <- 1.2; land[3,3] <- 1; land[4,3] <- 1
storage[3,3] <- 1.2
e <- data.frame(lake_objectid=c(1847L,1847L),source_cell=c(12L,17L),
                receiver_cell=c(13L,18L),receiver_pointer=c(0,2))
sum <- l1847_summary(e,p,w,land,storage,raw,filled,expected=FALSE)
stopifnot(sum$total==2L,sum$zero_edges==1L,sum$continuing_edges==1L,
          sum$unique_zero==1L,sum$distinct_zero_storage_raised==1L,
          sum$distinct_zero_raw_fill_unchanged==1L,
          sum$continuing_source==17L,sum$continuing_receiver==18L,
          identical(l1847_global_cell(c(1L,12L),10L,20L,5L,30L),c(290L,351L)))
fail <- function(expr) inherits(tryCatch(force(expr),error=identity),'error')
stopifnot(fail(l1847_summary(e,p,w,land,storage,raw,filled,expected=TRUE)))
bad <- e; bad$receiver_cell[1L] <- 12L
stopifnot(fail(l1847_summary(bad,p,w,land,storage,raw,filled,expected=FALSE)))
bad <- e; bad$source_cell[2L] <- bad$source_cell[1L]
stopifnot(fail(l1847_summary(bad,p,w,land,storage,raw,filled,expected=FALSE)))
read <- function(cell) list(pointer=if (cell==18L) 2L else if (cell==19L) 0L else NA_real_,
                            water_class=NA_integer_,lake_id=NA_integer_)
a <- l1847_trace(18L,5L,5L,read)
stopifnot(a$status=='D8_ZERO',a$cell==19L,a$steps==1L)
read_cycle <- function(cell) list(pointer=if (cell==18L) 2L else 32L,
                                   water_class=NA_integer_,lake_id=NA_integer_)
b <- l1847_trace(18L,5L,5L,read_cycle)
stopifnot(b$status=='CYCLE')
read_water <- function(cell) list(pointer=0L,water_class=1L,lake_id=1847L)
stopifnot(l1847_trace(18L,5L,5L,read_water)$status=='REACHES_WATER_CLASS')
cat('PASS: LOW 1847 local window counts, elevations, mask and bounded D8 tracing\n')
