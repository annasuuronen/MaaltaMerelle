# Component-level regression for the LOW E200000_N6900000 02D.7K evidence.
# Run after the LOW hydrology pipeline has completed.
run_root <- Sys.getenv("HYDRO_RUN_ROOT", unset = "")
if (!nzchar(run_root)) stop("HYDRO_RUN_ROOT must point to the completed LOW run.")

evidence_dir <- file.path(run_root, "02_baseline")
component_path <- file.path(
  evidence_dir,
  "02D7K_non_target_raised_component_resolution.csv"
)
link_path <- file.path(
  evidence_dir,
  "02D7K_non_target_raised_link_resolution.csv"
)
if (!file.exists(component_path)) stop("Missing LOW 02D.7K component evidence.")
if (!file.exists(link_path)) stop("Missing LOW 02D.7K link evidence.")

components <- read.csv(component_path, stringsAsFactors = FALSE)
links <- read.csv(link_path, stringsAsFactors = FALSE)
required_component_columns <- c(
  "depression_component_id",
  "gate_level_m",
  "gate_target_keys",
  "flat_target_keys",
  "flat_water_agrees_with_gate",
  "flat_water_mismatch_supported_by_lower_river_exit",
  "n_flat_lower_escape_edges",
  "n_flat_other_depression_edges",
  "n_flat_untraced_level_land_edges",
  "touches_raster_edge"
)
missing_component_columns <- setdiff(
  required_component_columns,
  names(components)
)
if (length(missing_component_columns)) {
  stop(
    "LOW 02D.7K component evidence is missing columns: ",
    paste(missing_component_columns, collapse = ", ")
  )
}
required_link_columns <- c(
  "depression_component_id",
  "link_resolution"
)
missing_link_columns <- setdiff(required_link_columns, names(links))
if (length(missing_link_columns)) {
  stop(
    "LOW 02D.7K link evidence is missing columns: ",
    paste(missing_link_columns, collapse = ", ")
  )
}

component <- components[
  components$depression_component_id == 396,
  ,
  drop = FALSE
]
component_links <- links[
  links$depression_component_id == 396,
  ,
  drop = FALSE
]
stopifnot(
  nrow(component) == 1L,
  abs(component$gate_level_m[1] - 0.370) < 1e-6,
  component$gate_target_keys[1] == "LAKE:1892",
  component$flat_target_keys[1] == "RIVER_LINE",
  !component$flat_water_agrees_with_gate[1],
  isTRUE(component$flat_water_mismatch_supported_by_lower_river_exit[1]),
  component$n_flat_lower_escape_edges[1] == 1L,
  component$n_flat_other_depression_edges[1] == 0L,
  component$n_flat_untraced_level_land_edges[1] == 0L,
  !component$touches_raster_edge[1],
  nrow(component_links) == 1L,
  component_links$link_resolution[1] == "EXTERNAL_CANDIDATE",
  sum(links$link_resolution == "ORIGIN_RETURN_ONLY") == 195L,
  sum(links$link_resolution == "EXTERNAL_CANDIDATE") == 1L,
  sum(links$link_resolution == "REVIEW") == 0L
)

cat("PASS: LOW component 396 remains one lower-escape external candidate\n")
