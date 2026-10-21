#!/usr/bin/env Rscript
# Fresh receiver process: serialized receiver state and ONE message only.
args <- commandArgs(trailingOnly=TRUE)
repo <- normalizePath(args[1L]); job <- readRDS(args[2L])
source(file.path(repo,"diagnostics/low_d8_scope/lake_1847_focus_core.R"))
source(file.path(repo,"diagnostics/land_first_water/first_water_contact.R"))
source(file.path(repo,"diagnostics/02g_accumulation_tile/accumulation.R"))
source(file.path(repo,"diagnostics/02g_accumulation_tile/tiles.R"))
source(file.path(repo,"diagnostics/02g_independent_tile_receipts/messages.R"))
stopifnot(identical(names(job),c("receiver","message")))
saveRDS(g2r_receive(job$receiver,job$message),args[3L])
