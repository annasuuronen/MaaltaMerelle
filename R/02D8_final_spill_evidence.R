# 02D.8: final candidate evidence, NOT outlet selection or routing.
stopifnot(exists("target_evidence"),exists("ev"),exists("links_02d7h"),
          exists("link_resolution_02d7k2"),exists("DIR_02"))
x <- target_evidence
t <- ev
stopifnot(nrow(x)>0,!anyDuplicated(x$spill_group_id),
          !anyDuplicated(t$spill_group_id),
          setequal(x$spill_group_id,t$spill_group_id))
m <- match(x$spill_group_id,t$spill_group_id)
t <- t[m,,drop=FALSE]
stopifnot(all(x$lake_objectid==t$lake_objectid),
          all(x$evidence_class %in%
            c("LOWER_OTHER_LAKE","RIVER_CONTACT","MULTI_WATER_CONTACT",
              "LAND_ONLY","EDGE_CASE")))
count_names <- c("n_lower_external","n_lower_other","n_lower_edge",
                 "n_level_lower_escape","n_level_water","n_level_depression",
                 "n_level_untraced")
stopifnot(all(is.finite(as.matrix(t[,count_names,drop=FALSE]))),
          all(as.matrix(t[,count_names,drop=FALSE])>=0))
lk <- links_02d7h
nr <- link_resolution_02d7k2
key <- function(z) paste(z$spill_group_id,z$lake_objectid,
                          z$depression_component_id,z$link_source,sep=":")
stopifnot(!anyDuplicated(key(lk)),!anyDuplicated(key(nr)),
          all(lk$spill_group_id %in% x$spill_group_id),
          !anyNA(lk$needs_non_target_review),
          !anyNA(lk$has_known_external_escape))
lk$terminal_class <- NA_character_
nt <- which(lk$needs_non_target_review)
if(length(nt)) {
  ix <- match(key(lk[nt,,drop=FALSE]),key(nr))
  stopifnot(!anyNA(ix))
  lk$terminal_class[nt] <- nr$link_resolution[ix]
  stopifnot(!anyNA(lk$terminal_class[nt]),
            all(lk$terminal_class[nt] %in%
              c("ORIGIN_RETURN_ONLY","EXTERNAL_CANDIDATE","REVIEW")))
}
out <- x[,c("spill_group_id","lake_objectid","spill_level_m",
            "evidence_class"),drop=FALSE]
out$n_direct_water_groups <- as.integer(out$evidence_class %in%
  c("LOWER_OTHER_LAKE","RIVER_CONTACT","MULTI_WATER_CONTACT"))
out$n_lower_land_external <- t$n_lower_external
out$n_level_land_lower_escape <- t$n_level_lower_escape
out$n_level_water_contact <- t$n_level_water
out$n_raised_links <- 0L
out$n_raised_external_evidence <- 0L
out$n_raised_origin_return <- 0L
out$n_raised_review <- 0L
for(i in seq_len(nrow(out))) {
  z <- lk[lk$spill_group_id==out$spill_group_id[i],,drop=FALSE]
  out$n_raised_links[i] <- nrow(z)
  if(!nrow(z)) next
  non_target <- z$needs_non_target_review
  out$n_raised_external_evidence[i] <- sum(
    (!non_target & z$has_known_external_escape) |
    (non_target & z$terminal_class %in% "EXTERNAL_CANDIDATE"))
  out$n_raised_origin_return[i] <- sum(
    non_target & z$terminal_class %in% "ORIGIN_RETURN_ONLY")
  out$n_raised_review[i] <- sum(
    (!non_target & !z$has_known_external_escape) |
    (non_target & z$terminal_class %in% "REVIEW"))
}
out$has_external_evidence <- (
  out$n_direct_water_groups + out$n_lower_land_external +
  out$n_level_land_lower_escape + out$n_level_water_contact +
  out$n_raised_external_evidence > 0)
out$needs_review <- (
  out$evidence_class=="EDGE_CASE" |
  t$n_lower_other>0 | t$n_lower_edge>0 |
  t$n_level_untraced>0 | out$n_raised_review>0 |
  (t$n_level_depression>0 & out$n_raised_links==0))
out$evidence_status <- ifelse(out$needs_review,"REVIEW_REQUIRED",
  ifelse(out$has_external_evidence,"EXTERNAL_EVIDENCE","NO_EXTERNAL_EVIDENCE"))
out$outlet_selection <- "UNASSIGNED"
out <- out[order(out$lake_objectid,out$spill_group_id),,drop=FALSE]
rownames(out) <- NULL
stopifnot(nrow(out)==nrow(x),!anyDuplicated(out$spill_group_id),
          all(out$outlet_selection=="UNASSIGNED"),!anyNA(out$evidence_status))
write.csv(out,file.path(DIR_02,"02D8_final_spill_evidence.csv"),row.names=FALSE)
cat("\n=== 02D.8 FINAL CANDIDATE EVIDENCE (NO OUTLET SELECTION) ===\n")
print(table(out$evidence_status,useNA="ifany"))
cat("Lakes with multiple lowest-spill groups:",
    sum(table(out$lake_objectid)>1), "\n")
cat("02D.8 HARD QA: PASS\n")
