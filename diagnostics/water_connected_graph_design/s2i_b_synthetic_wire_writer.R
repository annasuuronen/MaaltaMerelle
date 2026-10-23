# S2I-B: independent Base-R writer for the pinned S2I-A synthetic wire format.
# Pure in-memory values; NO Terra, filesystem, source data, signing or auth.
.s2ib_fail <- function(reason) stop(paste0('S2IB_STOP:', reason), call. = FALSE)
.s2ib_need <- function(ok, reason) if (!isTRUE(ok)) .s2ib_fail(reason)
.s2ib_hex <- function(x) {
  .s2ib_need(is.character(x) && length(x)==1L && !is.na(x) &&
              nchar(x, type='bytes') %% 2L == 0L &&
              grepl('^[0-9a-f]*$', x), 'INVALID_HEX')
  if (!nzchar(x)) return(raw())
  as.raw(strtoi(substring(x, seq.int(1L,nchar(x),2L),
                           seq.int(2L,nchar(x),2L)), 16L))
}
.s2ib_uuid <- function(s) {
  .s2ib_need(is.character(s) && length(s)==1L && !is.na(s) &&
                grepl('^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',s),
             'RUN_ID_FORMAT')
  .s2ib_hex(gsub('-', '', s, fixed=TRUE))
}
.s2ib_int <- function(x, lower, upper, code) {
  .s2ib_need(is.numeric(x) && length(x)==1L && !is.na(x) && is.finite(x) &&
              x == floor(x) && x >= lower && x <= upper && is.null(attributes(x)),code)
  as.integer(x)
}
.s2ib_u8 <- function(x) as.raw(.s2ib_int(x, 0, 255, 'UINT8'))
.s2ib_u16 <- function(x) {
  n <- .s2ib_int(x,0,65535,'UINT16')
  as.raw(c(n %% 256L, n %/% 256L))
}
.s2ib_i32 <- function(x) {
  n <- .s2ib_int(x,-2147483647,2147483647,'INT32')
  writeBin(n, raw(), size=4L, endian='little')
}
# The minimum signed 32-bit integer is reserved for R's NA_INTEGER in this format.
.s2ib_scalar <- function(tag, bytes) {
  .s2ib_need(is.character(tag) && length(tag)==1L && !is.na(tag) &&
              tag %in% c('FINITE','R_NA','NAN','POS_INF','NEG_INF','NA_INTEGER','NODATA') &&
              is.raw(bytes), 'SCALAR_TYPE')
  list(tag=tag, raw_le=bytes)
}
s2ib_byte <- function(x) {
  n <- .s2ib_int(x,0,255,'BYTE_VALUE')
  .s2ib_scalar(if(n==255L) 'NODATA' else 'FINITE', as.raw(n))
}
s2ib_int32 <- function(x) {
  if (is.integer(x) && length(x)==1L && is.na(x))
    return(.s2ib_scalar('NA_INTEGER', .s2ib_hex('00000080')))
  .s2ib_scalar('FINITE', .s2ib_i32(x))
}
s2ib_float64_raw <- function(bytes) {
  .s2ib_need(is.raw(bytes) && length(bytes)==8L, 'FLOAT64_BYTES')
  b <- as.integer(bytes)
  exponent <- bitwAnd(b[8L],127L)*16L + bitwShiftR(b[7L],4L)
  mantissa_zero <- all(b[1L:6L]==0L) && bitwAnd(b[7L],15L)==0L
  tag <- if(exponent != 2047L) 'FINITE' else if(mantissa_zero) {
    if(bitwAnd(b[8L],128L)!=0L) 'NEG_INF' else 'POS_INF'
  } else if(identical(bytes, .s2ib_hex('a20700000000f07f'))) 'R_NA' else 'NAN'
  .s2ib_scalar(tag,bytes)
}
s2ib_float64 <- function(x) {
  .s2ib_need(is.double(x) && length(x)==1L && is.null(attributes(x)), 'FLOAT64_INPUT')
  s2ib_float64_raw(writeBin(x,raw(),size=8L,endian='little'))
}
.s2ib_scalar_check <- function(value, role) {
  .s2ib_need(is.list(value) && identical(sort(names(value)),c('raw_le','tag')) &&
                is.character(value$tag) && length(value$tag)==1L &&
                is.raw(value$raw_le), 'SCALAR_TYPE')
  expected <- switch(role,
    WATER_CLASS={.s2ib_need(length(value$raw_le)==1L,'SCALAR_WIDTH');s2ib_byte(as.integer(value$raw_le))},
    LAKE_ID={
      .s2ib_need(length(value$raw_le)==4L,'SCALAR_WIDTH')
      if(identical(value$raw_le,.s2ib_hex('00000080'))) s2ib_int32(NA_integer_)
      else {
        # Preserve signed INT32 values including negative ones; -2147483648 is NA only.
        b <- as.integer(value$raw_le)
        unsigned <- b[1L] + 256*b[2L] + 65536*b[3L] + 16777216*b[4L]
        signed <- if(unsigned >= 2147483648) unsigned - 4294967296 else unsigned
        s2ib_int32(signed)
      }
    },
    POINTER=s2ib_float64_raw(value$raw_le),
    .s2ib_fail('ROLE'))
  .s2ib_need(identical(value$tag,expected$tag) && identical(value$raw_le,expected$raw_le),
              'SCALAR_TAG_DTYPE')
}
s2ib_encode_batch <- function(run_id, attempt_id, grid_id, rows, cols,
                              x_origin, y_origin, sequence, role,
                              requested_cells, values) {
  run <- .s2ib_uuid(run_id); attempt <- .s2ib_uuid(attempt_id)
  .s2ib_need(!identical(run,attempt),'ATTEMPT_EQUALS_RUN')
  .s2ib_need(is.character(grid_id) && length(grid_id)==1L && !is.na(grid_id) &&
                grepl('^[a-z][a-z0-9_-]{0,31}$',grid_id),'GRID_ID')
  r <- .s2ib_int(rows,1,9,'ROWS'); c <- .s2ib_int(cols,1,9,'COLS')
  .s2ib_need(r*c<=81L, 'GRID_LIMIT')
  x <- .s2ib_int(x_origin,-100000000,100000000,'X_ORIGIN')
  y <- .s2ib_int(y_origin,-100000000,100000000,'Y_ORIGIN')
  seqn <- .s2ib_int(sequence,1,24,'SEQUENCE_LIMIT')
  roles <- c(WATER_CLASS=1L,LAKE_ID=2L,POINTER=3L)
  .s2ib_need(is.character(role) && length(role)==1L && !is.na(role) &&
                role %in% names(roles), 'ROLE')
  .s2ib_need(is.list(values) && length(values)>=1L && length(values)<=32L &&
                is.numeric(requested_cells) && !is.object(requested_cells) &&
                length(requested_cells)==length(values), 'CELL_VALUE_COUNT')
  .s2ib_need(all(is.finite(requested_cells) & requested_cells >= 1 &
                  requested_cells <=r*c & requested_cells==floor(requested_cells)),
              'CELL_ID_OUT_OF_GRID')
  tags <- c(FINITE=1L,R_NA=2L,NAN=3L,POS_INF=4L,NEG_INF=5L,NA_INTEGER=6L,NODATA=7L)
  raw <- c(charToRaw('MM-S2IA'),as.raw(0L),as.raw(1L),run,attempt,
           .s2ib_u8(nchar(grid_id)), charToRaw(grid_id),
           .s2ib_u16(r),.s2ib_u16(c),.s2ib_i32(x),.s2ib_i32(y),
           .s2ib_u16(seqn),.s2ib_u8(roles[[role]]),.s2ib_u16(length(values)))
  for(i in seq_along(values)) {
    .s2ib_scalar_check(values[[i]],role)
    raw <- c(raw,.s2ib_u16(requested_cells[[i]]), .s2ib_u8(tags[[values[[i]]$tag]]),
             values[[i]]$raw_le)
  }
  .s2ib_need(length(raw)<=4096L,'BYTE_BUDGET')
  raw
}