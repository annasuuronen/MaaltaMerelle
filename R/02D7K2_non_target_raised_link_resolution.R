# 02D.7K2 - NON-TARGET RAISED LINK RESOLUTION
# Diagnostic only. Resolve raised-component evidence reached by non-raised
# LEVEL groups. Equal-level raised components connected through the traced
# LEVEL flat are collapsed to one evidence cluster before classification.
# No outlet selection, pointer edits, D8 edits or accumulation.

req_02d7k2 <- c(
  "links_02d7h",
  "non_target_gate_edges_02d7i",
  "non_target_gate_summary_02d7i",
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

tol_02d7k2 <- if (exists("gate_level_tol_m", inherits=TRUE)) {
  get("gate_level_tol_m", inherits=TRUE)
} else {
  1e-6
}

target_key_02d7k2 <- function(type, lake_id) {
  if (identical(type, "LAKE") && is.finite(lake_id)) {
    return(paste0("LAKE:", as.integer(lake_id)))
  }
  if (identical(type, "RIVER_AREA")) return("RIVER_AREA")
  if (identical(type, "RIVER_LINE")) return("RIVER_LINE")
  NA_character_
}

split_keys_02d7k2 <- function(x) {
  if (length(x) != 1L || is.na(x) || !nzchar(x)) return(character(0))
  strsplit(x, ";", fixed=TRUE)[[1]]
}

component_ids_k2 <- sort(unique(links_k2$depression_component_id))
component_rows_k2 <- vector("list", length(component_ids_k2))

for (ii in seq_along(component_ids_k2)) {
  did <- component_ids_k2[ii]

  gs <- non_target_gate_summary_02d7i[
    non_target_gate_summary_02d7i$depression_component_id == did,
    ,
    drop=FALSE
  ]
  stopifnot(nrow(gs) == 1L)

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
  stopifnot(nrow(fs) <= 1L)

  flat_lower <- if (nrow(fs) == 1L) as.integer(fs$n_lower_escape_edges[1]) else 0L
  flat_other <- if (nrow(fs) == 1L) as.integer(fs$n_other_depression_edges[1]) else 0L
  flat_untraced <- if (nrow(fs) == 1L) {
    as.integer(fs$n_untraced_level_land_edges[1])
  } else {
    0L
  }
  flat_edge <- if (nrow(fs) == 1L) isTRUE(fs$touches_raster_edge[1]) else FALSE

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
    gate_level_m=as.numeric(gs$gate_level_m[1]),
    n_gate_target_keys=length(gate_keys),
    gate_target_keys=if(length(gate_keys)) paste(gate_keys, collapse=";") else "",
    n_flat_target_keys=length(flat_keys),
    flat_target_keys=if(length(flat_keys)) paste(flat_keys, collapse=";") else "",
    flat_water_agrees_with_gate=flat_agrees,
    n_flat_lower_escape_edges=flat_lower,
    n_flat_other_depression_edges=flat_other,
    n_flat_untraced_level_land_edges=flat_untraced,
    touches_raster_edge=isTRUE(gs$touches_raster_edge[1]) || flat_edge,
    stringsAsFactors=FALSE
  )
}

component_resolution_02d7k2 <- do.call(rbind, component_rows_k2)
row.names(component_resolution_02d7k2) <- NULL

# ------------------------------------------------------------
# Collapse connected equal-level raised components.
#
# 02D.7J can encounter another raised component on the boundary of the
# same LEVEL flat. Treating that internal component contact as an external
# escape creates a false REVIEW. Build an undirected graph only from
# explicit LEVEL other-depression edges whose two components have the
# same validated minimum-gate level.
# ------------------------------------------------------------

level_dep_edges_k2 <- data.frame(
  from=integer(0),
  to=integer(0),
  stringsAsFactors=FALSE
)

if (nrow(non_target_flat_edges_02d7j)) {
  z <- non_target_flat_edges_02d7j[
    non_target_flat_edges_02d7j$is_other_depression %in% TRUE &
      is.finite(non_target_flat_edges_02d7j$receiver_depression_component_id),
    ,
    drop=FALSE
  ]

  if (nrow(z)) {
    to_id <- as.integer(z$receiver_depression_component_id)
    m_to <- match(to_id, component_resolution_02d7k2$depression_component_id)
    to_level <- component_resolution_02d7k2$gate_level_m[m_to]

    same_level <- (
      !is.na(m_to) &
      is.finite(z$gate_level_m) &
      is.finite(to_level) &
      abs(z$gate_level_m - to_level) <= tol_02d7k2
    )

    if (any(same_level)) {
      level_dep_edges_k2 <- unique(data.frame(
        from=as.integer(z$depression_component_id[same_level]),
        to=to_id[same_level],
        stringsAsFactors=FALSE
      ))
      level_dep_edges_k2 <- level_dep_edges_k2[
        level_dep_edges_k2$from != level_dep_edges_k2$to,
        ,
        drop=FALSE
      ]
    }
  }
}

neighbors_k2 <- setNames(
  vector("list", length(component_ids_k2)),
  as.character(component_ids_k2)
)
if (nrow(level_dep_edges_k2)) {
  for (i in seq_len(nrow(level_dep_edges_k2))) {
    a <- as.character(level_dep_edges_k2$from[i])
    b <- as.character(level_dep_edges_k2$to[i])
    neighbors_k2[[a]] <- unique(c(neighbors_k2[[a]], as.integer(b)))
    neighbors_k2[[b]] <- unique(c(neighbors_k2[[b]], as.integer(a)))
  }
}

cluster_id_by_component_k2 <- setNames(
  rep(NA_integer_, length(component_ids_k2)),
  as.character(component_ids_k2)
)

for (start in component_ids_k2) {
  skey <- as.character(start)
  if (is.finite(cluster_id_by_component_k2[[skey]])) next

  queue <- as.integer(start)
  members <- integer(0)

  while (length(queue)) {
    cur <- queue[1]
    queue <- queue[-1]
    ckey <- as.character(cur)
    if (cur %in% members) next
    members <- c(members, cur)
    nxt <- neighbors_k2[[ckey]]
    if (length(nxt)) queue <- c(queue, nxt[!nxt %in% members])
  }

  cid <- min(members)
  cluster_id_by_component_k2[as.character(members)] <- cid
}

stopifnot(all(is.finite(cluster_id_by_component_k2)))

component_resolution_02d7k2$evidence_cluster_id <- as.integer(
  cluster_id_by_component_k2[
    as.character(component_resolution_02d7k2$depression_component_id)
  ]
)

cluster_ids_k2 <- sort(unique(component_resolution_02d7k2$evidence_cluster_id))
cluster_rows_k2 <- vector("list", length(cluster_ids_k2))

for (ii in seq_along(cluster_ids_k2)) {
  cid <- cluster_ids_k2[ii]
  cr <- component_resolution_02d7k2[
    component_resolution_02d7k2$evidence_cluster_id == cid,
    ,
    drop=FALSE
  ]
  members <- sort(cr$depression_component_id)

  gate_keys <- sort(unique(unlist(
    lapply(cr$gate_target_keys, split_keys_02d7k2),
    use.names=FALSE
  )))
  flat_keys <- sort(unique(unlist(
    lapply(cr$flat_target_keys, split_keys_02d7k2),
    use.names=FALSE
  )))
  all_keys <- sort(unique(c(gate_keys, flat_keys)))

  dep_edges <- if (nrow(non_target_flat_edges_02d7j)) {
    non_target_flat_edges_02d7j[
      non_target_flat_edges_02d7j$depression_component_id %in% members &
        non_target_flat_edges_02d7j$is_other_depression %in% TRUE &
        is.finite(non_target_flat_edges_02d7j$receiver_depression_component_id),
      ,
      drop=FALSE
    ]
  } else {
    data.frame()
  }

  n_internal_dep <- 0L
  n_external_dep <- 0L
  if (nrow(dep_edges)) {
    recv <- as.integer(dep_edges$receiver_depression_component_id)
    recv_cluster <- cluster_id_by_component_k2[as.character(recv)]
    internal <- !is.na(recv_cluster) & as.integer(recv_cluster) == cid
    n_internal_dep <- sum(internal)
    n_external_dep <- sum(!internal)
  }

  cluster_rows_k2[[ii]] <- data.frame(
    evidence_cluster_id=cid,
    n_components=nrow(cr),
    component_ids=paste(members, collapse=";"),
    gate_level_min_m=min(cr$gate_level_m),
    gate_level_max_m=max(cr$gate_level_m),
    n_gate_target_keys=length(gate_keys),
    gate_target_keys=if(length(gate_keys)) paste(gate_keys, collapse=";") else "",
    n_flat_target_keys=length(flat_keys),
    flat_target_keys=if(length(flat_keys)) paste(flat_keys, collapse=";") else "",
    n_all_target_keys=length(all_keys),
    all_target_keys=if(length(all_keys)) paste(all_keys, collapse=";") else "",
    n_flat_lower_escape_edges=sum(cr$n_flat_lower_escape_edges),
    n_internal_equal_level_depression_edges=n_internal_dep,
    n_external_other_depression_edges=n_external_dep,
    n_untraced_level_land_edges=sum(cr$n_flat_untraced_level_land_edges),
    touches_raster_edge=any(cr$touches_raster_edge),
    stringsAsFactors=FALSE
  )
}

cluster_resolution_02d7k2 <- do.call(rbind, cluster_rows_k2)
row.names(cluster_resolution_02d7k2) <- NULL

stopifnot(
  nrow(cluster_resolution_02d7k2) > 0,
  !anyDuplicated(cluster_resolution_02d7k2$evidence_cluster_id),
  all(
    abs(
      cluster_resolution_02d7k2$gate_level_max_m -
        cluster_resolution_02d7k2$gate_level_min_m
    ) <= tol_02d7k2
  )
)

# ------------------------------------------------------------
# Classify each non-target link using cluster-level evidence.
# ORIGIN_RETURN_ONLY is allowed only when the full equal-level cluster
# has one terminal water target equal to the origin lake and no lower,
# external-depression, raster-edge or untraced LEVEL evidence.
# ------------------------------------------------------------

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
  component_resolution_02d7k2[
    ,
    c(
      "depression_component_id",
      "evidence_cluster_id"
    ),
    drop=FALSE
  ],
  by="depression_component_id",
  all.x=TRUE,
  sort=FALSE
)

link_resolution_02d7k2 <- merge(
  link_resolution_02d7k2,
  cluster_resolution_02d7k2,
  by="evidence_cluster_id",
  all.x=TRUE,
  sort=FALSE
)

link_resolution_02d7k2$link_resolution <- "REVIEW"
link_resolution_02d7k2$returns_to_origin_lake <- FALSE
link_resolution_02d7k2$has_external_candidate <- FALSE

for (i in seq_len(nrow(link_resolution_02d7k2))) {
  target_keys <- split_keys_02d7k2(
    link_resolution_02d7k2$all_target_keys[i]
  )
  origin_key <- paste0(
    "LAKE:",
    as.integer(link_resolution_02d7k2$lake_objectid[i])
  )

  lower <- link_resolution_02d7k2$n_flat_lower_escape_edges[i]
  external_dep <- link_resolution_02d7k2$n_external_other_depression_edges[i]
  untraced <- link_resolution_02d7k2$n_untraced_level_land_edges[i]
  edge <- isTRUE(link_resolution_02d7k2$touches_raster_edge[i])

  numeric_ok <- all(is.finite(c(lower, external_dep, untraced)))
  trace_complete <- (
    numeric_ok &&
      external_dep == 0 &&
      untraced == 0 &&
      !edge
  )

  unique_target <- length(target_keys) == 1L
  returns_origin <- (
    trace_complete &&
      lower == 0 &&
      unique_target &&
      identical(target_keys[1], origin_key)
  )

  if (!trace_complete) {
    cls <- "REVIEW"
  } else if (lower > 0) {
    cls <- "EXTERNAL_CANDIDATE"
  } else if (!unique_target) {
    cls <- "REVIEW"
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
  cluster_resolution_02d7k2,
  file.path(DIR_02,"02D7K_non_target_raised_cluster_resolution.csv"),
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
cat("Evidence clusters          :", nrow(cluster_resolution_02d7k2), "\n")
cat("Multi-component clusters   :", sum(cluster_resolution_02d7k2$n_components > 1), "\n")
cat("Internal LEVEL dep edges   :",
    sum(cluster_resolution_02d7k2$n_internal_equal_level_depression_edges), "\n")
cat("External dep edges         :",
    sum(cluster_resolution_02d7k2$n_external_other_depression_edges), "\n")
cat("Non-target links           :", nrow(link_resolution_02d7k2), "\n")
cat("Linked spill groups        :", nrow(group_resolution_02d7k2), "\n")
cat("\n--- LINK RESOLUTION ---\n")
print(table(link_resolution_02d7k2$link_resolution,useNA="ifany"))
cat("===============================================\n")

stopifnot(
  nrow(component_resolution_02d7k2) == length(component_ids_k2),
  !anyDuplicated(component_resolution_02d7k2$depression_component_id),
  all(component_resolution_02d7k2$flat_water_agrees_with_gate),
  nrow(link_resolution_02d7k2) == nrow(links_k2),
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
