#!/usr/bin/env Rscript
# Local report interpretation only. Input is read; CSV goes to stdout, never a
# raster, routing output, component file or production acceptance flag.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L || !args[2L] %in% c("lakes", "summary")) {
  stop("Usage: Rscript scripts/classify_02d5_readiness.R SUMMARY.csv lakes|summary")
}
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])
source(file.path(dirname(normalizePath(script)), "lib", "classify_02d5_readiness.R"))
if (file.info(args[1L])$size > 5 * 1024^2) stop("Report exceeds 5 MiB cap.")
x <- read.csv(args[1L], colClasses = "character", na.strings = "NA", check.names = FALSE)
result <- classify_02d5_readiness(x)
write.csv(if (args[2L] == "lakes") result$per_lake else result$summary,
          stdout(), row.names = FALSE, na = "NA")
# Exit 0 means a diagnostic report was produced, never authorization to run 02D.5.
