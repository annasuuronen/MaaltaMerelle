# S2I-B: synthetic R-side wire fixtures, cross-check with Python test only.
# Run Rscript --vanilla test_s2i_b_synthetic_emit.R. Does not source hydrology.
args <- commandArgs(trailingOnly=FALSE)
file_arg <- sub('^--file=', '', args[grepl('^--file=', args)])
if(length(file_arg)!=1L) stop('S2IB_STOP:SCRIPT_PATH')
source(file.path(dirname(normalizePath(file_arg)), 's2i_b_synthetic_wire_writer.R'), local=TRUE)
run <- '123e4567-e89b-42d3-a456-426614174000'
attempt <- '123e4567-e89b-42d3-a456-426614174001'
hex <- function(r) paste(sprintf('%02x',as.integer(r)), collapse='')
emit <- function(scenario, role, sequence, cells, values) {
  tryCatch({
    out <- s2ib_encode_batch(run, attempt, 'tiny', 3L, 3L, 199000L, 6911000L,
                             sequence, role, cells, values)
    cat(sprintf('CASE=%s|ROLE=%s|SEQ=%d|WIRE=%s\n',scenario,role,sequence,hex(out)))
  }, error=function(e) {
    cat(sprintf('R_FIXTURE_STAGE_STOP=%s:%s:%s\n',
                scenario,role,conditionMessage(e)),file=stderr())
    stop(e)
  })
}
# Actual 02F callback asks for WATER_CLASS -> LAKE_ID -> POINTER for same cells.
# Duplicate cell IDs are intentional; no hydrological model is executed.
emit('core','WATER_CLASS',1L,c(5L,5L,9L),lapply(c(1L,255L,0L),s2ib_byte))
emit('core','LAKE_ID',2L,c(5L,5L,9L),list(s2ib_int32(16777217L),
      s2ib_int32(NA_integer_),s2ib_int32(-123L)))
emit('core','POINTER',3L,c(5L,5L,9L),list(s2ib_float64(-0.0),
      s2ib_float64(NA_real_), s2ib_float64_raw(.s2ib_hex('010000000000f87f'))))
emit('special','WATER_CLASS',1L,c(1L,3L,8L),lapply(c(3L,2L,1L),s2ib_byte))
emit('special','LAKE_ID',2L,c(1L,3L,8L),lapply(c(0L,2147483647L,-2147483647L),s2ib_int32))
emit('special','POINTER',3L,c(1L,3L,8L),list(s2ib_float64(Inf),
      s2ib_float64(-Inf), s2ib_float64(0.25)))
emit('directions','WATER_CLASS',1L,1L:8L,lapply(rep.int(0L,8L),s2ib_byte))
emit('directions','LAKE_ID',2L,1L:8L,lapply(100L:107L,s2ib_int32))
emit('directions','POINTER',3L,1L:8L,lapply(as.double(c(1L,2L,4L,8L,16L,32L,64L,128L)),s2ib_float64))
# Synthetic-only negative cases are locally checked before producing a PASS claim.
expect_stop <- function(expr) {
  err <- tryCatch({force(expr);NULL},error=function(e) conditionMessage(e))
  stopifnot(is.character(err), length(err)==1L, startsWith(err,'S2IB_STOP:'))
}
expect_stop(s2ib_encode_batch(run,attempt,'tiny',3,3,199000,6911000,1,'POINTER',c(1),list(s2ib_byte(1))))
expect_stop(s2ib_encode_batch(run,run,'tiny',3,3,199000,6911000,1,'POINTER',c(1),list(s2ib_float64(1))))
expect_stop(s2ib_encode_batch(run,attempt,'tiny',3,3,199000,6911000,1,'WATER_CLASS',c(10),list(s2ib_byte(1))))
expect_stop(s2ib_encode_batch(run,attempt,'tiny',3,3,199000,6911000,1,'WATER_CLASS',c(1),list(s2ib_float64(1))))
cat('R_SYNTHETIC_NEGATIVE_PASS=4\n')