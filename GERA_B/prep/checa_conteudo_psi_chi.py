import xarray as xr
import numpy as np

file = "/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/BTRAIN_PREP/output/2026010300/FULL_f48.nc"

ds = xr.open_dataset(file)

for var in ["stream_function", "velocity_potential","spechum", "temperature", "relhum", "surface_pressure", "uReconstructMeridional", "uReconstructZonal"]:
    data = ds[var].values
    print(f"\nVariável: {var}")
    print("shape:", data.shape)
    print("min:", np.nanmin(data))
    print("max:", np.nanmax(data))


for var in ["stream_function", "velocity_potential", "spechum", "temperature", "relhum", "surface_pressure", "uReconstructMeridional", "uReconstructZonal"]:
    arr = ds[var].values
    print(f"\nVariável: {var}")
    print("NaN:", np.isnan(arr).sum())
    print("Inf:", np.isinf(arr).sum())
