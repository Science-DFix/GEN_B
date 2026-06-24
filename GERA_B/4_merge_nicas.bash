#!/bin/bash
set -euo pipefail

# ============================================================
# Ambiente
# ============================================================
source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash
module load nco

# ============================================================
# Configuração fixa
# ============================================================
DIR_GENB="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/GEN_B"
DIR_PROC="${DIR_GENB}/proc"

NICAS_DIR="${DIR_PROC}/NICAS.split"
WORKDIR="${NICAS_DIR}/merge"

list_vars="stream_function velocity_potential temperature spechum surface_pressure"

NCPUS=64
PBS_QUEUE="pesqextra"
PBS_WALLTIME="04:00:00"
PBS_JOBNAME="NICASmerge"

# ============================================================
# Preparação
# ============================================================
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==============================================="
echo "4) MERGE NICAS"
echo "==============================================="
echo "NICAS_DIR   = ${NICAS_DIR}"
echo "WORKDIR     = ${WORKDIR}"
echo "list_vars   = ${list_vars}"
echo "NCPUS       = ${NCPUS}"
echo ""

# ============================================================
# Checagens iniciais
# ============================================================
first_var=$(echo "${list_vars}" | awk '{print $1}')

if [ -z "${first_var}" ]; then
  echo "ERRO: list_vars está vazio."
  exit 1
fi

for variable in ${list_vars}; do
  if [ ! -d "${NICAS_DIR}/${variable}" ]; then
    echo "ERRO: diretório da variável não existe: ${NICAS_DIR}/${variable}"
    exit 1
  fi

  for f in mpas_nicas.nc mpas.nicas_norm.nc mpas.dirac_nicas.nc; do
    if [ ! -f "${NICAS_DIR}/${variable}/${f}" ]; then
      echo "ERRO: arquivo não encontrado: ${NICAS_DIR}/${variable}/${f}"
      exit 1
    fi
  done
done

# ============================================================
# Descoberta automática do número de arquivos locais
# ============================================================
nlocal=$(find "${NICAS_DIR}/${first_var}" -maxdepth 1 -type f \
  -name 'mpas_nicas_local_*.nc' | wc -l | awk '{print $1}')

if [ "${nlocal}" -eq 0 ]; then
  echo "ERRO: nenhum arquivo mpas_nicas_local_*.nc encontrado em ${NICAS_DIR}/${first_var}"
  exit 1
fi

ntotpad=$(printf "%06d" "${nlocal}")

echo "Número de arquivos locais detectados: ${nlocal}"
echo "Prefixo total detectado            : ${ntotpad}"
echo ""

# ============================================================
# Checa arquivos locais em todas as variáveis
# ============================================================
for itot in $(seq 1 "${nlocal}"); do
  itotpad=$(printf "%06d" "${itot}")
  local_file="mpas_nicas_local_${ntotpad}-${itotpad}.nc"
  local_grid="mpas_nicas_grids_local_${ntotpad}-${itotpad}.nc"

  for variable in ${list_vars}; do
    for f in "${NICAS_DIR}/${variable}/${local_file}" \
             "${NICAS_DIR}/${variable}/${local_grid}"; do
      if [ ! -f "${f}" ]; then
        echo "ERRO: arquivo não encontrado: ${f}"
        exit 1
      fi
    done
  done
done

echo "OK: todos os arquivos locais existem para todas as variáveis."
echo ""

# ============================================================
# Limpeza
# ============================================================
rm -f \
  merge_nicas_*.bash \
  merge_nicas.pbs \
  job_id.txt \
  merge_job.out \
  mpas_nicas_local_*.nc \
  mpas_nicas_grids_local_*.nc \
  mpas_nicas.nc \
  mpas.nicas_norm.nc \
  mpas.dirac_nicas.nc

# ============================================================
# 1) Scripts de merge dos arquivos locais
# ============================================================
for itot in $(seq 1 "${nlocal}"); do
  itotpad=$(printf "%06d" "${itot}")

  filename_full="mpas_nicas_local_${ntotpad}-${itotpad}.nc"
  filename_grids_full="mpas_nicas_grids_local_${ntotpad}-${itotpad}.nc"
  script_name="merge_nicas_${itotpad}.bash"

  cat > "${script_name}" << EOF
#!/bin/bash
set -euo pipefail
source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash
module load nco
cd "${WORKDIR}"
EOF

  first_full=1
  first_grid=1

  for variable in ${list_vars}; do
    src_full="../${variable}/${filename_full}"
    src_grid="../${variable}/${filename_grids_full}"

    if [ "${first_full}" -eq 1 ]; then
      echo "cp -f \"${src_full}\" \"${filename_full}\"" >> "${script_name}"
      first_full=0
    else
      echo "ncks -A \"${src_full}\" \"${filename_full}\"" >> "${script_name}"
    fi
    echo "ncatted -O -a _FillValue,global,d,, \"${filename_full}\" || true" >> "${script_name}"
    echo "ncatted -O -a eulaVlliF_,global,d,, \"${filename_full}\" || true" >> "${script_name}"

    if [ "${first_grid}" -eq 1 ]; then
      echo "cp -f \"${src_grid}\" \"${filename_grids_full}\"" >> "${script_name}"
      first_grid=0
    else
      echo "ncks -A \"${src_grid}\" \"${filename_grids_full}\"" >> "${script_name}"
    fi
    echo "ncatted -O -a _FillValue,global,d,, \"${filename_grids_full}\" || true" >> "${script_name}"
    echo "ncatted -O -a eulaVlliF_,global,d,, \"${filename_grids_full}\" || true" >> "${script_name}"
  done

  chmod +x "${script_name}"
done

# ============================================================
# 2) Script de merge do arquivo global mpas_nicas.nc
# ============================================================
global_id=$((nlocal + 1))
global_pad=$(printf "%06d" "${global_id}")
global_script="merge_nicas_${global_pad}.bash"

cat > "${global_script}" << EOF
#!/bin/bash
set -euo pipefail
source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash
module load nco
cd "${WORKDIR}"
EOF

first_global=1
for variable in ${list_vars}; do
  src_global="../${variable}/mpas_nicas.nc"
  if [ "${first_global}" -eq 1 ]; then
    echo "cp -f \"${src_global}\" \"mpas_nicas.nc\"" >> "${global_script}"
    first_global=0
  else
    echo "ncks -A \"${src_global}\" \"mpas_nicas.nc\"" >> "${global_script}"
  fi
  echo "ncatted -O -a _FillValue,global,d,, \"mpas_nicas.nc\" || true" >> "${global_script}"
  echo "ncatted -O -a eulaVlliF_,global,d,, \"mpas_nicas.nc\" || true" >> "${global_script}"
done

chmod +x "${global_script}"

# ============================================================
# 3) PBS para rodar os merges em paralelo
# ============================================================
ntotal_jobs=$((nlocal + 1))

cat > merge_nicas.pbs << EOF
#!/bin/bash
#PBS -S /bin/bash
#PBS -q ${PBS_QUEUE}
#PBS -l select=1:ncpus=${NCPUS}:mpiprocs=${NCPUS}
#PBS -l walltime=${PBS_WALLTIME}
#PBS -N ${PBS_JOBNAME}
#PBS -j oe
#PBS -o ${WORKDIR}/merge_job.out

set -euo pipefail

source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash
module load nco

cd "${WORKDIR}" || exit 1

SECONDS=0
ntotal_jobs=${ntotal_jobs}
ncpus=${NCPUS}
nbatch=\$(( (ntotal_jobs + ncpus - 1) / ncpus ))
itot=0

echo "===== Iniciando merge NICAS ====="
echo "ntotal_jobs = \${ntotal_jobs}"
echo "ncpus       = \${ncpus}"
echo "nbatch      = \${nbatch}"
echo "================================="

for ibatch in \$(seq 1 \${nbatch}); do
  echo "---- Batch \${ibatch}/\${nbatch} ----"
  for i in \$(seq 1 \${ncpus}); do
    itot=\$((itot + 1))
    if [ "\${itot}" -le "\${ntotal_jobs}" ]; then
      itotpad=\$(printf "%06d" "\${itot}")
      echo "Rodando: ./merge_nicas_\${itotpad}.bash"
      ./merge_nicas_\${itotpad}.bash &
    fi
  done
  wait
done

echo "===== Merge dos NICAS concluído ====="
echo "ELAPSED TIME = \${SECONDS} s"

# ============================================================
# Merge dos diagnósticos nicas_norm e dirac_nicas
# ============================================================
rm -f mpas.nicas_norm.nc mpas.dirac_nicas.nc

first_norm=1
first_dirac=1

for variable in ${list_vars}; do
  src_norm="../\${variable}/mpas.nicas_norm.nc"
  src_dirac="../\${variable}/mpas.dirac_nicas.nc"

  if [ "\${first_norm}" -eq 1 ]; then
    cp -f "\${src_norm}" mpas.nicas_norm.nc
    first_norm=0
  else
    ncks -A "\${src_norm}" mpas.nicas_norm.nc
  fi
  ncatted -O -a _FillValue,global,d,, mpas.nicas_norm.nc || true
  ncatted -O -a eulaVlliF_,global,d,, mpas.nicas_norm.nc || true

  if [ "\${first_dirac}" -eq 1 ]; then
    cp -f "\${src_dirac}" mpas.dirac_nicas.nc
    first_dirac=0
  else
    ncks -A "\${src_dirac}" mpas.dirac_nicas.nc
  fi
  ncatted -O -a _FillValue,global,d,, mpas.dirac_nicas.nc || true
  ncatted -O -a eulaVlliF_,global,d,, mpas.dirac_nicas.nc || true
done

echo "===== Diagnósticos agregados concluídos ====="
ls -lh mpas_nicas.nc mpas.nicas_norm.nc mpas.dirac_nicas.nc || true
EOF

chmod +x merge_nicas.pbs

# ============================================================
# Submeter
# ============================================================
echo ""
echo "==============================================="
echo "Submetendo merge NICAS..."
echo "==============================================="
JOB_ID=$(qsub merge_nicas.pbs)
echo "${JOB_ID}" > job_id.txt
echo "JOB_ID = ${JOB_ID}"
echo ""
echo "Monitorar: qstat ${JOB_ID}"
echo "Log: ${WORKDIR}/merge_job.out"
echo ""
echo "==============================================="
echo "4) MERGE NICAS SUBMETIDO"
echo "==============================================="
