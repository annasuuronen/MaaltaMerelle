#!/usr/bin/env Rscript
here<-dirname(normalizePath(sub("^--file=","",grep("^--file=",commandArgs(),value=TRUE))))
root<-dirname(here)
source(file.path(root,"count_core.R"));source(file.path(here,"fixtures_oracle.R"))
checks<-0L;cases<-0L;stops<-list()
check<-function(ok,label="check") { checks<<-checks+1L;if(!isTRUE(ok))stop("02G3_TEST_FAILURE: ",label,call.=FALSE) }
case<-function(name,expr) { force(expr);cases<<-cases+1L;cat("PASS:",name,"\n") }
verify<-function(f,pair) {
  before<-serialize(pair,NULL);r<-complete_local_dag_counts(pair$graph,pair$evidence)
  check(identical(before,serialize(pair,NULL)),"input graph/census immutable")
  ref<-explicit_source_oracle(f);expected<-vapply(ref$sets,length,integer(1));i<-match(names(expected),r$nodes$cell_uid)
  check(setequal(r$nodes$cell_uid,names(expected)),"complete global node identity")
  check(identical(as.numeric(r$nodes$local_upstream_cells[i]),as.numeric(expected)),"independent explicit source sets match all numeric counts")
  check(identical(as.numeric(r$nodes$local_upstream_area_m2[i]),4*as.numeric(expected)),"exact four-square-metre source units")
  check(identical(r$nodes$source_uid[!is.na(r$nodes$source_uid)],truth_uid(sort(f$land),f)),"land sources only")
  for(uid in names(ref$endings)) check(r$nodes$first_water_uid[match(uid,r$nodes$cell_uid)]==ref$endings[[uid]],"independent first-water identity")
  check(sum(r$first_water$local_upstream_cells)==length(f$land),"first-water partition, not sum of all node counts")
  check(r$balance$n_owned_land_sources==length(f$land)&&r$balance$n_first_water_sources==length(f$land)&&r$balance$n_unresolved==0&&r$balance$n_approved_exports==0)
  check(all(is.na(r$nodes$total_upstream_cells))&&all(is.na(r$nodes$total_upstream_area_m2))&&r$external_import=="UNKNOWN")
  check(r$result_kind=="LOCAL_COMPLETE_DAG_NUMERIC"&&r$membership_mode=="NOT_MATERIALIZED"&&is.null(r$source_sets)&&is.null(r$paths))
  check(r$channel_threshold_cells==10000L&&r$channel_threshold_area_m2==40000)
  check(r$hydrological_validation=="NOT_ASSESSED"&&r$channel_interpretation=="NOT_ASSESSED"&&r$MODERATE=="REVIEW_REQUIRED"&&r$NATIONAL=="LOCKED")
  check(identical(r$identity,pair$graph$identity)&&identical(r$evidence_identity,pair$evidence$identity))
  r
}
expect_stop<-function(code,pair,label=code) {
  snapshot<-serialize(pair,NULL)
  e<-tryCatch(complete_local_dag_counts(pair$graph,pair$evidence),local_dag_stop=identity)
  check(inherits(e,"local_dag_stop")&&e$reason_code==code,paste(label,"explicit STOP code"))
  check(identical(snapshot,serialize(pair,NULL)),"STOP does not mutate inputs")
  check(e$status=="STOP"&&e$result_kind=="NO_NUMERIC_RESULT"&&is.null(e$nodes)&&is.null(e$first_water),"no partial full numeric result")
  check(e$identity$run_id==pair$graph$identity$run_id&&e$identity$graph_version==pair$graph$identity$graph_version,"STOP provenance retained")
  check(e$hydrological_validation=="NOT_ASSESSED"&&e$channel_interpretation=="NOT_ASSESSED"&&e$MODERATE=="REVIEW_REQUIRED"&&e$NATIONAL=="LOCKED")
  stops[[length(stops)+1L]]<<-data.frame(case=label,status=e$status,reason_code=e$reason_code,
    run_id=e$identity$run_id,graph_version=e$identity$graph_version)
}
main<-truth_fixture();base<-inputs(main)
chain<-truth_fixture(1L,4L,1:3,rbind(c(1,2,2),c(2,3,2),c(3,4,2)))
chain_input<-inputs(chain,truth_cores(chain))
case("chain counts include each land unit once, water contributes zero", {
  r<-verify(chain,chain_input)
  check(identical(r$nodes$local_upstream_cells,c(1,2,3,3))&&sum(r$nodes$local_upstream_cells)!=3)
})
case("C1 two tributaries merge without double counting", {
  f<-truth_fixture(3L,3L,c(1L,3L,5L),rbind(c(1,5,4),c(3,5,16),c(5,8,8)))
  r<-verify(f,inputs(f,truth_cores(f)));check(r$nodes$local_upstream_cells[5]==3&&r$nodes$local_upstream_area_m2[5]==12)
})
case("27-position 11-source three-tributary complete local graph", {
  r<-verify(main,base);check(r$balance$local_source_area_m2==44&&r$nodes$local_upstream_cells[18]==11)
  write.csv(r$nodes,file.path(root,"example_nodes.csv"),row.names=FALSE)
  write.csv(r$first_water,file.path(root,"example_first_water.csv"),row.names=FALSE)
})
case("several first waters retain classes and partition sources", {
  f<-truth_fixture(3L,5L,c(1,3,6:10),rbind(c(1,7,4),c(3,8,8),c(6,7,2),c(7,8,2),c(8,13,8),c(9,10,2),c(10,15,8)))
  f$water_class[13]<-2;f$water_class[15]<-3
  r<-verify(f,inputs(f,truth_cores(f)))
  check(r$nodes$local_upstream_cells[13]==5&&r$nodes$local_upstream_cells[15]==2&&all(is.na(r$first_water$source_uid)))
})
case("all eight Whitebox directions are checked on global cell identities", {
  for(j in seq_along(c(1,2,4,8,16,32,64,128))) {
    target<-c(3,6,9,8,7,4,1,2)[j];code<-c(1,2,4,8,16,32,64,128)[j]
    f<-truth_fixture(3L,3L,5L,matrix(c(5,target,code),ncol=3))
    r<-verify(f,inputs(f,truth_cores(f)));check(r$nodes$local_upstream_cells[target]==1)
  }
})
case("node, edge, core, census and inventory row order do not affect results", {
  expected<-verify(main,base);set.seed(20261021)
  for(j in 1:4) {
    x<-base
    x$graph$nodes<-x$graph$nodes[sample.int(nrow(x$graph$nodes)),]
    x$graph$edges<-x$graph$edges[sample.int(nrow(x$graph$edges)),]
    x$graph$cores<-x$graph$cores[sample.int(nrow(x$graph$cores)),]
    x$evidence$observations<-x$evidence$observations[sample.int(nrow(x$evidence$observations)),]
    x$evidence$source_inventory<-x$evidence$source_inventory[sample.int(nrow(x$evidence$source_inventory)),]
    x$evidence$available_cores<-rev(x$evidence$available_cores)
    check(identical(expected,verify(main,x)),"semantic deterministic result")
  }
})
case("water outgoing zero, missing or invalid code is never followed", {
  expected<-verify(main,base)
  for(code in c(0,NA_real_,3)) {
    f<-main;f$pointer[18]<-code
    check(identical(expected,verify(f,inputs(f))),"first water invariant")
  }
})
case("schema field order is immaterial and output metadata is canonical", {
  expected<-verify(main,base);x<-base
  for(key in c("nodes","edges","cores"))x$graph[[key]]<-x$graph[[key]][,rev(names(x$graph[[key]])),drop=FALSE]
  for(key in c("observations","source_inventory"))x$evidence[[key]]<-x$evidence[[key]][,rev(names(x$evidence[[key]])),drop=FALSE]
  x$graph$grid<-rev(x$graph$grid);x$graph$identity<-rev(x$graph$identity);x$evidence$identity<-rev(x$evidence$identity)
  x$graph<-rev(x$graph);x$evidence<-rev(x$evidence);before<-serialize(x,NULL)
  check(identical(expected,complete_local_dag_counts(x$graph,x$evidence)))
  check(identical(before,serialize(x,NULL)))
})
case("zero-source known-water domain has typed zero counts", {
  f<-truth_fixture(1L,1L,integer(),matrix(numeric(),ncol=3));r<-verify(f,inputs(f,truth_cores(f)))
  check(r$nodes$local_upstream_cells==0&&r$nodes$local_upstream_area_m2==0&&r$balance$n_owned_land_sources==0)
})
case("a cell DAG may cross A-B-A without a cell cycle", {
  f<-truth_fixture(3L,2L,c(1,2,3),rbind(c(1,2,2),c(2,3,16),c(3,5,8)))
  r<-verify(f,inputs(f,truth_cores(f,c(1,2,3))));check(r$nodes$local_upstream_cells[5]==3)
})
case("C2 censored unions and a bare complete flag cannot enter this result mode", {
  x<-chain_input;x$evidence<-NULL;expect_stop("MISSING_EVIDENCE",x,"C2 union without independent census")
  x<-chain_input;x$graph$complete<-TRUE;expect_stop("GRAPH_FIELDS",x,"C2 bare complete=true")
  x<-chain_input;x$graph$input_kind<-"TRACE_EDGE_UNION";expect_stop("GRAPH_ORIGIN",x,"C2 trace-edge union")
  x<-chain_input;x$evidence$observation_status<-"STEP_LIMIT";expect_stop("CENSORED_EVIDENCE",x,"C2 per-source step limit")
  x<-chain_input;x$evidence$input_kind<-"OBSERVED_SOURCE_TRACES";expect_stop("CENSUS_CONTRACT",x,"C2 wrong observation origin")
  x<-chain_input;x$evidence$observation_status<-TRUE;expect_stop("CENSUS_CONTRACT",x,"boolean is not independent observation evidence")
  # Manually supplied old observed prefixes are audit expectations, never SUT
  # inputs. K=1 yields only c at water; a fresh independently complete graph
  # has three local sources. The two result contracts remain distinct.
  observed_prefixes<-list(c(1L,2L),c(2L,3L),c(3L,4L))
  check(sum(vapply(observed_prefixes,function(p)4L%in%p,logical(1)))==1L)
  check(verify(chain,chain_input)$nodes$local_upstream_cells[4]==3)
})
case("C3 cycle and inconsistent DAG structure stop before numeric output", {
  f<-truth_fixture(1L,3L,c(1,2),rbind(c(1,2,2),c(2,1,32)))
  expect_stop("CYCLE",inputs(f,truth_cores(f)),"C3 two-cell cycle")
  x<-base;x$graph$edges<-rbind(x$graph$edges,x$graph$edges[1,]);expect_stop("DUPLICATE_SUCCESSOR",x,"C6 repeated same edge")
  x<-base;extra<-x$graph$edges[1,];extra$to_uid<-truth_uid(12,main);x$graph$edges<-rbind(x$graph$edges,extra)
  expect_stop("DUPLICATE_SUCCESSOR",x,"two successors")
  x<-base;x$graph$edges<-x$graph$edges[-1,];expect_stop("EDGE_COVERAGE",x,"missing source edge")
  x<-base;x$graph$edges$to_uid[1]<-"SYNTHETIC-02G3:999:999";expect_stop("MISSING_TARGET",x)
  x<-base;x$graph$edges$d8_code[1]<-4;expect_stop("D8_POINTER_CONFLICT",x)
  x<-base;x$graph$edges$to_uid[1]<-truth_uid(12,main);expect_stop("D8_GEOMETRY",x)
  x<-base;x$graph$edges<-rbind(x$graph$edges,data.frame(from_uid=truth_uid(18,main),to_uid=truth_uid(19,main),d8_code=2))
  expect_stop("EDGE_COVERAGE",x,"no water outgoing edge")
})
case("C4 missing neighbour, halo or owned observation cannot be replaced", {
  x<-base;x$evidence$available_cores<-c("A","C");expect_stop("MISSING_CORE",x,"C4 missing B")
  x<-base;obs<-x$evidence$observations;drop<-which(obs$observer_core=="A"&obs$cell_uid==truth_uid(4,main))[1]
  x$evidence$observations<-obs[-drop,];expect_stop("MISSING_REQUIRED_HALO",x)
  x<-base;obs<-x$evidence$observations;drop<-which(obs$observer_core=="A"&obs$cell_uid==truth_uid(2,main))[1]
  x$evidence$observations<-obs[-drop,];expect_stop("MISSING_CORE_OBSERVATION",x)
  x<-base;x$graph$cores<-x$graph$cores[-2,];expect_stop("MISSING_CORE",x,"unowned grid positions")
  x<-base;x$graph$cores$col_max[1]<-204;expect_stop("DUPLICATE_OWNER",x)
  x<-base;x$graph$nodes$owner_core[2]<-"B";expect_stop("OWNER_CONFLICT",x)
})
case("invalid observations, duplicate rows and source inventory are rejected", {
  x<-base;x$graph$nodes$valid[2]<-FALSE;expect_stop("NODATA",x)
  x<-base;x$evidence$observations$valid[1]<-FALSE;expect_stop("NODATA_OBSERVATION",x)
  for(code in c(0,NA_real_,3)) { x<-base;x$graph$nodes$pointer[2]<-code;expect_stop("LAND_POINTER",x,paste("land pointer",code)) }
  x<-base;x$graph$nodes$water_class[18]<-4;expect_stop("WATER_CLASS",x)
  x<-base;x$graph$nodes$water_class[2]<-NaN;expect_stop("WATER_CLASS",x,"NaN is not land")
  x<-base;x$evidence$observations$pointer[1]<-2;expect_stop("OBSERVATION_CONFLICT",x)
  x<-base;x$evidence$observations<-rbind(x$evidence$observations,x$evidence$observations[1,]);expect_stop("DUPLICATE_OBSERVATION",x)
  x<-chain_input;x$graph$nodes<-rbind(x$graph$nodes,x$graph$nodes[1,]);expect_stop("DUPLICATE_CELL",x)
  x<-base;x$graph$nodes<-x$graph$nodes[-1,];expect_stop("NODE_COVERAGE",x)
  x<-base;x$evidence$source_inventory<-rbind(x$evidence$source_inventory,x$evidence$source_inventory[1,]);expect_stop("DUPLICATE_SOURCE",x)
  x<-base;x$evidence$source_inventory<-x$evidence$source_inventory[-1,];expect_stop("SOURCE_COVERAGE",x)
  for(units in c(1.5,Inf,2^53,1+.Machine$double.eps)) { x<-base;x$evidence$source_inventory$source_units[1]<-units;expect_stop("SOURCE_UNITS",x,paste("bad units",units)) }
  x<-base;x$evidence$source_inventory$owner_core[1]<-"B";expect_stop("SOURCE_UNITS",x,"halo cannot own source")
  x<-base;x$graph$nodes$source_uid[18]<-truth_uid(18,main);expect_stop("SOURCE_IDENTITY",x,"water cannot own a source")
})
case("size, identity, numerical precision and external-import contracts are bounded", {
  x<-base;x$graph$grid$ncol<-28;expect_stop("GRID_LIMIT",x)
  x<-base;x$graph$nodes$water_class[1]<-NA_real_;x$graph$nodes$kind[1]<-"LAND";expect_stop("SOURCE_LIMIT",x)
  x<-base;x$graph$grid$row_offset<-2^53;expect_stop("GRID_NUMERIC",x)
  x<-base;x$graph$grid$xmin<-1e100;expect_stop("GRID_NUMERIC",x,"huge origin")
  x<-base;x$graph$nodes$global_row[1]<-101.5;expect_stop("CELL_IDENTITY",x)
  x<-base;x$graph$grid$crs<-"EPSG:4326";expect_stop("GRID_NUMERIC",x,"wrong CRS")
  x<-base;x$graph$grid$resolution_m<-3;expect_stop("GRID_NUMERIC",x,"wrong resolution")
  x<-base;x$graph$grid$nrow<-3+1i;expect_stop("GRID_LIMIT",x,"complex dimension")
  x<-base;x$graph$nodes$pointer<-as.complex(x$graph$nodes$pointer);expect_stop("POINTER_VALUE",x,"complex pointer")
  x<-base;x$graph$nodes$water_class<-as.complex(x$graph$nodes$water_class);expect_stop("WATER_CLASS",x,"complex water class")
  x<-base;x$graph$nodes$pointer[2]<-1e100;expect_stop("POINTER_VALUE",x,"oversized pointer")
  x<-base;x$evidence$identity$graph_version<-"different";expect_stop("IDENTITY_CONFLICT",x)
  x<-base;x$graph$external_import<-"KNOWN_ZERO";expect_stop("EXTERNAL_IMPORT",x,"C5 unknown is not zero")
  x<-base;x$graph$command<-"anything";expect_stop("GRAPH_FIELDS",x,"no command fields")
})
check(cases>0L&&checks>0L&&length(stops)>0L)
write.csv(do.call(rbind,stops),file.path(root,"stop_cases.csv"),row.names=FALSE)
cat("R_VERSION=",as.character(getRversion()),"\n",sep="")
cat(sprintf("RESULT n=27 scenario=complete_dag cases=%d checks=%d stop_cases=%d status=PASS\n",cases,checks,length(stops)))
