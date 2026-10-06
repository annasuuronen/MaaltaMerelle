# 02D.7G - candidate evidence consolidation
# Diagnostic only: no outlet choice, pointer edits, D8, or flow accumulation.

req <- c("target_evidence","land_seed_level_02d7e","trace_zero_evidence_02d7d","group_summary_02d7f","DIR_02")
miss <- req[!vapply(req, exists, logical(1), inherits=TRUE)]
if(length(miss)) stop("02D.7G missing: ",paste(miss,collapse=", "))

ev <- target_evidence
ev$n_lower <- 0L
ev$n_level <- 0L
ev$n_lower_external <- 0L
ev$n_lower_origin <- 0L
ev$n_lower_edge <- 0L
ev$n_lower_other <- 0L
ev$level_status <- NA_character_
ev$n_level_lower_escape <- 0L
ev$n_level_water <- 0L
ev$n_level_depression <- 0L
ev$n_level_untraced <- 0L

land_ids <- ev$spill_group_id[ev$evidence_class=="LAND_ONLY"]
for(gid in land_ids){
  j <- which(ev$spill_group_id==gid)
  sx <- land_seed_level_02d7e[land_seed_level_02d7e$spill_group_id==gid,,drop=FALSE]
  lo <- sx$seed_cell[sx$level_relation=="LOWER"]
  le <- sx$seed_cell[sx$level_relation=="LEVEL"]
  tx <- trace_zero_evidence_02d7d[trace_zero_evidence_02d7d$spill_group_id==gid &
                                  trace_zero_evidence_02d7d$seed_cell %in% lo,,drop=FALSE]
  stopifnot(nrow(tx)==length(unique(lo)))
  cc <- tx$refined_terminal_class
  extc <- cc %in% c("OTHER_LAKE","RIVER_AREA","RIVER_LINE","ZERO_SAFE_OTHER",
                    "ZERO_REVIEW_MIN_LAKE_OTHER","ZERO_REVIEW_MIN_RIVER_AREA",
                    "ZERO_REVIEW_MIN_RIVER_LINE")
  origc <- cc %in% c("ORIGIN_LAKE","ZERO_SAFE_ORIGIN","ZERO_REVIEW_MIN_LAKE_ORIGIN")
  edgec <- cc %in% c("ZERO_UNMAPPED_EDGE","DOMAIN_EXIT")
  ev$n_lower[j] <- length(lo)
  ev$n_level[j] <- length(le)
  ev$n_lower_external[j] <- sum(extc)
  ev$n_lower_origin[j] <- sum(origc)
  ev$n_lower_edge[j] <- sum(edgec)
  ev$n_lower_other[j] <- sum(!(extc|origc|edgec))
  if(length(le)){
    fx <- group_summary_02d7f[group_summary_02d7f$spill_group_id==gid,,drop=FALSE]
    stopifnot(nrow(fx)==1)
    ev$level_status[j] <- fx$status
    ev$n_level_lower_escape[j] <- fx$n_lower_escape_edges
    ev$n_level_water[j] <- fx$n_level_water_edges
    ev$n_level_depression[j] <- fx$n_other_depression_edges
    ev$n_level_untraced[j] <- fx$n_untraced_level_land_edges
  }
}
ev <- ev[order(ev$lake_objectid,ev$spill_group_id),,drop=FALSE]
row.names(ev) <- NULL
write.csv(ev,file.path(DIR_02,"02D7G_candidate_evidence.csv"),row.names=FALSE)

cat("\n=== 02D.7G CANDIDATE EVIDENCE CONSOLIDATION ===\n")
cat("Groups:",nrow(ev)," LAND_ONLY:",length(land_ids),"\n")
cat("LAND groups with lower external evidence:",sum(ev$evidence_class=="LAND_ONLY" & ev$n_lower_external>0),"\n")
cat("LAND groups with level lower/water evidence:",sum(ev$evidence_class=="LAND_ONLY" & (ev$n_level_lower_escape>0|ev$n_level_water>0)),"\n")
cat("LAND groups with depression links:",sum(ev$evidence_class=="LAND_ONLY" & ev$n_level_depression>0),"\n")
cat("LEVEL untraced:",sum(ev$n_level_untraced),"\n")
stopifnot(nrow(ev)==nrow(target_evidence),!anyDuplicated(ev$spill_group_id),
          setequal(ev$spill_group_id,target_evidence$spill_group_id),
          sum(ev$n_level_untraced)==0)
cat("02D.7G HARD QA: PASS\n")
