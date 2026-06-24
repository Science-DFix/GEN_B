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
DIR_SAMPLES="${DIR_PROC}/samples"
DIR_HDIAG_VAR="${DIR_PROC}/HDIAG_VAR"
WORKDIR="${DIR_HDIAG_VAR}/vargroup2"

BUILDROOT="/p/projetos/satdas/diego_workdir/build-jedi"
EXEDIR="${BUILDROOT}/bin"
PHYSFILESDIR="${BUILDROOT}/_deps/mpas_data-src/atmosphere/physics_wrf/files"

BUNDLECODE="/lustre/projetos/satdas/diego_workdir/mpas-bundle"

GRAPH_BASE="/p/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/60km"
GRAPH_FILE="${GRAPH_BASE}/x1.163842.graph.info.part.128"

INVARIANT_FILE="/p/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/invariant/x1.163842.invariant.nc"

PREV_MPAS_DIR="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/PREV_MPAS"

LABELI="2026010100"
LABELF="2026010500"

NTASKS=128
RES="163842"
SAMPLE_PREFIX="PTB_f48mf24"

PBS_QUEUE="pesqmidi"
PBS_WALLTIME="02:00:00"
PBS_JOBNAME="MPAS_HDIAG_VAR_G2"

# ============================================================
# Função diffdate
# ============================================================
diffdate() {
  local di="${1}"
  local df="${2}"

  local si sf
  si=$(date --date "${di:0:8} ${di:8:2}:${di:10:2}:${di:12:2}" +%s)
  sf=$(date --date "${df:0:8} ${df:8:2}:${df:10:2}:${df:12:2}" +%s)

  local dddias ddhoras ddminutos ddsegundos
  (( dddias = (sf - si)/86400 ))
  (( ddhoras = ((sf - si) - dddias*86400)/3600 ))
  (( ddminutos = ((sf - si) - dddias*86400 - ddhoras*3600)/60 ))
  (( ddsegundos = (sf - si) - dddias*86400 - ddhoras*3600 - ddminutos*60 ))

  dddias=$(printf "%02d" "${dddias}")
  ddhoras=$(printf "%02d" "${ddhoras}")
  ddminutos=$(printf "%02d" "${ddminutos}")
  ddsegundos=$(printf "%02d" "${ddsegundos}")

  echo "${dddias}_${ddhoras}:${ddminutos}:${ddsegundos}"
}

# ============================================================
# Função de checagem NetCDF com awk
# ============================================================
check_nc_var() {
  local ncfile="$1"
  local varname="$2"

  ncdump -h "$ncfile" | awk -v target="$varname" '
    /^[[:space:]]*(byte|char|short|int|float|double)[[:space:]]+/ {
        name=$2
        gsub(/\(.*/, "", name)
        if (name == target) found=1
    }
    END {
        if (found==1) exit 0
        else exit 1
    }
  '

  if [ $? -ne 0 ]; then
    echo "ERRO: variável ${varname} não encontrada em ${ncfile}"
    return 1
  fi
}

# ============================================================
# Descoberta de arquivos auxiliares oficiais do MPAS-JEDI
# ============================================================
JEDI_TESTINPUT_CODE_DIR=""
JEDI_NAMELIST_DIR=""

if [ -d "${BUNDLECODE}/mpas-jedi/test/testinput" ]; then
  JEDI_TESTINPUT_CODE_DIR="${BUNDLECODE}/mpas-jedi/test/testinput"
fi

if [ -d "${JEDI_TESTINPUT_CODE_DIR}/namelists" ]; then
  JEDI_NAMELIST_DIR="${JEDI_TESTINPUT_CODE_DIR}/namelists"
fi

# ============================================================
# Datas e arquivos derivados
# ============================================================
start_date="${LABELI:0:4}-${LABELI:4:2}-${LABELI:6:2}_${LABELI:8:2}:00:00"
start_dateT="${LABELI:0:4}-${LABELI:4:2}-${LABELI:6:2}T${LABELI:8:2}:00:00"
start_dateP="${LABELI:0:4}-${LABELI:4:2}-${LABELI:6:2}_${LABELI:8:2}.00.00"
run_duration=$(diffdate "${LABELI}0000" "${LABELF}0000")

BACKGROUND_FILE="${PREV_MPAS_DIR}/${LABELI}/history.${start_dateP}.nc"
NAMELIST_SOURCE="${PREV_MPAS_DIR}/${LABELI}/namelist.atmosphere"

NMEMBERS=$(find "${DIR_SAMPLES}" -maxdepth 1 \( -type f -o -type l \) -name "${SAMPLE_PREFIX}_*.nc" | wc -l | awk '{print $1}')

# ============================================================
# Preparação
# ============================================================
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==============================================="
echo "2b) RUN HDIAG_VAR - VARGROUP2 (HIDROMETEOROS)"
echo "==============================================="
echo "WORKDIR            = ${WORKDIR}"
echo "DIR_SAMPLES        = ${DIR_SAMPLES}"
echo "EXEDIR             = ${EXEDIR}"
echo "GRAPH_FILE         = ${GRAPH_FILE}"
echo "INVARIANT_FILE     = ${INVARIANT_FILE}"
echo "BACKGROUND_FILE    = ${BACKGROUND_FILE}"
echo "NAMELIST_SOURCE    = ${NAMELIST_SOURCE}"
echo "NMEMBERS           = ${NMEMBERS}"
echo ""

# ============================================================
# Checagens
# ============================================================
for f in \
  "${EXEDIR}/mpasjedi_error_covariance_toolbox.x" \
  "${GRAPH_FILE}" \
  "${INVARIANT_FILE}" \
  "${BACKGROUND_FILE}" \
  "${NAMELIST_SOURCE}"
do
  if [ ! -e "${f}" ]; then
    echo "ERRO: arquivo não encontrado: ${f}"
    exit 1
  fi
done

if [ ! -d "${DIR_SAMPLES}" ]; then
  echo "ERRO: diretório não encontrado: ${DIR_SAMPLES}"
  exit 1
fi

if [ "${NMEMBERS}" -lt 2 ]; then
  echo "ERRO: poucos membros em ${DIR_SAMPLES} (NMEMBERS=${NMEMBERS})"
  exit 1
fi

for i in $(seq 1 "${NMEMBERS}"); do
  tag=$(printf "%03d" "${i}")
  if [ ! -e "${DIR_SAMPLES}/${SAMPLE_PREFIX}_${tag}.nc" ]; then
    echo "ERRO: membro não encontrado: ${DIR_SAMPLES}/${SAMPLE_PREFIX}_${tag}.nc"
    exit 1
  fi
done

echo "Checando presença dos hidrometeoros no primeiro sample..."
for v in qc qi qr qs qg; do
  check_nc_var "${DIR_SAMPLES}/${SAMPLE_PREFIX}_001.nc" "${v}" || exit 1
done

echo "Checando presença dos hidrometeoros no background..."
for v in qc qi qr qs qg; do
  check_nc_var "${BACKGROUND_FILE}" "${v}" || exit 1
done

echo "OK: hidrometeoros encontrados nos arquivos de entrada."
echo ""

# ============================================================
# Limpeza
# ============================================================
rm -f \
  x1.${RES}.invariant.nc \
  x1.${RES}.graph.info.part.${NTASKS} \
  bg.${start_dateP}.nc \
  templateFields.${RES}.nc \
  background.nc \
  control.nc \
  ensemble.nc \
  analysis.nc \
  output.nc \
  diagnostics.nc \
  streams.atmosphere \
  namelist.atmosphere \
  namelist.atmosphere.source \
  stream_list.atmosphere.* \
  geovars.yaml \
  keptvars.yaml \
  run_hdiag_var_g2.yaml \
  run_hdiag_var_g2.pbs \
  run_hdiag_var_g2.runlog* \
  hdiag_g2_job.out \
  job_id.txt \
  log.atmosphere.* \
  mpas.stddev.nc \
  mpas.cor_rh.nc \
  mpas.cor_rv.nc \
  mpas_*.nc \
  GENPARM.TBL \
  LANDUSE.TBL \
  SOILPARM.TBL \
  VEGPARM.TBL \
  COMPATIBILITY \
  VERSION \
  RRTMG* \
  OZONE* \
  CAM*

# ============================================================
# Links principais
# ============================================================
ln -sf "${GRAPH_FILE}"     "x1.${RES}.graph.info.part.${NTASKS}"
ln -sf "${INVARIANT_FILE}" "x1.${RES}.invariant.nc"

ln -sf "${BACKGROUND_FILE}" "bg.${start_dateP}.nc"
ln -sf "${BACKGROUND_FILE}" "templateFields.${RES}.nc"

ln -sf "${BACKGROUND_FILE}" "background.nc"
ln -sf "${BACKGROUND_FILE}" "control.nc"
ln -sf "${BACKGROUND_FILE}" "ensemble.nc"

# ============================================================
# namelist.atmosphere vindo da rodada real
# ============================================================
cp -f "${NAMELIST_SOURCE}" ./namelist.atmosphere.source
cp -f "${NAMELIST_SOURCE}" ./namelist.atmosphere

if grep -qi '^[[:space:]]*&assimilation' namelist.atmosphere; then
  awk '
    BEGIN{inassim=0; wrote=0}
    /^[[:space:]]*&assimilation[[:space:]]*$/ {
      print "&assimilation"
      print "    config_jedi_da = true"
      inassim=1
      wrote=1
      next
    }
    inassim && /^[[:space:]]*\/[[:space:]]*$/ {
      print "/"
      inassim=0
      next
    }
    !inassim { print }
    END{
      if (!wrote) {
        print ""
        print "&assimilation"
        print "    config_jedi_da = true"
        print "/"
      }
    }
  ' namelist.atmosphere > namelist.atmosphere.tmp
  mv namelist.atmosphere.tmp namelist.atmosphere
else
  cat >> namelist.atmosphere << EOF

&assimilation
    config_jedi_da = true
/
EOF
fi

# ============================================================
# streams.atmosphere no padrão do stream de referência
# ============================================================
cat > streams.atmosphere << EOF
<streams>
<immutable_stream name="invariant"
                  type="input"
                  precision="single"
                  filename_template="x1.${RES}.invariant.nc"
                  input_interval="initial_only" />

<immutable_stream name="input"
                  type="input"
                  precision="single"
                  filename_template="templateFields.${RES}.nc"
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

<immutable_stream name="iau"
                  type="none"
                  filename_template="x1.${RES}.AmB.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  filename_interval="none"
                  packages="iau"
                  input_interval="none" />

<immutable_stream name="lbc_in"
                  type="input"
                  io_type="pnetcdf,cdf5"
                  filename_template="lbc.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  filename_interval="input_interval"
                  packages="limited_area"
                  input_interval="3:00:00" />

</streams>
EOF

# ============================================================
# Arquivos auxiliares
# ============================================================
ln -sf "${JEDI_NAMELIST_DIR}/stream_list.atmosphere.background" ./stream_list.atmosphere.background
ln -sf "${JEDI_NAMELIST_DIR}/stream_list.atmosphere.control"    ./stream_list.atmosphere.control
ln -sf "${JEDI_NAMELIST_DIR}/stream_list.atmosphere.ensemble"   ./stream_list.atmosphere.ensemble
ln -sf "${JEDI_NAMELIST_DIR}/stream_list.atmosphere.analysis"   ./stream_list.atmosphere.analysis
ln -sf "${JEDI_NAMELIST_DIR}/geovars.yaml"                      ./geovars.yaml

cat > keptvars.yaml << EOF
fields:
  - qc
  - qi
  - qr
  - qs
  - qg
  - theta
  - pressure
  - pressure_base
  - rho
  - temperature
  - relhum
  - spechum
EOF

# ============================================================
# Tabelas físicas
# ============================================================
for f in \
  GENPARM.TBL \
  LANDUSE.TBL \
  SOILPARM.TBL \
  VEGPARM.TBL \
  COMPATIBILITY \
  VERSION
do
  if [ -e "${PHYSFILESDIR}/${f}" ]; then
    ln -sf "${PHYSFILESDIR}/${f}" "${f}"
  fi
done

for f in \
  CAM_ABS_DATA.DBL \
  CAM_AEROPT_DATA.DBL \
  OZONE_DAT.TBL \
  OZONE_LAT.TBL \
  OZONE_PLEV.TBL \
  RRTMG_LW_DATA \
  RRTMG_LW_DATA.DBL \
  RRTMG_SW_DATA \
  RRTMG_SW_DATA.DBL
do
  if [ -e "${PHYSFILESDIR}/${f}" ]; then
    ln -sf "${PHYSFILESDIR}/${f}" "${f}"
  fi
done

# ============================================================
# YAML do HDIAG/VAR - GRUPO 2
# ============================================================
cat > run_hdiag_var_g2.yaml << EOF
_member config: &memberConfig
  state variables: &vars
    - qc
    - qi
    - qr
    - qs
    - qg
  date: &date '${start_dateT}Z'
  stream name: control
  transform model to analysis: false

geometry:
  nml_file: "./namelist.atmosphere"
  streams_file: "./streams.atmosphere"
  fields:
    - qc
    - qi
    - qr
    - qs
    - qg
  bump vunit: "avgheight"

background:
  state variables: *vars
  filename: "./bg.${start_dateP}.nc"
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
        filename: ${DIR_SAMPLES}/${SAMPLE_PREFIX}_%iMember%.nc
      pattern: "%iMember%"
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
        computation grid size: 24000
        diagnostic grid size: 1000
        distance classes: 20
        distance class width: 200.0e3
        reduced levels: 10
        local diagnostic: true
        averaging length-scale: 3000.0e3

      variance:
        objective filtering: true
        filtering iterations: 1
        initial length-scale:
          - variables:
              - qc
              - qi
              - qr
              - qs
              - qg
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
cat > run_hdiag_var_g2.pbs << EOF
#!/bin/bash
#PBS -S /bin/bash
#PBS -q ${PBS_QUEUE}
#PBS -l select=1:ncpus=${NTASKS}:mpiprocs=${NTASKS}
#PBS -l walltime=${PBS_WALLTIME}
#PBS -N ${PBS_JOBNAME}
#PBS -j oe
#PBS -o ${WORKDIR}/hdiag_g2_job.out

source /lustre/projetos/satdas/opt/spack/linux-sles15-zen4/gcc-13.3.0/lmod-8.7.37-6uohtfnul3kvi74dn5y2gj4dkj2hd77p/lmod/lmod/init/bash
source /lustre/projetos/satdas/diego_workdir/spack_env_for_mpas_bundle/gcc13.3-openmpi.sh

export NP=${NTASKS}
export OMP_NUM_THREADS=1
ulimit -s unlimited
export GFORTRAN_CONVERT_UNIT='big_endian:101-200'

cd ${WORKDIR} || exit 1

echo "===== namelist.atmosphere ====="
cat namelist.atmosphere
echo "===== streams.atmosphere ====="
cat streams.atmosphere
echo "===== run_hdiag_var_g2.yaml ====="
cat run_hdiag_var_g2.yaml
echo "================================="

mpirun -np \${NP} ${EXEDIR}/mpasjedi_error_covariance_toolbox.x ./run_hdiag_var_g2.yaml ./run_hdiag_var_g2.runlog
EOF

chmod +x run_hdiag_var_g2.pbs

echo "Submetendo..."
JOBID=$(qsub run_hdiag_var_g2.pbs)
echo "${JOBID}" > job_id.txt
echo "JOBID = ${JOBID}"
