# 02D.7H - NON-RAISED -> RAISED DEPRESSION LINK INVENTORY
# Diagnostic only: identify the actual raised components reached by
# non-raised LEVEL evidence. No outlet selection or routing edits.

req_02d7h <- c(
  "target_02d7f","escape_edges_02d7f","depression_components",
  "dep_escape_summary","dep_flat_summary","cell_values","DIR_02"
)
miss_02d7h <- req_02d7h[!vapply(req_02d7h, exists, logical(1), inherits=TRUE)]
if (length(miss_02d7h)) stop("02D.7H missing: ", paste(miss_02d7h, collapse=", "))

# Direct LEVEL seeds that are themselves in a raised component.
seed_dep_02d7h <- cell_values(depression_components, target_02d7f$seed_cell)
direct_02d7h <- data.frame(
  spill_group_id=target_02d7f$spill_group_id,
  lake_objectid=target_02d7f$lake_objectid,
  depression_component_id=as.integer(seed_dep_02d7h),
  link_source="LEVEL_SEED",
  stringsAsFactors=FALSE
)
direct_02d7h <- direct_02d7h[is.finite(direct_02d7h$depression_component_id),,drop=FALSE]

# Raised components met at the boundary of a traced outside flat.
edge_02d7h <- data.frame()
if (nrow(escape_edges_02d7f)) {
  z <- escape_edges_02d7f[
    escape_edges_02d7f$is_other_depression %in% TRUE &
      is.finite(escape_edges_02d7f$receiver_depression_component_id),
    ,drop=FALSE
  ]
  if (nrow(z)) {
    edge_02d7h <- data.frame(
      spill_group_id=z$spill_group_id,
      lake_objectid=z$lake_objectid,
      depression_component_id=as.integer(z$receiver_depression_component_id),
      link_source="FLAT_BOUNDARY",
      stringsAsFactors=FALSE
    )
  }
}

links_02d7h <- unique(rbind(direct_02d7h, edge_02d7h))
links_02d7h <- links_02d7h[
  order(links_02d7h$lake_objectid,links_02d7h$spill_group_id,
        links_02d7h$depression_component_id,links_02d7h$link_source),
  ,drop=FALSE
]
row.names(links_02d7h) <- NULL

stopifnot(nrow(links_02d7h)>0)

# Every linked component must be a known raised component with gate evidence.
m_dep <- match(links_02d7h$depression_component_id,
               dep_escape_summary$depression_component_id)
stopifnot(all(!is.na(m_dep)))

links_02d7h$groups_direct_lower <-
  dep_escape_summary$groups_direct_lower[m_dep]
links_02d7h$groups_direct_water <-
  dep_escape_summary$groups_direct_water[m_dep]
links_02d7h$all_groups_level_land_only <-
  dep_escape_summary$all_groups_level_land_only[m_dep]

# For all-level raised components, attach the already validated 02D.6
# terminal evidence. Components with a direct lower/water gate do not
# require a 02D.6 row.
links_02d7h$flat_status <- NA_character_
links_02d7h$n_flat_lower_escape_edges <- 0L
links_02d7h$n_flat_level_water_edges <- 0L
links_02d7h$n_flat_other_depression_edges <- 0L
links_02d7h$n_flat_untraced_level_land_edges <- 0L

for (i in seq_len(nrow(links_02d7h))) {
  if (isTRUE(links_02d7h$all_groups_level_land_only[i])) {
    j <- match(links_02d7h$depression_component_id[i],
               dep_flat_summary$depression_component_id)
    stopifnot(!is.na(j))
    links_02d7h$flat_status[i] <- dep_flat_summary$status[j]
    links_02d7h$n_flat_lower_escape_edges[i] <-
      dep_flat_summary$n_lower_escape_edges[j]
    links_02d7h$n_flat_level_water_edges[i] <-
      dep_flat_summary$n_level_water_edges[j]
    links_02d7h$n_flat_other_depression_edges[i] <-
      dep_flat_summary$n_other_depression_edges[j]
    links_02d7h$n_flat_untraced_level_land_edges[i] <-
      dep_flat_summary$n_untraced_level_land_edges[j]
  }
}

links_02d7h$has_known_external_escape <- (
  links_02d7h$groups_direct_lower > 0 |
  links_02d7h$groups_direct_water > 0 |
  links_02d7h$n_flat_lower_escape_edges > 0 |
  links_02d7h$n_flat_level_water_edges > 0
)
links_02d7h$links_onward_to_depression <-
  links_02d7h$n_flat_other_depression_edges > 0
links_02d7h$needs_link_chain_review <- (
  !links_02d7h$has_known_external_escape &
  links_02d7h$links_onward_to_depression
)

group_ids_02d7h <- sort(unique(links_02d7h$spill_group_id))
group_links_02d7h <- do.call(rbind,lapply(group_ids_02d7h,function(gid){
  x <- links_02d7h[links_02d7h$spill_group_id==gid,,drop=FALSE]
  data.frame(
    spill_group_id=gid,
    lake_objectid=x$lake_objectid[1],
    n_linked_components=length(unique(x$depression_component_id)),
    n_links_with_known_external_escape=sum(x$has_known_external_escape),
    n_links_needing_chain_review=sum(x$needs_link_chain_review),
    all_links_have_known_external_escape=all(x$has_known_external_escape),
    stringsAsFactors=FALSE
  )
}))
row.names(group_links_02d7h) <- NULL

write.csv(links_02d7h,
          file.path(DIR_02,"02D7H_nonraised_depression_links.csv"),
          row.names=FALSE)
write.csv(group_links_02d7h,
          file.path(DIR_02,"02D7H_nonraised_depression_link_group_summary.csv"),
          row.names=FALSE)

cat("\n=== 02D.7H NON-RAISED -> RAISED DEPRESSION LINKS ===\n")
cat("Linked LAND groups             :",nrow(group_links_02d7h),"\n")
cat("Unique raised components       :",length(unique(links_02d7h$depression_component_id)),"\n")
cat("Links with external escape     :",sum(links_02d7h$has_known_external_escape),"\n")
cat("Links needing chain review     :",sum(links_02d7h$needs_link_chain_review),"\n")
cat("Raised flat untraced LEVEL     :",sum(links_02d7h$n_flat_untraced_level_land_edges),"\n")

stopifnot(
  !anyDuplicated(links_02d7h[,c("spill_group_id","depression_component_id","link_source")]),
  all(links_02d7h$n_flat_untraced_level_land_edges==0),
  all(group_links_02d7h$n_linked_components>0)
)
cat("02D.7H HARD QA: PASS\n")
