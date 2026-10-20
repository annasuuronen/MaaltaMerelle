# Synthetic-only fixtures: an explicit successor graph is the independent truth.
# Encoding pointers is fixture construction, never a replacement routing core.
generate_scale_fixture <- function(n, scenario) {
  stopifnot(length(n) == 1L, n %in% c(100L, 1000L, 10000L, 100000L),
            scenario %in% c("fan", "long", "mixed", "random"))
  nr <- as.integer(n / 10); nc <- 10L
  id <- seq_len(n); row <- (id - 1L) %/% nc + 1L; col <- (id - 1L) %% nc + 1L
  next_row <- row; next_col <- col + 1L
  valid <- rep(TRUE, n); water <- lake <- rep(NA_real_, n); terminal <- rep("", n)
  if (scenario == "fan") {
    # Multiple upstream branches enter the next row's common eastward chain.
    odd <- row %% 2 == 1
    next_row[odd] <- row[odd] + 1L; next_col[odd] <- col[odd]
  } else if (scenario == "long") {
    next_col[row %% 2 == 0] <- col[row %% 2 == 0] - 1L
    bend <- (row %% 2 == 1 & col == nc) | (row %% 2 == 0 & col == 1L)
    next_row[bend] <- row[bend] + 1L; next_col[bend] <- col[bend]
  } else if (scenario == "mixed") {
    terminal[row %% 7 == 1 & col == 3] <- "D8_ZERO"
    terminal[row %% 7 == 2 & col == 4] <- "POINTER_NA"
    terminal[row %% 7 == 3 & col == 6] <- "INVALID_POINTER"
    valid[row %% 7 == 4 & col == 8] <- FALSE
    next_col[row %% 7 == 5 & col == 5] <- 4L
    water[row %% 7 == 6 & col == 7] <- 4
    for (w in 1:3) water[row %% 7 == 0 & col == c(2L, 5L, 8L)[w]] <- w
    lake[water %in% 1] <- 9001
  } else if (scenario == "random") {
    had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
    if (had_seed) saved <- get(".Random.seed", envir = .GlobalEnv)
    on.exit(if (had_seed) assign(".Random.seed", saved, envir = .GlobalEnv) else
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv))
    set.seed(20261020)
    choices <- sample.int(8L, n, replace = TRUE)
    next_row <- row + c(-1L, 0L, 1L, 1L, 1L, 0L, -1L, -1L)[choices]
    next_col <- col + c(1L, 1L, 1L, 0L, -1L, -1L, -1L, 0L)[choices]
    kinds <- sample.int(100L, n, replace = TRUE)
    valid[kinds <= 3] <- FALSE
    terminal[kinds == 4] <- "D8_ZERO"; terminal[kinds == 5] <- "POINTER_NA"
    terminal[kinds == 6] <- "INVALID_POINTER"
    for (w in 1:3) water[kinds == 6 + w] <- w
    water[kinds == 10] <- 4
    lake[water %in% 1] <- 9001
  }
  dr <- next_row - row; dc <- next_col - col
  # Independent fixture encoder; oracle consumes successors, not this mapping.
  direction_key <- paste(dr, dc, sep = ":")
  lookup <- c("-1:1" = 1, "0:1" = 2, "1:1" = 4, "1:0" = 8,
              "1:-1" = 16, "0:-1" = 32, "-1:-1" = 64, "-1:0" = 128)
  pointer <- unname(lookup[direction_key]); stopifnot(!anyNA(pointer))
  pointer[terminal == "D8_ZERO"] <- 0
  pointer[terminal == "POINTER_NA"] <- NA_real_
  pointer[terminal == "INVALID_POINTER"] <- 3
  outside <- next_row < 1L | next_row > nr | next_col < 1L | next_col > nc
  successor <- ifelse(outside, 0L, (next_row - 1L) * nc + next_col)
  kind <- rep("LAND", n); kind[water %in% 1:3] <- "WATER"
  kind[!is.na(water) & !water %in% 1:3] <- "INVALID_WATER_CLASS"; kind[!valid] <- "NO_DATA"
  grid <- list(grid_id = "SYNTHETIC-SCALE", nrow = nr, ncol = nc,
    row_offset = 100L, col_offset = 200L, xmin = 200000, ymax = 6900000,
    resolution_m = 2, crs = "EPSG:3067")
  provenance <- list(run_id = paste("synthetic", scenario, n, sep = ":"), code_revision = "synthetic-generator-v1",
    pointer_source = "generated-pointer", water_source = "generated-water", lake_id_source = "generated-lake-id",
    validity_source = "generated-domain", lake_id_namespace = "SYNTHETIC_ONLY")
  structure(list(n = n, scenario = scenario, grid = grid, provenance = provenance,
    row = row, col = col, kind = kind, terminal = terminal, successor = successor,
    pointer = matrix(pointer, nr, nc, byrow = TRUE), water = matrix(water, nr, nc, byrow = TRUE),
    lake = matrix(lake, nr, nc, byrow = TRUE), valid = matrix(valid, nr, nc, byrow = TRUE)),
    class = "synthetic_d8_fixture")
}

# Test-local copies differ only at numeric allocation-limit literals. The
# production functions, D8 decoder, driver and real I/O bounds remain unchanged.
synthetic_scale_methods <- function(max_cells, inventory_function = analyse_land_network_topology) {
  stopifnot(max_cells %in% c(100L, 121L, 1000L, 10000L, 100000L))
  clone <- function(fn, expected_replacements) {
    count <- 0L
    replace <- function(expr) {
      if (is.numeric(expr) && length(expr) == 1L && !is.na(expr) && expr == 121) {
        count <<- count + 1L
        return(if (is.integer(expr)) as.integer(max_cells) else as.numeric(max_cells))
      }
      if (is.call(expr)) for (i in seq_along(expr)) {
        if (!identical(expr[[i]], quote(expr = ))) expr[i] <- list(replace(expr[[i]]))
      }
      expr
    }
    body(fn) <- replace(body(fn))
    if (count != expected_replacements) stop("SYNTHETIC_ADAPTER_SOURCE_CONTRACT_CHANGED")
    fn
  }
  list(build = clone(build_land_d8_network, 2L),
       analyse = clone(inventory_function, 1L),
       select = clone(select_land_network_cases, 1L))
}
