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
DIR_SAMPLES_UNB="${DIR_PROC}/samplesUnbalanced"
DIR_HDIAG_VAR="${DIR_PROC}/HDIAG_VAR"
WORKDIR="${DIR_HDIAG_VAR}/vargroup1"

BUILDROOT="/lustre/projetos/satdas/diego_workdir/build-mpich"
EXEDIR="${BUILDROOT}/bin"
PHYSFILESDIR="${BUILDROOT}/_deps/mpas_data-src/atmosphere/physics_wrf/files"
JEDI_TEST_BUILD_DIR="${BUILDROOT}/mpas-jedi/test"

# Arquivos de grade 60km
GRAPH_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/invariant/x1.163842.graph.info.part.64"
INVARIANT_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/invariant/x1.163842.invariant.nc"

# Background — mesmo mpasout usado no script 1
# NOTA: DATE_YAML, DATE_FILE e BG_FILE devem ser consistentes entre si
BG_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/PREV_MPAS/2026010100/mpasout.2026-01-02_00.00.00.nc"
DATE_YAML="2026-01-02T00:00:00Z"
DATE_FILE="2026-01-02_00.00.00"

# init.nc — derivado automaticamente do DATE_FILE
# DATE_FILE="2026-01-02_00.00.00" → remove "-", "." e "_" → "2026010200"
INIT_DATE=$(echo "${DATE_FILE}" | sed 's/[-.]//g' | sed 's/[_]//g' | cut -c1-10)
INIT_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/rodadas/MPAS-A/${INIT_DATE}/x1.163842.init.nc"

# Converter DATE_FILE para formato do namelist: 2026-01-02_00.00.00 → 2026-01-02_00:00:00
NAMELIST_DATE=$(echo "${DATE_FILE}" | sed 's/\./:/g' | sed 's/_\([0-9][0-9]\):\([0-9][0-9]\):\([0-9][0-9]\)/_\1:\2:\3/')

NTASKS=64
RES="163842"
SAMPLE_PREFIX="PTB_f48mf24"

PBS_QUEUE="pesqextra"
PBS_WALLTIME="04:00:00"
PBS_JOBNAME="MPAS_HDIAG_VAR"

# ============================================================
# Contar membros automaticamente do samplesUnbalanced
# ============================================================
NMEMBERS=$(find "${DIR_SAMPLES_UNB}" -maxdepth 1 \( -type l -o -type f \) \
  -name "${SAMPLE_PREFIX}_*.nc" | wc -l)

# ============================================================
# Preparação
# ============================================================
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==============================================="
echo "2a) RUN HDIAG_VAR — vargroup1 (vars dinâmicas)"
echo "==============================================="
echo "WORKDIR         = ${WORKDIR}"
echo "DIR_SAMPLES_UNB = ${DIR_SAMPLES_UNB}"
echo "NMEMBERS        = ${NMEMBERS}"
echo "DATE_FILE       = ${DATE_FILE}"
echo "INIT_DATE       = ${INIT_DATE}"
echo "INIT_FILE       = ${INIT_FILE}"
echo "NAMELIST_DATE   = ${NAMELIST_DATE}"
echo "BG_FILE         = ${BG_FILE}"
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

if [ "${NMEMBERS}" -lt 2 ]; then
  echo "ERRO: poucos membros em ${DIR_SAMPLES_UNB} (NMEMBERS=${NMEMBERS})"
  echo "Execute o script 1_run_vbal.bash antes deste."
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
# namelist.atmosphere — idêntico ao script 1
# ============================================================
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
# streams.atmosphere — idêntico ao script 1
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
# stream_list.atmosphere.* — idêntico ao script 1
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

if [ -d "${JEDI_TEST_BUILD_DIR}" ]; then
  for f in "${JEDI_TEST_BUILD_DIR}"/stream_list*; do
    [ -e "${f}" ] && ln -sf "${f}" "$(basename ${f})"
  done
fi

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
[ -f "${JEDI_TEST_BUILD_DIR}/geovars.yaml" ] && \
  ln -sf "${JEDI_TEST_BUILD_DIR}/geovars.yaml" ./geovars.yaml
[ -f "${JEDI_TEST_BUILD_DIR}/keptvars.yaml" ] && \
  ln -sf "${JEDI_TEST_BUILD_DIR}/keptvars.yaml" ./keptvars.yaml

# ============================================================
# Tabelas físicas
# ============================================================
for f in GENPARM.TBL LANDUSE.TBL SOILPARM.TBL VEGPARM.TBL COMPATIBILITY VERSION \
         CAM_ABS_DATA.DBL CAM_AEROPT_DATA.DBL OZONE_DAT.TBL OZONE_LAT.TBL \
         OZONE_PLEV.TBL RRTMG_LW_DATA RRTMG_LW_DATA.DBL RRTMG_SW_DATA RRTMG_SW_DATA.DBL; do
  [ -e "${PHYSFILESDIR}/${f}" ] && ln -sf "${PHYSFILESDIR}/${f}" "${f}"
done

# ============================================================
# YAML do HDIAG_VAR — vargroup1 (vars dinâmicas)
# Fiel ao tutorial
# ============================================================
cat > run_hdiag_var.yaml << EOF
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
  bump vunit: "avgheight"

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
        filename: ${DIR_SAMPLES_UNB}/${SAMPLE_PREFIX}_%iMember%.nc
      pattern: '%iMember%'
      start: 1
      zero padding: 3
      nmembers: ${NMEMBERS}

  saber central block:
    saber block name: BUMP_NICAS
    calibration:
      io:
        files prefix: mpas
      drivers:
        compute covariance: true
        compute correlation: true
        multivariate strategy: univariate
        write global sampling: true
        compute variance: true
        compute moments: true
        write diagnostics: true
      sampling:
        computation grid size: 12000
        diagnostic grid size: 1000
        distance classes: 10
        distance class width: 1000.0e3
        reduced levels: 10
        local diagnostic: true
        averaging length-scale: 3000.0e3
      variance:
        objective filtering: true
        filtering iterations: 1
        initial length-scale:
        - variables:
          - stream_function
          - velocity_potential
          - temperature
          - spechum
          - surface_pressure
          value: 3000.0e3
      fit:
        horizontal filtering length-scale: 3000.0e3
      output model files:
      - parameter: stddev
        file:
          filename: ./mpas.stddev.nc
          date: *date
          stream name: control
      - parameter: cor_rh
        file:
          filename: ./mpas.cor_rh.nc
          date: *date
          stream name: control
      - parameter: cor_rv
        file:
          filename: ./mpas.cor_rv.nc
          date: *date
          stream name: control
EOF

# ============================================================
# PBS
# ============================================================
cat > run_hdiag_var.pbs << EOF
#!/bin/bash
#PBS -S /bin/bash
#PBS -q ${PBS_QUEUE}
#PBS -l select=1:ncpus=${NTASKS}:mpiprocs=${NTASKS}
#PBS -l walltime=${PBS_WALLTIME}
#PBS -N ${PBS_JOBNAME}
#PBS -j oe
#PBS -o ${WORKDIR}/hdiag_job.out

#source /lustre/projetos/satdas/opt/spack/linux-sles15-zen4/gcc-13.3.0/lmod-8.7.37-6uohtfnul3kvi74dn5y2gj4dkj2hd77p/lmod/lmod/init/bash
#source /lustre/projetos/satdas/diego_workdir/spack_env_for_mpas_bundle/gcc13.3-openmpi.sh
source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash

export OMP_NUM_THREADS=1
export GFORTRAN_CONVERT_UNIT='big_endian:101-200'

cd ${WORKDIR} || exit 1

#mpirun -np ${NTASKS} ${EXEDIR}/mpasjedi_error_covariance_toolbox.x ./run_hdiag_var.yaml ./run_hdiag_var.runlog
mpiexec -n ${NTASKS} ${EXEDIR}/mpasjedi_error_covariance_toolbox.x ./run_hdiag_var.yaml ./run_hdiag_var.runlog
echo "HDIAG_VAR concluído: \$(date)"
EOF

chmod +x run_hdiag_var.pbs

# ============================================================
# Submeter
# ============================================================
echo ""
echo "==============================================="
echo "Submetendo HDIAG_VAR vargroup1"
echo "==============================================="
JOBID=$(qsub run_hdiag_var.pbs)
echo "JOBID = ${JOBID}"
echo "${JOBID}" > job_id.txt
echo ""
echo "Saídas esperadas:"
echo "  ${WORKDIR}/mpas.stddev.nc"
echo "  ${WORKDIR}/mpas.cor_rh.nc"
echo "  ${WORKDIR}/mpas.cor_rv.nc"
echo ""
echo "Monitorar: qstat ${JOBID}"
echo "Log: ${WORKDIR}/hdiag_job.out"
echo "Log: ${WORKDIR}/run_hdiag_var.runlog"
