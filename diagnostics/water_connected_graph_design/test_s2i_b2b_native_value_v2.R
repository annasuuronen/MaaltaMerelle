# New standalone v2 tests/emitter only. No S2F, 02F or hydrology sources.
args <- commandArgs(trailingOnly=FALSE)
path <- sub("^--file=","",args[grepl("^--file=",args)])
if(length(path)!=1L) stop("V2_TEST_SCRIPT_PATH")
source(file.path(dirname(normalizePath(path)),"s2i_b2b_native_value_v2.R"),local=TRUE)
counts <- c(PASS=0L,FAIL=0L,NOT_RUN=0L); names_seen <- character()
test <- function(name,expr) {
  if(name %in% names_seen) stop("DUPLICATE_TEST_NAME")
  names_seen <<- c(names_seen,name)
  tryCatch({eval(substitute(expr),parent.frame());counts["PASS"]<<-counts["PASS"]+1L;
    cat("PASS ",name,"\n",sep="")},error=function(e) {
      counts["FAIL"]<<-counts["FAIL"]+1L;cat("FAIL ",name,": ",conditionMessage(e),"\n",sep="")})
}
expect_stop <- function(expr,code) {
  answer <- tryCatch({force(expr);"NO_STOP"},s2cv2_stop=function(e) e$reason_code)
  stopifnot(identical(answer,code))
}
raw_hex <- function(s) {
  if(!nzchar(s)) return(raw())
  as.raw(strtoi(substring(s,seq.int(1L,nchar(s),2L),seq.int(2L,nchar(s),2L)),16L))
}
hex <- function(r) paste(sprintf("%02x",as.integer(r)),collapse="")
run <- "123e4567-e89b-42d3-a456-426614174000"
attempt <- "123e4567-e89b-42d3-a456-426614174001"
head_fixture <- function(...) s2cv_header(run,attempt,"tiny",3L,3L,0L,0L,
                                          r_version="0.0.1",r_platform="synthetic-fixture",...)
doubles <- function(tags,bits) s2cv_values_raw("DOUBLE",tags,raw_hex(paste(bits,collapse="")))
triplet <- function(request,responses,start=1L) lapply(1L:3L,function(i)
  s2cv_batch(start+i-1L,c("WATER_CLASS","LAKE_ID","POINTER")[[i]],request,responses[[i]]))
na <- "a20700000000f07f"; qnan <- "010000000000f87f"
pzero <- "0000000000000000"; nzero <- "0000000000000080"
inf <- "000000000000f07f"; ninf <- "000000000000f0ff"
cases <- list()
cases$minimum <- list(h=head_fixture(),b=triplet(s2cv_request(5L),list(
  s2cv_values(3L),s2cv_values(NA_integer_),doubles("FINITE",nzero))))
cases$mixed <- list(h=head_fixture(),b=triplet(s2cv_request(c(5L,5L,9L)),list(
  doubles(c("NA_REAL","FINITE","FINITE"),c(na,pzero,nzero)),
  s2cv_values(c(16777217L,NA_integer_,-123L)),
  doubles(c("NAN","POS_INF","NEG_INF"),c(qnan,inf,ninf)))))
cases$flipped <- list(h=head_fixture(),b=triplet(s2cv_request(c(1,1,9)),list(
  s2cv_values(c(NA_integer_,3L,255L)),
  doubles(c("NA_REAL","FINITE","FINITE"),c(na,nzero,"0100000000000000")),
  s2cv_values(c(0L,128L,-2147483647L)))))
cases$extremes <- list(h=head_fixture(),b=triplet(s2cv_request(c(2,2,8)),list(
  doubles(c("NAN","FINITE","FINITE"),c("010000000000f8ff","00000000000004c0","0000000000e06f40")),
  s2cv_values(c(-2147483647L,2147483647L,0L)),
  doubles(rep("FINITE",3L),c("0100000000000000","ffffffffffffef7f","ffffffffffffefff")))))
cases$declared <- cases$flipped;cases$declared$h <- head_fixture(declared_dtypes=c(1L,2L,3L))
many <- list()
for(n in c(32L,32L,32L,32L,32L,4L,3L,3L)) {
  r <- s2cv_request(rep(1,n));v <- s2cv_values(rep(0,n))
  many <- c(many,triplet(r,list(v,v,v),length(many)+1L))
}
cases$many <- list(h=head_fixture(),b=many)
cases$max_header <- list(h=s2cv_header(run,attempt,paste0("g",paste(rep("x",31L),collapse="")),
  9L,9L,-100000000L,100000000L,"999.999.999",paste(rep("p",64L),collapse="")),
  b=triplet(s2cv_request(81L),list(s2cv_values(3L),s2cv_values(NA_integer_),doubles("FINITE",nzero))))
enc <- function(x) s2cv_encode(x$h,x$b)
mutate <- function(f) {x <- cases$minimum;f(x)}

test("seven_synthetic_transcripts_encode_with_structure_only_status", {
  for(x in cases) stopifnot(is.raw(enc(x)$data),length(enc(x)$data)<=16384L,
                            enc(x)$disposition=="STRUCTURALLY_WELL_FORMED")
})
test("native_NA_nan_zero_infinities_preserve_tags_and_all_bits", {
  x <- c(NA_real_,NaN,0.0,-0.0,Inf,-Inf)
  before <- writeBin(x,raw(),size=8L,endian="little")
  v <- s2cv_values(x)
  stopifnot(identical(v$validity,c("NA_REAL","NAN","FINITE","FINITE","POS_INF","NEG_INF")),
            identical(v$raw_le,before),
            identical(before,writeBin(x,raw(),size=8L,endian="little")))
})
test("native_runtime_profile_matches_int32_binary64", {
  .s2cv_native_profile()
  stopifnot(identical(s2cv_values(1.0)$raw_le,raw_hex("000000000000f03f")))
})
test("unsupported_native_runtime_profile_stops_without_coercion", {
  isolated <- new.env(parent=environment(.s2cv_native_profile))
  isolated$.Machine <- .Machine;isolated$.Machine$double.digits <- 52L
  check <- .s2cv_native_profile;environment(check) <- isolated
  isolated$.s2cv_native_profile <- check
  capture <- s2cv_values;environment(capture) <- isolated
  expect_stop(capture(1.0),"R_NATIVE_PROFILE")
})
test("custom_nan_payload_and_sign_preserved", {
  x <- doubles(c("NAN","NAN"),c(qnan,"010000000000f8ff"))
  stopifnot(identical(x$raw_le,raw_hex(paste0(qnan,"010000000000f8ff"))))
})
test("native_integer_large_ID_NA_and_boundaries_exact", {
  v <- s2cv_values(c(16777217L,NA_integer_,-2147483647L,2147483647L))
  stopifnot(identical(v$raw_le,raw_hex("010000010000008001000080ffffff7f")))
})
test("integer_and_double_same_number_have_distinct_wire", {
  x <- cases$minimum;y <- x;y$b[[1L]]$response <- s2cv_values(3)
  stopifnot(!identical(enc(x)$data,enc(y)$data))
})
test("integer_and_double_requests_are_distinct", {
  x <- cases$minimum;y <- x
  for(i in 1L:3L) y$b[[i]]$request <- s2cv_request(5)
  stopifnot(!identical(enc(x)$data,enc(y)$data))
})
test("duplicate_request_IDs_and_order_remain_exact", {
  stopifnot(identical(cases$mixed$b[[1L]]$request$raw_le,
                      raw_hex("050000000500000009000000")))
})
test("declared_raster_dtype_does_not_coerce_native_vectors", {
  x <- cases$flipped;y <- cases$declared
  stopifnot(identical(x$b,y$b),!identical(enc(x)$data,enc(y)$data))
})
test("all_six_role_storage_pairs_are_encodable", {
  pairs <- unique(unlist(lapply(cases,function(x) vapply(x$b,function(b)
    paste(b$role,b$response$storage_type),""))))
  stopifnot(length(pairs)==6L)
})
test("510_slots_24_batches_and_32_values_per_batch_are_accepted", {
  stopifnot(length(many)==24L,sum(vapply(many,function(b) length(b$response$validity),1L))==510L,
            length(enc(cases$many)$data)<=9140L)
})
test("encoding_leaves_original_input_values_unchanged", {
  before <- serialize(cases,NULL,version=2L,xdr=TRUE)
  invisible(lapply(cases,enc))
  stopifnot(identical(before,serialize(cases,NULL,version=2L,xdr=TRUE)))
})
test("numeric_255_is_finite_not_inferred_NoData", {
  stopifnot(identical(s2cv_values(255L)$validity,"FINITE"))
})
test("all_API_records_and_output_retain_fixed_locks", {
  objs <- list(cases$minimum$h,cases$minimum$b[[1L]],s2cv_values(1L),s2cv_request(1L),enc(cases$minimum))
  for(x in objs) stopifnot(identical(x$safety,.s2cv_safety()),!x$safety$routing_authorized,
                         x$safety$HISTORIC_02F_EFFECTIVE_D8=="NOT_ASSESSED")
})
test("valid_NA_REAL_NAN_tag_alternative_is_preserved_not_authenticated", {
  x <- cases$mixed;y <- x;y$b[[1L]]$response$validity[1L] <- "NAN"
  stopifnot(!identical(enc(x)$data,enc(y)$data),enc(y)$authentication=="NOT_AUTHENTICATED")
})

test("reject_logical_native_vector",expect_stop(s2cv_values(TRUE),"NATIVE_VECTOR"))
test("reject_classed_native_vector",expect_stop(s2cv_values(I(1)),"NATIVE_VECTOR"))
test("reject_named_native_vector",expect_stop(s2cv_values(c(x=1L)),"NATIVE_VECTOR"))
test("reject_empty_native_vector",expect_stop(s2cv_values(numeric()),"NATIVE_VECTOR"))
test("reject_33_native_values",expect_stop(s2cv_values(rep(1L,33L)),"NATIVE_VECTOR"))
test("reject_unknown_storage_type",expect_stop(s2cv_values_raw("Byte","FINITE",as.raw(1L)),"NATIVE_TYPE"))
test("reject_unknown_validity_tag",expect_stop(s2cv_values_raw("INTEGER","NODATA",raw(4L)),"VALIDITY_TAG"))
test("reject_integer_NA_with_finite_tag",expect_stop(s2cv_values_raw("INTEGER","FINITE",raw_hex("00000080")),"TAG_BITS"))
test("reject_finite_double_with_NA_tag",expect_stop(doubles("NA_REAL",pzero),"TAG_BITS"))
test("reject_nan_with_finite_tag",expect_stop(doubles("FINITE",qnan),"TAG_BITS"))
test("reject_infinity_with_wrong_sign_tag",expect_stop(doubles("POS_INF",ninf),"TAG_BITS"))
test("reject_wrong_raw_width",expect_stop(s2cv_values_raw("DOUBLE","FINITE",raw(7L)),"VALUE_WIDTH"))
test("reject_raw_attributes",expect_stop(s2cv_values_raw("INTEGER","FINITE",structure(raw(4L),x=TRUE)),"VALUE_WIDTH"))
test("reject_integer_zero_request",expect_stop(s2cv_request(0L),"REQUEST_CELL"))
test("reject_negative_request",expect_stop(s2cv_request(-1L),"REQUEST_CELL"))
test("reject_fractional_double_request",expect_stop(s2cv_request(1.5),"REQUEST_CELL"))
test("reject_double_NA_request",expect_stop(s2cv_request(NA_real_),"REQUEST_CELL"))
test("reject_double_nan_request",expect_stop(s2cv_request(NaN),"REQUEST_CELL"))
test("reject_double_infinite_request",expect_stop(s2cv_request(Inf),"REQUEST_CELL"))
test("reject_raw_64_integer_requests",expect_stop(s2cv_request_raw("INTEGER",rep(raw_hex("01000000"),64L)),"VALUE_COUNT"))
test("reject_other_grid_cell", {
  x <- cases$minimum;for(i in 1L:3L) x$b[[i]]$request <- s2cv_request(10L)
  expect_stop(enc(x),"REQUEST_CELL")
})
test("reject_non_UUID4_run",expect_stop(s2cv_header(toupper(run),attempt,"tiny",3,3,0,0),"UUID4"))
test("reject_equal_run_attempt",expect_stop(s2cv_header(run,run,"tiny",3,3,0,0),"ATTEMPT_EQUALS_RUN"))
test("reject_grid_outside_bounds",expect_stop(s2cv_header(run,attempt,"tiny",10,3,0,0),"GRID_ROWS"))
test("reject_fractional_origin",expect_stop(s2cv_header(run,attempt,"tiny",3,3,0.5,0),"GRID_ORIGIN"))
test("reject_R_version_trailing_newline",expect_stop(s2cv_header(run,attempt,"tiny",3,3,0,0,"4.6.1\n","fixture"),"R_VERSION"))
test("reject_dtype_declaration_4",expect_stop(head_fixture(declared_dtypes=c(0,4,0)),"DTYPE_DECLARATIONS"))
test("reject_unknown_approval_field", {
  x <- cases$minimum;x$h$approved <- TRUE;expect_stop(enc(x),"RECORD_SCHEMA")
})
test("reject_modified_scientific_lock", {
  x <- cases$minimum;x$h$safety$routing_authorized <- TRUE;expect_stop(enc(x),"RECORD_SCHEMA")
})
test("reject_missing_triplet_batch", {
  x <- cases$minimum;x$b <- x$b[1L:2L];expect_stop(enc(x),"COMPLETE_TRIPLETS")
})
test("reject_zero_batches", {
  x <- cases$minimum;x$b <- list();expect_stop(enc(x),"COMPLETE_TRIPLETS")
})
test("reject_27_batches", {
  x <- cases$minimum;x$b <- rep(x$b,9L);expect_stop(enc(x),"COMPLETE_TRIPLETS")
})
test("reject_named_batch_container", {
  x <- cases$minimum;names(x$b) <- c("a","b","c");expect_stop(enc(x),"COMPLETE_TRIPLETS")
})
test("reject_reordered_role", {
  x <- cases$minimum;x$b[[1L]]$role <- "LAKE_ID";expect_stop(enc(x),"ROLE_SEQUENCE")
})
test("reject_noncontiguous_sequence", {
  x <- cases$minimum;x$b[[1L]]$sequence <- 2L;expect_stop(enc(x),"SEQUENCE")
})
test("reject_substituted_triplet_cell", {
  x <- cases$minimum;x$b[[2L]]$request <- s2cv_request(6L);expect_stop(enc(x),"TRIPLET_REQUEST")
})
test("reject_changed_triplet_request_type", {
  x <- cases$minimum;x$b[[2L]]$request <- s2cv_request(5);expect_stop(enc(x),"TRIPLET_REQUEST")
})
test("reject_truncated_response", {
  x <- cases$minimum;x$b[[1L]]$response$raw_le <- raw(3L);expect_stop(enc(x),"VALUE_WIDTH")
})
test("reject_role_storage_change_between_triplets", {
  x <- cases$minimum;second <- x$b
  for(i in 1L:3L) second[[i]]$sequence <- i+3L
  second[[1L]]$response <- s2cv_values(3)
  x$b <- c(x$b,second);expect_stop(enc(x),"ROLE_STORAGE_CHANGED")
})
test("reject_513_slots_without_truncating_or_extending_limits", {
  x <- cases$many
  for(i in 22L:24L) {
    x$b[[i]]$request <- s2cv_request(rep(1,4L));x$b[[i]]$response <- s2cv_values(rep(0,4L))
  }
  expect_stop(enc(x),"SLOT_LIMIT")
})
test("STOP_error_contains_locked_scientific_status", {
  e <- tryCatch({s2cv_values(TRUE);NULL},s2cv2_stop=function(e)e)
  stopifnot(e$status=="STOP",identical(e$safety,.s2cv_safety()))
})

if(counts["FAIL"]==0L && length(names_seen)>0L) {
  lines <- vapply(names(cases),function(name) paste0("V2_CASE=",name,"|WIRE=",hex(enc(cases[[name]])$data)),"")
  if(sum(nchar(lines,type="bytes"))+length(lines)>50000L) stop("V2_TEST_OUTPUT_LIMIT")
  cat(paste(lines,collapse="\n"),"\n",sep="")
}
cat(sprintf("R_V2_SUMMARY PASS=%d FAIL=%d NOT_RUN=%d R=%s\n",counts[1L],counts[2L],counts[3L],as.character(getRversion())))
if(length(names_seen)==0L || counts["FAIL"]!=0L) quit(status=1L)
