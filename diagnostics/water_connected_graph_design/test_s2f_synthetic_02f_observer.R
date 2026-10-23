# Fresh Base-R process from repo root; only these two repository code sources.
source("R/02F_water_connected_route_diagnostics.R")
source("diagnostics/water_connected_graph_design/s2f_synthetic_02f_observer.R")

native <- trace_water_connected_candidate_routes
native_body_before <- serialize(body(native), NULL, version = 2L, xdr = TRUE)
counts <- c(PASS = 0L, FAIL = 0L, NOT_RUN = 0L)
seen_names <- character()
test <- function(name, code) {
  if (name %in% seen_names) stop("duplicate test name")
  seen_names <<- c(seen_names, name)
  tryCatch({
    eval(substitute(code), parent.frame())
    counts["PASS"] <<- counts["PASS"] + 1L
    cat("PASS ", name, "\n", sep = "")
  }, error = function(e) {
    counts["FAIL"] <<- counts["FAIL"] + 1L
    cat("FAIL ", name, ": ", conditionMessage(e), "\n", sep = "")
  })
}
expect_code <- function(expr, code) {
  actual <- tryCatch({ eval(substitute(expr), parent.frame()); "NO_ERROR" },
                     s2f_stop = function(e) e$code)
  stopifnot(identical(actual, code))
}
expect_error <- function(expr) {
  actual <- tryCatch({ eval(substitute(expr), parent.frame()); FALSE }, error = function(e) TRUE)
  stopifnot(actual)
}
edges <- function(starts = 13L, origins = rep(10L, length(starts))) {
  data.frame(spill_group_id = seq_along(starts), lake_objectid = origins,
             source_cell = rep(1L, length(starts)), receiver_cell = starts)
}
chain <- function() {
  p <- rep(0, 25L); p[c(13L, 14L)] <- 2
  w <- rep(NA_real_, 25L); w[15L] <- 3
  s2f_synthetic_fixture(p, w, rep(NA_integer_, 25L), 5L, 5L)
}
single <- function(pointer = 0, water = NA_real_, lake = NA_integer_) {
  p <- if (typeof(pointer) == "integer") rep(0L, 9L) else rep(0, 9L)
  p[5L] <- pointer
  w <- rep(NA_real_, 9L); w[5L] <- water
  l <- if (typeof(lake) == "integer") rep(NA_integer_, 9L) else rep(NA_real_, 9L)
  l[5L] <- lake
  s2f_synthetic_fixture(p, w, l, 3L, 3L)
}
run <- function(f = chain(), e = edges(), steps = 16L, callback = s2f_synthetic_values, fn = native, ...) {
  s2f_observe_02f(fn, f, e, steps, cell_values = callback, ...)
}
# Independent delegation recorder: observes the supplied original callback both
# with and without the S2F wrapper; no alternate routing algorithm is written.
pair <- function(f = chain(), e = edges(), steps = 16L) {
  delegated <- list()
  callback <- function(raster, cells) {
    answer <- raster$values[cells]
    delegated[[length(delegated) + 1L]] <<- list(role = raster$role, cells = cells, values = answer)
    answer
  }
  reference <- native(e, f$handles$POINTER, f$handles$WATER_CLASS, f$handles$LAKE_ID,
                      f$nrow, f$ncol, callback, steps)
  original_calls <- delegated; delegated <- list()
  observed <- run(f, e, steps, callback)
  stopifnot(observed$observation_status == "COMPLETE",
            identical(serialize(reference, NULL, version = 2L, xdr = TRUE),
                      serialize(observed$result, NULL, version = 2L, xdr = TRUE)),
            identical(delegated, original_calls), observed$observed_calls == length(delegated))
  for (i in seq_along(delegated)) {
    x <- observed$calls[[i]]; d <- delegated[[i]]
    stopifnot(identical(x$role, d$role), identical(x$requested_cells, d$cells),
              identical(x$returned_values, d$values), identical(x$returned_type, typeof(d$values)),
              identical(x$request_encoding, s2f_encode_values(d$cells)),
              identical(x$response_encoding, s2f_encode_values(d$values)))
  }
  stopifnot(s2f_check_transcript(observed)$status == "COMPLETE")
  list(observed = observed, reference = reference)
}

# Route behavior and lossless values.
test("full_routes_edges_groups_and_QA_exact_parity", {
  x <- pair(); stopifnot(x$observed$result$routes$route_steps == 2L,
                         x$observed$result$routes$route_status == "REACHES_RIVER_LINE")
})
test("all_actual_requests_in_class_lake_pointer_order", {
  x <- pair()$observed
  stopifnot(x$observed_calls == 9L,
            identical(vapply(x$calls, `[[`, "", "role"), rep(c("WATER_CLASS", "LAKE_ID", "POINTER"), 3L)),
            identical(lapply(x$calls, `[[`, "requested_cells"), rep(list(13L, 14L, 15L), each = 3L)))
})
test("water_cell_pointer_still_observed", {
  x <- pair()$observed
  stopifnot(x$calls[[9L]]$role == "POINTER", identical(x$calls[[9L]]$requested_cells, 15L),
            identical(x$calls[[9L]]$returned_values, 0))
})
test("finite_zero_is_not_missing", {
  x <- pair(single(), edges(5L))$observed
  stopifnot(x$result$routes$route_status == "D8_ZERO_INTERIOR",
            x$calls[[3L]]$response_encoding$validity == "FINITE", x$calls[[3L]]$returned_values == 0)
})
test("NA_real_pointer_is_recorded_exactly", {
  x <- pair(single(NA_real_), edges(5L))$observed
  stopifnot(x$result$routes$route_status == "D8_POINTER_NA", x$calls[[3L]]$response_encoding$validity == "NA_REAL")
})
test("NA_integer_pointer_preserves_storage_type", {
  x <- pair(single(NA_integer_), edges(5L))$observed
  stopifnot(x$calls[[3L]]$returned_type == "integer", x$calls[[3L]]$response_encoding$validity == "NA_INTEGER")
})
test("NaN_differs_from_NA_despite_same_route_status", {
  a <- pair(single(NA_real_), edges(5L))$observed; b <- pair(single(NaN), edges(5L))$observed
  stopifnot(identical(a$result, b$result), b$calls[[3L]]$response_encoding$validity == "NAN",
            !identical(a$canonical_bytes, b$canonical_bytes))
})
test("signed_zero_bits_retained", {
  a <- pair(single(0), edges(5L))$observed; b <- pair(single(-0), edges(5L))$observed
  stopifnot(identical(a$result, b$result),
            !identical(a$calls[[3L]]$response_encoding$little_endian_bits,
                       b$calls[[3L]]$response_encoding$little_endian_bits))
})
for (value in c(Inf, -Inf, 3)) {
  test(paste0("invalid_pointer_", value), {
    x <- pair(single(value), edges(5L))$observed
    stopifnot(x$result$routes$route_status == "D8_POINTER_INVALID",
              identical(x$calls[[3L]]$returned_values, value))
  })
}
# All eight Whitebox directions from the center of a 3x3 row-major grid.
for (i in seq_len(8L)) {
  code <- c(1, 2, 4, 8, 16, 32, 64, 128)[i]
  target <- c(3L, 6L, 9L, 8L, 7L, 4L, 1L, 2L)[i]
  test(paste0("whitebox_direction_", code), {
    p <- rep(0, 9L); p[5L] <- code; w <- rep(NA_real_, 9L); w[target] <- 2
    x <- pair(s2f_synthetic_fixture(p, w, rep(NA_integer_, 9L), 3L, 3L), edges(5L))$observed
    stopifnot(x$result$routes$terminal_cell == target, x$result$routes$route_steps == 1L,
              identical(x$calls[[4L]]$requested_cells, target))
  })
}
test("water_precedence_over_invalid_pointer", {
  x <- pair(single(3, 2), edges(5L))$observed
  stopifnot(x$result$routes$route_status == "REACHES_RIVER_AREA", x$result$routes$route_steps == 0L,
            identical(x$calls[[3L]]$returned_values, 3))
})
test("origin_lake_return_preserved", {
  x <- pair(single(0, 1, 10L), edges(5L))$observed
  stopifnot(x$result$routes$route_status == "RETURNS_TO_ORIGIN_LAKE")
})
test("integer_lake_id_above_float32_exact_range", {
  x <- pair(single(0, 1, 16777217L), edges(5L))$observed
  stopifnot(x$calls[[2L]]$returned_type == "integer", identical(x$calls[[2L]]$returned_values, 16777217L),
            x$result$routes$terminal_lake_objectid == 16777217L)
})
test("double_lake_id_not_silently_changed_to_integer_in_callback", {
  x <- pair(single(0, 1, 16777217), edges(5L))$observed
  stopifnot(x$calls[[2L]]$returned_type == "double", identical(x$calls[[2L]]$returned_values, 16777217))
})
test("lake_id_missing_remains_missing", {
  x <- pair(single(0, 1), edges(5L))$observed
  stopifnot(x$result$routes$route_status == "LAKE_ID_MISSING")
})
test("raster_edge_zero_is_not_coastline", {
  f <- single(); x <- pair(f, edges(1L))$observed
  stopifnot(x$result$routes$route_status == "D8_ZERO_AT_RASTER_EDGE", !x$routing_authorized)
})
test("domain_exit_without_inventing_receiver", {
  p <- rep(0, 9L); p[1L] <- 128
  x <- pair(s2f_synthetic_fixture(p, rep(NA_real_, 9L), rep(NA_integer_, 9L), 3L, 3L), edges(1L))$observed
  stopifnot(x$result$routes$route_status == "D8_DOMAIN_EXIT", x$result$routes$route_steps == 0L)
})
test("cycle_exact_parity", {
  p <- rep(0, 9L); p[c(5L, 6L)] <- c(2, 32)
  x <- pair(s2f_synthetic_fixture(p, rep(NA_real_, 9L), rep(NA_integer_, 9L), 3L, 3L), edges(5L))$observed
  stopifnot(x$result$routes$route_status == "D8_CYCLE", x$result$routes$route_steps == 1L)
})
test("step_limit_tail_not_queried", {
  x <- pair(chain(), edges(), 1L)$observed
  stopifnot(x$result$routes$route_status == "STEP_LIMIT", x$result$routes$terminal_cell == 14L,
            x$observed_calls == 3L, all(vapply(x$calls, function(c) identical(c$requested_cells, 13L), logical(1))))
})
test("duplicate_starts_and_route_order_preserved", {
  x <- pair(chain(), edges(c(13L, 7L, 13L), c(10L, 20L, 10L)))$observed
  stopifnot(nrow(x$result$routes) == 2L, nrow(x$result$edge_routes) == 3L,
            identical(x$calls[[1L]]$requested_cells, c(13L, 7L)))
})
test("simultaneous_converging_routes_keep_duplicate_cell_queries", {
  p <- rep(0, 25L); p[c(8L, 12L, 13L)] <- c(8, 2, 2)
  w <- rep(NA_real_, 25L); w[14L] <- 2
  x <- pair(s2f_synthetic_fixture(p, w, rep(NA_integer_, 25L), 5L, 5L), edges(c(8L, 12L)))$observed
  stopifnot(identical(x$calls[[4L]]$requested_cells, c(13L, 13L)),
            x$requested_value_slots == 18L, x$returned_value_slots == 18L)
})
test("empty_candidates_vacuous_zero_reads_not_fabricated_reads", {
  x <- pair(chain(), edges(integer()))$observed
  stopifnot(x$observed_calls == 0L, nrow(x$result$routes) == 0L)
})
test("outside_start_has_no_queried_cell_claim", {
  x <- pair(single(), edges(10L))$observed
  stopifnot(x$observed_calls == 0L, x$result$routes$route_status == "START_OUTSIDE_RASTER")
})

# Source and callback tampering; no route correction or fallback is permitted.
test("unapproved_real_source_kind_rejected", {
  expect_code(s2f_synthetic_fixture(rep(0, 9), rep(NA_real_, 9), rep(NA_integer_, 9), 3L, 3L,
                                     data_kind = "REAL_CSC"), "UNAPPROVED_SOURCE_KIND")
})
test("file_path_is_not_a_synthetic_vector", {
  expect_code(s2f_synthetic_fixture("/scratch/project_2004707/a.tif", rep(NA_real_, 9),
                                     rep(NA_integer_, 9), 3L, 3L), "SYNTHETIC_VECTOR_REQUIRED")
})
test("unapproved_fixture_fails_before_callback", {
  x <- run("/scratch/project_2004707/a.tif")
  stopifnot(x$reason_code == "UNAPPROVED_FIXTURE", x$observed_calls == 0L)
})
test("same_nominal_name_different_handle_is_not_same_pointer", {
  f <- chain(); clone <- chain()
  fn <- function(...) { a <- list(...); a$ptr_land_water <- clone$handles$POINTER; do.call(native, a) }
  x <- run(f, fn = fn)
  stopifnot(x$reason_code == "UNBOUND_HANDLE", x$observed_calls == 2L)
})
test("swapped_parameters_detected_by_handle_identity", {
  fn <- function(...) { a <- list(...); a$water_class <- a$ptr_land_water; do.call(native, a) }
  x <- run(fn = fn)
  stopifnot(x$reason_code == "ROLE_SEQUENCE_MISMATCH", x$observed_calls == 0L)
})
test("falsely_declared_role_is_rejected", {
  f <- chain(); h <- f$handles$POINTER
  unlockBinding("role", h); h$role <- "WATER_CLASS"; lockBinding("role", h)
  stopifnot(run(f)$reason_code == "HANDLE_BINDING_MISMATCH")
})
test("same_source_name_modified_values_rejected", {
  f <- chain(); h <- f$handles$POINTER
  unlockBinding("values", h); h$values[13L] <- 0; lockBinding("values", h)
  stopifnot(run(f)$reason_code == "SOURCE_SUBSTITUTION")
})
test("callback_modified_values_logged_then_stop", {
  cb <- function(raster, cells) if (raster$role == "POINTER") rep(0, length(cells)) else raster$values[cells]
  x <- run(callback = cb)
  stopifnot(x$reason_code == "CALLBACK_RESULT_MISMATCH", is.null(x$result),
            identical(x$calls[[3L]]$returned_values, 0), x$observation_status == "STOP")
})
test("source_mutation_during_callback_is_not_accepted", {
  f <- chain()
  cb <- function(r, cells) {
    answer <- r$values[cells]
    h <- f$handles$POINTER
    unlockBinding("values", h); h$values[13L] <- 0; lockBinding("values", h)
    answer
  }
  x <- run(f, callback = cb)
  stopifnot(x$reason_code == "SOURCE_SUBSTITUTION", x$observed_calls == 1L, is.null(x$result))
})
test("callback_integer_to_double_coercion_not_hidden", {
  cb <- function(raster, cells) if (raster$role == "LAKE_ID") as.numeric(raster$values[cells]) else raster$values[cells]
  x <- run(callback = cb)
  stopifnot(x$reason_code == "CALLBACK_RESULT_MISMATCH", x$calls[[2L]]$returned_type == "double")
})
test("incomplete_response_logged_then_stop", {
  cb <- function(raster, cells) numeric()
  x <- run(callback = cb)
  stopifnot(x$reason_code == "RESPONSE_LENGTH_MISMATCH", x$calls[[1L]]$response_encoding$length == 0L)
})
test("callback_crash_preserves_partial_request", {
  cb <- function(raster, cells) { if (raster$role == "POINTER") stop("intentional"); raster$values[cells] }
  x <- run(callback = cb)
  stopifnot(x$reason_code == "CALLBACK_ERROR", x$observed_calls == 3L,
            x$calls[[3L]]$return_state == "CALLBACK_ERROR", is.null(x$calls[[3L]]$response_encoding),
            x$requested_value_slots == 3L, x$returned_value_slots == 2L,
            s2f_check_transcript(x)$reason_code == "OBSERVATION_INCOMPLETE")
})
test("unsupported_callback_response_never_serializes_arbitrary_object", {
  x <- run(callback = function(raster, cells) new.env())
  stopifnot(x$reason_code == "UNSUPPORTED_CALLBACK_RESPONSE", x$calls[[1L]]$returned_type == "environment",
            x$calls[[1L]]$return_state == "UNSUPPORTED_RESPONSE")
})
test("triplet_query_response_scope_mismatch", {
  fn <- function(...) {
    a <- list(...); observed <- a$cell_values
    a$cell_values <- function(r, cells) observed(r, if (r$role == "LAKE_ID") cells + 1L else cells)
    do.call(native, a)
  }
  x <- run(fn = fn)
  stopifnot(x$reason_code == "TRIPLET_QUERY_MISMATCH", x$observed_calls == 1L)
})
test("equal_query_ids_with_changed_scalar_type_are_not_silently_coerced", {
  fn <- function(...) {
    a <- list(...); observed <- a$cell_values
    a$cell_values <- function(r, cells) observed(r, if (r$role == "LAKE_ID") as.numeric(cells) else cells)
    do.call(native, a)
  }
  stopifnot(run(fn = fn)$reason_code == "TRIPLET_QUERY_MISMATCH")
})
test("interrupted_consumer_has_incomplete_observation", {
  fn <- function(...) { a <- list(...); a$cell_values(a$water_class, 13L); stop("intentional trace crash") }
  x <- run(fn = fn)
  stopifnot(x$reason_code == "TRACE_ERROR", x$observed_calls == 1L, x$observation_status == "STOP")
})
test("partial_triplet_cannot_be_finalized_as_complete", {
  expected <- pair()$reference
  fn <- function(...) { a <- list(...); a$cell_values(a$water_class, 13L); expected }
  stopifnot(run(fn = fn)$reason_code == "OBSERVATION_INCOMPLETE")
})
test("no_observations_cannot_substitute_nonempty_route_result", {
  expected <- pair()$reference
  stopifnot(run(fn = function(...) expected)$reason_code == "OBSERVATION_INCOMPLETE")
})

# Finalized ordinary-R immutability and local tamper evidence.
test("finalized_bindings_and_nested_values_are_locked", {
  x <- pair()$observed
  expect_error(x$observation_status <- "VALIDATED")
  expect_error(x$calls[[1L]]$role <- "POINTER")
  stopifnot(s2f_check_transcript(x)$status == "COMPLETE")
})
test("captured_callback_cannot_append_after_finalization", {
  saved <- new.env()
  fn <- function(...) { a <- list(...); saved$callback <- a$cell_values; do.call(native, a) }
  f <- chain(); x <- run(f, fn = fn); before <- x$canonical_bytes
  expect_code(saved$callback(f$handles$WATER_CLASS, 13L), "OBSERVER_FINALIZED")
  stopifnot(identical(x$canonical_bytes, before), s2f_check_transcript(x)$status == "COMPLETE")
})
test("removed_log_entry_rejected", {
  x <- pair()$observed
  stopifnot(s2f_check_transcript(x, calls = x$calls[-length(x$calls)])$reason_code == "OBSERVATION_INCOMPLETE")
})
test("reordered_log_entries_rejected", {
  x <- pair()$observed; calls <- x$calls; calls[c(1L, 2L)] <- calls[c(2L, 1L)]
  stopifnot(s2f_check_transcript(x, calls)$reason_code == "CALL_SEQUENCE_MISMATCH")
})
test("changed_role_rejected_even_after_renumbering", {
  x <- pair()$observed; calls <- x$calls; calls[[1L]]$role <- "LAKE_ID"
  stopifnot(s2f_check_transcript(x, calls)$reason_code == "ROLE_SEQUENCE_MISMATCH")
})
test("changed_query_without_encoding_rejected", {
  x <- pair()$observed; calls <- x$calls; calls[[1L]]$requested_cells <- 14L
  stopifnot(s2f_check_transcript(x, calls)$reason_code == "QUERY_ENCODING_MISMATCH")
})
test("changed_response_without_encoding_rejected", {
  x <- pair()$observed; calls <- x$calls; calls[[3L]]$returned_values <- 0
  stopifnot(s2f_check_transcript(x, calls)$reason_code == "RESPONSE_ENCODING_MISMATCH")
})
test("consistent_substituted_response_rejected_against_local_seal", {
  x <- pair()$observed; calls <- x$calls; calls[[3L]]$returned_values <- 0
  calls[[3L]]$response_encoding <- s2f_encode_values(0)
  stopifnot(s2f_check_transcript(x, calls)$reason_code == "TRANSCRIPT_MISMATCH")
})
test("query_response_length_mismatch_rejected", {
  x <- pair()$observed; calls <- x$calls; calls[[3L]]$returned_values <- numeric()
  stopifnot(s2f_check_transcript(x, calls)$reason_code == "RESPONSE_LENGTH_MISMATCH")
})
test("altered_trace_result_rejected", {
  x <- pair()$observed; result <- x$result; result$routes$route_steps[1L] <- 99L
  stopifnot(s2f_check_transcript(x, result = result)$reason_code == "TRACE_RESULT_MISMATCH")
})
test("unchanged_same_runtime_transcript_deterministic", {
  a <- run(); b <- run()
  stopifnot(identical(a$canonical_bytes, b$canonical_bytes), identical(a$LOCAL_TRANSCRIPT_ID_HEX, b$LOCAL_TRANSCRIPT_ID_HEX),
            a$R_version == R.version.string, a$transcript_authentication == "NOT_AUTHENTICATED")
})
test("lossless_binary64_value_encoding_roundtrip", {
  values <- c(0, -0, NA_real_, NaN, Inf, -Inf, 16777217)
  encoded <- s2f_encode_values(values)
  decoded <- readBin(encoded$little_endian_bits, double(), n = length(values), size = 8L, endian = "little")
  stopifnot(identical(encoded$validity, c("FINITE", "FINITE", "NA_REAL", "NAN", "POS_INF", "NEG_INF", "FINITE")),
            length(encoded$little_endian_bits) == 8L * length(values),
            identical(s2f_encode_values(decoded), encoded))
})
test("changed_sealed_bytes_are_detected", {
  x <- pair()$observed; unlockBinding("canonical_bytes", x)
  x$canonical_bytes[1L] <- as.raw(0); lockBinding("canonical_bytes", x)
  stopifnot(s2f_check_transcript(x)$reason_code == "TRANSCRIPT_SEAL_MISMATCH")
})
test("changed_local_byte_identifier_is_detected", {
  x <- pair()$observed; unlockBinding("LOCAL_TRANSCRIPT_ID_HEX", x)
  x$LOCAL_TRANSCRIPT_ID_HEX <- "forged"; lockBinding("LOCAL_TRANSCRIPT_ID_HEX", x)
  stopifnot(s2f_check_transcript(x)$reason_code == "LOCAL_IDENTIFIER_MISMATCH")
})
test("source_name_alone_does_not_determine_transcript", {
  a <- single(0); b <- single(NA_real_)
  x <- run(a, edges(5L)); y <- run(b, edges(5L))
  stopifnot(a$nominal_name == b$nominal_name, !identical(x$canonical_bytes, y$canonical_bytes))
})

# Small, explicit resource gates.
test("call_count_limit_stops_before_extra_delegation", {
  x <- run(max_calls = 2L)
  stopifnot(x$reason_code == "CALL_LIMIT", x$observed_calls == 2L, x$attempted_calls == 3L)
})
test("value_count_limit_stops_before_extra_delegation", {
  x <- run(max_values = 1L)
  stopifnot(x$reason_code == "VALUE_LIMIT", x$observed_calls == 1L)
})
test("elapsed_budget_is_checked_after_callback", {
  cb <- function(r, cells) { Sys.sleep(0.05); s2f_synthetic_values(r, cells) }
  stopifnot(run(callback = cb, max_seconds = 0.02)$reason_code == "TIME_LIMIT")
})
test("fixture_grid_limit", {
  expect_code(s2f_synthetic_fixture(rep(0, 100), rep(NA_real_, 100), rep(NA_integer_, 100), 10L, 10L), "GRID_LIMIT")
})
test("candidate_count_limit", {
  stopifnot(run(e = edges(rep(13L, 33L)))$reason_code == "CANDIDATE_SCHEMA_OR_LIMIT")
})
test("query_vector_limit", {
  fn <- function(...) { a <- list(...); a$cell_values(a$water_class, rep(13L, 33L)) }
  stopifnot(run(fn = fn)$reason_code == "QUERY_SCOPE_OR_LIMIT")
})
test("out_of_grid_query_rejected", {
  fn <- function(...) { a <- list(...); a$cell_values(a$water_class, 0L) }
  stopifnot(run(fn = fn)$reason_code == "QUERY_SCOPE_OR_LIMIT")
})
test("invalid_resource_limit_rejected", {
  stopifnot(run(max_seconds = Inf)$reason_code == "INVALID_LIMIT", run(max_calls = 0L)$reason_code == "INVALID_LIMIT")
})
test("all_results_keep_scientific_locks_and_historical_stop", {
  for (x in list(run(), run(max_calls = 1L), run("REAL_CSC"))) {
    for (key in names(.s2f_locks())) stopifnot(identical(x[[key]], .s2f_locks()[[key]]))
    y <- s2f_check_transcript(x)
    for (key in names(.s2f_locks())) stopifnot(identical(y[[key]], .s2f_locks()[[key]]))
  }
})
test("original_02f_function_body_unchanged", {
  stopifnot(identical(native_body_before, serialize(body(native), NULL, version = 2L, xdr = TRUE)))
})

cat(sprintf("SUMMARY PASS=%d FAIL=%d NOT_RUN=%d NAMED_TESTS=%d R=%s\n",
            counts["PASS"], counts["FAIL"], counts["NOT_RUN"], length(seen_names), getRversion()))
cat("EFFECTIVE_CONSUMER_TRANSCRIPT=OBSERVED_SYNTHETIC INDEPENDENT_WITNESS=NOT_IMPLEMENTED SOURCE_AUTHENTICATION=NOT_ASSESSED historical_02f_status=STOP\n")
cat("NATIONAL=LOCKED MODERATE=REVIEW_REQUIRED hydrological_validation=NOT_ASSESSED channel_interpretation=NOT_ASSESSED routing_authorized=false\n")
if (length(seen_names) == 0L || counts["FAIL"] > 0L) quit(status = 1L)
