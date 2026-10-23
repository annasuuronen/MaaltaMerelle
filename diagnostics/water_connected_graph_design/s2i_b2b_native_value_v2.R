# Standalone Base-R MM-S2CV v2 encoder. Explicit synthetic memory only.
# Does not source S2F/02F, open files, call processes, or infer raster storage.
.s2cv_safety <- function() list(
  NATIONAL="LOCKED", MODERATE="REVIEW_REQUIRED",
  hydrological_validation="NOT_ASSESSED", channel_interpretation="NOT_ASSESSED",
  routing_authorized=FALSE, outlet_selection="UNASSIGNED",
  HISTORIC_02F_EFFECTIVE_D8="NOT_ASSESSED", SOURCE_AUTHENTICATION="NOT_ASSESSED",
  INDEPENDENT_WITNESS="NOT_IMPLEMENTED")
.s2cv_fail <- function(code) stop(structure(
  list(message=paste0("S2CV2_STOP:",code), call=NULL, reason_code=code,
       status="STOP", safety=.s2cv_safety()), class=c("s2cv2_stop","error","condition")))
.s2cv_need <- function(ok, code) if (!isTRUE(ok)) .s2cv_fail(code)
.s2cv_record <- function(fields) c(fields,list(safety=.s2cv_safety()))
.s2cv_fields <- function(x, fields) {
  .s2cv_need(is.list(x) && identical(class(x),"list") && identical(names(x),c(fields,"safety")) &&
              identical(x$safety,.s2cv_safety()),"RECORD_SCHEMA")
}
.s2cv_int <- function(x, lo, hi, code) {
  .s2cv_need(is.numeric(x) && length(x)==1L && is.null(attributes(x)) &&
              is.finite(x) && x>=lo && x<=hi && x==floor(x),code)
  invisible(TRUE)
}
.s2cv_text <- function(x, pattern, maximum, code) {
  .s2cv_need(is.character(x) && length(x)==1L && is.null(attributes(x)) && !is.na(x) &&
    nchar(x,type="bytes")>=1L && nchar(x,type="bytes")<=maximum &&
    grepl(paste0("\\A(?:",pattern,")\\z"),x,perl=TRUE),code)
}
.s2cv_raw <- function(x, maximum, code) {
  .s2cv_need(is.raw(x) && is.null(attributes(x)) && length(x)<=maximum,code)
}
.s2cv_width <- function(storage) {
  .s2cv_text(storage,"INTEGER|DOUBLE",7L,"NATIVE_TYPE")
  if (storage=="INTEGER") 4L else 8L
}
.s2cv_uuid <- function(x) {
  .s2cv_text(x,"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}",
             36L,"UUID4")
  h <- gsub("-","",x,fixed=TRUE)
  as.raw(strtoi(substring(h,seq.int(1L,31L,2L),seq.int(2L,32L,2L)),16L))
}
.s2cv_u16 <- function(x) {
  .s2cv_int(x,0,65535,"UINT16")
  as.raw(c(x%%256L,x%/%256L))
}
.s2cv_i32 <- function(x) {
  .s2cv_int(x,-2147483647,2147483647,"INT32")
  writeBin(as.integer(x),raw(),size=4L,endian="little")
}
.s2cv_string <- function(x) c(as.raw(nchar(x,type="bytes")),charToRaw(x))
.s2cv_native_profile <- function() {
  .s2cv_need(.Machine$double.base==2 && .Machine$double.digits==53 &&
    .Machine$double.max.exp==1024 && .Machine$integer.max==2147483647 &&
    identical(writeBin(1L,raw(),size=4L,endian="little"),as.raw(c(1L,0L,0L,0L))) &&
    identical(writeBin(1.0,raw(),size=8L,endian="little"),as.raw(c(0L,0L,0L,0L,0L,0L,240L,63L))),
    "R_NATIVE_PROFILE")
}
.s2cv_header_check <- function(h) {
  .s2cv_fields(h,c("run_id","attempt_id","grid_id","rows","cols","x_origin","y_origin",
                   "r_version","r_platform","declared_dtypes"))
  .s2cv_uuid(h$run_id); .s2cv_uuid(h$attempt_id)
  .s2cv_need(!identical(h$run_id,h$attempt_id),"ATTEMPT_EQUALS_RUN")
  .s2cv_text(h$grid_id,"[a-z][a-z0-9_-]{0,31}",32L,"GRID_ID")
  .s2cv_int(h$rows,1,9,"GRID_ROWS"); .s2cv_int(h$cols,1,9,"GRID_COLS")
  .s2cv_int(h$x_origin,-100000000,100000000,"GRID_ORIGIN")
  .s2cv_int(h$y_origin,-100000000,100000000,"GRID_ORIGIN")
  .s2cv_text(h$r_version,"[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}",32L,"R_VERSION")
  .s2cv_text(h$r_platform,"[A-Za-z0-9._-]{1,64}",64L,"R_PLATFORM")
  d <- h$declared_dtypes
  .s2cv_need(is.numeric(d) && length(d)==3L && is.null(attributes(d)) &&
              all(is.finite(d) & d>=0 & d<=3 & d==floor(d)),"DTYPE_DECLARATIONS")
  invisible(TRUE)
}
s2cv_header <- function(run_id,attempt_id,grid_id,rows,cols,x_origin,y_origin,
                         r_version=as.character(getRversion()), r_platform=R.version$platform,
                         declared_dtypes=c(0L,0L,0L)) {
  h <- .s2cv_record(list(run_id=run_id,attempt_id=attempt_id,grid_id=grid_id,rows=rows,cols=cols,
                       x_origin=x_origin,y_origin=y_origin,r_version=r_version,
                       r_platform=r_platform,declared_dtypes=declared_dtypes))
  .s2cv_header_check(h)
  h
}
.s2cv_values_check <- function(v) {
  .s2cv_fields(v,c("storage_type","validity","raw_le"))
  width <- .s2cv_width(v$storage_type)
  .s2cv_need(is.character(v$validity) && is.null(attributes(v$validity)) &&
    length(v$validity)>=1L && length(v$validity)<=32L && !anyNA(v$validity) &&
    all(v$validity %in% c("FINITE","NA_INTEGER","NA_REAL","NAN","POS_INF","NEG_INF")),
    "VALIDITY_TAG")
  .s2cv_raw(v$raw_le,256L,"VALUE_WIDTH")
  .s2cv_need(length(v$raw_le)==width*length(v$validity),"VALUE_WIDTH")
  for (i in seq_along(v$validity)) {
    b <- as.integer(v$raw_le[seq.int((i-1L)*width+1L,i*width)])
    tag <- v$validity[[i]]
    if (width==4L) {
      integer_na <- identical(b,c(0L,0L,0L,128L))
      .s2cv_need(identical(tag,if(integer_na) "NA_INTEGER" else "FINITE"),"TAG_BITS")
    } else {
      exponent <- bitwAnd(b[8L],127L)*16L + bitwShiftR(b[7L],4L)
      nonzero <- any(b[1L:6L]!=0L) || bitwAnd(b[7L],15L)!=0L
      ok <- if(exponent!=2047L) tag=="FINITE" else if(nonzero) {
        tag %in% c("NA_REAL","NAN")
      } else tag==if(bitwAnd(b[8L],128L)!=0L) "NEG_INF" else "POS_INF"
      .s2cv_need(ok,"TAG_BITS")
    }
  }
  width
}
s2cv_values_raw <- function(storage_type,validity,raw_le) {
  v <- .s2cv_record(list(storage_type=storage_type,validity=validity,raw_le=raw_le))
  .s2cv_values_check(v)
  v
}
s2cv_values <- function(x) {
  .s2cv_native_profile()
  .s2cv_need(typeof(x) %in% c("integer","double") && is.null(attributes(x)) &&
              length(x)>=1L && length(x)<=32L,"NATIVE_VECTOR")
  storage <- if(typeof(x)=="integer") "INTEGER" else "DOUBLE"
  tags <- rep("FINITE",length(x))
  tags[is.nan(x)] <- "NAN"
  tags[is.na(x) & !is.nan(x)] <- if(storage=="INTEGER") "NA_INTEGER" else "NA_REAL"
  tags[is.infinite(x) & x>0] <- "POS_INF"
  tags[is.infinite(x) & x<0] <- "NEG_INF"
  s2cv_values_raw(storage,tags,writeBin(x,raw(),size=.s2cv_width(storage),endian="little"))
}
.s2cv_request_check <- function(r,count,cells) {
  .s2cv_int(count,1,32,"VALUE_COUNT")
  .s2cv_fields(r,c("storage_type","raw_le"))
  width <- .s2cv_width(r$storage_type)
  .s2cv_raw(r$raw_le,256L,"REQUEST_WIDTH")
  .s2cv_need(length(r$raw_le)==count*width,"REQUEST_WIDTH")
  if(width==4L) {
    ids <- readBin(r$raw_le,what="integer",n=count,size=4L,endian="little")
    .s2cv_need(!anyNA(ids) && all(ids>=1L & ids<=cells),"REQUEST_CELL")
  } else {
    # Generate exact small-integer encodings; never round/coerce observed bytes.
    allowed <- lapply(seq_len(cells),function(i) writeBin(as.double(i),raw(),size=8L,endian="little"))
    for(i in seq_len(count)) {
      bytes <- r$raw_le[seq.int((i-1L)*8L+1L,i*8L)]
      .s2cv_need(any(vapply(allowed,identical,logical(1),bytes)),"REQUEST_CELL")
    }
  }
  width
}
s2cv_request_raw <- function(storage_type,raw_le) {
  width <- .s2cv_width(storage_type)
  .s2cv_raw(raw_le,256L,"REQUEST_WIDTH")
  .s2cv_need(length(raw_le)>=width && length(raw_le)%%width==0L,"REQUEST_WIDTH")
  r <- .s2cv_record(list(storage_type=storage_type,raw_le=raw_le))
  .s2cv_request_check(r,length(raw_le)%/%width,81L)
  r
}
s2cv_request <- function(x) {
  .s2cv_native_profile()
  .s2cv_need(typeof(x) %in% c("integer","double") && is.null(attributes(x)) &&
              length(x)>=1L && length(x)<=32L,"NATIVE_VECTOR")
  storage <- if(typeof(x)=="integer") "INTEGER" else "DOUBLE"
  s2cv_request_raw(storage,writeBin(x,raw(),size=.s2cv_width(storage),endian="little"))
}
s2cv_batch <- function(sequence,role,request,response) {
  .s2cv_int(sequence,1,24,"SEQUENCE")
  .s2cv_text(role,"WATER_CLASS|LAKE_ID|POINTER",11L,"ROLE_SEQUENCE")
  .s2cv_values_check(response)
  .s2cv_request_check(request,length(response$validity),81L)
  .s2cv_record(list(sequence=sequence,role=role,request=request,response=response))
}
s2cv_encode <- function(header,batches) {
  .s2cv_header_check(header)
  .s2cv_need(is.list(batches) && identical(class(batches),"list") && is.null(names(batches)) &&
    length(batches)>=3L && length(batches)<=24L && length(batches)%%3L==0L,
    "COMPLETE_TRIPLETS")
  roles <- c("WATER_CLASS","LAKE_ID","POINTER")
  widths <- c(INTEGER=4L,DOUBLE=8L); type_codes <- c(INTEGER=1L,DOUBLE=2L)
  tag_codes <- c(FINITE=1L,NA_INTEGER=2L,NA_REAL=3L,NAN=4L,POS_INF=5L,NEG_INF=6L)
  slots <- 0L; stored <- list(); frames <- list()
  for(i in seq_along(batches)) {
    b <- batches[[i]]
    .s2cv_fields(b,c("sequence","role","request","response"))
    .s2cv_int(b$sequence,i,i,"SEQUENCE")
    .s2cv_need(identical(b$role,roles[(i-1L)%%3L+1L]),"ROLE_SEQUENCE")
    vw <- .s2cv_values_check(b$response); n <- length(b$response$validity)
    rw <- .s2cv_request_check(b$request,n,header$rows*header$cols)
    slots <- slots+n; .s2cv_need(slots<=512L,"SLOT_LIMIT")
    if((i-1L)%%3L!=0L) .s2cv_need(
      identical(b$request,batches[[((i-1L)%/%3L)*3L+1L]]$request),"TRIPLET_REQUEST")
    old <- stored[[b$role]]
    .s2cv_need(is.null(old) || identical(old,b$response$storage_type),"ROLE_STORAGE_CHANGED")
    stored[[b$role]] <- b$response$storage_type
    body <- c(.s2cv_u16(i),as.raw(match(b$role,roles)),
              as.raw(type_codes[[b$request$storage_type]]),
              as.raw(type_codes[[b$response$storage_type]]),.s2cv_u16(n))
    for(j in seq_len(n)) body <- c(body,
      b$request$raw_le[seq.int((j-1L)*rw+1L,j*rw)],
      as.raw(tag_codes[[b$response$validity[[j]]]]),
      b$response$raw_le[seq.int((j-1L)*vw+1L,j*vw)])
    .s2cv_need(length(body)==7L+n*(rw+1L+vw) && length(body)<=551L,"BODY_LENGTH")
    frames[[i]] <- c(.s2cv_u16(length(body)),body)
  }
  h <- header
  out <- c(charToRaw("MM-S2CV"),as.raw(c(0L,2L,1L,1L)),raw(4L),
    .s2cv_uuid(h$run_id),.s2cv_uuid(h$attempt_id),.s2cv_string(h$grid_id),
    .s2cv_u16(h$rows),.s2cv_u16(h$cols),.s2cv_i32(3067L),
    .s2cv_i32(h$x_origin),.s2cv_i32(h$y_origin),as.raw(c(2L,1L,1L)),
    .s2cv_string(h$r_version),.s2cv_string(h$r_platform),as.raw(h$declared_dtypes),
    .s2cv_u16(length(batches)),.s2cv_i32(slots),do.call(c,frames),
    charToRaw("MM-END2"),as.raw(0L),.s2cv_u16(length(batches)),.s2cv_i32(slots))
  .s2cv_need(length(out)<=16384L,"BYTE_LIMIT")
  out[12L:15L] <- .s2cv_i32(length(out))
  .s2cv_record(list(data=out,disposition="STRUCTURALLY_WELL_FORMED",authentication="NOT_AUTHENTICATED"))
}
