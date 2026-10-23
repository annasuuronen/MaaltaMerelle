# S2F: local synthetic callback observations, never source authentication.
# Source this module and the existing 02F function explicitly; no auto-sourcing/IO.

.s2f_locks <- function() list(
  EFFECTIVE_CONSUMER_TRANSCRIPT = "OBSERVED_SYNTHETIC",
  INDEPENDENT_WITNESS = "NOT_IMPLEMENTED", SOURCE_AUTHENTICATION = "NOT_ASSESSED",
  historical_02f_status = "STOP", NATIONAL = "LOCKED", MODERATE = "REVIEW_REQUIRED",
  hydrological_validation = "NOT_ASSESSED", channel_interpretation = "NOT_ASSESSED",
  routing_authorized = FALSE
)

.s2f_stop <- function(code) {
  stop(structure(c(list(message = code, call = NULL, code = code), .s2f_locks()),
                 class = c("s2f_stop", "error", "condition")))
}
.s2f_need <- function(ok, code) if (!isTRUE(ok)) .s2f_stop(code)
.s2f_copy <- function(x) unserialize(serialize(x, NULL, version = 2L, xdr = TRUE))
.s2f_locked <- function(fields, class_name) {
  e <- list2env(fields, parent = emptyenv())
  class(e) <- class_name
  lockEnvironment(e, bindings = TRUE)
  e
}
.s2f_integer <- function(x, lo, hi) {
  is.numeric(x) && length(x) == 1L && is.null(attributes(x)) &&
    is.finite(x) && x >= lo && x <= hi && x == floor(x)
}
.s2f_vector <- function(x, maximum = 81L) {
  typeof(x) %in% c("integer", "double") && is.null(attributes(x)) && length(x) <= maximum
}

# Each vector is homogeneous; storage_type applies to every scalar. Raw bytes
# preserve signed zero, integer IDs, NA/NaN and the runtime's actual NaN payloads.
s2f_encode_values <- function(x) {
  .s2f_need(.s2f_vector(x, 81L), "UNSUPPORTED_VALUE_VECTOR")
  tags <- rep("FINITE", length(x))
  tags[is.nan(x)] <- "NAN"
  tags[is.na(x) & !is.nan(x)] <- if (typeof(x) == "integer") "NA_INTEGER" else "NA_REAL"
  tags[is.infinite(x) & x > 0] <- "POS_INF"
  tags[is.infinite(x) & x < 0] <- "NEG_INF"
  list(storage_type = typeof(x), length = length(x), validity = tags,
       little_endian_bits = writeBin(x, raw(), size = if (typeof(x) == "integer") 4L else 8L,
                                     endian = "little"))
}

s2f_synthetic_fixture <- function(pointer, water_class, lake_id, nrow, ncol,
                                  nominal_name = "tiny", data_kind = "SYNTHETIC_IN_MEMORY") {
  .s2f_need(identical(data_kind, "SYNTHETIC_IN_MEMORY"), "UNAPPROVED_SOURCE_KIND")
  .s2f_need(.s2f_integer(nrow, 1, 9) && .s2f_integer(ncol, 1, 9), "GRID_LIMIT")
  .s2f_need(is.character(nominal_name) && length(nominal_name) == 1L && !is.na(nominal_name) &&
              grepl("^[A-Za-z][A-Za-z0-9_-]{0,39}$", nominal_name), "INVALID_SOURCE_LABEL")
  values <- list(WATER_CLASS = water_class, LAKE_ID = lake_id, POINTER = pointer)
  .s2f_need(all(vapply(values, function(x) .s2f_vector(x) && length(x) == nrow * ncol,
                       logical(1))), "SYNTHETIC_VECTOR_REQUIRED")
  values <- .s2f_copy(values)
  handles <- lapply(names(values), function(role) .s2f_locked(
    list(role = role, scope = "SYNTHETIC_IN_MEMORY", nominal_name = nominal_name,
         values = values[[role]]), "s2f_handle"))
  names(handles) <- names(values)
  .s2f_locked(list(scope = "SYNTHETIC_IN_MEMORY", nominal_name = nominal_name,
                   nrow = as.integer(nrow), ncol = as.integer(ncol), handles = handles,
                   source_snapshot = values), "s2f_fixture")
}

# Supplied reference callback for these synthetic handles. No coercion or IO.
s2f_synthetic_values <- function(raster, cells) raster$values[cells]

.s2f_validate_fixture <- function(f) {
  .s2f_need(is.environment(f) && identical(class(f), "s2f_fixture") && environmentIsLocked(f),
              "UNAPPROVED_FIXTURE")
  .s2f_need(identical(f$scope, "SYNTHETIC_IN_MEMORY") &&
              .s2f_integer(f$nrow, 1, 9) && .s2f_integer(f$ncol, 1, 9), "UNAPPROVED_FIXTURE")
  .s2f_need(identical(names(f$handles), c("WATER_CLASS", "LAKE_ID", "POINTER")) &&
              identical(names(f$source_snapshot), names(f$handles)), "HANDLE_BINDING_MISMATCH")
  for (role in names(f$handles)) {
    h <- f$handles[[role]]
    .s2f_need(is.environment(h) && identical(class(h), "s2f_handle") && environmentIsLocked(h) &&
                identical(h$role, role) && identical(h$scope, f$scope) &&
                identical(h$nominal_name, f$nominal_name), "HANDLE_BINDING_MISMATCH")
    .s2f_need(.s2f_vector(h$values) && length(h$values) == f$nrow * f$ncol &&
                identical(s2f_encode_values(h$values), s2f_encode_values(f$source_snapshot[[role]])),
                "SOURCE_SUBSTITUTION")
  }
  .s2f_need(!identical(f$handles[[1L]], f$handles[[2L]]) &&
              !identical(f$handles[[1L]], f$handles[[3L]]) &&
              !identical(f$handles[[2L]], f$handles[[3L]]), "HANDLE_BINDING_MISMATCH")
  invisible(TRUE)
}

.s2f_result_shape <- function(x) {
  is.list(x) && identical(names(x), c("routes", "edge_routes", "group_summary", "qa")) &&
    all(vapply(x, function(d) identical(class(d), "data.frame") && nrow(d) <= 32L && ncol(d) <= 16L &&
      all(vapply(d, function(v) is.null(attributes(v)) &&
                   typeof(v) %in% c("integer", "double", "logical", "character") &&
                   length(v) <= 32L && (!is.character(v) || all(!is.na(v) & nchar(v, type = "bytes") <= 256L)),
                 logical(1))), logical(1)))
}

.s2f_seal <- function(payload) {
  payload <- c(payload, .s2f_locks())
  bytes <- serialize(payload, NULL, version = 2L, xdr = TRUE)
  .s2f_need(length(bytes) <= 1048576L, "TRANSCRIPT_BYTE_LIMIT")
  # This is an exact local byte identifier, NOT a SHA256 or an attestation.
  .s2f_locked(c(payload, list(canonical_bytes = bytes,
                            LOCAL_TRANSCRIPT_ENCODING = "LOCAL_R_SERIALIZE_V2_WITH_LE_VALUE_BITS",
                            LOCAL_TRANSCRIPT_ID_HEX = paste(format(bytes), collapse = ""),
                            transcript_authentication = "NOT_AUTHENTICATED")), "s2f_report")
}

s2f_observe_02f <- function(trace_fn, fixture, candidate_edges, max_steps = 16L,
                            cell_values = s2f_synthetic_values,
                            max_calls = 192L, max_values = 4096L, max_seconds = 2) {
  state <- new.env(parent = emptyenv())
  state$calls <- list(); state$attempts <- 0L; state$values <- 0L; state$sealed <- FALSE
  state$triplet_cells <- NULL
  snapshot <- NULL; edges <- NULL; grid <- NULL; steps <- NULL
  start <- proc.time()[["elapsed"]]
  check_time <- function() .s2f_need(proc.time()[["elapsed"]] - start <= max_seconds, "TIME_LIMIT")
  invoke <- function() {
    .s2f_need(.s2f_integer(max_calls, 1, 192) && .s2f_integer(max_values, 1, 4096) &&
                is.numeric(max_seconds) && length(max_seconds) == 1L &&
                is.finite(max_seconds) && max_seconds > 0 && max_seconds <= 10, "INVALID_LIMIT")
    .s2f_validate_fixture(fixture)
    snapshot <<- .s2f_copy(list(nominal_name = fixture$nominal_name, values = fixture$source_snapshot))
    grid <<- c(nrow = fixture$nrow, ncol = fixture$ncol)
    .s2f_need(is.function(trace_fn) && is.function(cell_values), "CALLBACK_REQUIRED")
    .s2f_need(.s2f_integer(max_steps, 1, 64), "STEP_LIMIT_CONFIG")
    steps <<- as.integer(max_steps)
    .s2f_need(identical(class(candidate_edges), "data.frame") &&
                identical(names(candidate_edges), c("spill_group_id", "lake_objectid", "source_cell", "receiver_cell")) &&
                nrow(candidate_edges) <= 32L && all(vapply(candidate_edges, function(v)
                  .s2f_vector(v, 32L) && all(is.finite(v) & v > 0 & v <= 2147483647 & v == floor(v)),
                  logical(1))), "CANDIDATE_SCHEMA_OR_LIMIT")
    edges <<- .s2f_copy(candidate_edges)
    observed_cell_values <- function(raster, cells) {
      .s2f_need(!state$sealed, "OBSERVER_FINALIZED")
      state$attempts <- state$attempts + 1L
      check_time()
      .s2f_need(state$attempts <= max_calls, "CALL_LIMIT")
      .s2f_validate_fixture(fixture)
      matches <- which(vapply(fixture$handles, function(h) identical(h, raster), logical(1)))
      .s2f_need(length(matches) == 1L, "UNBOUND_HANDLE")
      role <- names(fixture$handles)[matches]
      expected_role <- c("WATER_CLASS", "LAKE_ID", "POINTER")[(state$attempts - 1L) %% 3L + 1L]
      .s2f_need(identical(role, expected_role), "ROLE_SEQUENCE_MISMATCH")
      .s2f_need(.s2f_vector(cells, 32L) && length(cells) >= 1L &&
                  all(is.finite(cells) & cells >= 1 & cells <= prod(grid) & cells == floor(cells)),
                  "QUERY_SCOPE_OR_LIMIT")
      request <- s2f_encode_values(cells)
      if (expected_role == "WATER_CLASS") state$triplet_cells <- request
      .s2f_need(identical(request, state$triplet_cells), "TRIPLET_QUERY_MISMATCH")
      .s2f_need(state$values + length(cells) <= max_values, "VALUE_LIMIT")
      state$values <- state$values + length(cells)
      i <- length(state$calls) + 1L
      state$calls[[i]] <- list(sequence = i, role = role, requested_cells = .s2f_copy(cells),
                               request_encoding = request, returned_values = NULL,
                               response_encoding = NULL, returned_type = NULL, return_state = "CALLBACK_ERROR")
      answer <- tryCatch(cell_values(raster, cells), error = function(e) .s2f_stop("CALLBACK_ERROR"))
      state$calls[[i]]$returned_type <- typeof(answer)
      state$calls[[i]]$return_state <- "UNSUPPORTED_RESPONSE"
      .s2f_need(.s2f_vector(answer, 32L), "UNSUPPORTED_CALLBACK_RESPONSE")
      state$calls[[i]]$returned_values <- .s2f_copy(answer)
      state$calls[[i]]$response_encoding <- s2f_encode_values(answer)
      state$calls[[i]]$return_state <- "RETURNED"
      check_time()
      .s2f_need(length(answer) == length(cells), "RESPONSE_LENGTH_MISMATCH")
      .s2f_validate_fixture(fixture)
      expected <- snapshot$values[[role]][cells]
      .s2f_need(identical(s2f_encode_values(answer), s2f_encode_values(expected)), "CALLBACK_RESULT_MISMATCH")
      answer # Exactly the supplied callback's vector; no coercion/repair/fallback.
    }
    result <- trace_fn(candidate_edges = candidate_edges, ptr_land_water = fixture$handles$POINTER,
                       water_class = fixture$handles$WATER_CLASS, lake_id = fixture$handles$LAKE_ID,
                       nrow_raster = fixture$nrow, ncol_raster = fixture$ncol,
                       cell_values = observed_cell_values, max_steps = max_steps)
    check_time()
    .s2f_validate_fixture(fixture)
    .s2f_need(.s2f_result_shape(result), "TRACE_RESULT_SHAPE")
    .s2f_need(nrow(result$edge_routes) == nrow(edges) &&
                nrow(result$routes) == nrow(unique(edges[c("receiver_cell", "lake_objectid")])) &&
                is.logical(result$qa$pass) && all(result$qa$pass), "TRACE_RESULT_SHAPE")
    .s2f_need(state$attempts == length(state$calls) && state$attempts %% 3L == 0L,
                "OBSERVATION_INCOMPLETE")
    .s2f_need(length(state$calls) > 0L || nrow(result$routes) == 0L ||
                all(result$routes$route_status == "START_OUTSIDE_RASTER"), "OBSERVATION_INCOMPLETE")
    result
  }
  reason <- "NONE"
  result <- tryCatch(invoke(), s2f_stop = function(e) { reason <<- e$code; NULL },
                     error = function(e) { reason <<- "TRACE_ERROR"; NULL })
  state$sealed <- TRUE
  payload <- list(encoding_version = "s2f.synthetic-consumer.v1", R_version = R.version.string,
                  R_platform = R.version$platform, observation_status = if (reason == "NONE") "COMPLETE" else "STOP",
                  reason_code = reason, source_snapshot = snapshot, grid = grid,
                  candidate_edges = edges, max_steps = steps, attempted_calls = state$attempts,
                  observed_calls = length(state$calls), requested_value_slots = state$values,
                  returned_value_slots = sum(vapply(state$calls, function(x) length(x$returned_values), integer(1))),
                  calls = .s2f_copy(state$calls), result = .s2f_copy(result))
  .s2f_seal(payload)
}

# Local tamper comparison with the finalized in-memory reference. No witness or
# replay/reconstruction of 02F routing is implemented here.
s2f_check_transcript <- function(report, calls = report$calls, result = report$result) {
  verdict <- function(code) .s2f_locked(c(list(status = if (code == "NONE") "COMPLETE" else "STOP",
                                               reason_code = code), .s2f_locks()), "s2f_check")
  tryCatch({
    .s2f_need(is.environment(report) && identical(class(report), "s2f_report") &&
                environmentIsLocked(report), "UNSEALED_REPORT")
    .s2f_need(identical(report$observation_status, "COMPLETE"), "OBSERVATION_INCOMPLETE")
    .s2f_need(is.list(calls) && length(calls) == report$observed_calls, "OBSERVATION_INCOMPLETE")
    for (i in seq_along(calls)) {
      x <- calls[[i]]
      .s2f_need(is.list(x) && identical(names(x), names(report$calls[[i]])), "LOG_SCHEMA")
      .s2f_need(identical(x$sequence, i), "CALL_SEQUENCE_MISMATCH")
      .s2f_need(identical(x$role, c("WATER_CLASS", "LAKE_ID", "POINTER")[(i - 1L) %% 3L + 1L]),
                  "ROLE_SEQUENCE_MISMATCH")
      .s2f_need(identical(x$request_encoding, s2f_encode_values(x$requested_cells)), "QUERY_ENCODING_MISMATCH")
      .s2f_need(identical(x$return_state, "RETURNED") &&
                  length(x$returned_values) == length(x$requested_cells), "RESPONSE_LENGTH_MISMATCH")
      .s2f_need(identical(x$returned_type, typeof(x$returned_values)) &&
                  identical(x$response_encoding, s2f_encode_values(x$returned_values)), "RESPONSE_ENCODING_MISMATCH")
    }
    .s2f_need(identical(calls, report$calls), "TRANSCRIPT_MISMATCH")
    .s2f_need(.s2f_result_shape(result), "TRACE_RESULT_SHAPE")
    .s2f_need(identical(serialize(result, NULL, version = 2L, xdr = TRUE),
                        serialize(report$result, NULL, version = 2L, xdr = TRUE)), "TRACE_RESULT_MISMATCH")
    fields <- setdiff(ls(report, all.names = TRUE), c("canonical_bytes", "LOCAL_TRANSCRIPT_ENCODING",
                                                   "LOCAL_TRANSCRIPT_ID_HEX", "transcript_authentication"))
    # Recreate original payload order (environment enumeration is alphabetical).
    payload_names <- c("encoding_version", "R_version", "R_platform", "observation_status", "reason_code",
                       "source_snapshot", "grid", "candidate_edges", "max_steps", "attempted_calls",
                       "observed_calls", "requested_value_slots", "returned_value_slots", "calls", "result", names(.s2f_locks()))
    .s2f_need(setequal(fields, payload_names), "REPORT_SCHEMA")
    payload <- mget(payload_names, envir = report, inherits = FALSE)
    .s2f_need(identical(serialize(payload, NULL, version = 2L, xdr = TRUE), report$canonical_bytes),
                "TRANSCRIPT_SEAL_MISMATCH")
    .s2f_need(identical(report$LOCAL_TRANSCRIPT_ID_HEX, paste(format(report$canonical_bytes), collapse = "")) &&
                identical(report$transcript_authentication, "NOT_AUTHENTICATED"), "LOCAL_IDENTIFIER_MISMATCH")
    verdict("NONE")
  }, s2f_stop = function(e) verdict(e$code), error = function(e) verdict("LOG_SCHEMA"))
}
