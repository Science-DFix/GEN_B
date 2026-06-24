#!/bin/bash

filename1="mpas.cor_rh.nc"
filename2="mpas.cor_rv.nc"
filename3="mpas.stddev.nc"

cp ${filename1} ${filename1}_w_missing_qx
cp ${filename2} ${filename2}_w_missing_qx
cp ${filename3} ${filename3}_w_missing_qx

cat > modify_missing.py << EOF
import numpy as np
from netCDF4 import Dataset

var_for_modif_list = ['qc','qi','qr','qs','qg']

for fn in ["${filename1}","${filename2}","${filename3}"]:
    f = Dataset(fn,"r+",format="NETCDF4")
    for var in var_for_modif_list:
        dum = f[var][:]
        dum[dum <= 0.0] = 0.0
        f[var][:] = dum
    f.close()
EOF

python modify_missing.py
