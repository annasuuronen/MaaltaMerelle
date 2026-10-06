# 02D.7F - NON-RAISED LEVEL-FLAT ESCAPE TRACE
# Diagnostic only: no outlet selection, pointer edits, D8 or flow accumulation.

required_02d7f <- c("land_seed_level_02d7e","surface_storage","water_class",
                   "lake_id","depression_components","cell_values","is_edge_cell","DIR_02")
miss_02d7f <- required_02d7f[!vapply(required_02d7f, exists, logical(1), inherits=TRUE)]
if (length(miss_02d7f)) stop("02D.7F missing required objects: ", paste(miss_02d7f, collapse=", "))

tol_02d7f <- 1e-6
initial_margin_02d7f <- 250
full_ext_02d7f <- ext(surface_storage)
max_margin_02d7f <- max(xmax(full_ext_02d7f)-xmin(full_ext_02d7f),
                         ymax(full_ext_02d7f)-ymin(full_ext_02d7f))

target_02d7f <- land_seed_level_02d7e[land_seed_level_02d7e$level_relation=="LEVEL",,drop=FALSE]
stopifnot(nrow(target_02d7f)>0)
keys_02d7f <- unique(target_02d7f[,c("spill_group_id","lake_objectid","spill_level_m")])
keys_02d7f <- keys_02d7f[order(keys_02d7f$lake_objectid,keys_02d7f$spill_group_id),,drop=FALSE]

edge_out_02d7f <- list()
group_out_02d7f <- vector("list",nrow(keys_02d7f))

for (ii in seq_len(nrow(keys_02d7f))) {
  gid <- keys_02d7f$spill_group_id[ii]
  lid <- keys_02d7f$lake_objectid[ii]
  lev <- keys_02d7f$spill_level_m[ii]
  seeds <- sort(unique(target_02d7f$seed_cell[target_02d7f$spill_group_id==gid]))
  stopifnot(length(seeds)>0)

  seed_z <- cell_values(surface_storage,seeds)
  seed_w <- cell_values(water_class,seeds)
  seed_d <- cell_values(depression_components,seeds)
  stopifnot(
    all(is.finite(seed_z)),
    all(abs(seed_z-lev)<=tol_02d7f),
    all(!is.finite(seed_w))
  )

  # LEVEL LAND seeds that belong to any raised depression are
  # explicit depression links, not ordinary outside-flat cells.
  # This mirrors the already validated 02D.6 treatment of gate
  # receivers and prevents tracing through raised depressions.
  seed_other_dep <- is.finite(seed_d)
  n_direct_other_dep_seeds <- sum(seed_other_dep)
  seeds <- seeds[!seed_other_dep]

  if (!length(seeds)) {
    group_out_02d7f[[ii]] <- data.frame(
      spill_group_id=gid,lake_objectid=lid,spill_level_m=lev,
      n_level_seeds=0L,n_flat_cells=0L,n_back_to_origin_edges_filtered=0L,
      n_lower_escape_edges=0L,n_level_water_edges=0L,
      n_other_depression_edges=n_direct_other_dep_seeds,
      n_untraced_level_land_edges=0L,touches_raster_edge=FALSE,
      used_margin_m=NA_real_,status="OTHER_DEPRESSION",
      stringsAsFactors=FALSE
    )
    next
  }

  sxy <- xyFromCell(surface_storage,seeds)
  xmin0<-min(sxy[,1]); xmax0<-max(sxy[,1]); ymin0<-min(sxy[,2]); ymax0<-max(sxy[,2])
  margin <- initial_margin_02d7f
  plateau <- NULL
  reaches_edge <- FALSE

  repeat {
    if (margin>=max_margin_02d7f) e<-full_ext_02d7f else
      e<-ext(max(xmin(full_ext_02d7f),xmin0-margin),min(xmax(full_ext_02d7f),xmax0+margin),
             max(ymin(full_ext_02d7f),ymin0-margin),min(ymax(full_ext_02d7f),ymax0+margin))
    ss<-crop(surface_storage,e); ww<-crop(water_class,e); dd<-crop(depression_components,e)
    flat<-ifel(abs(ss-lev)<=tol_02d7f & is.na(ww) & is.na(dd),1,NA)
    pp<-patches(flat,directions=8)
    sl<-cellFromXY(pp,sxy); sl<-sl[is.finite(sl)]
    pids<-sort(unique(cell_values(pp,sl))); pids<-pids[is.finite(pids)]
    if(!length(pids)) stop("02D.7F LEVEL seeds absent from flat for group ",gid)
    pt<-as.data.frame(pp,cells=TRUE,na.rm=TRUE); names(pt)[2]<-"pid"
    sel<-pt[pt$pid %in% pids,,drop=FALSE]
    rc<-rowColFromCell(pp,sel$cell)
    touch<-any(rc[,1]==1|rc[,1]==nrow(pp)|rc[,2]==1|rc[,2]==ncol(pp))
    ee<-ext(pp)
    full<-abs(xmin(ee)-xmin(full_ext_02d7f))<=1e-8 && abs(xmax(ee)-xmax(full_ext_02d7f))<=1e-8 &&
          abs(ymin(ee)-ymin(full_ext_02d7f))<=1e-8 && abs(ymax(ee)-ymax(full_ext_02d7f))<=1e-8
    if(!touch || full) {
      gc<-cellFromXY(surface_storage,xyFromCell(pp,sel$cell))
      plateau<-sort(unique(gc[is.finite(gc)]))
      reaches_edge<-touch && full
      break
    }
    old<-margin; margin<-min(margin*2,max_margin_02d7f)
    if(margin<=old) stop("02D.7F crop cannot expand for group ",gid)
  }

  stopifnot(length(plateau)>0,
            all(!is.finite(cell_values(water_class,plateau))),
            all(!is.finite(cell_values(depression_components,plateau))),
            all(abs(cell_values(surface_storage,plateau)-lev)<=tol_02d7f))

  ap0<-adjacent(surface_storage,cells=plateau,directions=8,pairs=TRUE,include=FALSE)
  inside<-ap0[,2] %in% plateau
  recv_lake0<-cell_values(lake_id,ap0[,2])
  back_origin<-is.finite(recv_lake0) & as.integer(recv_lake0)==as.integer(lid)
  n_back<-sum(!inside & back_origin)
  ap<-ap0[!inside & !back_origin,,drop=FALSE]

  if(nrow(ap)) {
    rz<-cell_values(surface_storage,ap[,2]); rw<-cell_values(water_class,ap[,2])
    rl<-cell_values(lake_id,ap[,2]); rd<-cell_values(depression_components,ap[,2])
    rel<-rep("NA",nrow(ap)); fin<-is.finite(rz)
    rel[fin & rz<lev-tol_02d7f]<-"LOWER"
    rel[fin & abs(rz-lev)<=tol_02d7f]<-"LEVEL"
    rel[fin & rz>lev+tol_02d7f]<-"ABOVE"
    typ<-rep("LAND",nrow(ap)); typ[rw==1]<-"LAKE"; typ[rw==2]<-"RIVER_AREA"; typ[rw==3]<-"RIVER_LINE"
    otherdep<-is.finite(rd)
    et<-data.frame(spill_group_id=gid,lake_objectid=lid,spill_level_m=lev,
      source_cell=ap[,1],receiver_cell=ap[,2],receiver_storage_z_m=rz,relation=rel,
      receiver_type=typ,receiver_lake_objectid=as.integer(rl),
      receiver_depression_component_id=as.integer(rd),
      is_lower_escape=rel=="LOWER",
      is_level_water=rel=="LEVEL" & typ!="LAND",
      is_other_depression=rel=="LEVEL" & otherdep,
      is_untraced_level_land=rel=="LEVEL" & typ=="LAND" & !otherdep,
      stringsAsFactors=FALSE)
    edge_out_02d7f[[length(edge_out_02d7f)+1L]]<-et
    nl<-sum(et$is_lower_escape,na.rm=TRUE); nw<-sum(et$is_level_water,na.rm=TRUE)
    nd<-n_direct_other_dep_seeds + sum(et$is_other_depression,na.rm=TRUE); nu<-sum(et$is_untraced_level_land,na.rm=TRUE)
  } else { nl<-nw<-nu<-0L; nd<-n_direct_other_dep_seeds }

  status<-if(nu>0)"TRACE_INCOMPLETE" else if(nl>0)"LOWER_ESCAPE" else if(nw>0)"LEVEL_WATER_ESCAPE" else if(nd>0)"OTHER_DEPRESSION" else if(reaches_edge || any(is_edge_cell(surface_storage,plateau)))"CENSORED_BY_RASTER_EDGE" else "NO_ESCAPE"
  group_out_02d7f[[ii]]<-data.frame(spill_group_id=gid,lake_objectid=lid,spill_level_m=lev,
    n_level_seeds=length(seeds),n_flat_cells=length(plateau),n_back_to_origin_edges_filtered=n_back,
    n_lower_escape_edges=nl,n_level_water_edges=nw,n_other_depression_edges=nd,
    n_untraced_level_land_edges=nu,touches_raster_edge=reaches_edge || any(is_edge_cell(surface_storage,plateau)),
    used_margin_m=margin,status=status,stringsAsFactors=FALSE)
}

group_summary_02d7f<-do.call(rbind,group_out_02d7f); row.names(group_summary_02d7f)<-NULL
if(length(edge_out_02d7f)) { escape_edges_02d7f<-do.call(rbind,edge_out_02d7f); row.names(escape_edges_02d7f)<-NULL } else escape_edges_02d7f<-data.frame()

lake_ids_02d7f<-sort(unique(group_summary_02d7f$lake_objectid))
lake_summary_02d7f<-do.call(rbind,lapply(lake_ids_02d7f,function(lid){
  x<-group_summary_02d7f[group_summary_02d7f$lake_objectid==lid,,drop=FALSE]
  data.frame(lake_objectid=lid,n_groups=nrow(x),n_lower=sum(x$n_lower_escape_edges>0),
    n_level_water=sum(x$n_level_water_edges>0),n_other_depression=sum(x$n_other_depression_edges>0),
    n_edge=sum(x$touches_raster_edge),n_untraced=sum(x$n_untraced_level_land_edges),
    stringsAsFactors=FALSE)
}))
write.csv(group_summary_02d7f,file.path(DIR_02,"02D7F_nonraised_level_flat_group_summary.csv"),row.names=FALSE)
write.csv(escape_edges_02d7f,file.path(DIR_02,"02D7F_nonraised_level_flat_escape_edges.csv"),row.names=FALSE)
write.csv(lake_summary_02d7f,file.path(DIR_02,"02D7F_nonraised_level_flat_lake_summary.csv"),row.names=FALSE)

cat("\n=== 02D.7F NON-RAISED LEVEL-FLAT ESCAPE TRACE ===\n")
cat("Target groups                 :",nrow(group_summary_02d7f),"\n")
cat("Target lakes                  :",length(lake_ids_02d7f),"\n")
cat("Untraced LEVEL-land edges     :",sum(group_summary_02d7f$n_untraced_level_land_edges),"\n")
cat("Back-to-origin edges filtered :",sum(group_summary_02d7f$n_back_to_origin_edges_filtered),"\n")
cat("\n--- STATUS ---\n"); print(table(group_summary_02d7f$status,useNA="ifany"))
cat("===================================================\n")
stopifnot(nrow(group_summary_02d7f)==nrow(keys_02d7f),
          !anyDuplicated(group_summary_02d7f$spill_group_id),
          sum(group_summary_02d7f$n_untraced_level_land_edges)==0)
cat("\n02D.7F HARD QA: PASS\n")
