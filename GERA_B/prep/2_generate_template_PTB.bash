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

# Usar mpasout (restart completo) em vez de history
# O template precisa apenas da estrutura da grade (theta, dimensões)
# Qualquer mpasout serve — usamos o f24 da primeira rodada
REF_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/PREV_MPAS/2026010100/mpasout.2026-01-02_00.00.00.nc"

f_ref="MPAS_x1.163842.nc"
f_tmp="template_PTB.nc"

mkdir -p "${DIR_WORK}"
cd "${DIR_WORK}"

ln -fs "${REF_FILE}" "./${f_ref}"

# Extrair theta como base do template (zeros)
ncks -v theta "${f_ref}" "${f_tmp}_single"
ncap2 -A -s "theta=0.0" "${f_tmp}_single"

# Criar stream_function a partir do template zerado
cp "${f_tmp}_single" "${f_tmp}_work"
ncrename -v theta,stream_function "${f_tmp}_work"
ncatted -a long_name,stream_function,o,c,"stream function" "${f_tmp}_work"
ncatted -a units,stream_function,o,c,"m^2 s^(-1)" "${f_tmp}_work"
ncks -A -v stream_function "${f_tmp}_work" "${f_tmp}"

# Criar velocity_potential a partir do template zerado
cp "${f_tmp}_single" "${f_tmp}_work"
ncrename -v theta,velocity_potential "${f_tmp}_work"
ncatted -a long_name,velocity_potential,o,c,"velocity potential" "${f_tmp}_work"
ncatted -a units,velocity_potential,o,c,"m^2 s^(-1)" "${f_tmp}_work"
ncks -A -v velocity_potential "${f_tmp}_work" "${f_tmp}"

# Limpeza
rm "${f_ref}" "${f_tmp}_single" "${f_tmp}_work"

echo "Template PTB gerado em: ${DIR_WORK}/${f_tmp}"
ls -lh "${DIR_WORK}/${f_tmp}"
