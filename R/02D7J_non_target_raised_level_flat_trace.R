# 02D.7J - NON-TARGET RAISED LEVEL-FLAT ESCAPE TRACE
# Diagnostic only. Traces LEVEL+LAND minimum-gate receivers from 02D.7I.
# No outlet selection, pointer edits, D8 edits or flow accumulation.

req_02d7j <- c("non_target_gate_edges_02d7i","surface_storage","water_class",
               "lake_id","depression_components","cell_values","is_edge_cell","DIR_02")
miss_02d7j <- req_02d7j[!vapply(req_02d7j, exists, logical(1), inherits=TRUE)]
if (length(miss_02d7j)) stop("02D.7J missing: ", paste(miss_02d7j, collapse=", "))

tol_02d7j <- 1e-6
initial_margin_02d7j <- 250
full_ext_02d7j <- ext(surface_storage)
max_margin_02d7j <- max(xmax(full_ext_02d7j)-xmin(full_ext_02d7j),
                         ymax(full_ext_02d7j)-ymin(full_ext_02d7j))

target_02d7j <- non_target_gate_edges_02d7i[
  non_target_gate_edges_02d7i$receiver_relation=="LEVEL" &
  non_target_gate_edges_02d7i$receiver_type=="LAND",,drop=FALSE]
stopifnot(nrow(target_02d7j)>0)
keys_02d7j <- unique(target_02d7j[,c("depression_component_id","gate_level_m")])
keys_02d7j <- keys_02d7j[order(keys_02d7j$depression_component_id),,drop=FALSE]

edge_out_02d7j <- list()
group_out_02d7j <- vector("list",nrow(keys_02d7j))

for (ii in seq_len(nrow(keys_02d7j))) {
  did <- keys_02d7j$depression_component_id[ii]
  lev <- keys_02d7j$gate_level_m[ii]
  seeds <- sort(unique(target_02d7j$receiver_cell[
    target_02d7j$depression_component_id==did]))
  stopifnot(length(seeds)>0)

  seed_z <- cell_values(surface_storage,seeds)
  seed_w <- cell_values(water_class,seeds)
  seed_d <- cell_values(depression_components,seeds)
  stopifnot(all(is.finite(seed_z)), all(abs(seed_z-lev)<=tol_02d7j),
            all(!is.finite(seed_w)))

  # A LEVEL receiver already belonging to another raised component is a
  # depression link, not ordinary outside flat. Keep it as evidence only.
  seed_other_dep <- is.finite(seed_d) & seed_d != did
  n_direct_other_dep_seeds <- sum(seed_other_dep)
  seeds <- seeds[!seed_other_dep]

  if (!length(seeds)) {
    group_out_02d7j[[ii]] <- data.frame(
      depression_component_id=did,gate_level_m=lev,n_level_seeds=0L,
      n_flat_cells=0L,n_back_to_origin_edges_filtered=0L,
      n_lower_escape_edges=0L,n_level_water_edges=0L,
      n_other_depression_edges=n_direct_other_dep_seeds,
      n_untraced_level_land_edges=0L,touches_raster_edge=FALSE,
      used_margin_m=NA_real_,status="OTHER_DEPRESSION",stringsAsFactors=FALSE)
    next
  }

  sxy <- xyFromCell(surface_storage,seeds)
  xmin0<-min(sxy[,1]); xmax0<-max(sxy[,1]); ymin0<-min(sxy[,2]); ymax0<-max(sxy[,2])
  margin <- initial_margin_02d7j
  plateau <- NULL
  reaches_edge <- FALSE

  repeat {
    if (margin>=max_margin_02d7j) e<-full_ext_02d7j else
      e<-ext(max(xmin(full_ext_02d7j),xmin0-margin),min(xmax(full_ext_02d7j),xmax0+margin),
             max(ymin(full_ext_02d7j),ymin0-margin),min(ymax(full_ext_02d7j),ymax0+margin))
    ss<-crop(surface_storage,e); ww<-crop(water_class,e); dd<-crop(depression_components,e)
    flat<-ifel(abs(ss-lev)<=tol_02d7j & is.na(ww) & is.na(dd),1,NA)
    pp<-patches(flat,directions=8)
    sl<-cellFromXY(pp,sxy); sl<-sl[is.finite(sl)]
    pids<-sort(unique(cell_values(pp,sl))); pids<-pids[is.finite(pids)]
    if(!length(pids)) stop("02D.7J LEVEL seeds absent from flat for component ",did)
    pt<-as.data.frame(pp,cells=TRUE,na.rm=TRUE); names(pt)[2]<-"pid"
    sel<-pt[pt$pid %in% pids,,drop=FALSE]
    rc<-rowColFromCell(pp,sel$cell)
    touch<-any(rc[,1]==1|rc[,1]==nrow(pp)|rc[,2]==1|rc[,2]==ncol(pp))
    ee<-ext(pp)
    full<-abs(xmin(ee)-xmin(full_ext_02d7j))<=1e-8 && abs(xmax(ee)-xmax(full_ext_02d7j))<=1e-8 &&
          abs(ymin(ee)-ymin(full_ext_02d7j))<=1e-8 && abs(ymax(ee)-ymax(full_ext_02d7j))<=1e-8
    if(!touch || full) {
      gc<-cellFromXY(surface_storage,xyFromCell(pp,sel$cell))
      plateau<-sort(unique(gc[is.finite(gc)]))
      reaches_edge<-touch && full
      break
    }
    old<-margin; margin<-min(margin*2,max_margin_02d7j)
    if(margin<=old) stop("02D.7J crop cannot expand for component ",did)
  }

  stopifnot(length(plateau)>0,
            all(!is.finite(cell_values(water_class,plateau))),
            all(!is.finite(cell_values(depression_components,plateau))),
            all(abs(cell_values(surface_storage,plateau)-lev)<=tol_02d7j))

  ap0<-adjacent(surface_storage,cells=plateau,directions=8,pairs=TRUE,include=FALSE)
  inside<-ap0[,2] %in% plateau
  recv_dep0<-cell_values(depression_components,ap0[,2])
  back_origin<-is.finite(recv_dep0) & as.integer(recv_dep0)==as.integer(did)
  n_back<-sum(!inside & back_origin)
  ap<-ap0[!inside & !back_origin,,drop=FALSE]

  if(nrow(ap)) {
    rz<-cell_values(surface_storage,ap[,2]); rw<-cell_values(water_class,ap[,2])
    rl<-cell_values(lake_id,ap[,2]); rd<-cell_values(depression_components,ap[,2])
    rel<-rep("NA",nrow(ap)); fin<-is.finite(rz)
    rel[fin & rz<lev-tol_02d7j]<-"LOWER"
    rel[fin & abs(rz-lev)<=tol_02d7j]<-"LEVEL"
    rel[fin & rz>lev+tol_02d7j]<-"ABOVE"
    typ<-rep("LAND",nrow(ap)); typ[rw==1]<-"LAKE"; typ[rw==2]<-"RIVER_AREA"; typ[rw==3]<-"RIVER_LINE"
    otherdep<-is.finite(rd) & as.integer(rd)!=as.integer(did)
    et<-data.frame(depression_component_id=did,gate_level_m=lev,
      source_cell=ap[,1],receiver_cell=ap[,2],receiver_storage_z_m=rz,relation=rel,
      receiver_type=typ,receiver_lake_objectid=as.integer(rl),
      receiver_depression_component_id=as.integer(rd),
      is_lower_escape=rel=="LOWER",
      is_level_water=rel=="LEVEL" & typ!="LAND",
      is_other_depression=rel=="LEVEL" & otherdep,
      is_untraced_level_land=rel=="LEVEL" & typ=="LAND" & !otherdep,
      stringsAsFactors=FALSE)
    edge_out_02d7j[[length(edge_out_02d7j)+1L]]<-et
    nl<-sum(et$is_lower_escape,na.rm=TRUE); nw<-sum(et$is_level_water,na.rm=TRUE)
    nd<-n_direct_other_dep_seeds+sum(et$is_other_depression,na.rm=TRUE)
    nu<-sum(et$is_untraced_level_land,na.rm=TRUE)
  } else { nl<-nw<-nu<-0L; nd<-n_direct_other_dep_seeds }

  status<-if(nu>0)"TRACE_INCOMPLETE" else if(nl>0)"LOWER_ESCAPE" else
    if(nw>0)"LEVEL_WATER_ESCAPE" else if(nd>0)"OTHER_DEPRESSION" else
    if(reaches_edge || any(is_edge_cell(surface_storage,plateau)))"CENSORED_BY_RASTER_EDGE" else "NO_ESCAPE"

  group_out_02d7j[[ii]]<-data.frame(
    depression_component_id=did,gate_level_m=lev,n_level_seeds=length(seeds),
    n_flat_cells=length(plateau),n_back_to_origin_edges_filtered=n_back,
    n_lower_escape_edges=nl,n_level_water_edges=nw,n_other_depression_edges=nd,
    n_untraced_level_land_edges=nu,
    touches_raster_edge=reaches_edge || any(is_edge_cell(surface_storage,plateau)),
    used_margin_m=margin,status=status,stringsAsFactors=FALSE)
}

non_target_flat_summary_02d7j<-do.call(rbind,group_out_02d7j)
row.names(non_target_flat_summary_02d7j)<-NULL
if(length(edge_out_02d7j)) {
  non_target_flat_edges_02d7j<-do.call(rbind,edge_out_02d7j)
  row.names(non_target_flat_edges_02d7j)<-NULL
} else non_target_flat_edges_02d7j<-data.frame()

write.csv(non_target_flat_summary_02d7j,
  file.path(DIR_02,"02D7J_non_target_raised_level_flat_summary.csv"),row.names=FALSE)
write.csv(non_target_flat_edges_02d7j,
  file.path(DIR_02,"02D7J_non_target_raised_level_flat_edges.csv"),row.names=FALSE)

cat("\n=== 02D.7J NON-TARGET RAISED LEVEL-FLAT ESCAPE TRACE ===\n")
cat("Target components             :",nrow(non_target_flat_summary_02d7j),"\n")
cat("Untraced LEVEL-land edges     :",sum(non_target_flat_summary_02d7j$n_untraced_level_land_edges),"\n")
cat("Back-to-origin edges filtered :",sum(non_target_flat_summary_02d7j$n_back_to_origin_edges_filtered),"\n")
cat("\n--- STATUS ---\n"); print(table(non_target_flat_summary_02d7j$status,useNA="ifany"))
cat("==========================================================\n")

stopifnot(
  nrow(non_target_flat_summary_02d7j)==nrow(keys_02d7j),
  !anyDuplicated(non_target_flat_summary_02d7j$depression_component_id),
  setequal(non_target_flat_summary_02d7j$depression_component_id,keys_02d7j$depression_component_id),
  sum(non_target_flat_summary_02d7j$n_untraced_level_land_edges)==0
)
cat("\n02D.7J HARD QA: PASS\n")
