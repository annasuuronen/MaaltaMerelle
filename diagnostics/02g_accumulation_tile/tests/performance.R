#!/usr/bin/env Rscript
here <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))))
source(file.path(here,"support.R"))
source(file.path(repo,"diagnostics/land_network_topology/synthetic_scale/generator.R"))
s<-generate_scale_fixture(1000L,"fan")
f<-list(cells=data.frame(cell=1:1000,pointer=as.vector(t(s$pointer)),water_class=as.vector(t(s$water)),
  lake_id=as.vector(t(s$lake)),valid=as.vector(t(s$valid))),successor=s$successor,terminal=s$terminal,kind=s$kind,
  grid=s$grid,provenance=s$provenance)
f$terminal[f$successor==0]<-"DOMAIN_EXIT_UNRESOLVED"; f$provenance$synthetic<-TRUE
start<-proc.time()[["elapsed"]];r<-run_fixture(f,32L); compute<-proc.time()[["elapsed"]]-start
start<-proc.time()[["elapsed"]];verify(f,r,32L);oracle<-proc.time()[["elapsed"]]-start
check(r$balance$n_sources==1000 && r$balance$local_recurrence=="PASS")
cat(sprintf("RESULT n=1000 scenario=performance cap=32 compute_s=%.6f oracle_s=%.6f object_mib=%.6f checks=%d status=PASS\n",
 compute,oracle,as.numeric(object.size(r))/1024^2,checks))
