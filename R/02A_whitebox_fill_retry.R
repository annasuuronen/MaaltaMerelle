whitebox_fill_depressions_with_retry <- function(
  output,
  run_fill,
  label,
  attempts = 2L
) {
  if (!is.function(run_fill)) stop("run_fill must be a function.")
  if (!is.character(output) || length(output) != 1L ||
      is.na(output) || !nzchar(output)) {
    stop("output must be one non-empty path.")
  }
  if (!is.character(label) || length(label) != 1L ||
      is.na(label) || !nzchar(label)) {
    stop("label must be one non-empty string.")
  }
  if (!is.numeric(attempts) || length(attempts) != 1L ||
      is.na(attempts) || !is.finite(attempts) ||
      attempts < 1L || attempts != as.integer(attempts)) {
    stop("attempts must be a positive integer.")
  }

  previous_max_procs <- Sys.getenv(
    "R_WHITEBOX_MAX_PROCS",
    unset = NA_character_
  )
  on.exit({
    if (is.na(previous_max_procs)) {
      Sys.unsetenv("R_WHITEBOX_MAX_PROCS")
    } else {
      Sys.setenv(R_WHITEBOX_MAX_PROCS = previous_max_procs)
    }
  })
  Sys.setenv(R_WHITEBOX_MAX_PROCS = "1")

  for (attempt in seq_len(as.integer(attempts))) {
    if (file.exists(output) && !file.remove(output)) {
      stop(label, " could not remove the existing output: ", output)
    }

    if (attempt > 1L) {
      message(label, " produced no output; retrying once.")
    }
    run_fill()

    output_info <- file.info(output)
    if (!is.na(output_info$size) && output_info$size > 0) {
      return(invisible(output))
    }
  }

  stop(
    label,
    " failed to create a non-empty output after ",
    as.integer(attempts),
    " attempts: ",
    output
  )
}
