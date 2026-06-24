#!/bin/bash
#set -euo pipefail

esmfWeightsDir=ESMF_weights

source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash
module load ncl/6.2.2
#module load netcdf
module load esmf/8.8.0-cray-turin-par

DIR_WORK="/p/projetos/satdas/diego_workdir/SOURCE/dataout/BTRAIN_PREP"
INVAR_FILE="/p/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/invariant/x1.163842.invariant.nc"

workdir=${DIR_WORK}/${esmfWeightsDir}

mkdir -p ${workdir}
cd ${workdir}

ln -fs ${INVAR_FILE} ./MPAS_x1.163842.nc

isSinglePrecision=`ncdump -h ./MPAS_x1.163842.nc | grep 'float latCell' | wc -l`
echo $isSinglePrecision

cat > generateEsmfWeights.ncl << EOF
;======================================================================
; based on ESMF_all_patch_12.ncl
; : https://www.ncl.ucar.edu/Applications/Scripts/ESMF_all_patch_12.ncl
;======================================================================
; Concepts illustrated:
;   - Interpolating from one grid to another using ESMF software
;   - Interpolating data from a latlon grid to an MPAS grid
;======================================================================
load "\$NCARG_ROOT/lib/ncarg/nclscripts/esmf/ESMF_regridding.ncl"

begin
;---Input files
    srcFileName = "N/A" ; Not Needed
    dstFileName = "MPAS_x1.163842.nc"

;---Interpolation method to use
    interpMethod = "bilinear"   ; "patch", "conserve", or "neareststod"

;---Output (and, eventually, input) files
    srcGridName = "SCRIP_latlon_0p5.nc"
    dstGridName = "ESMF_MPAS_x1.163842.nc"
    wgtFile1    = "latlon_0p5_to_MPAS_x1.163842_" + interpMethod + ".nc" ; From latlon to MPAS
    wgtFile2    = "MPAS_x1.163842_to_latlon_0p5_" + interpMethod + ".nc" ; From MPAS to latlon

;---Set to True if you want to skip any of these steps
    SKIP_TRI_SCRIP_GEN  = False
    SKIP_MPAS_ESMF_GEN  = False
    SKIP_WGT_GEN_1      = False
    SKIP_WGT_GEN_2      = False

;----------------------------------------------------------------------
; Step 1
;   Convert source lat/lon grid to a SCRIP File.
;----------------------------------------------------------------------
    if(.not.SKIP_TRI_SCRIP_GEN) then
      Opt                = True
      Opt@ForceOverwrite = True
      Opt@PrintTimings   = True

      Opt@LLCorner       = (/ -89.75d0, -179.75d0 /)
      Opt@URCorner       = (/  89.75d0,  179.75d0 /)
      Opt@Title          = "Fixed lat/lon grid : 0.5 degree"
      latlon_to_SCRIP(srcGridName,"0.5deg",Opt)

;---Clean up
      delete(Opt)
    end if
    
;----------------------------------------------------------------------
; Step 2
;   Converting destination MPAS grid to an unstructured ESMF File.
;----------------------------------------------------------------------
    dfile = addfile(dstFileName,"r")

;---Read in lat/lon cell centers and convert to degrees from radians
EOF

if [ ${isSinglePrecision} -eq 1 ]; then
cat >> generateEsmfWeights.ncl << EOF
    r2d     = 180.0/(atan(1)*4.0)
EOF
else
cat >> generateEsmfWeights.ncl << EOF
    r2d     = 180.0d0/(atan(1.d0)*4.d0) ;-----180.0e/(atan(1)*4.0e)
EOF
fi

cat >> generateEsmfWeights.ncl << EOF
    lonCell = dfile->lonCell
    latCell = dfile->latCell
    lonCell = lonCell*r2d
    latCell = latCell*r2d

    if(.not.SKIP_MPAS_ESMF_GEN) then
      Opt                = True
      Opt@ForceOverwrite = True
      Opt@PrintTimings   = True
      Opt@InputFileName  = dstFileName

      print("Converting MPAS to Unstructured ESMF convention file ...")
      unstructured_to_ESMF(dstGridName,latCell,lonCell,Opt)

;---Clean up
      delete(Opt)
    end if

;----------------------------------------------------------------------
; Step 3a
;    Generate weights 1: from latlon to MPAS
;----------------------------------------------------------------------
    if(.not.SKIP_WGT_GEN_1) then
      Opt                      = True
      Opt@InterpMethod         = interpMethod
      Opt@SrcESMF              = False
      Opt@DstESMF              = True
      Opt@ForceOverwrite       = True
      Opt@PrintTimings         = True
      Opt@Debug                = True
      Opt@Check                = True
      Opt@DstGridType          = "unstructured"

      print("Generating interpolation weights from latlon to MPAS grid ...")
      ESMF_regrid_gen_weights(srcGridName, dstGridName, wgtFile1, Opt)
    end if

;----------------------------------------------------------------------
; Step 3b
;    Generate weights 1: from MPAS to latlon
;----------------------------------------------------------------------
    if(.not.SKIP_WGT_GEN_2) then
      Opt                      = True
      Opt@InterpMethod         = interpMethod
      Opt@SrcESMF              = True
      Opt@DstESMF              = False
      Opt@ForceOverwrite       = True
      Opt@PrintTimings         = True
      Opt@Debug                = True
      Opt@Check                = True
      Opt@DstGridType          = "unstructured"

      print("Generating interpolation weights from MPAS to latlon grid ...")
      ESMF_regrid_gen_weights(dstGridName, srcGridName, wgtFile2, Opt)
    end if

end
EOF

ncl generateEsmfWeights.ncl

cd ..
