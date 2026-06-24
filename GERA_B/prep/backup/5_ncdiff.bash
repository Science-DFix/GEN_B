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
WRFBIN="/lustre/projetos/satdas/diego_workdir/WRFDA/var/build"

LABELI="${1:?Informe LABELI}"
LABELF="${2:?Informe LABELF}"
FHR0="${3:?Informe passo entre tempos válidos, em horas}"
FHR1="${4:?Informe o primeiro forecast hour, ex: 12}"
FHR2="${5:?Informe o segundo forecast hour, ex: 24}"

OUTDIR="${DIR_WORK}/output"
cd "${OUTDIR}"

vdate="$("${WRFBIN}/da_advance_time.exe" "${LABELI}" "+${FHR2}h")"
lastvdate="$("${WRFBIN}/da_advance_time.exe" "${LABELF}" "+${FHR1}h")"

icnt=0

while [ "${vdate}" -le "${lastvdate}" ]; do
    f_fcst1="${vdate}/FULL_f${FHR1}.nc"
    f_fcst2="${vdate}/FULL_f${FHR2}.nc"
    f_ptb="${vdate}/PTB_f${FHR2}mf${FHR1}.nc"

    if [ ! -s "${f_fcst1}" ] || [ ! -s "${f_fcst2}" ]; then
        echo "== Pulando valid=${vdate}: FULL_f${FHR1}.nc ou FULL_f${FHR2}.nc ausente"
        vdate="$("${WRFBIN}/da_advance_time.exe" "${vdate}" "+${FHR0}h")"
        continue
    fi

    echo "== ncdiff para valid=${vdate}"
    ncdiff -O "${f_fcst2}" "${f_fcst1}" "${f_ptb}"

    icnt=$((icnt+1))
    vdate="$("${WRFBIN}/da_advance_time.exe" "${vdate}" "+${FHR0}h")"
done

echo "== Total de PTBs gerados: ${icnt}"
