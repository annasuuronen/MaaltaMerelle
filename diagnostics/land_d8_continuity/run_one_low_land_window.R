#!/usr/bin/env Rscript
# Read-only one-window LOW 02B->land continuity evidence. PR #17 dependencies.
# Usage: Rscript --vanilla diagnostics/land_d8_continuity/run_one_low_land_window.R BASELINE_DIR
# Reads one <=64 MiB 02B CSV, one small manifest, 11x11 x four raster samples.
# No changed DEM, no Whitebox, no full-raster scan, no output files.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Usage: Rscript run_one_low_land_window.R BASELINE_DIR")
suppressPackageStartupMessages(library(terra))
a <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(a) != 1L) stop("Rscript --file= required")
here <- dirname(normalizePath(sub("^--file=", "", a)))
source(file.path(here, "..", "low_d8_scope", "lake_1847_focus_core.R"), local = FALSE)
source(file.path(here, "..", "land_first_water", "first_water_contact.R"), local = FALSE)
source(file.path(here, "trace_land_d8_route.R"), local = FALSE)
base <- normalizePath(args[[1L]], mustWork = TRUE)
required_file <- function(p, max_bytes = Inf) {
  if (!file.exists(p) || dir.exists(p) || nzchar(Sys.readlink(p)))
    stop("MISSING_OR_LINKED: ", p)
  n <- file.info(p)$size
  if (!is.finite(n) || n > max_bytes) stop("FILE_TOO_LARGE_OR_UNKNOWN: ", p)
  normalizePath(p, mustWork = TRUE)
}
man_path <- required_file(file.path(dirname(base), "01_inputs", "01_input_manifest.csv"), 65536)
man <- read.csv(man_path, stringsAsFactors = FALSE)
if (!all(c("item", "value") %in% names(man)) || anyDuplicated(man$item))
  stop("BAD_MANIFEST_SCHEMA")
find_source <- function(item) {
  x <- as.character(man$value[man$item == item])
  if (length(x) != 1L || is.na(x) || !nzchar(x))
    stop("MISSING_MANIFEST_KEY: ", item)
  required_file(x)
}
files <- list(
  pointer = required_file(file.path(base, "d8_pointer_land_water_FLT8S.tif")),
  water = find_source("water_class_raster"),
  lake = find_source("lake_id_raster"),
  land = required_file(file.path(base, "routing_surface_land_water_FLT8S.tif"))
)
csv <- required_file(file.path(base, "02B_land_to_first_water_entries.csv"), 64 * 1024^2)
rasters <- lapply(files, terra::rast)
if (any(vapply(rasters, terra::nlyr, integer(1)) != 1L) ||
    any(!vapply(rasters[-1L], function(r)
      terra::compareGeom(rasters$pointer, r, stopOnError = FALSE), logical(1))) ||
    !isTRUE(terra::same.crs(rasters$pointer, "EPSG:3067")) ||
    any(abs(terra::res(rasters$pointer) - c(2, 2)) > 1e-9))
  stop("GRID_CRS_OR_RESOLUTION_MISMATCH")
nr <- terra::nrow(rasters$pointer)
nc <- terra::ncol(rasters$pointer)
if (nr < 11L || nc < 11L || nr * as.double(nc) > .Machine$integer.max)
  stop("UNSUPPORTED_GRID")
e <- read.csv(csv, stringsAsFactors = FALSE)
need <- c("source_cell", "source_x", "source_y", "d8_code", "receiver_cell",
          "receiver_x", "receiver_y", "water_class", "lake_objectid")
if (!all(need %in% names(e)) || !nrow(e)) stop("BAD_OR_EMPTY_02B")
valid_codes <- c(1L, 2L, 4L, 8L, 16L, 32L, 64L, 128L)
sr <- (e$source_cell - 1) %/% nc + 1
sc <- (e$source_cell - 1) %% nc + 1
eligible <- which(is.finite(e$source_cell) & is.finite(e$receiver_cell) &
  e$source_cell == floor(e$source_cell) & e$receiver_cell == floor(e$receiver_cell) &
  sr >= 6 & sr <= nr - 5 & sc >= 6 & sc <= nc - 5 &
  e$water_class %in% 1:3 & e$d8_code %in% valid_codes)
if (!length(eligible)) stop("NO_INTERIOR_02B_ANCHOR; NO_RASTER_SAMPLED")
ord <- order(e$water_class[eligible], e$receiver_cell[eligible],
             e$source_cell[eligible], e$d8_code[eligible], eligible)
k <- eligible[ord[1L]]
entry <- e[k, , drop = FALSE]
s <- as.integer(entry$source_cell)
t <- as.integer(entry$receiver_cell)
r0 <- as.integer((s - 1L) %/% nc + 1L) - 5L
c0 <- as.integer((s - 1L) %% nc + 1L) - 5L
if (r0 < 1L || c0 < 1L || r0 + 10L > nr || c0 + 10L > nc)
  stop("WINDOW_OUT_OF_GRID")
read_square <- function(r) {
  v <- as.numeric(terra::values(r, mat = FALSE, row = r0, nrows = 11L,
                                col = c0, ncols = 11L))
  if (length(v) != 121L) stop("BAD_BOUNDED_RASTER_READ")
  matrix(v, nrow = 11L, ncol = 11L, byrow = TRUE)
}
p <- read_square(rasters$pointer)
w <- read_square(rasters$water)
l <- read_square(rasters$lake)
z <- read_square(rasters$land)
codes <- c(1L, 2L, 4L, 8L, 16L, 32L, 64L, 128L)
dr <- c(-1L, 0L, 1L, 1L, 1L, 0L, -1L, -1L)
dc <- c(1L, 1L, 1L, 0L, -1L, -1L, -1L, 0L)
in_window <- function(r, c) r >= 1L && r <= 11L && c >= 1L && c <= 11L
in_core <- function(r, c) r >= 2L && r <= 10L && c >= 2L && c <= 10L
land <- function(r, c) in_window(r, c) && is.finite(z[r, c]) && is.na(w[r, c])
step_to <- function(r, c) {
  j <- match(p[r, c], codes)
  if (is.na(j)) return(c(NA_integer_, NA_integer_))
  c(r + dr[j], c + dc[j])
}
idx <- function(r, c) (r - 1L) * 11L + c
full <- function(r, c) (r0 + r - 2L) * nc + c0 + c - 1L
if (full(6L, 6L) != s || !land(6L, 6L) || is.na(p[6L,6L]) ||
    p[6L,6L] != entry$d8_code)
  stop("02B_SOURCE_OR_POINTER_MISMATCH")
target <- step_to(6L, 6L)
if (!in_window(target[1L], target[2L]) ||
    full(target[1L], target[2L]) != t ||
    !is.finite(z[target[1L], target[2L]]) ||
    is.na(w[target[1L], target[2L]]) ||
    w[target[1L], target[2L]] != entry$water_class)
  stop("02B_RECEIVER_OR_WATER_CLASS_MISMATCH")
if (entry$water_class == 1L &&
    (is.na(entry$lake_objectid) || is.na(l[target[1L], target[2L]]) ||
     entry$lake_objectid != l[target[1L], target[2L]]))
  stop("02B_LAKE_ID_MISMATCH")
xy <- terra::xyFromCell(rasters$pointer, c(s, t))
sx <- as.numeric(unlist(entry[, c("source_x", "source_y"), drop=FALSE], use.names=FALSE))
tx <- as.numeric(unlist(entry[, c("receiver_x", "receiver_y"), drop=FALSE], use.names=FALSE))
if (any(!is.finite(xy)) || any(!is.finite(c(sx, tx))) ||
    max(abs(xy[1L,] - sx), abs(xy[2L,] - tx)) > 1e-4)
  stop("02B_COORDINATE_MISMATCH")
# Restrict graph to valid LAND->LAND D8 edges entirely inside 9x9 core.
pred <- vector("list", 121L)
core_edges <- 0L
to_halo <- 0L
for (rr in 2:10) for (cc in 2:10) {
  if (!land(rr, cc)) next
  dst <- step_to(rr, cc)
  if (anyNA(dst)) next
  if (!in_core(dst[1L], dst[2L])) {
    if (in_window(dst[1L], dst[2L])) to_halo <- to_halo + 1L
    next
  }
  if (!land(dst[1L], dst[2L])) next
  pred[[idx(dst[1L], dst[2L])]] <- c(pred[[idx(dst[1L], dst[2L])]], idx(rr, cc))
  core_edges <- core_edges + 1L
}
# Reverse BFS: longest found start <=31 land edges from 02B anchor.
dist <- rep(NA_integer_, 121L)
at <- idx(6L, 6L)
dist[at] <- 0L
q <- at
head <- 1L
while (head <= length(q)) {
  v <- q[head]; head <- head + 1L
  if (dist[v] >= 31L) next
  for (u in pred[[v]]) if (is.na(dist[u])) {
    dist[u] <- dist[v] + 1L
    q <- c(q, u)
  }
}
up <- which(!is.na(dist) & dist > 0L)
if (length(up)) {
  candidates <- up[dist[up] == max(dist[up])]
  global <- vapply(candidates, function(i)
    full((i - 1L) %/% 11L + 1L, (i - 1L) %% 11L + 1L), numeric(1))
  start <- candidates[which.min(global)]
} else start <- at
grid <- list(grid_id = "LOW-E200000-N6900000", nrow = 11L, ncol = 11L,
  row_offset = r0 - 1L, col_offset = c0 - 1L,
  xmin = terra::xmin(rasters$pointer), ymax = terra::ymax(rasters$pointer),
  resolution_m = 2, crs = "EPSG:3067")
provenance <- list(run_id = "LOW-existing-02B",
  code_revision = "PR17-753ac0d5", pointer_source = files$pointer,
  water_source = files$water, lake_id_source = files$lake,
  validity_source = files$land, lake_id_namespace = "RANTA10:UNVERIFIED_VERSION")
reader <- function(i) {
  rr <- (i - 1L) %/% 11L + 1L
  cc <- (i - 1L) %% 11L + 1L
  list(pointer = as.numeric(p[rr, cc]), water_class = as.numeric(w[rr, cc]),
       lake_id = as.numeric(l[rr, cc]), valid = is.finite(z[rr, cc]))
}
result <- trace_land_d8_route(start, grid, reader,
                              max_steps = 32L, provenance = provenance)
cat("========== TULOKSET ALKAVAT ==========\n")
cat("MODE READ_ONLY; WINDOW 11x11; 121 positions x 4 rasters; EPSG:3067\n")
cat("CSV", csv, "\n")
cat("INPUTS", paste(names(files), files, sep="=", collapse=" | "), "\n")
cat("GRID", nr, nc, "TOP_LEFT", r0, c0, "02B_ROW", k, "\n")
cat("02B SOURCE", s, "POINTER", entry$d8_code, "RECEIVER", t,
    "WATER_CLASS", entry$water_class, "LAKE_ID", entry$lake_objectid, "\n")
cat("CORE_UPSTREAM_N", length(up), "MAX_REVERSE_DIST",
    if (length(up)) max(dist[up]) else 0L, "CORE_LAND_EDGES", core_edges,
    "CORE_TO_HALO_EDGES", to_halo, "\n")
cat("START_FULL_CELL", full((start - 1L)%/%11L+1L, (start - 1L)%%11L+1L),
    "HAS_UPSTREAM_START", length(up)>0L, "\n")
cat("ROUTE", result$route_status, "STEPS", result$n_transitions,
    "UNRESOLVED", result$continuation_unresolved, "\n")
print(result$path[,c("step","global_row","global_col","cell_uid","cell_kind","revisited")],
      row.names=FALSE)
print(result$transitions[,c("step","from_uid","to_uid","d8_code","edge_kind","closes_cycle")],
      row.names=FALSE)
cat("FIRST_WATER",
    if(is.null(result$first_water)) "NOT_REACHED" else result$first_water$cell_uid, "\n")
cat("INTERPRETATION ONLY COMPUTATIONAL_CONTINUITY; NO DITCH CLASSIFICATION\n")
cat("WINDOW_CENSORED TRUE; HYDROLOGICAL_APPROVAL FALSE\n")
cat("MODERATE REVIEW_REQUIRED; NATIONAL LOCKED\n")
cat("========== TULOKSET LOPPUVAT ==========\n")