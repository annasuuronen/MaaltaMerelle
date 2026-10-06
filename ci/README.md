# Persistent TEST_SULKU_11 CI fixtures

This branch exists only to hold the persistent binary fixtures needed by the
GitHub Actions hydrology regression workflow.

Expected layout:

- `ci/TEST_SULKU_11/dem_12km_rumpukorjattu.tif.part01`
- `ci/TEST_SULKU_11/dem_12km_rumpukorjattu.tif.part02`
- `ci/TEST_SULKU_11/dem_12km_rumpukorjattu.tif.part03`
- `ci/TEST_SULKU_11/RANTA10_TEST_SULKU_11.gpkg`
- `ci/TEST_SULKU_11/ranta10_lake_id.tif`
- `ci/TEST_SULKU_11/ranta10_river_area_mask.tif`
- `ci/TEST_SULKU_11/ranta10_river_line_mask.tif`
- `ci/TEST_SULKU_11/ranta10_water_class.tif`
- `ci/TEST_SULKU_11/ranta10_water_mask.tif`
- `ci/TEST_SULKU_11/HYDRO_STRUCTURES_LOCAL_TEST_SULKU_11_12km.gpkg`
- `ci/whitebox/whitebox_tools`

The DEM is deliberately stored as three sub-50-MiB Git blobs and reconstructed
by CI. The reconstructed file must be exactly 76,508,853 bytes with SHA-256:

`bc67829650e894e0a17f45d3c9bd112b9ef1e9d359449554be30f9e9d0804e2e`

Do not add generated `runs/` outputs to this branch.
