#!/usr/bin/env Rscript
here<-dirname(normalizePath(sub("^--file=","",grep("^--file=",commandArgs(),value=TRUE))))
root<-dirname(here);repo<-normalizePath(file.path(root,"..",".."))
source(file.path(repo,"diagnostics/low_d8_scope/lake_1847_focus_core.R"))
source(file.path(repo,"diagnostics/land_first_water/first_water_contact.R"))
source(file.path(repo,"diagnostics/02g_accumulation_tile/accumulation.R"))
source(file.path(repo,"diagnostics/02g_accumulation_tile/tiles.R"))
source(file.path(root,"messages.R"));source(file.path(here,"oracle.R"))
checks<-0L;cases<-0L
check<-function(ok,label="check") { checks<<-checks+1L;if(!isTRUE(ok))stop("02G2_TEST_FAILURE: ",label,call.=FALSE) }
reject<-function(expr) check(inherits(tryCatch({force(expr);NULL},error=identity),"error"),"invalid input rejected")
case<-function(name,expr) { force(expr);cases<<-cases+1L;cat("PASS:",name,"\n") }
layout3<-list(A=list(rows=c(1,3),cols=c(1,3)),B=list(rows=c(1,3),cols=c(4,6)),C=list(rows=c(1,3),cols=c(7,9)))
layout2<-list(A=list(rows=c(1,3),cols=c(1,4)),B=list(rows=c(1,3),cols=c(5,9)))
owner_map<-function(f,layout) {
  # Independent ownership, using explicitly declared rectangular cuts.
  row<-(seq_len(nrow(f$cells))-1L)%/%f$grid$ncol+1L;col<-(seq_len(nrow(f$cells))-1L)%%f$grid$ncol+1L
  owner<-rep(NA_character_,length(row))
  for(id in names(layout)) { b<-layout[[id]]; hit<-row>=b$rows[1]&row<=b$rows[2]&col>=b$cols[1]&col<=b$cols[2];stopifnot(all(is.na(owner[hit])));owner[hit]<-id }
  stopifnot(!anyNA(owner));owner
}
actors_for<-function(f,layout=layout3,cap=32L,available=names(layout)) {
  contract<-g2r_contract(f$grid,layout,f$provenance,cap)
  setNames(lapply(available,function(id) {
    b<-layout[[id]]
    rows<-(f$cells$cell-1L)%/%f$grid$ncol+1L;cols<-(f$cells$cell-1L)%%f$grid$ncol+1L
    in_halo<-rows>=max(1,b$rows[1]-1)&rows<=min(f$grid$nrow,b$rows[2]+1)&
      cols>=max(1,b$cols[1]-1)&cols<=min(f$grid$ncol,b$cols[2]+1)
    g2r_seed(g2r_actor(id,list(grid=f$grid,cells=f$cells[in_halo,]),contract))
  }),available)
}
drain<-function(actors,order="fifo",replay=FALSE) {
  delivered<-character(); deliveries<-0L
  repeat {
    pending<-unlist(lapply(actors,function(a)unname(a$outbox)),recursive=FALSE)
    pending<-Filter(function(m)!m$message_id%in%delivered && m$receiving_tile%in%names(actors),pending)
    if(!length(pending))break
    m<-pending[[if(order=="reverse")length(pending) else if(order=="shuffle")sample.int(length(pending),1) else 1L]]
    result<-g2r_receive(actors[[m$receiving_tile]],m)
    actors[[m$receiving_tile]]<-result$state
    if(replay) {
      duplicate<-g2r_receive(result$state,m)
      check(identical(duplicate$state,result$state)&&identical(duplicate$receipt,result$receipt)&&duplicate$delivery_status=="REPLAY","duplicate delivery is idempotent")
    }
    actors[[m$sending_tile]]<-g2r_confirm(actors[[m$sending_tile]],result$receipt)
    if(replay)check(identical(actors[[m$sending_tile]],g2r_confirm(actors[[m$sending_tile]],result$receipt)),"duplicate receipt idempotent")
    delivered<-c(delivered,m$message_id);deliveries<-deliveries+1L;check(deliveries<=256L,"bounded delivery loop")
  }
  actors
}
verify<-function(f,layout,actors,cap) {
  result<-g2r_collect(actors);ref<-r_reference(f,owner_map(f,layout),names(actors),cap)
  ids<-r_uid(ref$seeds,f);at<-match(ids,result$nodes$cell_uid)
  check(setequal(result$nodes$cell_uid,ids),"unique owned sources")
  for(i in seq_along(ref$seeds)) {
    cell<-ref$seeds[i];uid<-ids[i];s<-r_uid(ref$sets[[as.character(cell)]],f)
    check(setequal(result$source_sets[[uid]],s),"independent local source sets")
    check(result$nodes$observed_source_count[at[i]]==length(s),"unique contribution count")
    if(cell%in%ref$cycles)check(is.na(result$nodes$local_upstream_cells[at[i]]),"no finite cyclic recurrence")
    else check(result$nodes$local_upstream_cells[at[i]]==length(s)&&result$nodes$local_upstream_area_m2[at[i]]==4*length(s))
    j<-match(uid,result$source_ledger$source_uid)
    check(result$source_ledger$endpoint_type[j]==ref$status[i]&&result$source_ledger$terminal_uid[j]==r_uid(ref$endpoints[i],f),"independent source endpoint")
  }
  for(cell in names(ref$water_sets)) check(setequal(result$water_source_sets[[r_uid(as.integer(cell),f)]],r_uid(ref$water_sets[[cell]],f)),"independent first-water set")
  actual<-unlist(lapply(actors,function(a)vapply(a$outbox,function(m)paste(m$source_cell,m$from_cell,m$receiver_cell,length(m$codes),sep="|"),character(1))),use.names=FALSE)
  check(setequal(actual,ref$transfers)&&!anyDuplicated(actual),"independent source/edge/budget transfer ledger")
  check(result$balance$n_sources==length(ref$seeds)&&result$balance$n_sources==result$balance$n_first_water+result$balance$n_unresolved,"one source unit in final balance")
  check(result$balance$n_approved_exports==0 && all(is.na(result$nodes$total_upstream_cells)) && result$external_import=="UNKNOWN")
  check(result$hydrological_validation=="NOT_ASSESSED"&&result$channel_interpretation=="NOT_ASSESSED"&&result$MODERATE=="REVIEW_REQUIRED"&&result$NATIONAL=="LOCKED")
  check(result$channel_threshold_cells==10000L&&length(result$source_sets)==length(ref$seeds),"threshold never filters")
  invisible(result)
}
f<-r_fixture();baseline<-NULL
case("two/three tiles match explicit oracle under independent message orders and replays", {
  for(layout in list(layout2,layout3)) for(cap in c(2L,32L)) {
    canonical<-NULL
    for(order in c("fifo","reverse","shuffle")) {
      set.seed(20261021);actors<-drain(actors_for(f,layout,cap),order,TRUE)
      result<-verify(f,layout,actors,cap)
      if(is.null(canonical))canonical<-result else check(identical(canonical,result),"semantic result invariant to arrival order")
      check(result$balance$sent==result$balance$independently_received&&result$balance$sent==result$balance$confirmed&&result$balance$unconfirmed==0)
      if(length(layout)==3L&&cap==32L) { baseline<-actors;check(result$balance$n_sources==11&&result$balance$n_first_water==11) }
      if(length(layout)==3L&&cap==2L) {
        check(result$balance$n_unresolved>0,"step budget not restarted at seam")
        crossing<-Filter(function(m)m$from_cell==12L&&m$receiver_cell==13L,actors$A$outbox)
        check(length(actors$A$source_sets[[r_uid(12L,f)]])==4L&&length(crossing)==2L,
          "four observed sender contributors do not become four transferred sources at cap 2")
      }
    }
  }
})
case("receiver executes in a fresh R process with only its own state and one message", {
  actors<-actors_for(f);m<-actors$A$outbox[[1L]];b<-actors$B
  check(nrow(b$cells)<nrow(f$cells)&&!m$source_cell%in%b$cells$cell,"receiver lacks foreign source observation")
  dir<-tempfile("g2r-worker-");dir.create(dir)
  input<-file.path(dir,"input.rds");output<-file.path(dir,"output.rds")
  saveRDS(list(receiver=b,message=m),input)
  rscript<-Sys.getenv("MM_RSCRIPT",file.path(R.home("bin"),"Rscript"))
  exit<-system2(rscript,c("--vanilla",shQuote(file.path(here,"receive_worker.R")),shQuote(repo),shQuote(input),shQuote(output)))
  check(exit==0L&&file.exists(output),"isolated receiver worker completed")
  actual<-readRDS(output);expected<-g2r_receive(b,m)
  check(identical(actual,expected),"independent process produces exact receiver result")
  check(identical(b,actors$B),"functional receive leaves original receiver unchanged")
  unlink(dir,recursive=TRUE)
})
case("conflicting payloads, runs, directions and unknown fields fail before mutation", {
  a<-actors_for(f);m<-a$A$outbox[[1L]];b<-a$B;snapshot<-serialize(b,NULL)
  changes<-list(function(x){x$contract$provenance$run_id<-"stale";x},
    function(x){x$codes[length(x$codes)]<-8;x},function(x){x$source_uid<-"forged";x},
    function(x){x$receiving_tile<-"C";x},function(x){x$sending_tile<-"C";x},
    function(x){x$accumulation<-999;x},function(x){x$command<-"anything";x},
    function(x){x$path<-c(x$path,x$receiver_cell);x},function(x){x$message_id<-"different";x})
  for(change in changes) { reject(g2r_receive(b,change(m)));check(identical(snapshot,serialize(b,NULL)),"rejection is atomic") }
  first<-g2r_receive(b,m);bad<-m;bad$contract$max_steps<-31L;reject(g2r_receive(first$state,bad))
  badtile<-b;badtile$cells$pointer[badtile$cells$cell==m$from_cell]<-8
  reject(g2r_receive(badtile,m))
  ack<-first$receipt;ack$receiver_observation$valid<-FALSE;reject(g2r_confirm(a$A,ack))
  ack<-first$receipt;ack$hydrological_validation<-"PASS";reject(g2r_confirm(a$A,ack))
  # Even a syntactically plausible acknowledgement cannot pass reconciliation
  # without a separately stored receiver entry.
  forged<-a;forged$A<-g2r_confirm(a$A,first$receipt);reject(g2r_collect(forged))
})
case("conflicting replay path with the same logical ID is rejected", {
  a<-actors_for(f);m<-a$A$outbox[[1L]];first<-g2r_receive(a$B,m)
  bad<-m;bad$source_cell<-bad$source_cell+1L
  reject(g2r_receive(first$state,bad));check(identical(first$state,g2r_receive(first$state,m)$state))
  reject(g2r_seed(a$A))
})
case("missing neighbour never fabricates receipts, imports or missing source units", {
  actors<-drain(actors_for(f,available=c("A","C")),"reverse",TRUE)
  result<-verify(f,layout3,actors,32L)
  check(result$balance$n_sources==7&&result$balance$n_first_water==3&&result$balance$n_unresolved==4)
  check(result$balance$sent==4&&result$balance$independently_received==0&&result$balance$confirmed==0&&result$balance$unconfirmed==4)
  check(identical(result$missing_tiles,"B")&&sum(result$source_ledger$endpoint_type=="MISSING_NEIGHBOUR_TILE")==4)
})
case("lost deliveries and lost acknowledgements remain distinct and restartable", {
  a<-actors_for(f);pending<-g2r_collect(a)
  check(any(pending$source_ledger$endpoint_type=="PENDING_DELIVERY")&&pending$balance$confirmed==0)
  m<-a$A$outbox[[1L]];got<-g2r_receive(a$B,m);a$B<-got$state
  before<-g2r_collect(a);check(before$balance$independently_received==1&&before$balance$confirmed==0)
  replay<-g2r_receive(a$B,m);check(identical(replay$receipt,got$receipt))
  a$A<-g2r_confirm(a$A,replay$receipt)
  path<-tempfile(fileext=".rds");saveRDS(a,path);a<-readRDS(path);unlink(path)
  result<-verify(f,layout3,drain(a,"reverse",TRUE),32L)
  check(result$balance$unconfirmed==0&&result$balance$n_first_water==11)
})
case("a missing neighbour can join without reseeding the existing owners", {
  partial<-drain(actors_for(f,available=c("A","C")),"reverse",TRUE)
  checkpoint<-serialize(partial,NULL);partial$B<-actors_for(f,available="B")$B
  check(identical(checkpoint,serialize(partial[c("A","C")],NULL)),"existing owners remain unchanged when neighbour joins")
  recovered<-verify(f,layout3,drain(partial,"shuffle",TRUE),32L)
  check(recovered$balance$n_sources==11&&recovered$balance$n_first_water==11&&recovered$balance$unconfirmed==0)
})
case("cross-tile cycle stays unresolved and has no finite cyclic accumulation", {
  cycle<-r_fixture(land=c(11:16),edges=rbind(cbind(11:15,12:16),c(16,15)),water=integer())
  actors<-drain(actors_for(cycle),"shuffle",TRUE);result<-verify(cycle,layout3,actors,32L)
  check(all(result$source_ledger$endpoint_type=="CYCLE")&&length(result$cycle_cells)==2&&result$balance$unconfirmed==0)
})
case("zero, NA, invalid pointer, NoData, invalid class and raster boundary remain unresolved", {
  for(kind in c("zero","pointer_na","invalid","nodata","invalid_class","boundary")) {
    t<-r_fixture();cell<-16L
    if(kind=="zero") { t$cells$pointer[cell]<-0;t$successor[cell]<-0;t$terminal[cell]<-"D8_ZERO" }
    if(kind=="pointer_na") { t$cells$pointer[cell]<-NA_real_;t$terminal[cell]<-"POINTER_NA" }
    if(kind=="invalid") { t$cells$pointer[cell]<-3;t$terminal[cell]<-"INVALID_POINTER" }
    if(kind=="nodata") { t$cells$valid[cell]<-FALSE;t$kind[cell]<-"NO_DATA" }
    if(kind=="invalid_class") { t$cells$water_class[cell]<-4;t$kind[cell]<-"INVALID_WATER_CLASS" }
    if(kind=="boundary") { t$cells$water_class[18]<-NA_real_;t$cells$lake_id[18]<-NA_real_;t$kind[18]<-"LAND";t$cells$pointer[18]<-2;t$terminal[18]<-"DOMAIN_EXIT_UNRESOLVED" }
    result<-verify(t,layout3,drain(actors_for(t),"reverse",TRUE),32L)
    check(result$balance$n_unresolved>0&&result$balance$n_approved_exports==0)
  }
})
case("first contact ignores water outgoing pointer and never implies an outlet", {
  expected<-g2r_collect(baseline)
  for(class in 1:3)for(pointer in c(0,3,NA_real_)) {
    t<-f;t$cells$water_class[18]<-class;t$cells$pointer[18]<-pointer;t$cells$lake_id[18]<-if(class==1)9001 else NA_real_
    r<-verify(t,layout3,drain(actors_for(t),"reverse"),32L)
    check(identical(r$source_sets,expected$source_sets)&&identical(r$water_source_sets,expected$water_source_sets))
    check(r$water$water_class==class&&r$water$local_source_cells==11&&
      if(class==1)r$water$lake_objectid==9001 else is.na(r$water$lake_objectid),"water class and valid lake ID only")
  }
})
case("empty domains and bad metadata are safe", {
  empty<-r_fixture(land=integer(),edges=matrix(integer(),ncol=2),water=integer())
  r<-verify(empty,layout3,actors_for(empty),32L);check(r$balance$n_sources==0&&r$balance$sent==0)
  p<-f$provenance;p$synthetic<-FALSE;reject(g2r_contract(f$grid,layout3,p))
  reject(g2r_contract(f$grid,layout3,f$provenance,0L))
  g<-f$grid;g$nrow<-14L;reject(g2r_contract(g,layout3,f$provenance))
  a<-actors_for(f);bad<-a$A;bad$contract$grid$resolution_m<-3;reject(g2r_collect(list(A=bad,B=a$B,C=a$C)))
  tile<-list(grid=f$grid,cells=a$A$cells[-1L,1:5]);reject(g2r_actor("A",tile,a$A$contract))
  badlayout<-layout3;badlayout$A$cols<-c(1,4);reject(g2r_contract(f$grid,badlayout,f$provenance))
  incomplete<-a;entry<-g2r_receive(a$B,a$A$outbox[[1L]]);incomplete$B<-entry$state
  incomplete$A$outbox<-list();reject(g2r_collect(incomplete))
})
case("independent sender and receiver audit products retain matching source identities", {
  messages<-unlist(lapply(baseline,function(a)unname(a$outbox)),recursive=FALSE)
  entries<-unlist(lapply(baseline,function(a)unname(a$inbox)),recursive=FALSE)
  sent<-do.call(rbind,lapply(messages,function(m)data.frame(message_id=m$message_id,source_uid=m$source_uid,
    sending_tile=m$sending_tile,receiving_tile=m$receiving_tile,from_uid=r_uid(m$from_cell,f),
    receiver_uid=r_uid(m$receiver_cell,f),global_steps=length(m$codes))))
  # Deliberately derive received evidence only from the independent inbox.
  received<-do.call(rbind,lapply(entries,function(e) {
    ack<-e$receipt;v<-ack$receiver_observation
    data.frame(message_id=ack$message_id,source_uid=ack$source_uid,receiving_tile=ack$receiving_tile,
      receiver_uid=r_uid(ack$receiver_cell,f),observed_pointer=v$pointer,observed_water_class=v$water_class,
      observed_valid=v$valid,receipt_status=ack$status,hydrological_validation=ack$hydrological_validation)
  }))
  sent<-sent[order(sent$message_id),];received<-received[order(received$message_id),]
  check(identical(sent$message_id,received$message_id)&&identical(sent$source_uid,received$source_uid))
  check(nrow(sent)==12L&&length(unique(sent$source_uid))==8L,"transit memberships are not new source units")
  write.csv(sent,file.path(root,"example_sent.csv"),row.names=FALSE)
  write.csv(received,file.path(root,"example_received.csv"),row.names=FALSE)
  write.csv(g2r_collect(baseline)$source_ledger,file.path(root,"example_source_ledger.csv"),row.names=FALSE)
})
stopifnot(cases>0L,checks>0L)
cat("R_VERSION=",as.character(getRversion()),"\n",sep="")
cat(sprintf("RESULT n=27 scenario=receipts cases=%d checks=%d status=PASS\n",cases,checks))
