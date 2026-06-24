#!/bin/bash

filename1="mpas.cor_rh.nc"

cp ${filename1} ${filename1}_org

cat > modify_cor.py << EOF
import numpy as np
from netCDF4 import Dataset

fn1 = './${filename1}'

f1 = Dataset(fn1, "r+", format="NETCDF4")

var_for_modif_list = ["stream_function", "velocity_potential"]

for var in var_for_modif_list:
    dum = f1[var][:]
    dum = dum / 2.0
    f1[var][:] = dum

f1.close()
EOF

python modify_cor.py
