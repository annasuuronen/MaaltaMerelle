# 02D.7K - NON-TARGET RAISED LINK RESOLUTION
#
# Diagnostic only. Resolves non-target raised components reached by
# non-raised LEVEL evidence using the component's own minimum-gate water
# contacts (02D.7I) and optional LEVEL-flat evidence (02D.7J).
#
# No outlet selection, pointer edits, D8 edits or flow accumulation.

req_02d7k <- c(
  "links_02d7h",
  "non_target_gate_edges_02d7i",
  "non_target_gate_summary_02d7i",
  "non_target_flat_summary_02d7j",
  "non_target_flat_edges_02d7j",
  "DIR_02"
)
miss_02d7k <- req_02d7k[
  !vapply(req_02d7k, exists, logical(1), inherits=TRUE)
]
if (length(miss_02d7k)) {
  stop("02D.7K missing: ", paste(miss_02d7k, collapse=", "))
}

non_target_links_02d7k <- links_02d7h[
  links_02d7h$needs_non_target_review %in% TRUE,
  ,
  drop=FALSE
]
stopifnot(nrow(non_target_links_02d7k) > 0)

component_ids_02d7k <- sort(unique(
  non_target_links_02d7k$depression_component_id
))

component_resolution_list_02d7k <- vector(
  "list",
  length(component_ids_02d7k)
)

for (ii in seq_along(component_ids_02d7k)) {
  did <- component_ids_02d7k[ii]

  gx <- non_target_gate_edges_02d7i[
    non_target_gate_edges_02d7i$depression_component_id == did,
    ,
    drop=FALSE
  ]
  stopifnot(nrow(gx) > 0)

  water <- gx[
    gx$receiver_type != "LAND" &
      gx$receiver_relation %in% c("LOWER","LEVEL"),
    ,
    drop=FALSE
  ]

  lake_targets <- sort(unique(as.integer(
    water$receiver_lake_objectid[
      water$receiver_type == "LAKE" &
        is.finite(water$receiver_lake_objectid)
    ]
  )))
  has_river_area <- any(water$receiver_type == "RIVER_AREA")
  has_river_line <- any(water$receiver_type == "RIVER_LINE")

  target_keys <- character(0)
  if (length(lake_targets)) {
    target_keys <- c(target_keys, paste0("LAKE:", lake_targets))
  }
  if (has_river_area) target_keys <- c(target_keys, "RIVER_AREA")
  if (has_river_line) target_keys <- c(target_keys, "RIVER_LINE")
  target_keys <- sort(unique(target_keys))

  gate_target_class <- if (!length(target_keys)) {
    "NO_MIN_GATE_WATER"
  } else if (length(target_keys) > 1) {
    "MULTI_MIN_GATE_WATER"
  } else if (grepl("^LAKE:", target_keys[1])) {
    "UNIQUE_MIN_GATE_LAKE"
  } else if (target_keys[1] == "RIVER_AREA") {
    "UNIQUE_MIN_GATE_RIVER_AREA"
  } else if (target_keys[1] == "RIVER_LINE") {
    "UNIQUE_MIN_GATE_RIVER_LINE"
  } else {
    "UNCLASSIFIED_MIN_GATE_WATER"
  }

  flat_sum <- non_target_flat_summary_02d7j[
    non_target_flat_summary_02d7j$depression_component_id == did,
    ,
    drop=FALSE
  ]
  stopifnot(nrow(flat_sum) <= 1)

  flat_status <- if (nrow(flat_sum)) flat_sum$status[1] else NA_character_
  flat_lower <- if (nrow(flat_sum)) flat_sum$n_lower_escape_edges[1] else 0L
  flat_other_dep <- if (nrow(flat_sum)) flat_sum$n_other_depression_edges[1] else 0L

  flat_water_keys <- character(0)
  if (nrow(non_target_flat_edges_02d7j)) {
    fw <- non_target_flat_edges_02d7j[
      non_target_flat_edges_02d7j$depression_component_id == did &
        non_target_flat_edges_02d7j$is_level_water %in% TRUE,
      ,
      drop=FALSE
    ]
    if (nrow(fw)) {
      fl <- sort(unique(as.integer(
        fw$receiver_lake_objectid[
          fw$receiver_type == "LAKE" &
            is.finite(fw$receiver_lake_objectid)
        ]
      )))
      if (length(fl)) {
        flat_water_keys <- c(flat_water_keys, paste0("LAKE:", fl))
      }
      if (any(fw$receiver_type == "RIVER_AREA")) {
        flat_water_keys <- c(flat_water_keys, "RIVER_AREA")
      }
      if (any(fw$receiver_type == "RIVER_LINE")) {
        flat_water_keys <- c(flat_water_keys, "RIVER_LINE")
      }
      flat_water_keys <- sort(unique(flat_water_keys))
    }
  }

  component_resolution_list_02d7k[[ii]] <- data.frame(
    depression_component_id=did,
    gate_target_class=gate_target_class,
    n_gate_target_keys=length(target_keys),
    gate_target_keys=if(length(target_keys)) paste(target_keys,collapse=";") else "",
    n_gate_lake_targets=length(lake_targets),
    gate_lake_targets=if(length(lake_targets)) paste(lake_targets,collapse=";") else "",
    has_gate_river_area=has_river_area,
    has_gate_river_line=has_river_line,
    flat_status=flat_status,
    n_flat_lower_escape_edges=as.integer(flat_lower),
    n_flat_other_depression_edges=as.integer(flat_other_dep),
    n_flat_water_target_keys=length(flat_water_keys),
    flat_water_target_keys=if(length(flat_water_keys)) paste(flat_water_keys,collapse=";") else "",
    flat_water_agrees_with_gate=(
      !length(flat_water_keys) ||
        setequal(flat_water_keys, target_keys)
    ),
    stringsAsFactors=FALSE
  )
}

component_resolution_02d7k <- do.call(
  rbind,
  component_resolution_list_02d7k
)
row.names(component_resolution_02d7k) <- NULL

link_resolution_02d7k <- merge(
  non_target_links_02d7k,
  component_resolution_02d7k,
  by="depression_component_id",
  all.x=TRUE,
  sort=FALSE
)

link_resolution_02d7k <- link_resolution_02d7k[
  order(
    link_resolution_02d7k$lake_objectid,
    link_resolution_02d7k$spill_group_id,
    link_resolution_02d7k$depression_component_id,
    link_resolution_02d7k$link_source
  ),
  ,
  drop=FALSE
]
row.names(link_resolution_02d7k) <- NULL

link_resolution_02d7k$link_resolution <- "UNRESOLVED"
link_resolution_02d7k$has_external_candidate <- FALSE
link_resolution_02d7k$returns_to_origin_lake <- FALSE

for (i in seq_len(nrow(link_resolution_02d7k))) {
  x <- link_resolution_02d7k[i,,drop=FALSE]

  gate_keys <- if (
    is.na(x$gate_target_keys) || x$gate_target_keys == ""
  ) character(0) else strsplit(x$gate_target_keys, ";", fixed=TRUE)[[1]]

  flat_keys <- if (
    is.na(x$flat_water_target_keys) || x$flat_water_target_keys == ""
  ) character(0) else strsplit(x$flat_water_target_keys, ";", fixed=TRUE)[[1]]

  origin_key <- paste0("LAKE:", as.integer(x$lake_objectid))

  all_water_keys <- sort(unique(c(gate_keys, flat_keys)))
  external_water_keys <- setdiff(all_water_keys, origin_key)

  has_external <- (
    length(external_water_keys) > 0 ||
      x$n_flat_lower_escape_edges > 0
  )

  returns_origin <- origin_key %in% all_water_keys

  unresolved <- (
    x$gate_target_class %in% c(
      "NO_MIN_GATE_WATER",
      "MULTI_MIN_GATE_WATER",
      "UNCLASSIFIED_MIN_GATE_WATER"
    ) ||
      !isTRUE(x$flat_water_agrees_with_gate) ||
      x$n_flat_other_depression_edges > 0
  )

  if (unresolved) {
    cls <- "REVIEW"
  } else if (has_external) {
    cls <- "EXTERNAL_CANDIDATE"
  } else if (returns_origin) {
    cls <- "ORIGIN_RETURN_ONLY"
  } else {
    cls <- "NO_EXTERNAL_EVIDENCE"
  }

  link_resolution_02d7k$link_resolution[i] <- cls
  link_resolution_02d7k$has_external_candidate[i] <- has_external
  link_resolution_02d7k$returns_to_origin_lake[i] <- returns_origin
}

group_ids_02d7k <- sort(unique(link_resolution_02d7k$spill_group_id))
group_resolution_02d7k <- do.call(
  rbind,
  lapply(group_ids_02d7k, function(gid) {
    x <- link_resolution_02d7k[
      link_resolution_02d7k$spill_group_id == gid,
      ,
      drop=FALSE
    ]
    data.frame(
      spill_group_id=gid,
      lake_objectid=x$lake_objectid[1],
      n_non_target_links=nrow(x),
      n_origin_return_links=sum(x$link_resolution=="ORIGIN_RETURN_ONLY"),
      n_external_candidate_links=sum(x$link_resolution=="EXTERNAL_CANDIDATE"),
      n_review_links=sum(x$link_resolution=="REVIEW"),
      n_no_external_evidence_links=sum(x$link_resolution=="NO_EXTERNAL_EVIDENCE"),
      all_non_target_links_resolved=all(
        !x$link_resolution %in% c("REVIEW","NO_EXTERNAL_EVIDENCE")
      ),
      stringsAsFactors=FALSE
    )
  })
)
row.names(group_resolution_02d7k) <- NULL

write.csv(
  component_resolution_02d7k,
  file.path(DIR_02,"02D7K_non_target_raised_component_resolution.csv"),
  row.names=FALSE
)
write.csv(
  link_resolution_02d7k,
  file.path(DIR_02,"02D7K_non_target_raised_link_resolution.csv"),
  row.names=FALSE
)
write.csv(
  group_resolution_02d7k,
  file.path(DIR_02,"02D7K_non_target_raised_group_resolution.csv"),
  row.names=FALSE
)

cat("\n=== 02D.7K NON-TARGET RAISED LINK RESOLUTION ===\n")
cat("Target components             :", nrow(component_resolution_02d7k), "\n")
cat("Non-target links              :", nrow(link_resolution_02d7k), "\n")
cat("Linked spill groups           :", nrow(group_resolution_02d7k), "\n")
cat("Unique min-gate lake target   :",
    sum(component_resolution_02d7k$gate_target_class=="UNIQUE_MIN_GATE_LAKE"), "\n")
cat("Flat/gate target disagreement :",
    sum(!component_resolution_02d7k$flat_water_agrees_with_gate), "\n")
cat("\n--- LINK RESOLUTION ---\n")
print(table(link_resolution_02d7k$link_resolution,useNA="ifany"))
cat("===============================================\n")

stopifnot(
  nrow(component_resolution_02d7k) == length(component_ids_02d7k),
  !anyDuplicated(component_resolution_02d7k$depression_component_id),
  setequal(
    component_resolution_02d7k$depression_component_id,
    component_ids_02d7k
  ),
  nrow(link_resolution_02d7k) == nrow(non_target_links_02d7k),
  all(component_resolution_02d7k$flat_water_agrees_with_gate),
  !any(link_resolution_02d7k$link_resolution == "REVIEW")
)

# TEST_SULKU_11 regression lock. These values document the current accepted
# evidence partition; they do not define the method above.
stopifnot(
  nrow(component_resolution_02d7k) == 275,
  nrow(link_resolution_02d7k) == 296,
  nrow(group_resolution_02d7k) == 210,
  sum(component_resolution_02d7k$gate_target_class=="UNIQUE_MIN_GATE_LAKE") == 275,
  sum(link_resolution_02d7k$link_resolution=="ORIGIN_RETURN_ONLY") == 296,
  sum(link_resolution_02d7k$has_external_candidate) == 0,
  sum(group_resolution_02d7k$n_review_links) == 0
)

cat("\n02D.7K HARD QA: PASS\n")
