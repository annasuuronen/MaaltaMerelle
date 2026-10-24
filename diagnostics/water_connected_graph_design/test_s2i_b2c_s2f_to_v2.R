# Targeted NEW interoperability tests; no accepted test runner is sourced.
args <- commandArgs(trailingOnly=FALSE)
script <- sub("^--file=","",args[grepl("^--file=",args)])
if(length(script)!=1L) stop("S2C_TEST_SCRIPT")
bootstrap <- Sys.getenv("MM_S2C_BOOTSTRAP",unset="")
if(!nzchar(bootstrap) || file.info(bootstrap)$size>262144L) stop("S2C_BOOTSTRAP_REQUIRED")
source(bootstrap,local=TRUE)
source(file.path(dirname(normalizePath(script)),"s2i_b2c_s2f_to_v2.R"),local=TRUE)
sf <- s2c_dependencies$s2f;cv <- s2c_dependencies$codec
native <- sf$trace_water_connected_candidate_routes
native_before <- serialize(body(native),NULL,version=2L,xdr=TRUE)
counts <- c(PASS=0L,FAIL=0L,NOT_RUN=0L);seen <- character()
test <- function(name,expr) {
  if(name %in% seen) stop("DUPLICATE_TEST")
  seen <<- c(seen,name)
  tryCatch({eval(substitute(expr),parent.frame());counts["PASS"]<<-counts["PASS"]+1L;
    cat("PASS ",name,"\n",sep="")},error=function(e){counts["FAIL"]<<-counts["FAIL"]+1L;
      cat("FAIL ",name,": ",conditionMessage(e),"\n",sep="")})
}
expect_stop <- function(expr,code=NULL) {
  e <- tryCatch({force(expr);NULL},s2c_stop=function(e)e,s2cv2_stop=function(e)e)
  stopifnot(!is.null(e),identical(e$safety,.s2c_safety()))
  if(!is.null(code)) stopifnot(identical(e$reason_code,code))
}
run_id <- "123e4567-e89b-42d3-a456-426614174000"
attempt <- "123e4567-e89b-42d3-a456-426614174001"
export <- function(r,d=s2c_dependencies,...) s2c_export(r,d,run_id,attempt,...)
hex <- function(x) paste(sprintf("%02x",as.integer(x)),collapse="")
from_hex <- function(h) as.raw(strtoi(substring(h,seq.int(1L,nchar(h),2L),seq.int(2L,nchar(h),2L)),16L))
edges <- function(starts,origins=rep(10L,length(starts))) data.frame(spill_group_id=seq_along(starts),
  lake_objectid=origins,source_cell=rep(1L,length(starts)),receiver_cell=starts)
fixtures <- function() {
  p <- rep(0,9L);p[5L] <- 2;w <- rep(NA_real_,9L);w[6L] <- 3
  a <- list(f=sf$s2f_synthetic_fixture(p,w,rep(NA_integer_,9L),3L,3L),
            e=edges(c(5L,5L),c(10L,11L)),steps=4L)
  p <- rep(0,25L);p[c(6L,7L,12L)] <- c(4,8,8);p[17L] <- -0.0
  w <- rep(NA_integer_,25L);w[17L] <- 2L
  l <- rep(NA_real_,25L);l[17L] <- 16777217
  b <- list(f=sf$s2f_synthetic_fixture(p,w,l,5L,5L),e=edges(c(6L,7L),c(10L,11L)),steps=4L)
  p <- rep(0L,9L);p[5L] <- 2L;w <- rep(NA_real_,9L);w[6L] <- 1
  l <- rep(NA_integer_,9L);l[6L] <- 16777217L
  c <- list(f=sf$s2f_synthetic_fixture(p,w,l,3L,3L),e=edges(5L),steps=4L)
  # Establish the originally specified bits before S2F, without relying on signed literals.
  p <- readBin(from_hex(paste0("a20700000000f07f","010000000000f87f",
    "000000000000f07f","000000000000f0ff","0000000000000000","0000000000000080",
    "0000000000000840","000000000000d03f","0000000000006040")),
    "double",n=9L,size=8L,endian="little")
  stopifnot(identical(writeBin(p[5L:6L],raw(),size=8L,endian="little"),
                       from_hex("00000000000000000000000000000080")))
  d <- list(f=sf$s2f_synthetic_fixture(p,rep(NA_real_,9L),rep(NA_integer_,9L),3L,3L),
            e=edges(1L:9L),steps=1L)
  p <- rep(0L,25L);p[c(13L,14L)] <- 2L
  e <- list(f=sf$s2f_synthetic_fixture(p,rep(NA_real_,25L),rep(NA_integer_,25L),5L,5L),
            e=edges(13L),steps=1L)
  list(chain=a,convergence=b,lake=c,special=d,work_limit=e)
}
observed <- list();baselines <- list();delegations <- list();wires <- list()
for(name in names(fixtures())) {
  x <- fixtures()[[name]];calls <- list()
  recorder <- function(raster,cells) {
    answer <- sf$s2f_synthetic_values(raster,cells)
    calls[[length(calls)+1L]] <<- list(role=raster$role,cells=cells,values=answer)
    answer
  }
  baseline <- native(x$e,x$f$handles$POINTER,x$f$handles$WATER_CLASS,x$f$handles$LAKE_ID,
                     x$f$nrow,x$f$ncol,recorder,x$steps)
  r <- sf$s2f_observe_02f(native,x$f,x$e,max_steps=x$steps,max_calls=24L,max_values=512L)
  observed[[name]] <- r;baselines[[name]] <- baseline;delegations[[name]] <- calls
  test(paste0(name,"_unchanged_four_native_result_components"), {
    stopifnot(r$observation_status=="COMPLETE",sf$s2f_check_transcript(r)$status=="COMPLETE")
    for(part in c("routes","edge_routes","group_summary","qa"))
      stopifnot(identical(serialize(baseline[[part]],NULL,version=2L,xdr=TRUE),
                          serialize(r$result[[part]],NULL,version=2L,xdr=TRUE)))
  })
  test(paste0(name,"_independent_delegation_matches_every_call"), {
    stopifnot(length(calls)==r$observed_calls)
    for(i in seq_along(calls)) {
      a <- calls[[i]];b <- r$calls[[i]]
      stopifnot(identical(a$role,b$role),identical(a$cells,b$requested_cells),
        identical(sf$s2f_encode_values(a$values),b$response_encoding))
    }
  })
  test(paste0(name,"_export_preserves_report_and_results"), {
    before <- r$canonical_bytes;out <- export(r)
    stopifnot(identical(before,r$canonical_bytes),sf$s2f_check_transcript(r)$status=="COMPLETE",
              identical(out$safety,.s2c_safety()),!out$safety$routing_authorized)
    wires[[name]] <- out$data
    for(part in names(baseline)) stopifnot(identical(baseline[[part]],r$result[[part]]))
  })
}
test("duplicate_requests_and_exact_role_order", {
  r <- observed$chain
  stopifnot(identical(vapply(r$calls,`[[`,"","role"),rep(c("WATER_CLASS","LAKE_ID","POINTER"),2L)),
    identical(lapply(r$calls,`[[`,"requested_cells"),c(rep(list(c(5L,5L)),3L),rep(list(c(6L,6L)),3L))))
})
test("convergence_keeps_duplicated_downstream_observations", {
  stopifnot(identical(lapply(observed$convergence$calls,`[[`,"requested_cells"),
    c(rep(list(c(6L,7L)),3L),rep(list(c(12L,12L)),3L),rep(list(c(17L,17L)),3L))))
})
test("large_lake_ID_preserved_without_Float32", {
  stopifnot(observed$lake$result$routes$terminal_lake_objectid==16777217L,
    identical(observed$lake$calls[[5L]]$returned_values,16777217L))
})
test("work_limit_remains_censored_without_added_calls", {
  stopifnot(observed$work_limit$result$routes$route_status=="STEP_LIMIT",
    observed$work_limit$observed_calls==3L,
    observed$work_limit$result$routes$terminal_cell==14L)
})
test("special_values_retained_in_actual_pointer_callback", {
  v <- observed$special$calls[[3L]]$response_encoding
  stopifnot(identical(v$validity,c("NA_REAL","NAN","POS_INF","NEG_INF",rep("FINITE",5L))),
    identical(v$little_endian_bits[9L:16L],from_hex("010000000000f87f")),
    identical(v$little_endian_bits[41L:48L],from_hex("0000000000000080")))
})
test("signed_zero_fixture_bits_are_established_before_observation", {
  p <- fixtures()$special$f$source_snapshot$POINTER
  stopifnot(identical(writeBin(p[5L:6L],raw(),size=8L,endian="little"),
    from_hex("00000000000000000000000000000080")))
})
test("all_six_role_native_types_are_observed", {
  pairs <- unique(unlist(lapply(observed,function(r) vapply(r$calls,function(x)
    paste(x$role,x$returned_type),""))))
  stopifnot(length(pairs)==6L)
})

# Data-only adversarial reports; no pinned function or private callback is changed.
clone_report <- function(r,edit,reseal=FALSE) {
  values <- mget(ls(r,all.names=TRUE),envir=r,inherits=FALSE)
  values <- edit(values)
  if(reseal) {
    payload <- c("encoding_version","R_version","R_platform","observation_status","reason_code",
      "source_snapshot","grid","candidate_edges","max_steps","attempted_calls","observed_calls",
      "requested_value_slots","returned_value_slots","calls","result")
    return(sf$.s2f_seal(values[payload]))
  }
  out <- list2env(values,parent=emptyenv());class(out) <- "s2f_report"
  lockEnvironment(out,bindings=TRUE);out
}
bad <- function(edit,code,reseal=FALSE) expect_stop(export(clone_report(observed$chain,edit,reseal)),code)
test("reordered_callbacks_STOP",bad(function(v){v$calls[c(1L,2L)]<-v$calls[c(2L,1L)];v},
                                    "S2F_VALIDATION_CALL_SEQUENCE_MISMATCH"))
test("wrong_role_STOP",bad(function(v){v$calls[[1L]]$role<-"POINTER";v},
                            "S2F_VALIDATION_ROLE_SEQUENCE_MISMATCH"))
test("changed_request_cells_STOP",bad(function(v){v$calls[[2L]]$requested_cells<-c(5L,6L);v},
                                       "S2F_VALIDATION_QUERY_ENCODING_MISMATCH"))
test("modified_returned_values_STOP",bad(function(v){v$calls[[3L]]$returned_values<-c(4,4);v},
                                          "S2F_VALIDATION_RESPONSE_ENCODING_MISMATCH"))
test("modified_raw_response_bytes_STOP",bad(function(v){v$calls[[3L]]$response_encoding$little_endian_bits[1L]<-as.raw(1L);v},
                                            "S2F_VALIDATION_RESPONSE_ENCODING_MISMATCH"))
test("truncated_observations_STOP",bad(function(v){v$calls<-v$calls[-6L];v},"REPORT_BUDGET_OR_COUNTS"))
test("truncated_returned_vector_STOP",bad(function(v){v$calls[[3L]]$returned_values<-2;v},"CALL_BUDGET_OR_LENGTH"))
test("modified_output_result_STOP",bad(function(v){v$result$routes$route_steps[1L]<-0L;v},
                                        "S2F_VALIDATION_TRANSCRIPT_SEAL_MISMATCH"))
test("missing_seal_STOP",bad(function(v){v$canonical_bytes<-raw();v},
                              "S2F_VALIDATION_TRANSCRIPT_SEAL_MISMATCH"))
test("counter_disagreement_STOP",bad(function(v){v$requested_value_slots<-1L;v},"REPORT_BUDGET_OR_COUNTS"))
test("overbudget_steps_STOP",bad(function(v){v$max_steps<-9L;v},"REPORT_BUDGET_OR_COUNTS"))
test("runtime_substitution_resealed_still_STOP",bad(function(v){v$R_version<-"another-runtime";v},"RUNTIME_CONTEXT",TRUE))
test("snapshot_source_substitution_resealed_still_STOP",bad(function(v){
  v$source_snapshot$values$POINTER[5L]<-4;v},"SOURCE_SNAPSHOT_MISMATCH",TRUE))
test("science_lock_substitution_resealed_still_STOP", {
  r <- clone_report(observed$chain,function(v)v,TRUE)
  # Deliberate ordinary-R tampering is data-only and is rejected by the original checker.
  unlockBinding("routing_authorized",r);r$routing_authorized<-TRUE;lockBinding("routing_authorized",r)
  expect_stop(export(r),"S2F_VALIDATION_TRANSCRIPT_SEAL_MISMATCH")
})
test("public_callback_source_substitution_yields_unexportable_STOP", {
  x <- fixtures()$chain
  wrong <- function(raster,cells) {
    if(raster$role=="POINTER") return(rep(4,length(cells)))
    sf$s2f_synthetic_values(raster,cells)
  }
  r <- sf$s2f_observe_02f(native,x$f,x$e,max_steps=4L,cell_values=wrong,max_calls=24L,max_values=512L)
  stopifnot(r$observation_status=="STOP",r$reason_code=="CALLBACK_RESULT_MISMATCH")
  expect_stop(export(r),"OBSERVATION_INCOMPLETE")
})
test("partial_callback_failure_not_exported", {
  x <- fixtures()$chain
  fail <- function(raster,cells) {
    if(raster$role=="POINTER") stop("synthetic interruption")
    sf$s2f_synthetic_values(raster,cells)
  }
  r <- sf$s2f_observe_02f(native,x$f,x$e,max_steps=4L,cell_values=fail,max_calls=24L,max_values=512L)
  stopifnot(r$observation_status=="STOP",r$returned_value_slots<r$requested_value_slots)
  expect_stop(export(r),"OBSERVATION_INCOMPLETE")
})
test("zero_observations_have_no_fabricated_triplet", {
  x <- fixtures()$chain;r <- sf$s2f_observe_02f(native,x$f,x$e[FALSE,],max_steps=4L)
  stopifnot(r$observation_status=="COMPLETE",r$observed_calls==0L)
  expect_stop(export(r),"REPORT_BUDGET_OR_COUNTS")
})
test("wrong_dependency_pin_STOP", {
  d <- new.env(parent=emptyenv());d$s2f<-sf;d$codec<-cv;d$pins<-.s2c_pins();d$pins$S2F<-paste(rep("0",40L),collapse="")
  class(d)<-"s2c_dependencies";lockEnvironment(d,bindings=TRUE)
  expect_stop(export(observed$chain,d),"DEPENDENCY_PIN")
})
test("unlocked_report_STOP", {
  r <- list2env(mget(ls(observed$chain),observed$chain,inherits=FALSE),parent=emptyenv());class(r)<-"s2f_report"
  expect_stop(export(r),"REPORT_TYPE")
})
test("native_function_body_and_pinned_namespaces_unchanged", {
  stopifnot(identical(native_before,serialize(body(native),NULL,version=2L,xdr=TRUE)),
    environmentIsLocked(sf),environmentIsLocked(cv),bindingIsLocked("trace_water_connected_candidate_routes",sf))
})
if(counts["FAIL"]==0L && length(wires)==5L) {
  lines <- vapply(names(wires),function(name) paste0("S2C_CASE=",name,"|WIRE=",hex(wires[[name]])),"")
  if(sum(nchar(lines,type="bytes"))+length(lines)>50000L) stop("S2C_TEST_OUTPUT_BUDGET")
  cat(paste(lines,collapse="\n"),"\n",sep="")
  cat("S2C_SOURCE_PIN=",s2c_dependencies$pins$S2F,"|V2_PIN=",s2c_dependencies$pins$V2,"\n",sep="")
}
cat(sprintf("R_S2C_SUMMARY PASS=%d FAIL=%d NOT_RUN=%d R=%s PLATFORM=%s\n",counts[1L],counts[2L],counts[3L],as.character(getRversion()),R.version$platform))
if(!length(seen) || counts["FAIL"]!=0L || length(wires)!=5L) quit(status=1L)
