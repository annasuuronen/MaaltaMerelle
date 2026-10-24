# Pure read-only adapter for complete, local synthetic S2F reports.
# Dependencies are supplied by the detached pinned source loader; no I/O here.
.s2c_safety <- function() list(
  NATIONAL="LOCKED",MODERATE="REVIEW_REQUIRED",hydrological_validation="NOT_ASSESSED",
  channel_interpretation="NOT_ASSESSED",routing_authorized=FALSE,outlet_selection="UNASSIGNED",
  HISTORIC_02F_EFFECTIVE_D8="NOT_ASSESSED",SOURCE_AUTHENTICATION="NOT_ASSESSED",
  INDEPENDENT_WITNESS="NOT_IMPLEMENTED")
.s2c_stop <- function(code) stop(structure(list(message=paste0("S2C_STOP:",code),call=NULL,
  reason_code=code,status="STOP",safety=.s2c_safety()),class=c("s2c_stop","error","condition")))
.s2c_need <- function(ok,code) if(!isTRUE(ok)) .s2c_stop(code)
.s2c_int <- function(x,lo,hi) is.numeric(x) && length(x)==1L && is.null(attributes(x)) &&
  is.finite(x) && x>=lo && x<=hi && x==floor(x)
.s2c_vector <- function(x,limit) typeof(x) %in% c("integer","double") &&
  is.null(attributes(x)) && length(x)<=limit
.s2c_plain_list <- function(x) is.list(x) && identical(class(x),"list")
.s2c_pins <- function() list(S2F="477c5b13d5714d618c9c9de88f5f80290b53d994",
                            V2="8d94ec33ce3aeeb20626b6665ae81594934087ce")
.s2c_dependencies <- function(d) {
  .s2c_need(is.environment(d) && identical(class(d),"s2c_dependencies") &&
    environmentIsLocked(d) && setequal(ls(d,all.names=TRUE),c("s2f","codec","pins")),"DEPENDENCIES")
  .s2c_need(!any(vapply(ls(d,all.names=TRUE),bindingIsActive,logical(1),env=d)),"DEPENDENCIES")
  .s2c_need(identical(d$pins,.s2c_pins()) && is.environment(d$s2f) &&
    is.environment(d$codec) && environmentIsLocked(d$s2f) && environmentIsLocked(d$codec),
    "DEPENDENCY_PIN")
  .s2c_need(all(vapply(c("s2f_check_transcript","s2f_encode_values"),function(n)
    exists(n,d$s2f,inherits=FALSE) && is.function(get(n,d$s2f,inherits=FALSE)),logical(1))),"DEPENDENCIES")
  invisible(TRUE)
}

s2c_export <- function(report,dependencies,run_id,attempt_id,grid_id="tiny",x_origin=0L,y_origin=0L) {
  start <- proc.time()[["elapsed"]]
  .s2c_dependencies(dependencies)
  sf <- dependencies$s2f; cv <- dependencies$codec
  .s2c_need(is.environment(report) && identical(class(report),"s2f_report") &&
    environmentIsLocked(report),"REPORT_TYPE")
  fields <- ls(report,all.names=TRUE)
  .s2c_need(length(fields)<=32L && !any(vapply(fields,bindingIsActive,logical(1),env=report)),"REPORT_FIELDS")
  required <- c("canonical_bytes","observation_status","calls","attempted_calls","observed_calls",
    "requested_value_slots","returned_value_slots","source_snapshot","grid","max_steps")
  .s2c_need(all(required %in% fields),"REPORT_FIELDS")
  .s2c_need(is.raw(report$canonical_bytes) && length(report$canonical_bytes)<=1048576L,
             "REPORT_BYTE_BUDGET")
  .s2c_need(identical(report$observation_status,"COMPLETE"),"OBSERVATION_INCOMPLETE")
  .s2c_need(.s2c_plain_list(report$calls) && length(report$calls)>=3L &&
    length(report$calls)<=24L && length(report$calls)%%3L==0L &&
    .s2c_int(report$observed_calls,3,24) && .s2c_int(report$attempted_calls,3,24) &&
    report$observed_calls==length(report$calls) && report$attempted_calls==report$observed_calls &&
    .s2c_int(report$requested_value_slots,1,512) && .s2c_int(report$returned_value_slots,1,512) &&
    report$requested_value_slots==report$returned_value_slots && .s2c_int(report$max_steps,1,8),
    "REPORT_BUDGET_OR_COUNTS")
  snap <- report$source_snapshot
  .s2c_need(.s2c_plain_list(snap) && identical(names(snap),c("nominal_name","values")) &&
    .s2c_plain_list(snap$values) && identical(names(snap$values),c("WATER_CLASS","LAKE_ID","POINTER")) &&
    is.character(snap$nominal_name) && length(snap$nominal_name)==1L && !is.na(snap$nominal_name) &&
    nchar(snap$nominal_name,type="bytes")<=40L,"SOURCE_SNAPSHOT")
  .s2c_need(is.integer(report$grid) && identical(names(report$grid),c("nrow","ncol")) &&
    length(report$grid)==2L && all(report$grid>=1L & report$grid<=9L),"GRID")
  cells <- prod(report$grid)
  .s2c_need(all(vapply(snap$values,function(x) .s2c_vector(x,81L) && length(x)==cells,logical(1))),
             "SOURCE_SNAPSHOT")
  for(x in report$calls) .s2c_need(.s2c_plain_list(x) &&
    .s2c_vector(x$requested_cells,32L) && length(x$requested_cells)>=1L &&
    .s2c_vector(x$returned_values,32L) && length(x$returned_values)==length(x$requested_cells),
    "CALL_BUDGET_OR_LENGTH")

  # Mandatory original public validation, before any v2 construction/export.
  check <- sf$s2f_check_transcript(report)
  .s2c_need(identical(check$status,"COMPLETE"),paste0("S2F_VALIDATION_",check$reason_code))
  expected_locks <- list(NATIONAL="LOCKED",MODERATE="REVIEW_REQUIRED",
    hydrological_validation="NOT_ASSESSED",channel_interpretation="NOT_ASSESSED",
    routing_authorized=FALSE,SOURCE_AUTHENTICATION="NOT_ASSESSED",INDEPENDENT_WITNESS="NOT_IMPLEMENTED",
    historical_02f_status="STOP",EFFECTIVE_CONSUMER_TRANSCRIPT="OBSERVED_SYNTHETIC")
  .s2c_need(all(vapply(names(expected_locks),function(n)
    identical(get(n,report,inherits=FALSE),expected_locks[[n]]),logical(1))),"SCIENTIFIC_LOCKS")
  .s2c_need(identical(report$R_version,R.version.string) && identical(report$R_platform,R.version$platform),
             "RUNTIME_CONTEXT")
  .s2c_need(identical(report$transcript_authentication,"NOT_AUTHENTICATED") &&
    identical(report$LOCAL_TRANSCRIPT_ENCODING,"LOCAL_R_SERIALIZE_V2_WITH_LE_VALUE_BITS"),"REPORT_ENCODING")
  h <- cv$s2cv_header(run_id,attempt_id,grid_id,report$grid[[1L]],report$grid[[2L]],x_origin,y_origin)
  batches <- vector("list",length(report$calls));slots <- 0L
  for(i in seq_along(report$calls)) {
    x <- report$calls[[i]]
    .s2c_need(all(is.finite(x$requested_cells) & x$requested_cells>=1 &
      x$requested_cells<=cells & x$requested_cells==floor(x$requested_cells)),"REQUEST_SCOPE")
    expected <- sf$s2f_encode_values(snap$values[[x$role]][x$requested_cells])
    .s2c_need(identical(expected,x$response_encoding),"SOURCE_SNAPSHOT_MISMATCH")
    # Copy captured raw encodings; never coerce actual values or call a reader.
    q <- x$request_encoding;v <- x$response_encoding
    r <- cv$s2cv_request_raw(toupper(q$storage_type),q$little_endian_bits)
    values <- cv$s2cv_values_raw(toupper(v$storage_type),v$validity,v$little_endian_bits)
    batches[[i]] <- cv$s2cv_batch(x$sequence,x$role,r,values)
    slots <- slots+length(x$requested_cells)
  }
  .s2c_need(slots==report$requested_value_slots && slots==report$returned_value_slots,"SLOT_COUNTS")
  wire <- cv$s2cv_encode(h,batches)
  .s2c_need(proc.time()[["elapsed"]]-start<=2,"EXPORT_TIME_LIMIT")
  result <- list2env(list(data=wire$data,disposition="CHECKED_SYNTHETIC_REPORT_EXPORT",
    authentication="NOT_AUTHENTICATED",observed_calls=length(batches),scalar_slots=slots,
    safety=.s2c_safety()),parent=emptyenv())
  class(result) <- "s2c_export"
  lockEnvironment(result,bindings=TRUE)
  result
}
