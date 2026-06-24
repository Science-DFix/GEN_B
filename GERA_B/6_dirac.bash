#!/bin/bash
set -euo pipefail

# ============================================================
# Ambiente
# ============================================================
source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash

# ============================================================
# Configuração — adaptar aqui para mudar datas/caminhos
# ============================================================
DIR_GENB="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/GEN_B"
DIR_PROC="${DIR_GENB}/proc"

DIR_NICAS_MERGE="${DIR_PROC}/NICAS.split/merge"
STDDEV_FILE="${DIR_PROC}/HDIAG_VAR/merge/mpas.stddev.nc"
DIR_VBAL="${DIR_PROC}/VBAL"

BUILDROOT="/lustre/projetos/satdas/diego_workdir/build-jedi"
EXEDIR="${BUILDROOT}/bin"
PHYSFILESDIR="${BUILDROOT}/_deps/mpas_data-src/atmosphere/physics_wrf/files"

GRAPH_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/invariant/x1.163842.graph.info.part.64"
INVARIANT_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/invariant/x1.163842.invariant.nc"

# Background — mesmo mpasout dos scripts anteriores
BG_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/PREV_MPAS/2026010100/mpasout.2026-01-02_00.00.00.nc"
DATE_FILE="2026-01-02_00.00.00"
DATE_YAML="2026-01-02T00:00:00Z"

# init.nc derivado do DATE_FILE
INIT_DATE=$(echo "${DATE_FILE}" | sed 's/[-.]//g' | sed 's/[_]//g' | cut -c1-10)
INIT_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/rodadas/MPAS-A/${INIT_DATE}/x1.163842.init.nc"

# Namelist date
NAMELIST_DATE=$(echo "${DATE_FILE}" | sed 's/\./:/g' | sed 's/_\([0-9][0-9]\):\([0-9][0-9]\):\([0-9][0-9]\)/_\1:\2:\3/')

RES="163842"
NTASKS=64

PBS_QUEUE="pesqextra"
PBS_WALLTIME="02:00:00"
PBS_JOBNAME="MPAS_DIRAC"

# ============================================================
# Parâmetros do teste Dirac
# Ponto único para evitar "duplicated dirac on >1 processors"
# ============================================================
DIRAC_VAR="temperature"
DIRAC_LEVEL=10
DIRAC_LAT="30.31011691"
DIRAC_LON="130.11182691"

# ============================================================
# Preparação
# ============================================================
WORKDIR="${DIR_PROC}/Dirac/test_${DIRAC_VAR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==============================================="
echo "6) RUN DIRAC"
echo "==============================================="
echo "WORKDIR         = ${WORKDIR}"
echo "DIR_NICAS_MERGE = ${DIR_NICAS_MERGE}"
echo "STDDEV_FILE     = ${STDDEV_FILE}"
echo "DIR_VBAL        = ${DIR_VBAL}"
echo "DATE_FILE       = ${DATE_FILE}"
echo "INIT_DATE       = ${INIT_DATE}"
echo "INIT_FILE       = ${INIT_FILE}"
echo "BG_FILE         = ${BG_FILE}"
echo "DIRAC_VAR       = ${DIRAC_VAR}"
echo "DIRAC_LEVEL     = ${DIRAC_LEVEL}"
echo "DIRAC_LAT       = ${DIRAC_LAT}"
echo "DIRAC_LON       = ${DIRAC_LON}"
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
  "${STDDEV_FILE}" \
  "${DIR_NICAS_MERGE}/mpas_nicas.nc" \
  "${DIR_NICAS_MERGE}/mpas_nicas_local_000064-000001.nc" \
  "${DIR_VBAL}/mpas_vbal.nc" \
  "${DIR_VBAL}/mpas_vbal_local_000064-000001.nc"
do
  if [ ! -e "${f}" ]; then
    echo "ERRO: arquivo não encontrado: ${f}"
    exit 1
  fi
done

# ============================================================
# Links principais — mesma lógica do script 5
# templateFields aponta para mpasout (stream input)
# background.nc aponta para mpasout (stream background)
# ============================================================
ln -sf "${GRAPH_FILE}"     "x1.${RES}.graph.info.part.${NTASKS}"
ln -sf "${INVARIANT_FILE}" "x1.${RES}.invariant.nc"
ln -sf "${INIT_FILE}"      "x1.${RES}.init.nc"
ln -sf "${BG_FILE}"        "templateFields.${RES}.nc"
ln -sf "${BG_FILE}"        "background.nc"
ln -sf "${BG_FILE}"        "control.nc"
ln -sf "${BG_FILE}"        "ensemble.nc"

# Tabelas físicas
for f in GENPARM.TBL LANDUSE.TBL SOILPARM.TBL VEGPARM.TBL COMPATIBILITY VERSION \
         CAM_ABS_DATA.DBL CAM_AEROPT_DATA.DBL OZONE_DAT.TBL OZONE_LAT.TBL \
         OZONE_PLEV.TBL RRTMG_LW_DATA RRTMG_LW_DATA.DBL RRTMG_SW_DATA RRTMG_SW_DATA.DBL; do
  [ -e "${PHYSFILESDIR}/${f}" ] && ln -sf "${PHYSFILESDIR}/${f}" "${f}"
done

# ============================================================
# geovars.yaml — gerado inline com mapeamento correto do tutorial
# CRÍTICO: air_temperature -> mpas identity field: temperature
# ============================================================
cat > geovars.yaml << 'EOF'
fields:
  - field name: air_pressure
    mpas template field: theta
    mpas identity field: pressure

  - field name: air_pressure_levels
    mpas template field: w

  - field name: upward_air_velocity
    mpas template field: theta

  - field name: geopotential_height
    mpas template field: theta

  - field name: geopotential_height_levels
    mpas template field: w

  - field name: virtual_temperature
    mpas template field: theta

  - field name: air_temperature
    mpas template field: theta
    mpas identity field: temperature

  - field name: temperature
    mpas template field: theta
    mpas identity field: temperature

  - field name: eastward_wind
    mpas template field: theta
    mpas identity field: uReconstructZonal

  - field name: northward_wind
    mpas template field: theta
    mpas identity field: uReconstructMeridional

  - field name: specific_humidity
    mpas template field: theta
    mpas identity field: spechum

  - field name: surface_pressure
    mpas template field: u10
    mpas identity field: surface_pressure

  - field name: landmask
    mpas template field: ivgtyp
    mpas identity field: landmask

  - field name: seaice_fraction
    mpas template field: u10
    mpas identity field: xice

  - field name: skin_temperature
    mpas template field: u10
    mpas identity field: skintemp

  - field name: uwind_at_10m
    mpas template field: u10
    mpas identity field: u10

  - field name: vwind_at_10m
    mpas template field: u10
    mpas identity field: v10

  - field name: qv
    mpas template field: theta
    mpas identity field: qv

  - field name: qc
    mpas template field: theta
    mpas identity field: qc

  - field name: qi
    mpas template field: theta
    mpas identity field: qi

  - field name: qr
    mpas template field: theta
    mpas identity field: qr

  - field name: qs
    mpas template field: theta
    mpas identity field: qs

  - field name: qg
    mpas template field: theta
    mpas identity field: qg
EOF

# ============================================================
# keptvars.yaml — gerado inline com campos do tutorial
# ============================================================
cat > keptvars.yaml << 'EOF'
fields:
  - re_cloud
  - re_ice
  - re_snow
  - cldfrac
  - lai
  - u10
  - v10
  - q2
  - t2m
  - pressure_p
  - pressure
  - pressure_base
  - surface_pressure
  - rho
  - theta
  - temperature
  - relhum
  - spechum
  - u
  - uReconstructZonal
  - uReconstructMeridional
  - stream_function
  - velocity_potential
  - landmask
  - xice
  - snowc
  - znt
  - skintemp
  - ivgtyp
  - isltyp
  - snowh
  - vegfra
  - smois
  - tslb
  - vorticity
  - w
EOF

# ============================================================
# stream_list — fiel ao tutorial (usa scalars, não qv diretamente)
# ============================================================
cat > stream_list.atmosphere.background << EOF
cldfrac
lai
pressure_base
pressure_p
re_cloud
re_ice
re_snow
rho
scalars
skintemp
smois
snowc
snowh
surface_pressure
theta
tslb
u
u10
uReconstructZonal
uReconstructMeridional
v10
vegfra
w
xice
EOF

cat > stream_list.atmosphere.control << EOF
scalars
spechum
stream_function
surface_pressure
temperature
uReconstructZonal
uReconstructMeridional
velocity_potential
EOF

cat > stream_list.atmosphere.analysis << EOF
pressure_p
rho
scalars
surface_pressure
theta
u
uReconstructZonal
uReconstructMeridional
EOF

cat > stream_list.atmosphere.ensemble << EOF
pressure_base
pressure_p
scalars
surface_pressure
theta
uReconstructZonal
uReconstructMeridional
EOF

# ============================================================
# namelist.atmosphere
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
# streams.atmosphere — fiel ao tutorial
# ============================================================
cat > streams.atmosphere << EOF
<streams>

<immutable_stream name="invariant"
                  type="input"
                  precision="single"
                  filename_template="x1.${RES}.invariant.nc"
                  io_type="pnetcdf,cdf5"
                  input_interval="initial_only" />

<immutable_stream name="input"
                  type="input"
                  precision="single"
                  filename_template="templateFields.${RES}.nc"
                  io_type="pnetcdf,cdf5"
                  input_interval="initial_only" />

<immutable_stream name="da_state"
                  type="output"
                  precision="single"
                  io_type="pnetcdf,cdf5"
                  filename_template="mpasout.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  output_interval="none"
                  clobber_mode="overwrite" />

<stream name="background"
        type="input;output"
        precision="single"
        io_type="pnetcdf,cdf5"
        filename_template="background.nc"
        input_interval="none"
        output_interval="none"
        clobber_mode="overwrite">
        <file name="stream_list.atmosphere.background"/>
</stream>

<stream name="analysis"
        type="output"
        precision="single"
        io_type="pnetcdf,cdf5"
        filename_template="analysis.nc"
        output_interval="none"
        clobber_mode="overwrite">
        <file name="stream_list.atmosphere.analysis"/>
</stream>

<stream name="ensemble"
        type="input;output"
        precision="single"
        io_type="pnetcdf,cdf5"
        filename_template="ensemble.nc"
        input_interval="none"
        output_interval="none"
        clobber_mode="overwrite">
        <file name="stream_list.atmosphere.ensemble"/>
</stream>

<stream name="control"
        type="input;output"
        precision="single"
        io_type="pnetcdf,cdf5"
        filename_template="control.nc"
        input_interval="none"
        output_interval="none"
        clobber_mode="overwrite">
        <file name="stream_list.atmosphere.control"/>
</stream>

<stream name="output"
        type="none"
        filename_template="output.nc"
        output_interval="0_01:00:00" >
</stream>

<stream name="diagnostics"
        type="none"
        filename_template="diagnostics.nc"
        output_interval="0_01:00:00" >
</stream>

</streams>
EOF

# ============================================================
# YAML do DIRAC
# ============================================================
cat > run_dirac.yaml << EOF
geometry:
  nml_file: "./namelist.atmosphere"
  streams_file: "./streams.atmosphere"
  deallocate non-da fields: false

background:
  state variables: &statevars
  - spechum
  - surface_pressure
  - temperature
  - uReconstructMeridional
  - uReconstructZonal
  - theta
  - rho
  - u
  - qv
  - pressure
  - pressure_p
  filename: "./background.nc"
  date: &date '${DATE_YAML}'

background error:
  covariance model: SABER

  saber central block:
    saber block name: BUMP_NICAS
    active variables: &ctlvars
    - stream_function
    - velocity_potential
    - temperature
    - spechum
    - surface_pressure
    read:
      io:
        data directory: ${DIR_NICAS_MERGE}
        files prefix: mpas
      drivers:
        multivariate strategy: univariate
        read local nicas: true
      grids:
      - model:
          variables:
          - stream_function
          - velocity_potential
          - temperature
          - spechum
      - model:
          variables:
          - surface_pressure

  saber outer blocks:
  - saber block name: StdDev
    read:
      model file:
        filename: ${STDDEV_FILE}
        date: *date
        stream name: control

  - saber block name: BUMP_VerticalBalance
    read:
      io:
        data directory: ${DIR_VBAL}
        files prefix: mpas
      drivers:
        read local sampling: true
        read vertical balance: true
      vertical balance:
        vbal:
        - balanced variable: velocity_potential
          unbalanced variable: stream_function
          diagonal regression: true
        - balanced variable: temperature
          unbalanced variable: stream_function
        - balanced variable: surface_pressure
          unbalanced variable: stream_function

  linear variable change:
    linear variable change name: Control2Analysis
    input variables: *ctlvars
    output variables: [spechum,surface_pressure,temperature,uReconstructMeridional,uReconstructZonal]

dirac:
  ndir: 1
  dirLats: [${DIRAC_LAT}]
  dirLons: [${DIRAC_LON}]
  ildir: ${DIRAC_LEVEL}
  dirvar: ${DIRAC_VAR}

output dirac:
  filename: "./mpas.dirac.nc"
  date: *date
  stream name: control
EOF

# ============================================================
# PBS
# ============================================================
cat > run_dirac.pbs << EOF
#!/bin/bash
#PBS -S /bin/bash
#PBS -q ${PBS_QUEUE}
#PBS -l select=1:ncpus=${NTASKS}:mpiprocs=${NTASKS}
#PBS -l walltime=${PBS_WALLTIME}
#PBS -N ${PBS_JOBNAME}
#PBS -j oe
#PBS -o ${WORKDIR}/dirac_job.out

source /lustre/projetos/satdas/opt/spack/linux-sles15-zen4/gcc-13.3.0/lmod-8.7.37-6uohtfnul3kvi74dn5y2gj4dkj2hd77p/lmod/lmod/init/bash
source /lustre/projetos/satdas/diego_workdir/spack_env_for_mpas_bundle/gcc13.3-openmpi.sh

export OMP_NUM_THREADS=1
export GFORTRAN_CONVERT_UNIT='big_endian:101-200'
ulimit -s unlimited

cd ${WORKDIR} || exit 1

mpirun -np ${NTASKS} ${EXEDIR}/mpasjedi_error_covariance_toolbox.x \
  ./run_dirac.yaml ./run_dirac.runlog

echo "DIRAC concluído: \$(date)"
EOF

chmod +x run_dirac.pbs

# ============================================================
# Submeter
# ============================================================
echo ""
echo "==============================================="
echo "Submetendo DIRAC..."
echo "==============================================="
JOBID=$(qsub run_dirac.pbs)
echo "${JOBID}" > job_id.txt
echo "JOBID = ${JOBID}"
echo ""
echo "Saída esperada: ${WORKDIR}/mpas.dirac.nc"
echo "Monitorar: qstat ${JOBID}"
echo "Log: ${WORKDIR}/dirac_job.out"
echo "Log: ${WORKDIR}/run_dirac.runlog"
