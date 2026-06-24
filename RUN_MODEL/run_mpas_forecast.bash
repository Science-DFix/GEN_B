#!/bin/bash
# ==============================================================================
# run_mpas_forecast.bash — Previsão MPAS-A
# Cluster: Jaci (CPTEC/INPE)
# Chamado por: master_run.bash
# ==============================================================================

# --- Caminhos fixos ---
DIR_DATAOUT="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/PREV_MPAS"
DIR_DATAIN_MPAS="/lustre/projetos/satdas/diego_workdir/SOURCE/rodadas/MPAS-A"
FILE_BASE_INI="/lustre/projetos/satdas/diego_workdir/SOURCE/FILE_BASE"

# DIR_EXE, DIR_PHYSICS e PRECISION vêm do master_run.bash
DIR_EXE=${DIR_EXE:-"/lustre/projetos/satdas/diego_workdir/build-mpich/bin"}
DIR_PHYSICS=${DIR_PHYSICS:-"/lustre/projetos/satdas/diego_workdir/build-mpich/_deps/mpas_data-src/atmosphere/physics_wrf/files"}
PRECISION=${PRECISION:-"double"}

# --- Parâmetros do master (com defaults) ---
RUN_DURATION=${RUN_DURATION:-"2_00:00:00"}
OUTPUT_INTERVAL=${OUTPUT_INTERVAL:-"06:00:00"}
DIAG_INTERVAL=${DIAG_INTERVAL:-"03:00:00"}
DT=${DT:-"360"}
RADT_INTERVAL=${RADT_INTERVAL:-"00:30:00"}
SST_UPDATE=${SST_UPDATE:-"false"}
IAU_OPTION=${IAU_OPTION:-"off"}

# --- Ambiente ---
# NÃO fazer module purge — o ambiente MPICH já está carregado pelo PBS
source "/lustre/projetos/satdas/diego_workdir/env_wrf_wps.bash"

# --- Validação ---
if [ -z "$TIMESTAMP" ]; then
    echo "ERRO: TIMESTAMP não definido."
    exit 1
fi

ano=${TIMESTAMP:0:4}
mes=${TIMESTAMP:4:2}
dia=${TIMESTAMP:6:2}
hora=${TIMESTAMP:8:2}
start_date="${ano}-${mes}-${dia}_${hora}:00:00"

WORK_DIR="${DIR_DATAOUT}/${TIMESTAMP}"
NP_RUN=${NP:-256}

echo "--- Forecast [${PRECISION}]: $TIMESTAMP | ${start_date} | ${RUN_DURATION} | IAU=${IAU_OPTION} ---"

# --- Verificações ---
if [ ! -f "${DIR_DATAIN_MPAS}/${TIMESTAMP}/x1.163842.init.nc" ]; then
    echo "ERRO: init.nc não encontrado"
    exit 1
fi
if [ ! -f "${DIR_EXE}/mpas_atmosphere" ]; then
    echo "ERRO: mpas_atmosphere não encontrado em ${DIR_EXE}"
    exit 1
fi

mkdir -p "$WORK_DIR" && cd "$WORK_DIR" || exit 1

# --- Links ---
ln -sf "${DIR_DATAIN_MPAS}/${TIMESTAMP}/x1.163842.init.nc" .
ln -sf "${DIR_EXE}/mpas_atmosphere" .
ln -sf "${FILE_BASE_INI}/60km/x1.163842.graph.info.part.${NP_RUN}" .
ln -sf "${FILE_BASE_INI}/invariant/x1.163842.invariant.nc" invariant.nc

for f in "${DIR_PHYSICS}"/*.TBL "${DIR_PHYSICS}"/*.DBL \
          "${DIR_PHYSICS}"/*DATA "${DIR_PHYSICS}"/VERSION \
          "${DIR_PHYSICS}"/COMPATIBILITY; do
    [ -e "$f" ] && ln -sf "$f" ./
done
ln -sf "${DIR_PHYSICS}/RRTMG_SW_DATA.DBL" ./RRTMG_SW_DATA
ln -sf "${DIR_PHYSICS}/RRTMG_LW_DATA.DBL" ./RRTMG_LW_DATA

# --- IAU ---
if [ "${IAU_OPTION}" = "on" ]; then
    IAU_FILE="${DIR_DATAIN_MPAS}/${TIMESTAMP}/x1.163842.AmB.${ano}-${mes}-${dia}_${hora}.00.00.nc"
    if [ -f "${IAU_FILE}" ]; then
        ln -sf "${IAU_FILE}" .
        echo "IAU ativado: $(basename ${IAU_FILE})"
    else
        echo "AVISO: IAU_OPTION=on mas arquivo AmB não encontrado. Desativando IAU."
        IAU_OPTION="off"
    fi
fi

# --- SST ---
if [ "${SST_UPDATE}" = "true" ]; then
    if [ -f "${DIR_DATAIN_MPAS}/${TIMESTAMP}/x1.163842.sfc_update.nc" ]; then
        ln -sf "${DIR_DATAIN_MPAS}/${TIMESTAMP}/x1.163842.sfc_update.nc" .
        echo "SST update ativado"
    else
        echo "AVISO: sfc_update.nc não encontrado. Desativando SST_UPDATE."
        SST_UPDATE="false"
    fi
fi

# --- Configurações ---
cp "${FILE_BASE_INI}/core_atmosphere/namelist.atmosphere" .
cp "${FILE_BASE_INI}/core_atmosphere/streams.atmosphere" .
cp "${FILE_BASE_INI}/core_atmosphere/stream_list.atmosphere."* .

sed -i -E "s|config_start_time\s*=\s*'[^']*'|config_start_time = '${start_date}'|"              namelist.atmosphere
sed -i -E "s|config_run_duration\s*=\s*'[^']*'|config_run_duration = '${RUN_DURATION}'|"        namelist.atmosphere
sed -i -E "s|config_dt\s*=\s*[0-9.]+|config_dt = ${DT}.0|"                                      namelist.atmosphere
sed -i -E "s|config_radtlw_interval\s*=\s*'[^']*'|config_radtlw_interval = '${RADT_INTERVAL}'|" namelist.atmosphere
sed -i -E "s|config_radtsw_interval\s*=\s*'[^']*'|config_radtsw_interval = '${RADT_INTERVAL}'|" namelist.atmosphere
sed -i -E "s|config_sst_update\s*=\s*\S+|config_sst_update = ${SST_UPDATE}|"                    namelist.atmosphere
sed -i -E "s|config_IAU_option\s*=\s*'[^']*'|config_IAU_option = '${IAU_OPTION}'|"              namelist.atmosphere

sed -i "/history\.\$Y/,/output_interval/ s|output_interval=\"[^\"]*\"|output_interval=\"${OUTPUT_INTERVAL}\"|" streams.atmosphere
sed -i "/diag\.\$Y/,/output_interval/ s|output_interval=\"[^\"]*\"|output_interval=\"${DIAG_INTERVAL}\"|"      streams.atmosphere

if [ "${SST_UPDATE}" = "true" ]; then
    sed -i "/sfc_update/,/input_interval/ s|input_interval=\"none\"|input_interval=\"24:00:00\"|" streams.atmosphere
fi

# --- Execução ---
ulimit -s unlimited
export GFORTRAN_CONVERT_UNIT='big_endian:101-200'
echo "Rodando mpas_atmosphere [${PRECISION}] com ${NP_RUN} processos..."
mpiexec -n ${NP_RUN} -iface hsn0 -bind-to core -launcher fork ./mpas_atmosphere

if [ $? -eq 0 ]; then
    echo "--- Forecast SUCESSO: $TIMESTAMP [${PRECISION}] ---"
    ls -lh history.*.nc diag.*.nc mpasout.*.nc 2>/dev/null | awk '{print "  "$NF, $5}'
    exit 0
else
    echo "--- Forecast ERRO: $TIMESTAMP [${PRECISION}] ---"
    tail -20 log.atmosphere.0000.err 2>/dev/null
    exit 1
fi
