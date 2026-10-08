# Compatibility entry point for 02D.7K.
# The active NA-safe implementation is kept in a separate file so the
# baseline driver and CI contract can retain the stable 02D.7K filename.
source(file.path("R", "02D7K2_non_target_raised_link_resolution.R"))
