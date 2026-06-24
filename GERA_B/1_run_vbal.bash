#!/bin/bash
set -euo pipefail

# ============================================================
# Ambiente
# ============================================================
source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash

# ============================================================
# Configuração fixa
# ============================================================
DIR_GENB="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/GEN_B"
DIR_PROC="${DIR_GENB}/proc"
DIR_SAMPLES="${DIR_PROC}/samples"
DIR_SAMPLES_UNB="${DIR_PROC}/samplesUnbalanced"
DIR_VBAL="${DIR_PROC}/VBAL"

BUILDROOT="/lustre/projetos/satdas/diego_workdir/build-mpich"
EXEDIR="${BUILDROOT}/bin"
PHYSFILESDIR="${BUILDROOT}/_deps/mpas_data-src/atmosphere/physics_wrf/files"

# Arquivos auxiliares do MPAS-JEDI (stream_list, geovars, keptvars)
JEDI_TEST_BUILD_DIR="${BUILDROOT}/mpas-jedi/test"

# Arquivos de grade 60km
GRAPH_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/invariant/x1.163842.graph.info.part.64"
INVARIANT_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/invariant/x1.163842.invariant.nc"

# Background: usar mpasout do ciclo desejado
# NOTA: DATE_YAML, DATE_FILE e BG_FILE devem ser consistentes entre si
# Ver README_data_referencia_vbal.md para instruções de como trocar a data
BG_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/PREV_MPAS/2026010100/mpasout.2026-01-02_00.00.00.nc"
DATE_YAML="2026-01-02T00:00:00Z"
DATE_FILE="2026-01-02_00.00.00"

# init.nc — derivado automaticamente do DATE_FILE
# DATE_FILE="2026-01-02_00.00.00" → remove "-", "." e "_" → "2026010200"
INIT_DATE=$(echo "${DATE_FILE}" | sed 's/[-.]//g' | sed 's/[_]//g' | cut -c1-10)
INIT_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/rodadas/MPAS-A/${INIT_DATE}/x1.163842.init.nc"

NMEMBERS=32
NTASKS=64
RES="163842"
SAMPLE_PREFIX="PTB_f48mf24"

PBS_QUEUE="pesqextra"
PBS_WALLTIME="06:00:00"
PBS_JOBNAME="MPAS_VBAL"

# ============================================================
# Preparação de diretórios
# ============================================================
mkdir -p "${DIR_VBAL}"
mkdir -p "${DIR_SAMPLES_UNB}"
cd "${DIR_VBAL}"

echo "==============================================="
echo "1) RUN VBAL"
echo "==============================================="
echo "DIR_VBAL        = ${DIR_VBAL}"
echo "DIR_SAMPLES     = ${DIR_SAMPLES}"
echo "DIR_SAMPLES_UNB = ${DIR_SAMPLES_UNB}"
echo "NMEMBERS        = ${NMEMBERS}"
echo "DATE_FILE       = ${DATE_FILE}"
echo "INIT_DATE       = ${INIT_DATE}"
echo "INIT_FILE       = ${INIT_FILE}"
echo "BG_FILE         = ${BG_FILE}"
echo "DATE_YAML       = ${DATE_YAML}"
echo ""

# ============================================================
# Checagens
# ============================================================
for f in \
  "${EXEDIR}/mpasjedi_error_covariance_toolbox.x" \
  "${GRAPH_FILE}" \
  "${INVARIANT_FILE}" \
  "${INIT_FILE}" \
  "${BG_FILE}"
do
  if [ ! -e "${f}" ]; then
    echo "ERRO: arquivo não encontrado: ${f}"
    exit 1
  fi
done

nsamp=$(find "${DIR_SAMPLES}" -maxdepth 1 \( -type l -o -type f \) -name "${SAMPLE_PREFIX}_*.nc" | wc -l)
if [ "${nsamp}" -ne "${NMEMBERS}" ]; then
  echo "ERRO: número de samples (${nsamp}) diferente de NMEMBERS (${NMEMBERS})"
  exit 1
fi

# ============================================================
# Links principais
# ============================================================
ln -sf "${INVARIANT_FILE}" "x1.${RES}.invariant.nc"
ln -sf "${GRAPH_FILE}"     "x1.${RES}.graph.info.part.${NTASKS}"
ln -sf "${INIT_FILE}"      "x1.${RES}.init.nc"
ln -sf "${BG_FILE}"        "bg.${DATE_FILE}.nc"
ln -sf "${BG_FILE}"        "templateFields.${RES}.nc"
ln -sf "${BG_FILE}"        "background.nc"
ln -sf "${BG_FILE}"        "control.nc"
ln -sf "${BG_FILE}"        "ensemble.nc"

# ============================================================
# namelist.atmosphere (para JEDI — physics desligada)
# ============================================================

# Converter DATE_FILE para formato do namelist: 2026-01-02_00.00.00 → 2026-01-02_00:00:00
NAMELIST_DATE=$(echo "${DATE_FILE}" | sed 's/\./:/g' | sed 's/_\([0-9][0-9]\):\([0-9][0-9]\):\([0-9][0-9]\)/_\1:\2:\3/')

cat > namelist.atmosphere << EOF
&nhyd_model
    config_dt = 360
    config_start_time = '${NAMELIST_DATE}'
    config_run_duration = '0_06:00:00'
    config_split_dynamics_transport = true
    config_number_of_sub_steps = 2
    config_dynamics_split_steps = 3
    config_h_mom_eddy_visc2 = 0.0
    config_h_mom_eddy_visc4 = 0.0
    config_v_mom_eddy_visc2 = 0.0
    config_h_theta_eddy_visc2 = 0.0
    config_h_theta_eddy_visc4 = 0.0
    config_v_theta_eddy_visc2 = 0.0
    config_horiz_mixing = '2d_smagorinsky'
    config_len_disp = 60000.0
    config_visc4_2dsmag = 0.05
    config_w_adv_order = 3
    config_theta_adv_order = 3
    config_scalar_adv_order = 3
    config_u_vadv_order = 3
    config_w_vadv_order = 3
    config_theta_vadv_order = 3
    config_scalar_vadv_order = 3
    config_scalar_advection = true
    config_positive_definite = false
    config_monotonic = true
    config_coef_3rd_order = 0.25
    config_epssm = 0.1
    config_smdiv = 0.1
/
&damping
    config_zd = 22000.0
    config_xnutr = 0.2
/
&io
    config_pio_num_iotasks = 0
    config_pio_stride = 1
/
&decomposition
    config_block_decomp_file_prefix = 'x1.${RES}.graph.info.part.'
/
&physics
    config_sst_update = false
    config_sstdiurn_update = false
    config_deepsoiltemp_update = false
    config_radtlw_interval = 'none'
    config_radtsw_interval = 'none'
    config_o3climatology = false
    config_bucket_update = 'none'
    config_physics_suite = 'none'
/
&assimilation
    config_jedi_da = true
/
EOF

# ============================================================
# streams.atmosphere (precisão simples — build com DOUBLE_PRECISION=OFF)
# ============================================================
cat > streams.atmosphere << EOF
<streams>

<immutable_stream name="input"
                  type="input"
                  precision="single"
                  io_type="pnetcdf,cdf5"
                  filename_template="x1.${RES}.init.nc"
                  input_interval="initial_only" />

<immutable_stream name="invariant"
                  type="input"
                  precision="single"
                  io_type="pnetcdf,cdf5"
                  filename_template="x1.${RES}.invariant.nc"
                  input_interval="initial_only" />

<immutable_stream name="da_state"
                  type="output"
                  precision="single"
                  io_type="pnetcdf,cdf5"
                  filename_template="mpasout.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  clobber_mode="overwrite"
                  output_interval="0_01:00:00" />

<stream name="background"
        type="input;output"
        precision="single"
        io_type="pnetcdf,cdf5"
        filename_template="background.nc"
        input_interval="initial_only"
        output_interval="0_01:00:00"
        clobber_mode="overwrite">
        <file name="stream_list.atmosphere.background"/>
</stream>

<stream name="analysis"
        type="output"
        precision="single"
        io_type="pnetcdf,cdf5"
        filename_template="analysis.nc"
        output_interval="0_01:00:00"
        clobber_mode="overwrite">
        <file name="stream_list.atmosphere.analysis"/>
</stream>

<stream name="control"
        type="input;output"
        precision="single"
        io_type="pnetcdf,cdf5"
        filename_template="control.nc"
        input_interval="initial_only"
        output_interval="0_01:00:00"
        clobber_mode="overwrite">
        <file name="stream_list.atmosphere.control"/>
</stream>

<stream name="ensemble"
        type="input;output"
        precision="single"
        io_type="pnetcdf,cdf5"
        filename_template="ensemble.nc"
        input_interval="initial_only"
        output_interval="0_01:00:00"
        clobber_mode="overwrite">
        <file name="stream_list.atmosphere.ensemble"/>
</stream>

</streams>
EOF

# ============================================================
# stream_list.atmosphere.*
# ============================================================
for sl in background control ensemble analysis; do
  cat > "stream_list.atmosphere.${sl}" << EOF
spechum
stream_function
surface_pressure
temperature
velocity_potential
EOF
done

# Tentar usar os oficiais do build se existirem
if [ -d "${JEDI_TEST_BUILD_DIR}" ]; then
  for f in "${JEDI_TEST_BUILD_DIR}"/stream_list*; do
    [ -e "${f}" ] && ln -sf "${f}" "$(basename ${f})"
  done
fi

# Sobrescrever stream_list.atmosphere.control como no tutorial
cat > stream_list.atmosphere.control << EOF
spechum
stream_function
surface_pressure
temperature
velocity_potential
EOF

# ============================================================
# geovars.yaml e keptvars.yaml
# ============================================================
if [ -f "${JEDI_TEST_BUILD_DIR}/geovars.yaml" ]; then
  ln -sf "${JEDI_TEST_BUILD_DIR}/geovars.yaml" ./geovars.yaml
fi
if [ -f "${JEDI_TEST_BUILD_DIR}/keptvars.yaml" ]; then
  ln -sf "${JEDI_TEST_BUILD_DIR}/keptvars.yaml" ./keptvars.yaml
fi

# ============================================================
# Tabelas físicas
# ============================================================
for f in GENPARM.TBL LANDUSE.TBL SOILPARM.TBL VEGPARM.TBL COMPATIBILITY VERSION \
         CAM_ABS_DATA.DBL CAM_AEROPT_DATA.DBL OZONE_DAT.TBL OZONE_LAT.TBL \
         OZONE_PLEV.TBL RRTMG_LW_DATA RRTMG_LW_DATA.DBL RRTMG_SW_DATA RRTMG_SW_DATA.DBL; do
  [ -e "${PHYSFILESDIR}/${f}" ] && ln -sf "${PHYSFILESDIR}/${f}" "${f}"
done

# ============================================================
# Links locais dos samples
# ============================================================
for i in $(seq 1 "${NMEMBERS}"); do
  tag=$(printf "%03d" "${i}")
  ln -sf "${DIR_SAMPLES}/${SAMPLE_PREFIX}_${tag}.nc" "${SAMPLE_PREFIX}_${tag}.nc"
done

# ============================================================
# YAML do VBAL — fiel ao tutorial
# ============================================================
cat > run_vbal.yaml << EOF
_member config: &memberConfig
  state variables: &vars
  - stream_function
  - velocity_potential
  - temperature
  - spechum
  - surface_pressure
  date: &date '${DATE_YAML}'
  stream name: control
  transform model to analysis: false

geometry:
  nml_file: "./namelist.atmosphere"
  streams_file: "./streams.atmosphere"

background:
  state variables: *vars
  filename: "./bg.${DATE_FILE}.nc"
  date: *date
  stream name: control
  transform model to analysis: false

background error:
  covariance model: SABER

  iterative ensemble loading: true

  ensemble:
    members from template:
      template:
        <<: *memberConfig
        filename: ${DIR_SAMPLES}/${SAMPLE_PREFIX}_%mem%.nc
      pattern: '%mem%'
      nmembers: ${NMEMBERS}
      zero padding: 3

  output ensemble:
    filename: ${DIR_SAMPLES_UNB}/${SAMPLE_PREFIX}_%{member}%.nc
    date: *date
    stream name: control

  saber central block:
    saber block name: ID

  saber outer blocks:
  - saber block name: BUMP_VerticalBalance
    calibration:
      io:
        files prefix: mpas
      drivers:
        write local sampling: true
        write global sampling: true
        compute vertical covariance: true
        compute vertical balance: true
        write vertical balance: true
      sampling:
        computation grid size: 12000
        diagnostic grid size: 200
        reduced levels: 55
        averaging latitude width: 10.0
      vertical balance:
        vbal:
        - balanced variable: velocity_potential
          unbalanced variable: stream_function
          diagonal regression: true
        - balanced variable: temperature
          unbalanced variable: stream_function
        - balanced variable: surface_pressure
          unbalanced variable: stream_function
        pseudo inverse: true
        dominant mode: 20
EOF

# ============================================================
# Script PBS
# ============================================================
cat > run_vbal.pbs << EOF
#!/bin/bash
#PBS -S /bin/bash
#PBS -q ${PBS_QUEUE}
#PBS -l select=1:ncpus=${NTASKS}:mpiprocs=${NTASKS}
#PBS -l walltime=${PBS_WALLTIME}
#PBS -N ${PBS_JOBNAME}
#PBS -j oe
#PBS -o ${DIR_VBAL}/vbal_job.out

#source /lustre/projetos/satdas/opt/spack/linux-sles15-zen4/gcc-13.3.0/lmod-8.7.37-6uohtfnul3kvi74dn5y2gj4dkj2hd77p/lmod/lmod/init/bash
#source /lustre/projetos/satdas/diego_workdir/spack_env_for_mpas_bundle/gcc13.3-openmpi.sh
source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash
export OMP_NUM_THREADS=1
export GFORTRAN_CONVERT_UNIT='big_endian:101-200'

cd ${DIR_VBAL} || exit 1

mpirun -np ${NTASKS} ${EXEDIR}/mpasjedi_error_covariance_toolbox.x \
  ./run_vbal.yaml ./run_vbal.runlog

echo "VBAL concluído: \$(date)"
EOF

chmod +x run_vbal.pbs

# ============================================================
# Submeter
# ============================================================
echo ""
echo "==============================================="
echo "Submetendo VBAL"
echo "==============================================="
JOBID=$(qsub run_vbal.pbs)
echo "JOBID = ${JOBID}"
echo "${JOBID}" > job_id_vbal.txt
echo ""
echo "Monitorar: qstat ${JOBID}"
echo "Log: ${DIR_VBAL}/vbal_job.out"
echo "Log: ${DIR_VBAL}/run_vbal.runlog"
