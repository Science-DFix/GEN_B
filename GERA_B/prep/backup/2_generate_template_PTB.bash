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

# Arquivo de referência:
# pode ser passado como argumento; se não for, use um history seu.
REF_FILE="${1:-}"

if [ -z "${REF_FILE}" ]; then
    echo "Uso:"
    echo "  $0 /caminho/para/history.YYYY-MM-DD_HH.00.00.nc"
    exit 1
fi

if [ ! -s "${REF_FILE}" ]; then
    echo "ERRO: REF_FILE não encontrado: ${REF_FILE}"
    exit 1
fi

cd "${DIR_WORK}"

F_REF_LINK="MPAS_ref_history.nc"
F_TMP="template_PTB.nc"

rm -f "${F_REF_LINK}" "${F_TMP}" "${F_TMP}_single" "${F_TMP}_work"

ln -sf "${REF_FILE}" "./${F_REF_LINK}"

# Extrai theta para herdar dimensões e estrutura vertical
ncks -O -v theta "${F_REF_LINK}" "${F_TMP}_single"

# Zera theta
ncap2 -O -s 'theta=0.0' "${F_TMP}_single" "${F_TMP}_single"

# stream_function
cp "${F_TMP}_single" "${F_TMP}_work"
ncrename -O -v theta,stream_function "${F_TMP}_work"
ncatted -O -a long_name,stream_function,o,c,"stream function" "${F_TMP}_work"
ncatted -O -a units,stream_function,o,c,"m^2 s^(-2)" "${F_TMP}_work"
ncks -A -v stream_function "${F_TMP}_work" "${F_TMP}"

# velocity_potential
cp "${F_TMP}_single" "${F_TMP}_work"
ncrename -O -v theta,velocity_potential "${F_TMP}_work"
ncatted -O -a long_name,velocity_potential,o,c,"velocity potential" "${F_TMP}_work"
ncatted -O -a units,velocity_potential,o,c,"m^2 s^(-2)" "${F_TMP}_work"
ncks -A -v velocity_potential "${F_TMP}_work" "${F_TMP}"

rm -f "${F_REF_LINK}" "${F_TMP}_single" "${F_TMP}_work"

echo "== Template gerado com sucesso: ${DIR_WORK}/${F_TMP}"
