# 02D.7K2 - NON-TARGET RAISED LINK RESOLUTION
# Diagnostic only. Resolves raised-component evidence reached by non-raised
# LEVEL groups. No outlet selection, pointer edits, D8 edits or accumulation.

req_02d7k2 <- c(
  "links_02d7h",
  "non_target_gate_edges_02d7i",
  "non_target_flat_summary_02d7j",
  "non_target_flat_edges_02d7j",
  "DIR_02"
)
miss_02d7k2 <- req_02d7k2[
  !vapply(req_02d7k2, exists, logical(1), inherits=TRUE)
]
if (length(miss_02d7k2)) {
  stop("02D.7K2 missing: ", paste(miss_02d7k2, collapse=", "))
}

links_k2 <- links_02d7h[
  links_02d7h$needs_non_target_review %in% TRUE,
  ,
  drop=FALSE
]
stopifnot(nrow(links_k2) > 0)

target_key_02d7k2 <- function(type, lake_id) {
  if (identical(type, "LAKE") && is.finite(lake_id)) {
    return(paste0("LAKE:", as.integer(lake_id)))
  }
  if (identical(type, "RIVER_AREA")) return("RIVER_AREA")
  if (identical(type, "RIVER_LINE")) return("RIVER_LINE")
  NA_character_
}

component_ids_k2 <- sort(unique(links_k2$depression_component_id))
component_rows_k2 <- vector("list", length(component_ids_k2))

for (ii in seq_along(component_ids_k2)) {
  did <- component_ids_k2[ii]

  ge <- non_target_gate_edges_02d7i[
    non_target_gate_edges_02d7i$depression_component_id == did &
      non_target_gate_edges_02d7i$receiver_type != "LAND" &
      non_target_gate_edges_02d7i$receiver_relation %in% c("LOWER","LEVEL"),
    ,
    drop=FALSE
  ]

  gate_keys <- character(0)
  if (nrow(ge)) {
    gate_keys <- vapply(
      seq_len(nrow(ge)),
      function(i) target_key_02d7k2(
        ge$receiver_type[i],
        ge$receiver_lake_objectid[i]
      ),
      character(1)
    )
    gate_keys <- sort(unique(gate_keys[!is.na(gate_keys)]))
  }

  fs <- non_target_flat_summary_02d7j[
    non_target_flat_summary_02d7j$depression_component_id == did,
    ,
    drop=FALSE
  ]

  flat_lower <- if (nrow(fs) == 1) {
    as.integer(fs$n_lower_escape_edges[1])
  } else {
    0L
  }

  flat_other_dep <- if (nrow(fs) == 1) {
    as.integer(fs$n_other_depression_edges[1])
  } else {
    0L
  }

  fe <- non_target_flat_edges_02d7j[
    nrow(non_target_flat_edges_02d7j) > 0 &
      non_target_flat_edges_02d7j$depression_component_id == did &
      non_target_flat_edges_02d7j$is_level_water %in% TRUE,
    ,
    drop=FALSE
  ]

  flat_keys <- character(0)
  if (nrow(fe)) {
    flat_keys <- vapply(
      seq_len(nrow(fe)),
      function(i) target_key_02d7k2(
        fe$receiver_type[i],
        fe$receiver_lake_objectid[i]
      ),
      character(1)
    )
    flat_keys <- sort(unique(flat_keys[!is.na(flat_keys)]))
  }

  flat_agrees <- (
    length(flat_keys) == 0 ||
      setequal(flat_keys, gate_keys)
  )

  component_rows_k2[[ii]] <- data.frame(
    depression_component_id=did,
    n_gate_target_keys=length(gate_keys),
    gate_target_keys=if(length(gate_keys)) paste(gate_keys, collapse=";") else "",
    n_flat_target_keys=length(flat_keys),
    flat_target_keys=if(length(flat_keys)) paste(flat_keys, collapse=";") else "",
    flat_water_agrees_with_gate=flat_agrees,
    n_flat_lower_escape_edges=flat_lower,
    n_flat_other_depression_edges=flat_other_dep,
    stringsAsFactors=FALSE
  )
}

component_resolution_02d7k2 <- do.call(rbind, component_rows_k2)
row.names(component_resolution_02d7k2) <- NULL

link_resolution_02d7k2 <- merge(
  links_k2[
    ,
    c(
      "spill_group_id",
      "lake_objectid",
      "depression_component_id",
      "link_source"
    ),
    drop=FALSE
  ],
  component_resolution_02d7k2,
  by="depression_component_id",
  all.x=TRUE,
  sort=FALSE
)

link_resolution_02d7k2$link_resolution <- "REVIEW"
link_resolution_02d7k2$returns_to_origin_lake <- FALSE
link_resolution_02d7k2$has_external_candidate <- FALSE

for (i in seq_len(nrow(link_resolution_02d7k2))) {
  gate_text <- link_resolution_02d7k2$gate_target_keys[i]
  gate_keys <- if (
    is.na(gate_text) || gate_text == ""
  ) character(0) else strsplit(gate_text, ";", fixed=TRUE)[[1]]

  origin_key <- paste0(
    "LAKE:",
    as.integer(link_resolution_02d7k2$lake_objectid[i])
  )

  unique_gate <- length(gate_keys) == 1
  returns_origin <- unique_gate && identical(gate_keys[1], origin_key)

  flat_agrees <- isTRUE(
    link_resolution_02d7k2$flat_water_agrees_with_gate[i]
  )
  flat_lower <- link_resolution_02d7k2$n_flat_lower_escape_edges[i]
  flat_other <- link_resolution_02d7k2$n_flat_other_depression_edges[i]

  numeric_ok <- (
    is.finite(flat_lower) &&
      is.finite(flat_other)
  )

  if (!unique_gate || !flat_agrees || !numeric_ok || flat_other > 0) {
    cls <- "REVIEW"
  } else if (flat_lower > 0) {
    cls <- "EXTERNAL_CANDIDATE"
  } else if (returns_origin) {
    cls <- "ORIGIN_RETURN_ONLY"
  } else {
    cls <- "EXTERNAL_CANDIDATE"
  }

  link_resolution_02d7k2$link_resolution[i] <- cls
  link_resolution_02d7k2$returns_to_origin_lake[i] <- returns_origin
  link_resolution_02d7k2$has_external_candidate[i] <- (
    cls == "EXTERNAL_CANDIDATE"
  )
}

group_ids_k2 <- sort(unique(link_resolution_02d7k2$spill_group_id))
group_resolution_02d7k2 <- do.call(
  rbind,
  lapply(group_ids_k2, function(gid) {
    x <- link_resolution_02d7k2[
      link_resolution_02d7k2$spill_group_id == gid,
      ,
      drop=FALSE
    ]
    data.frame(
      spill_group_id=gid,
      lake_objectid=x$lake_objectid[1],
      n_links=nrow(x),
      n_origin_return_links=sum(x$link_resolution=="ORIGIN_RETURN_ONLY"),
      n_external_candidate_links=sum(x$link_resolution=="EXTERNAL_CANDIDATE"),
      n_review_links=sum(x$link_resolution=="REVIEW"),
      all_links_resolved=all(x$link_resolution!="REVIEW"),
      stringsAsFactors=FALSE
    )
  })
)
row.names(group_resolution_02d7k2) <- NULL

write.csv(
  component_resolution_02d7k2,
  file.path(DIR_02,"02D7K_non_target_raised_component_resolution.csv"),
  row.names=FALSE
)
write.csv(
  link_resolution_02d7k2,
  file.path(DIR_02,"02D7K_non_target_raised_link_resolution.csv"),
  row.names=FALSE
)
write.csv(
  group_resolution_02d7k2,
  file.path(DIR_02,"02D7K_non_target_raised_group_resolution.csv"),
  row.names=FALSE
)

cat("\n=== 02D.7K NON-TARGET RAISED LINK RESOLUTION ===\n")
cat("Target components          :", nrow(component_resolution_02d7k2), "\n")
cat("Non-target links           :", nrow(link_resolution_02d7k2), "\n")
cat("Linked spill groups        :", nrow(group_resolution_02d7k2), "\n")
cat("Gate/flat disagreements    :",
    sum(!component_resolution_02d7k2$flat_water_agrees_with_gate), "\n")
cat("\n--- LINK RESOLUTION ---\n")
print(table(link_resolution_02d7k2$link_resolution,useNA="ifany"))
cat("===============================================\n")

stopifnot(
  nrow(component_resolution_02d7k2) == length(component_ids_k2),
  !anyDuplicated(component_resolution_02d7k2$depression_component_id),
  nrow(link_resolution_02d7k2) == nrow(links_k2),
  all(component_resolution_02d7k2$flat_water_agrees_with_gate),
  !any(link_resolution_02d7k2$link_resolution == "REVIEW")
)

# TEST_SULKU_11 regression lock; these observed values do not define the method.
stopifnot(
  nrow(component_resolution_02d7k2) == 275,
  nrow(link_resolution_02d7k2) == 296,
  nrow(group_resolution_02d7k2) == 210,
  sum(link_resolution_02d7k2$link_resolution=="ORIGIN_RETURN_ONLY") == 296,
  sum(link_resolution_02d7k2$has_external_candidate) == 0
)

cat("\n02D.7K HARD QA: PASS\n")
