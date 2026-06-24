#!/bin/bash
set -euo pipefail

# ============================================================
# Ambiente
# ============================================================
source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash
module load ncl/6.2.2
module load esmf/8.8.0-cray-turin-par

# ============================================================
# Configuração fixa
# ============================================================
DIR_PREV="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/PREV_MPAS"
DIR_ALL_PREV="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/ALL_PREV"
DIR_WORK="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/BTRAIN_PREP"
WRFBIN="/lustre/projetos/satdas/diego_workdir/WRFDA/var/build"

LL_TAG="${1:-1.0x1.0}"
LABELI="${2:?Informe LABELI, ex: 2026010100}"
LABELF="${3:?Informe LABELF, ex: 2026010500}"
FHR0="${4:?Informe passo entre inits, em horas}"
FHR="${5:?Informe forecast hour desejado, em horas}"

ESMF_DIR="${DIR_WORK}/ESMF_weights"
OUTDIR="${DIR_WORK}/output"

mkdir -p "${OUTDIR}"
cd "${OUTDIR}"

find_fcst_file() {
    local idate="$1"
    local vdate="$2"

    local yyyy="${vdate:0:4}"
    local mm="${vdate:4:2}"
    local dd="${vdate:6:2}"
    local hh="${vdate:8:2}"

    local f1="${DIR_PREV}/${idate}/history.${yyyy}-${mm}-${dd}_${hh}.00.00.nc"

    if [ -s "${f1}" ]; then
        echo "${f1}"
        return 0
    fi

    return 1
}

WGT1="${ESMF_DIR}/wgt_mpas_to_latlon_${LL_TAG}.nc"
WGT2="${ESMF_DIR}/wgt_latlon_to_mpas_${LL_TAG}.nc"

if [ ! -s "${WGT1}" ]; then
    echo "ERRO: peso não encontrado: ${WGT1}"
    exit 1
fi
if [ ! -s "${WGT2}" ]; then
    echo "ERRO: peso não encontrado: ${WGT2}"
    exit 1
fi
if [ ! -s "${DIR_WORK}/template_PTB.nc" ]; then
    echo "ERRO: template não encontrado: ${DIR_WORK}/template_PTB.nc"
    exit 1
fi

idate="${LABELI}"
lastidate="${LABELF}"
icnt=0

while [ "${idate}" -le "${lastidate}" ]; do
    echo "== init: ${idate}"
    vdate="$("${WRFBIN}/da_advance_time.exe" "${idate}" "+${FHR}h")"
    echo "   valid: ${vdate}"

    if ! f_fcst="$(find_fcst_file "${idate}" "${vdate}")"; then
        echo "   AVISO: forecast não encontrado para init=${idate} valid=${vdate}. Pulando."
        idate="$("${WRFBIN}/da_advance_time.exe" "${idate}" "+${FHR0}h")"
        continue
    fi

    mkdir -p "${vdate}"

    icnt=$((icnt+1))
    icntpad=$(printf "%.6d" "${icnt}")

    cat > "uv_to_psichi_f${FHR}h_${icntpad}.ncl" << EOF
load "\$NCARG_ROOT/lib/ncarg/nclscripts/esmf/ESMF_regridding.ncl"

begin
  FILE_IN   = "${f_fcst}"
  FILE_WGT1 = "${WGT1}"    ; MPAS -> latlon
  FILE_WGT2 = "${WGT2}"    ; latlon -> MPAS
  FILE_OUT  = "./${vdate}/FULL_f${FHR}.nc"

  setfileoption("nc","Format","LargeFile")

  f_in = addfile(FILE_IN, "r")

  ; [Time, nCells, nVertLevels] -> [nVertLevels, nCells]
  u_cell = transpose(f_in->uReconstructZonal(0,:,:))
  v_cell = transpose(f_in->uReconstructMeridional(0,:,:))

  print("== Regrid MPAS -> LatLon: " + systemfunc("date"))
  Opt = True
  Opt@PrintTimings = True

  u_ll = ESMF_regrid_with_weights(u_cell, FILE_WGT1, Opt)
  v_ll = ESMF_regrid_with_weights(v_cell, FILE_WGT1, Opt)

  delete(u_cell)
  delete(v_cell)

  dims = dimsizes(u_ll)
  nZ = dims(0)
  nY = dims(1)
  nX = dims(2)

  u = new((/nZ,nY,nX/), float)
  v = new((/nZ,nY,nX/), float)
  sf = new((/nZ,nY,nX/), float)
  vp = new((/nZ,nY,nX/), float)

  u = tofloat(u_ll)
  v = tofloat(v_ll)

  delete(u_ll)
  delete(v_ll)

  print("== uv2sfvpf: " + systemfunc("date"))
  uv2sfvpf(u, v, sf, vp)

  delete(u)
  delete(v)

  sf_cell4write = f_in->theta(:,:,:)
  vp_cell4write = f_in->theta(:,:,:)

  print("== Regrid LatLon -> MPAS: " + systemfunc("date"))
  sf_cell = ESMF_regrid_with_weights(sf, FILE_WGT2, Opt)
  vp_cell = ESMF_regrid_with_weights(vp, FILE_WGT2, Opt)

  delete(sf)
  delete(vp)

  ratio = 6371229.0/6371220.0

  sf_cell_transpose = transpose(sf_cell(:,:) * ratio)
  vp_cell_transpose = transpose(-1.0 * vp_cell(:,:) * ratio)

  delete(sf_cell)
  delete(vp_cell)

  sf_cell4write(0,:,:) = (/ sf_cell_transpose(:,:) /)
  vp_cell4write(0,:,:) = (/ vp_cell_transpose(:,:) /)

  delete(sf_cell_transpose)
  delete(vp_cell_transpose)

  sf_cell4write@units = "m^2 s^(-2)"
  sf_cell4write@long_name = "stream function"

  vp_cell4write@units = "m^2 s^(-2)"
  vp_cell4write@long_name = "velocity potential"

  system("cp ${DIR_WORK}/template_PTB.nc " + FILE_OUT)

  f_out = addfile(FILE_OUT, "rw")
  f_out->stream_function    = (/ sf_cell4write /)
  f_out->velocity_potential = (/ vp_cell4write /)

  delete(sf_cell4write)
  delete(vp_cell4write)
  delete(f_out)
  delete(f_in)

  print("== Finalizado: " + FILE_OUT)
end
EOF

    ncl "uv_to_psichi_f${FHR}h_${icntpad}.ncl"

    idate="$("${WRFBIN}/da_advance_time.exe" "${idate}" "+${FHR0}h")"
done

echo "== Total de scripts NCL executados: ${icnt}"
