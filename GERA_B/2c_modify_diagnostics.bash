#!/bin/bash
set -euo pipefail

# ============================================================
# Ambiente
# ============================================================
source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash

# ============================================================
# Configuração fixa
# ============================================================
DIR_GENB="/p/projetos/satdas/diego_workdir/SOURCE/dataout/GEN_B"
DIR_PROC="${DIR_GENB}/proc"

HDIAG_VAR_DIR="${DIR_PROC}/HDIAG_VAR"
HDIAG_VAR_MERGE_DIR="${HDIAG_VAR_DIR}/merge"

VARGROUP1_DIR="${HDIAG_VAR_DIR}/vargroup1"
VARGROUP2_DIR="${HDIAG_VAR_DIR}/vargroup2"

SCRIPT_DIR="/lustre/projetos/satdas/diego_workdir/SOURCE/scripts/GEN_B"

# ============================================================
# Controle da etapa
# 1 = sim | 2 = não
# Mantido no estilo do original
# ============================================================
include_hydrometeor=2   # 1: yes, 2: no
isTuneHdiag=1           # 1: yes
isTuneVar=1             # 1: yes

WORKDIR="${HDIAG_VAR_MERGE_DIR}"

# ============================================================
# Preparação
# ============================================================
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==============================================="
echo "2c) MODIFY DIAGNOSTICS"
echo "==============================================="
echo "WORKDIR             = ${WORKDIR}"
echo "VARGROUP1_DIR       = ${VARGROUP1_DIR}"
echo "VARGROUP2_DIR       = ${VARGROUP2_DIR}"
echo "SCRIPT_DIR          = ${SCRIPT_DIR}"
echo "include_hydrometeor = ${include_hydrometeor}"
echo "isTuneHdiag         = ${isTuneHdiag}"
echo "isTuneVar           = ${isTuneVar}"
echo ""

# ============================================================
# Checagens mínimas
# ============================================================
for f in \
  "${VARGROUP1_DIR}/mpas.cor_rh.nc" \
  "${VARGROUP1_DIR}/mpas.cor_rv.nc" \
  "${VARGROUP1_DIR}/mpas.stddev.nc"
do
  if [ ! -e "${f}" ]; then
    echo "ERRO: arquivo obrigatório não encontrado: ${f}"
    exit 1
  fi
done

if [ "${include_hydrometeor}" -eq 1 ]; then
  for f in \
    "${VARGROUP2_DIR}/mpas.cor_rh.nc" \
    "${VARGROUP2_DIR}/mpas.cor_rv.nc" \
    "${VARGROUP2_DIR}/mpas.stddev.nc"
  do
    if [ ! -e "${f}" ]; then
      echo "ERRO: include_hydrometeor=1, mas arquivo do vargroup2 não encontrado: ${f}"
      exit 1
    fi
  done
fi

# ============================================================
# Limpeza local
# ============================================================
rm -f \
  mpas.cor_rh.nc \
  mpas.cor_rv.nc \
  mpas.stddev.nc \
  etc_modify_cor.bash \
  etc_modify_missing.bash \
  etc_modify_var.bash

# ============================================================
# Copiar arquivos base do vargroup1
# ============================================================
cp "${VARGROUP1_DIR}/mpas.cor_rh.nc"  ./
cp "${VARGROUP1_DIR}/mpas.cor_rv.nc"  ./
cp "${VARGROUP1_DIR}/mpas.stddev.nc"  ./

echo "Arquivos base copiados de vargroup1:"
ls -l mpas.cor_rh.nc mpas.cor_rv.nc mpas.stddev.nc
echo ""

# ============================================================
# Mesclar arquivos do vargroup2 se necessário
# Mantido adaptado, mas desativado por enquanto
# ============================================================
if [ "${include_hydrometeor}" -eq 1 ]; then
  echo "include_hydrometeor = ${include_hydrometeor}"
  module load nco

  ncks -A -v qc,qi,qr,qs,qg "${VARGROUP2_DIR}/mpas.cor_rh.nc" ./mpas.cor_rh.nc
  ncks -A -v qc,qi,qr,qs,qg "${VARGROUP2_DIR}/mpas.cor_rv.nc" ./mpas.cor_rv.nc
  ncks -A -v qc,qi,qr,qs,qg "${VARGROUP2_DIR}/mpas.stddev.nc" ./mpas.stddev.nc

  echo "Hidrometeoros anexados a partir de vargroup2."
  echo ""
fi

# ============================================================
# Corrigir missing values para hidrometeoros se necessário
# Mantido preparado, mas desativado por enquanto
# ============================================================
if [ "${include_hydrometeor}" -eq 1 ]; then
  echo "include_hydrometeor = ${include_hydrometeor}"

  if [ ! -e "${SCRIPT_DIR}/etc_modify_missing.bash" ]; then
    echo "ERRO: script não encontrado: ${SCRIPT_DIR}/etc_modify_missing.bash"
    exit 1
  fi

  cp "${SCRIPT_DIR}/etc_modify_missing.bash" ./
  bash ./etc_modify_missing.bash
  echo ""
fi

# ============================================================
# Ajustar comprimentos de correlação se necessário
# ============================================================
if [ "${isTuneHdiag}" -eq 1 ]; then
  echo "isTuneHdiag = ${isTuneHdiag}"

  if [ ! -e "${SCRIPT_DIR}/etc_modify_cor.bash" ]; then
    echo "ERRO: script não encontrado: ${SCRIPT_DIR}/etc_modify_cor.bash"
    exit 1
  fi

  cp "${SCRIPT_DIR}/etc_modify_cor.bash" ./
  bash ./etc_modify_cor.bash
  echo ""
fi

# ============================================================
# Ajustar variâncias se necessário
# ============================================================
if [ "${isTuneVar}" -eq 1 ]; then
  echo "isTuneVar = ${isTuneVar}"

  if [ ! -e "${SCRIPT_DIR}/etc_modify_var.bash" ]; then
    echo "ERRO: script não encontrado: ${SCRIPT_DIR}/etc_modify_var.bash"
    exit 1
  fi

  cp "${SCRIPT_DIR}/etc_modify_var.bash" ./
  bash ./etc_modify_var.bash
  echo ""
fi

# ============================================================
# Resumo final
# ============================================================
echo "==============================================="
echo "2c FINALIZADO"
echo "==============================================="
echo "Diretório final: ${WORKDIR}"
echo ""
echo "Arquivos disponíveis:"
ls -l "${WORKDIR}"
echo ""
echo "Saídas principais:"
echo "${WORKDIR}/mpas.cor_rh.nc"
echo "${WORKDIR}/mpas.cor_rv.nc"
echo "${WORKDIR}/mpas.stddev.nc"
echo ""
