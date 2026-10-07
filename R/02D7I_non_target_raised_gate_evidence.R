# 02D.7I - NON-TARGET RAISED COMPONENT MIN-GATE EVIDENCE
# Diagnostic only. Extends the validated 02D.5 gate definition to raised
# components reached by non-raised LEVEL evidence but absent from the
# spill-raised target set. No outlet selection or routing edits.

req_02d7i <- c(
  "links_02d7h","depression_components","surface_storage",
  "surface_land_water","water_class","lake_id","cell_values",
  "is_edge_cell","DIR_02"
)
miss_02d7i <- req_02d7i[!vapply(req_02d7i, exists, logical(1), inherits=TRUE)]
if (length(miss_02d7i)) stop("02D.7I missing: ", paste(miss_02d7i, collapse=", "))

target_dep_02d7i <- sort(unique(
  links_02d7h$depression_component_id[links_02d7h$needs_non_target_review]
))
stopifnot(length(target_dep_02d7i) > 0)

all_dep_02d7i <- as.data.frame(depression_components, cells=TRUE, na.rm=TRUE)
names(all_dep_02d7i)[2] <- "depression_component_id"
all_dep_02d7i$depression_component_id <- as.integer(all_dep_02d7i$depression_component_id)
all_dep_02d7i <- all_dep_02d7i[
  all_dep_02d7i$depression_component_id %in% target_dep_02d7i,,drop=FALSE
]
stopifnot(setequal(unique(all_dep_02d7i$depression_component_id), target_dep_02d7i))

edge_list_02d7i <- vector("list", length(target_dep_02d7i))
summary_list_02d7i <- vector("list", length(target_dep_02d7i))

for (i in seq_along(target_dep_02d7i)) {
  did <- target_dep_02d7i[i]
  comp_cells <- all_dep_02d7i$cell[all_dep_02d7i$depression_component_id == did]
  stopifnot(length(comp_cells) > 0)

  ap <- terra::adjacent(
    depression_components, cells=comp_cells,
    directions=8, pairs=TRUE, include=FALSE
  )
  receiver_dep <- cell_values(depression_components, ap[,2])
  outside <- !is.finite(receiver_dep) | receiver_dep != did
  boundary <- ap[outside,,drop=FALSE]
  receiver_dep <- receiver_dep[outside]
  stopifnot(nrow(boundary) > 0)

  source_storage <- cell_values(surface_storage, boundary[,1])
  receiver_storage <- cell_values(surface_storage, boundary[,2])
  source_original <- cell_values(surface_land_water, boundary[,1])
  receiver_original <- cell_values(surface_land_water, boundary[,2])
  stopifnot(all(is.finite(source_storage)), all(is.finite(receiver_storage)))

  crossing <- pmax(source_storage, receiver_storage)
  gate_level <- min(crossing)
  is_gate <- abs(crossing - gate_level) <= gate_level_tol_m
  gb <- boundary[is_gate,,drop=FALSE]
  stopifnot(nrow(gb) > 0)

  rec_class <- cell_values(water_class, gb[,2])
  rec_lake <- cell_values(lake_id, gb[,2])
  rec_dep <- cell_values(depression_components, gb[,2])
  rec_original <- receiver_original[is_gate]
  rec_storage <- receiver_storage[is_gate]

  rec_type <- rep("LAND", nrow(gb))
  rec_type[rec_class == 1] <- "LAKE"
  rec_type[rec_class == 2] <- "RIVER_AREA"
  rec_type[rec_class == 3] <- "RIVER_LINE"

  relation <- rep("LEVEL", nrow(gb))
  relation[rec_original < gate_level - escape_tol_m] <- "LOWER"
  relation[rec_original > gate_level + escape_tol_m] <- "ABOVE"

  ee <- data.frame(
    depression_component_id=did,
    source_cell=gb[,1],
    receiver_cell=gb[,2],
    gate_level_m=gate_level,
    receiver_original_z_m=rec_original,
    receiver_storage_z_m=rec_storage,
    receiver_relation=relation,
    receiver_type=rec_type,
    receiver_lake_objectid=as.integer(rec_lake),
    receiver_depression_component_id=as.integer(rec_dep),
    touches_raster_edge=(
      is_edge_cell(depression_components, gb[,1]) |
      is_edge_cell(depression_components, gb[,2])
    ),
    stringsAsFactors=FALSE
  )
  edge_list_02d7i[[i]] <- ee

  summary_list_02d7i[[i]] <- data.frame(
    depression_component_id=did,
    n_component_cells=length(comp_cells),
    n_boundary_edges=nrow(boundary),
    n_min_gate_edges=nrow(gb),
    gate_level_m=gate_level,
    n_lower=sum(relation=="LOWER"),
    n_level=sum(relation=="LEVEL"),
    n_above=sum(relation=="ABOVE"),
    n_land=sum(rec_type=="LAND"),
    n_water=sum(rec_type!="LAND"),
    n_other_depression=sum(is.finite(rec_dep) & rec_dep != did),
    touches_raster_edge=any(ee$touches_raster_edge),
    stringsAsFactors=FALSE
  )
}

non_target_gate_edges_02d7i <- do.call(rbind, edge_list_02d7i)
non_target_gate_summary_02d7i <- do.call(rbind, summary_list_02d7i)
row.names(non_target_gate_edges_02d7i) <- NULL
row.names(non_target_gate_summary_02d7i) <- NULL

write.csv(
  non_target_gate_edges_02d7i,
  file.path(DIR_02,"02D7I_non_target_raised_min_gate_edges.csv"),
  row.names=FALSE
)
write.csv(
  non_target_gate_summary_02d7i,
  file.path(DIR_02,"02D7I_non_target_raised_min_gate_summary.csv"),
  row.names=FALSE
)

cat("\n=== 02D.7I NON-TARGET RAISED MIN-GATE EVIDENCE ===\n")
cat("Target raised components       :", length(target_dep_02d7i), "\n")
cat("Components with LOWER gate     :", sum(non_target_gate_summary_02d7i$n_lower>0), "\n")
cat("Components with LEVEL gate     :", sum(non_target_gate_summary_02d7i$n_level>0), "\n")
cat("Components with water gate     :", sum(non_target_gate_summary_02d7i$n_water>0), "\n")
cat("Components touching edge       :", sum(non_target_gate_summary_02d7i$touches_raster_edge), "\n")
cat("ABOVE min-gate edges           :", sum(non_target_gate_summary_02d7i$n_above), "\n")
cat("Adjacent other raised at gate  :", sum(non_target_gate_summary_02d7i$n_other_depression), "\n")

stopifnot(
  nrow(non_target_gate_summary_02d7i) == length(target_dep_02d7i),
  !anyDuplicated(non_target_gate_summary_02d7i$depression_component_id),
  setequal(non_target_gate_summary_02d7i$depression_component_id, target_dep_02d7i),
  all(non_target_gate_summary_02d7i$n_min_gate_edges > 0),
  sum(non_target_gate_summary_02d7i$n_above) == 0,
  sum(non_target_gate_summary_02d7i$n_other_depression) == 0
)
cat("02D.7I HARD QA: PASS\n")
