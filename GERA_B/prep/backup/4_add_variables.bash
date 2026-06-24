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

LABELI="${1:?Informe LABELI}"
LABELF="${2:?Informe LABELF}"
FHR0="${3:?Informe passo entre inits, em horas}"
FHR="${4:?Informe forecast hour desejado, em horas}"

OUTDIR="${DIR_WORK}/output"
cd "${OUTDIR}"

find_fcst_file() {
    local idate="$1"
    local vdate="$2"

    local yyyy="${vdate:0:4}"
    local mm="${vdate:4:2}"
    local dd="${vdate:6:2}"
    local hh="${vdate:8:2}"

    local f1="${DIR_PREV}/${idate}/history.${yyyy}-${mm}-${dd}_${hh}.00.00.nc"
    local f2="${DIR_ALL_PREV}/history.${yyyy}-${mm}-${dd}_${hh}.00.00.nc"

    if [ -s "${f1}" ]; then
        echo "${f1}"
        return 0
    fi

    if [ -s "${f2}" ]; then
        echo "${f2}"
        return 0
    fi

    return 1
}

has_var() {
    local varname="$1"
    local file="$2"
    ncks -m -v "${varname}" "${file}" >/dev/null 2>&1
}

append_if_exists() {
    local varname="$1"
    local src="$2"
    local dst="$3"

    if has_var "${varname}" "${src}"; then
        ncks -A -v "${varname}" "${src}" "${dst}"
        echo "   + variável adicionada: ${varname}"
    else
        echo "   - variável ausente, pulando: ${varname}"
    fi
}

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

    full_file="${vdate}/FULL_f${FHR}.nc"
    tmp_file="${vdate}/tmp_file_f${FHR}h.nc"

    if [ ! -s "${full_file}" ]; then
        echo "   AVISO: arquivo base não existe: ${full_file}. Pulando."
        idate="$("${WRFBIN}/da_advance_time.exe" "${idate}" "+${FHR0}h")"
        continue
    fi

    icnt=$((icnt+1))

    # --------------------------------------------------------
    # Diagnóstico de temperatura e umidade específica
    # Para o seu history, usar:
    #   temperature = theta * (pressure/100000)^(2/7)
    #   spechum     = qv/(1+qv)
    # --------------------------------------------------------
    if ! has_var "theta" "${f_fcst}"; then
        echo "ERRO: variável theta não encontrada em ${f_fcst}"
        exit 1
    fi

    if ! has_var "pressure" "${f_fcst}"; then
        echo "ERRO: variável pressure não encontrada em ${f_fcst}"
        exit 1
    fi

    if ! has_var "qv" "${f_fcst}"; then
        echo "ERRO: variável qv não encontrada em ${f_fcst}"
        exit 1
    fi

    ncap2 -O -s 'temperature=theta*(pressure/100000.0)^(2.0/7.0); spechum=qv/(1.0+qv)' \
        "${f_fcst}" "${tmp_file}"

    ncks -A -v temperature,spechum "${tmp_file}" "${full_file}"
    echo "   + variáveis adicionadas: temperature, spechum"

    append_if_exists "surface_pressure"       "${f_fcst}" "${full_file}"
    append_if_exists "uReconstructZonal"      "${f_fcst}" "${full_file}"
    append_if_exists "uReconstructMeridional" "${f_fcst}" "${full_file}"
    append_if_exists "relhum"                 "${f_fcst}" "${full_file}"

    for var in qc qi qr qs qg; do
        append_if_exists "${var}" "${f_fcst}" "${full_file}"
    done

    rm -f "${tmp_file}"

    idate="$("${WRFBIN}/da_advance_time.exe" "${idate}" "+${FHR0}h")"
done

echo "== Total de casos processados: ${icnt}"
