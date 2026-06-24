#!/bin/bash

filename="mpas.stddev.nc"
include_hydrometeor=2

if [ ${include_hydrometeor} -eq 1 ]; then
  var_for_modif_list='["stream_function","velocity_potential","temperature","spechum","surface_pressure","qc","qi","qr","qs","qg"]'
else
  var_for_modif_list='["stream_function","velocity_potential","temperature","spechum","surface_pressure"]'
fi

cp ${filename} ${filename}_org

cat > modify_var.py << EOF
import numpy as np
from netCDF4 import Dataset

fn = './${filename}'

f = Dataset(fn, "r+", format="NETCDF4")

var_for_modif_list = ${var_for_modif_list}

for var in var_for_modif_list:
    dum = f[var][:]
    dum = dum / 3.0
    f[var][:] = dum

f.close()
EOF

python modify_var.py
