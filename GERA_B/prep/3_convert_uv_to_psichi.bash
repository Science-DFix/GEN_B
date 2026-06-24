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
DIR_WORK="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/BTRAIN_PREP"
DIR_PREV="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/PREV_MPAS"
ADV_TIME_EXE="/lustre/projetos/satdas/diego_workdir/WRFDA/var/build/da_advance_time.exe"

esmfWeightsDir="ESMF_weights"
outputDir="output"

workdir="${DIR_WORK}/${outputDir}"

mkdir -p "${workdir}"
cd "${workdir}"

# ============================================================
# Argumento: fhr (24 ou 48)
# ============================================================
if [ $# -lt 1 ]; then
    echo "Uso: $0 <24|48>"
    exit 1
fi

fhr="$1"

if [ "$fhr" != "24" ] && [ "$fhr" != "48" ]; then
    echo "ERRO: fhr deve ser 24 ou 48"
    exit 1
fi

# ============================================================
# Período de rodada (idate = data de início da previsão)
# ============================================================
idate=2025122900
lastidate=2026013000

# ============================================================
# Pesos ESMF e template
# ============================================================
f_wgt1="../${esmfWeightsDir}/MPAS_x1.163842_to_latlon_0p5_bilinear.nc"
f_wgt2="../${esmfWeightsDir}/latlon_0p5_to_MPAS_x1.163842_bilinear.nc"
f_template="../template_PTB.nc"

if [ ! -s "${f_wgt1}" ]; then
    echo "ERRO: peso não encontrado: ${f_wgt1}"; exit 1
fi
if [ ! -s "${f_wgt2}" ]; then
    echo "ERRO: peso não encontrado: ${f_wgt2}"; exit 1
fi
if [ ! -s "${f_template}" ]; then
    echo "ERRO: template não encontrado: ${f_template}"; exit 1
fi

# ============================================================
# Loop principal — avança 24h por rodada
# ============================================================
icnt=0

while [ "${idate}" -le "${lastidate}" ]; do

    echo "==> Rodada iniciada em: ${idate}"

    # valid time = idate + fhr horas
    vdate=$("${ADV_TIME_EXE}" "${idate}" "+${fhr}h")
    echo "    valid time (f${fhr}): ${vdate}"

    vyyyy=$(echo "${vdate}" | cut -c1-4)
    vmm=$(echo   "${vdate}" | cut -c5-6)
    vdd=$(echo   "${vdate}" | cut -c7-8)
    vhh=$(echo   "${vdate}" | cut -c9-10)

    # O mpasout está no diretório da rodada (idate)
    # com o nome baseado no valid time
    f_fcst="${DIR_PREV}/${idate}/mpasout.${vyyyy}-${vmm}-${vdd}_${vhh}.00.00.nc"

    if [ ! -s "${f_fcst}" ]; then
        echo "    AVISO: mpasout não encontrado: ${f_fcst}"
        echo "    Pulando ${idate}"
        idate=$("${ADV_TIME_EXE}" "${idate}" "+24h")
        continue
    fi

    mkdir -p "${vdate}"

    icnt=$((icnt+1))
    icntpad=$(printf "%.6d" "${icnt}")

    # --------------------------------------------------------
    # Gerar script NCL para essa rodada
    # --------------------------------------------------------
    cat > uv_to_psichi_f${fhr}h_${icntpad}.ncl << EOF
load "\$NCARG_ROOT/lib/ncarg/nclscripts/esmf/ESMF_regridding.ncl"

begin

  FILE_IN   = "${f_fcst}"
  FILE_WGT1 = "${f_wgt1}"   ; MPAS -> latlon
  FILE_WGT2 = "${f_wgt2}"   ; latlon -> MPAS

  setfileoption("nc","Format","LargeFile")

  f_in = addfile(FILE_IN, "r")

  ; Ler vento reconstruído — [Time, nCells, nVertLevels]
  ; Transpor para [nVertLevels, nCells] para interpolação ESMF
  u_cell = transpose( f_in->uReconstructZonal(0,:,:) )
  v_cell = transpose( f_in->uReconstructMeridional(0,:,:) )

  print(" == Interpolando MPAS -> LatLon: " + systemfunc("date"))
  Opt              = True
  Opt@PrintTimings = True

  u_ll = ESMF_regrid_with_weights(u_cell, FILE_WGT1, Opt)
  v_ll = ESMF_regrid_with_weights(v_cell, FILE_WGT1, Opt)
  delete(u_cell)
  delete(v_cell)
  print(" == Interpolação concluída: " + systemfunc("date"))

  dims = dimsizes(u_ll)
  nZ = dims(0)
  nY = dims(1)
  nX = dims(2)

  u  = new((/nZ,nY,nX/), float)
  v  = new((/nZ,nY,nX/), float)
  sf = new((/nZ,nY,nX/), float)
  vp = new((/nZ,nY,nX/), float)

  u(:,:,:) = tofloat(u_ll(:,:,:))
  v(:,:,:) = tofloat(v_ll(:,:,:))
  delete(u_ll)
  delete(v_ll)

  print(" == Calculando stream function e velocity potential: " + systemfunc("date"))
  uv2sfvpf(u, v, sf, vp)
  delete(u)
  delete(v)
  print(" == Cálculo concluído: " + systemfunc("date"))

  ; Interpolar sf e vp de latlon -> MPAS
  sf_cell = ESMF_regrid_with_weights(sf, FILE_WGT2, Opt)
  vp_cell = ESMF_regrid_with_weights(vp, FILE_WGT2, Opt)
  delete(sf)
  delete(vp)

  ; Usar theta como container para escrita (mesmas dimensões)
  sf_cell4write = f_in->theta(:,:,:)
  vp_cell4write = f_in->theta(:,:,:)

  ; Transpor de [nVertLevels, nCells] -> [nCells, nVertLevels]
  ; e aplicar fator de escala (razão de raios terrestres)
  ratio = 6371229.0 / 6371220.0
  sf_cell4write(0,:,:) = (/ transpose(sf_cell(:,:) * ratio) /)
  vp_cell4write(0,:,:) = (/ transpose(-1.0 * vp_cell(:,:) * ratio) /)
  delete(sf_cell)
  delete(vp_cell)

  sf_cell4write@units     = "m^2 s^(-1)"
  sf_cell4write@long_name = "stream function"
  vp_cell4write@units     = "m^2 s^(-1)"
  vp_cell4write@long_name = "velocity potential"

  ; Copiar template e escrever resultados
  fdir = "./${vdate}"
  system("cp ../template_PTB.nc " + fdir + "/FULL_f${fhr}.nc")
  f_out = addfile(fdir + "/FULL_f${fhr}.nc", "rw")
  f_out->stream_function    = (/ sf_cell4write /)
  f_out->velocity_potential = (/ vp_cell4write /)
  delete(sf_cell4write)
  delete(vp_cell4write)
  delete(f_out)
  delete(f_in)

  print(" == Arquivo gerado: " + fdir + "/FULL_f${fhr}.nc")

end
EOF

    echo "    Executando NCL para ${vdate}..."
    ncl "uv_to_psichi_f${fhr}h_${icntpad}.ncl"
    echo "    Concluído: ${vdate}/FULL_f${fhr}.nc"

    # Avançar para próxima rodada
    idate=$("${ADV_TIME_EXE}" "${idate}" "+24h")

done

echo ""
echo "=== Script 3 concluído: ${icnt} arquivos FULL_f${fhr}.nc gerados ==="
