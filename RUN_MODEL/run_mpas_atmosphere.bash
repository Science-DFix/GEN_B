#!/bin/bash
# ==============================================================================
# run_mpas_atmosphere.bash — Ungrib + Init MPAS-A
# Cluster: Jaci (CPTEC/INPE)
# Chamado por: master_run.bash
# ==============================================================================

# --- Caminhos fixos ---
DIR_DATAOUT="/lustre/projetos/satdas/diego_workdir/SOURCE/rodadas/MPAS-A"
DIR_DATAIN_GFS="/lustre/projetos/satdas/diego_workdir/SOURCE/datainput/gfs"
FILE_BASE_INI="/lustre/projetos/satdas/diego_workdir/SOURCE/FILE_BASE"
DIR_WPS="/lustre/projetos/satdas/diego_workdir/WPS"
ENV_ALL="/lustre/projetos/satdas/diego_workdir/env_wrf_wps.bash"

# DIR_EXE e PRECISION vêm do master_run.bash
DIR_EXE=${DIR_EXE:-"/lustre/projetos/satdas/diego_workdir/build-mpich/bin"}
PRECISION=${PRECISION:-"double"}

# --- Ambiente ---
# NÃO fazer module purge — o ambiente MPICH já está carregado pelo PBS
source "$ENV_ALL"

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
start_date_for_date="${ano}-${mes}-${dia} ${hora}:00:00"
end_date=$(date -d "${start_date_for_date} 2 days" "+%Y-%m-%d_%H:%M:%S")

WORK_DIR="${DIR_DATAOUT}/${TIMESTAMP}"
NP_RUN=${NP:-256}

echo "--- Init [${PRECISION}]: $TIMESTAMP | start: ${start_date} | end: ${end_date} ---"

mkdir -p "$WORK_DIR" && cd "$WORK_DIR" || exit 1

# --- Links ---
ln -sf "${DIR_WPS}/ungrib.exe" .
ln -sf "${DIR_WPS}/link_grib.csh" .
ln -sf "${DIR_WPS}/ungrib/Variable_Tables/Vtable.GFS" Vtable
ln -sf "${FILE_BASE_INI}/60km/x1.163842.grid.nc" .
ln -sf "${FILE_BASE_INI}/60km/x1.163842.static.nc" .
ln -sf "${FILE_BASE_INI}/60km/x1.163842.graph.info.part.${NP_RUN}" .
ln -sf "${DIR_EXE}/mpas_init_atmosphere" init_atmosphere_model

# --- namelist.wps ---
cp "${FILE_BASE_INI}/namelist.wps" .
sed -i "s/^[[:space:]]*start_date[[:space:]]*=.*/ start_date = '${start_date}',/" namelist.wps
sed -i "s/^[[:space:]]*end_date[[:space:]]*=.*/ end_date   = '${end_date}',/"   namelist.wps

# --- Ungrib ---
./link_grib.csh "${DIR_DATAIN_GFS}/${TIMESTAMP}/gfs.0p25.${TIMESTAMP}.f*"
if [ ! -f "namelist.wps" ]; then
    echo "ERRO: namelist.wps não encontrado"
    exit 1
fi
./ungrib.exe > log.ungrib.out 2>&1

NFILE=$(ls FILE:* 2>/dev/null | wc -l)
if [ "$NFILE" -eq 0 ]; then
    echo "ERRO: ungrib não gerou arquivos FILE:*"
    tail -10 log.ungrib.out
    exit 1
fi
echo "ungrib OK — ${NFILE} arquivos FILE:* gerados"

mkdir -p met_data
mv FILE:* met_data/
ln -sf met_data/FILE:* .

# --- namelist.init_atmosphere ---
cp "${FILE_BASE_INI}/namelist.init_atmosphere" .
sed -i "s/^[[:space:]]*config_start_time[[:space:]]*=.*/ config_start_time = '${start_date}',/" namelist.init_atmosphere
sed -i "s/^[[:space:]]*config_stop_time[[:space:]]*=.*/ config_stop_time  = '${start_date}',/" namelist.init_atmosphere

# --- streams.init_atmosphere ---
cp "${FILE_BASE_INI}/streams.init_atmosphere" .

# --- Execução ---
ulimit -s unlimited
echo "Rodando init_atmosphere_model [${PRECISION}] com ${NP_RUN} processos..."
mpiexec -n ${NP_RUN} -iface hsn0 -bind-to core -launcher fork ./init_atmosphere_model

if [ $? -eq 0 ]; then
    echo "--- Init SUCESSO: $TIMESTAMP [${PRECISION}] ---"
    exit 0
else
    echo "--- Init ERRO: $TIMESTAMP [${PRECISION}] ---"
    tail -20 log.init_atmosphere.0000.out 2>/dev/null
    exit 1
fi
