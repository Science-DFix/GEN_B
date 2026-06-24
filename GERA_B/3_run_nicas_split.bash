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

NICAS_DIR="${DIR_PROC}/NICAS.split"
HDIAG_VAR_DIR="${DIR_PROC}/HDIAG_VAR"
MERGE_DIR="${HDIAG_VAR_DIR}/merge"
WORKDIR="${NICAS_DIR}"

# Variáveis ativas do grupo 1
LIST_VARS="stream_function velocity_potential temperature spechum surface_pressure"

BUILDROOT="/lustre/projetos/satdas/diego_workdir/build-mpich"
EXEDIR="${BUILDROOT}/bin"
PHYSFILESDIR="${BUILDROOT}/_deps/mpas_data-src/atmosphere/physics_wrf/files"
JEDI_TEST_BUILD_DIR="${BUILDROOT}/mpas-jedi/test"

# Arquivos de grade 60km
GRAPH_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/invariant/x1.163842.graph.info.part.64"
INVARIANT_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/invariant/x1.163842.invariant.nc"

# Background — mesmo mpasout dos scripts 1 e 2a
BG_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/PREV_MPAS/2026010100/mpasout.2026-01-02_00.00.00.nc"
DATE_YAML="2026-01-02T00:00:00Z"
DATE_FILE="2026-01-02_00.00.00"

# init.nc — derivado automaticamente do DATE_FILE
INIT_DATE=$(echo "${DATE_FILE}" | sed 's/[-.]//g' | sed 's/[_]//g' | cut -c1-10)
INIT_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/rodadas/MPAS-A/${INIT_DATE}/x1.163842.init.nc"

# Converter DATE_FILE para formato do namelist
NAMELIST_DATE=$(echo "${DATE_FILE}" | sed 's/\./:/g' | sed 's/_\([0-9][0-9]\):\([0-9][0-9]\):\([0-9][0-9]\)/_\1:\2:\3/')

RES="163842"
NTASKS=64

PBS_QUEUE="pesqextra"
PBS_WALLTIME="04:00:00"

# ============================================================
# Preparação
# ============================================================
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==============================================="
echo "3) RUN NICAS SPLIT"
echo "==============================================="
echo "WORKDIR      = ${WORKDIR}"
echo "MERGE_DIR    = ${MERGE_DIR}"
echo "LIST_VARS    = ${LIST_VARS}"
echo "DATE_FILE    = ${DATE_FILE}"
echo "INIT_DATE    = ${INIT_DATE}"
echo "INIT_FILE    = ${INIT_FILE}"
echo "NAMELIST_DATE= ${NAMELIST_DATE}"
echo "BG_FILE      = ${BG_FILE}"
echo ""

# ============================================================
# Checagens
# ============================================================
for f in \
  "${EXEDIR}/mpasjedi_error_covariance_toolbox.x" \
  "${GRAPH_FILE}" \
  "${INVARIANT_FILE}" \
  "${INIT_FILE}" \
  "${BG_FILE}" \
  "${MERGE_DIR}/mpas.cor_rh.nc" \
  "${MERGE_DIR}/mpas.cor_rv.nc"
do
  if [ ! -e "${f}" ]; then
    echo "ERRO: arquivo não encontrado: ${f}"
    exit 1
  fi
done

# ============================================================
# Links dos arquivos de merge no diretório NICAS.split
# ============================================================
ln -sf "${MERGE_DIR}/mpas.cor_rh.nc" ./mpas.cor_rh.nc
ln -sf "${MERGE_DIR}/mpas.cor_rv.nc" ./mpas.cor_rv.nc

# ============================================================
# Loop por variável
# ============================================================
for variable in ${LIST_VARS}; do

  echo "-----------------------------------------------"
  echo "Processing NICAS for ${variable}"
  echo "-----------------------------------------------"

  mkdir -p "${variable}"
  cd "${variable}"

  # ==========================================================
  # Links principais
  # ==========================================================
  ln -sf "${GRAPH_FILE}"     "x1.${RES}.graph.info.part.${NTASKS}"
  ln -sf "${INVARIANT_FILE}" "x1.${RES}.invariant.nc"
  ln -sf "${INIT_FILE}"      "x1.${RES}.init.nc"
  ln -sf "${BG_FILE}"        "bg.${DATE_FILE}.nc"
  ln -sf "${BG_FILE}"        "templateFields.${RES}.nc"
  ln -sf "${BG_FILE}"        "background.nc"
  ln -sf "${BG_FILE}"        "control.nc"
  ln -sf "${BG_FILE}"        "ensemble.nc"

  # ==========================================================
  # namelist.atmosphere — gerado diretamente como nos scripts 1 e 2a
  # ==========================================================
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

  # ==========================================================
  # streams.atmosphere
  # ==========================================================
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

  # ==========================================================
  # stream_list — apenas a variável atual
  # ==========================================================
  for sl in background control ensemble analysis; do
    echo "${variable}" > "stream_list.atmosphere.${sl}"
  done

  # ==========================================================
  # geovars.yaml e keptvars.yaml
  # ==========================================================
  [ -f "${JEDI_TEST_BUILD_DIR}/geovars.yaml" ] && \
    ln -sf "${JEDI_TEST_BUILD_DIR}/geovars.yaml" ./geovars.yaml
  [ -f "${JEDI_TEST_BUILD_DIR}/keptvars.yaml" ] && \
    ln -sf "${JEDI_TEST_BUILD_DIR}/keptvars.yaml" ./keptvars.yaml

  # ==========================================================
  # Tabelas físicas
  # ==========================================================
  for f in GENPARM.TBL LANDUSE.TBL SOILPARM.TBL VEGPARM.TBL COMPATIBILITY VERSION \
           CAM_ABS_DATA.DBL CAM_AEROPT_DATA.DBL OZONE_DAT.TBL OZONE_LAT.TBL \
           OZONE_PLEV.TBL RRTMG_LW_DATA RRTMG_LW_DATA.DBL RRTMG_SW_DATA RRTMG_SW_DATA.DBL; do
    [ -e "${PHYSFILESDIR}/${f}" ] && ln -sf "${PHYSFILESDIR}/${f}" "${f}"
  done

  # ==========================================================
  # Parâmetros dependentes da variável
  # ==========================================================
  nc1max=15000
  if [ "${variable}" = "qc" ] || [ "${variable}" = "qi" ] || \
     [ "${variable}" = "qr" ] || [ "${variable}" = "qs" ] || \
     [ "${variable}" = "qg" ]; then
    nc1max=30000
  fi

  if [ "${variable}" = "surface_pressure" ]; then
    vert_level_dirac=1
  else
    vert_level_dirac=36
  fi

  # ==========================================================
  # YAML do NICAS — fiel ao tutorial
  # ==========================================================
  cat > run_nicas.yaml << EOF
geometry:
  nml_file: "./namelist.atmosphere"
  streams_file: "./streams.atmosphere"
  deallocate non-da fields: true
  bump vunit: "avgheight"

background:
  state variables: &vars
  - ${variable}
  filename: "./bg.${DATE_FILE}.nc"
  date: &date '${DATE_YAML}'
  stream name: control
  transform model to analysis: false

background error:
  covariance model: SABER

  saber central block:
    saber block name: BUMP_NICAS
    calibration:
      io:
        files prefix: mpas
      drivers:
        multivariate strategy: univariate
        compute nicas: true
        write local nicas: true
        write global nicas: true
        write nicas grids: true
        internal dirac test: true
      nicas:
        resolution: 8
        max horizontal grid size: ${nc1max}
      dirac:
      - longitude: -45.0
        latitude: 0.0
        level: ${vert_level_dirac}
        variable: ${variable}
      - longitude: -135.0
        latitude: 0.0
        level: ${vert_level_dirac}
        variable: ${variable}
      - longitude: 45.0
        latitude: 0.0
        level: ${vert_level_dirac}
        variable: ${variable}
      - longitude: 135.0
        latitude: 0.0
        level: ${vert_level_dirac}
        variable: ${variable}
      - longitude: -135.0
        latitude: 45.0
        level: ${vert_level_dirac}
        variable: ${variable}
      - longitude: -45.0
        latitude: 45.0
        level: ${vert_level_dirac}
        variable: ${variable}
      - longitude: 45.0
        latitude: 45.0
        level: ${vert_level_dirac}
        variable: ${variable}
      - longitude: 135.0
        latitude: 45.0
        level: ${vert_level_dirac}
        variable: ${variable}
      - longitude: -135.0
        latitude: -45.0
        level: ${vert_level_dirac}
        variable: ${variable}
      - longitude: -45.0
        latitude: -45.0
        level: ${vert_level_dirac}
        variable: ${variable}
      - longitude: 45.0
        latitude: -45.0
        level: ${vert_level_dirac}
        variable: ${variable}
      - longitude: 135.0
        latitude: -45.0
        level: ${vert_level_dirac}
        variable: ${variable}
      input model files:
      - parameter: rh
        file:
          filename: ../mpas.cor_rh.nc
          date: *date
          stream name: control
      - parameter: rv
        file:
          filename: ../mpas.cor_rv.nc
          date: *date
          stream name: control
      output model files:
      - parameter: nicas_norm
        file:
          filename: ./mpas.nicas_norm.nc
          date: *date
          stream name: control
      - parameter: dirac_nicas
        file:
          filename: ./mpas.dirac_nicas.nc
          date: *date
          stream name: control
EOF

  # ==========================================================
  # PBS
  # ==========================================================
  cat > run_nicas.pbs << EOF
#!/bin/bash
#PBS -S /bin/bash
#PBS -q ${PBS_QUEUE}
#PBS -l select=1:ncpus=${NTASKS}:mpiprocs=${NTASKS}
#PBS -l walltime=${PBS_WALLTIME}
#PBS -N NICAS_${variable}
#PBS -j oe
#PBS -o ${WORKDIR}/${variable}/nicas_job.out

#source /lustre/projetos/satdas/opt/spack/linux-sles15-zen4/gcc-13.3.0/lmod-8.7.37-6uohtfnul3kvi74dn5y2gj4dkj2hd77p/lmod/lmod/init/bash
#source /lustre/projetos/satdas/diego_workdir/spack_env_for_mpas_bundle/gcc13.3-openmpi.sh

export OMP_NUM_THREADS=1
export GFORTRAN_CONVERT_UNIT='big_endian:101-200'

source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash

cd ${WORKDIR}/${variable} || exit 1

#mpirun -np ${NTASKS} ${EXEDIR}/mpasjedi_error_covariance_toolbox.x  ./run_nicas.yaml ./run_nicas.runlog
mpiexec -n ${NTASKS} ${EXEDIR}/mpasjedi_error_covariance_toolbox.x ./run_nicas.yaml ./run_nicas.runlog

echo "NICAS ${variable} concluído: \$(date)"
EOF

  chmod +x run_nicas.pbs

  JOB_ID=$(qsub run_nicas.pbs)
  echo "${JOB_ID}" > job_id.txt
  echo "Job submetido para ${variable}: ${JOB_ID}"
  echo ""

  cd ..
done

echo "==============================================="
echo "3) NICAS SPLIT SUBMETIDO — aguardando jobs"
echo "==============================================="
echo "Monitorar: qstat"
