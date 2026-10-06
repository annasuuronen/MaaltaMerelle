# Base-R tests for path resolution and unchanged configuration invariants.
# Run from the repository root: Rscript tests/portability.R
repo <- normalizePath(".", winslash = "/", mustWork = TRUE)
stopifnot(file.exists(file.path(repo, "R", "00_pipeline_config.R")))
variables <- c("HYDRO_PROJECT_ROOT", "HYDRO_MODE", "HYDRO_PIPELINE_ROOT",
               "HYDRO_SOURCE_TEST_ROOT", "HYDRO_STRUCTURES_ROOT",
               "HYDRO_CSC_ROOT", "HYDRO_RUN_ROOT")
old <- Sys.getenv(variables, unset = NA_character_)
work <- tempfile("hydro-portability-")
dir.create(file.path(work, "project with spaces", "R"), recursive = TRUE)
root <- normalizePath(file.path(work, "project with spaces"), winslash = "/")
stopifnot(all(file.copy(list.files(file.path(repo, "R"), full.names = TRUE), file.path(root, "R"))))
config <- file.path(root, "R", "00_pipeline_config.R")

run_checks <- function() {
  on.exit({
    Sys.unsetenv(variables)
    present <- !is.na(old)
    if (any(present)) do.call(Sys.setenv, as.list(old[present]))
    unlink(work, recursive = TRUE)
  })
  load_config <- function(settings = list()) {
    Sys.unsetenv(variables)
    if (length(settings)) do.call(Sys.setenv, settings)
    e <- new.env(parent = globalenv())
    source(config, local = e)
    e
  }
  for (f in list.files(file.path(repo, "R"), full.names = TRUE)) parse(f)
  e <- load_config()
  stopifnot(e$PROJECT_ROOT == root, e$HYDRO_MODE == "LOCAL_TEST",
            e$PIPELINE_ROOT == root,
            e$SOURCE_TEST_ROOT == file.path(root, "data", "TEST_SULKU_11"),
            e$STRUCTURES_GPKG == file.path(root, "data", "TEST_SULKU_11",
                                         "HYDRO_STRUCTURES_LOCAL_TEST_SULKU_11_12km.gpkg"),
            e$RUN_ROOT == file.path(root, "runs", "TEST_SULKU_11"),
            all(dir.exists(c(e$DIR_01, e$DIR_02, e$DIR_03, e$DIR_04, e$DIR_05, e$DIR_06))),
            e$CRS_EPSG == 3067, e$CELL_SIZE_M == 2, e$HALO_M == 1000,
            e$STREAM_THRESHOLD_HA == 4, e$STREAM_THRESHOLD_CELLS == 10000,
            e$POINTER_SCHEME == "whitebox", identical(e$OVERWRITE, FALSE),
            identical(e$TEST_EXTENT, c(xmin=407030, xmax=419030, ymin=7070072, ymax=7082072)),
            e$TEST_NCOL == 6000L, e$TEST_NROW == 6000L,
            identical(e$EXPECTED_TEST, list(lakes=108L, river_areas=8L, river_lines=81L,
              physical_structures=11L, hydraulic_sites=9L, confirms_current=3L,
              controls_existing=4L, adds_outlet_candidate=2L, unresolved_flow_split=2L)))
  cat("PASS: LOCAL_TEST defaults, directories, hydrological constants and regressions\n")
  e <- load_config(list(HYDRO_SOURCE_TEST_ROOT="external inputs", HYDRO_STRUCTURES_ROOT="structures",
                       HYDRO_PIPELINE_ROOT="output", HYDRO_RUN_ROOT="custom runs"))
  stopifnot(e$SOURCE_TEST_ROOT == file.path(root, "external inputs"),
            e$STRUCTURES_ROOT == file.path(root, "structures"),
            e$PIPELINE_ROOT == file.path(root, "output"),
            e$RUN_ROOT == file.path(root, "custom runs"))
  e <- load_config(list(HYDRO_PROJECT_ROOT=root, HYDRO_SOURCE_TEST_ROOT=file.path(work, "absolute inputs")))
  stopifnot(e$PROJECT_ROOT == root, e$SOURCE_TEST_ROOT == file.path(work, "absolute inputs"))
  # Exercise the actual resolver; native Windows execution is a separate check.
  for (path in c("C:/inputs", "C:\\inputs", "\\\\server\\share")) {
    Sys.setenv(HYDRO_SOURCE_TEST_ROOT=path)
    resolved <- e$hydro_path("HYDRO_SOURCE_TEST_ROOT", "unused")
    stopifnot(!startsWith(resolved, root))
  }
  cat("PASS: relative, absolute and project-root overrides; Windows path recognition\n")
  e <- load_config(list(HYDRO_MODE="CSC_TEST", HYDRO_RUN_ROOT=file.path(work, "csc run")))
  stopifnot(e$PIPELINE_ROOT == "/scratch/project_2004707/pienvedet/hydrology_pipeline_v2",
            e$SOURCE_TEST_ROOT == "/scratch/project_2004707/pienvedet/hydro_test/TEST_SULKU_11",
            e$STRUCTURES_GPKG == "/scratch/project_2004707/pienvedet/hydrology_structures/HYDRO_STRUCTURES_LOCAL_TEST_SULKU_11_12km.gpkg")
  e <- load_config(list(HYDRO_MODE="CSC_TEST", HYDRO_CSC_ROOT="csc", HYDRO_RUN_ROOT="csc runs"))
  stopifnot(e$PIPELINE_ROOT == file.path(root, "csc", "hydrology_pipeline_v2"))
  cat("PASS: CSC_TEST defaults and overrides\n")
  for (mode in c("NATIONAL", "INVALID")) {
    target <- file.path(work, paste0("forbidden-", mode))
    err <- tryCatch(load_config(list(HYDRO_MODE=mode, HYDRO_RUN_ROOT=target)), error=identity)
    stopifnot(inherits(err, "error"), !dir.exists(target))
    if (mode == "NATIONAL") stopifnot(grepl("NATIONAL RUN IS LOCKED", conditionMessage(err)))
  }
  err <- tryCatch(load_config(list(HYDRO_PROJECT_ROOT=work)), error=identity)
  stopifnot(inherits(err, "error"))
  cat("PASS: NATIONAL lock, invalid mode and invalid repository rejection\n")
}
run_checks()
