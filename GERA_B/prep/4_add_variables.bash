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
DIR_WORK="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/BTRAIN_PREP"
ADV_TIME_EXE="/lustre/projetos/satdas/diego_workdir/WRFDA/var/build/da_advance_time.exe"

outputDir="output"
workdir="${DIR_WORK}/${outputDir}"

mkdir -p "${workdir}"
cd "${workdir}"

# ============================================================
# Argumento: fhr (24 ou 48)
# ============================================================
if [ $# -lt 1 ]; then
    echo "Uso: $0 <24|48>"
    exit 1
fi

fhr="$1"

if [ "$fhr" != "24" ] && [ "$fhr" != "48" ]; then
    echo "ERRO: fhr deve ser 24 ou 48"
    exit 1
fi

# ============================================================
# Período de rodada
# ============================================================
idate=2025122900
lastidate=2026013100

# ============================================================
# Loop principal
# ============================================================
icnt=0

while [ "${idate}" -le "${lastidate}" ]; do

    echo "==> Rodada iniciada em: ${idate}"

    # valid time = idate + fhr horas
    vdate=$("${ADV_TIME_EXE}" "${idate}" "+${fhr}h")
    echo "    valid time (f${fhr}): ${vdate}"

    vyyyy=$(echo "${vdate}" | cut -c1-4)
    vmm=$(echo   "${vdate}" | cut -c5-6)
    vdd=$(echo   "${vdate}" | cut -c7-8)
    vhh=$(echo   "${vdate}" | cut -c9-10)

    # mpasout está no diretório da rodada (idate)
    # com nome baseado no valid time
    f_fcst="${DIR_PREV}/${idate}/mpasout.${vyyyy}-${vmm}-${vdd}_${vhh}.00.00.nc"

    # Verificar se o mpasout existe
    if [ ! -s "${f_fcst}" ]; then
        echo "    AVISO: mpasout não encontrado: ${f_fcst}"
        echo "    Pulando ${idate}"
        idate=$("${ADV_TIME_EXE}" "${idate}" "+24h")
        continue
    fi

    # Verificar se o FULL_fXX.nc já existe (gerado pelo script 3)
    if [ ! -s "${vdate}/FULL_f${fhr}.nc" ]; then
        echo "    AVISO: FULL_f${fhr}.nc não encontrado em ${vdate}/"
        echo "    Execute o script 3 antes do script 4"
        idate=$("${ADV_TIME_EXE}" "${idate}" "+24h")
        continue
    fi

    icnt=$((icnt+1))
    icntpad=$(printf "%.6d" "${icnt}")

    # --------------------------------------------------------
    # Gerar script bash para essa rodada
    # --------------------------------------------------------
    cat > add_variables_f${fhr}h_${icntpad}.bash << EOF
#!/bin/bash
set -euo pipefail

source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash

echo "  Processando: ${vdate} f${fhr}"

# Calcular temperatura e umidade específica a partir do mpasout
# NOTA: mpasout não tem 'pressure' diretamente
#       pressure total = pressure_p (perturbação) + pressure_base (estado base)
ncap2 -s 'temperature=theta*( (pressure_p+pressure_base)/100000.0 )^(2.0/7.0) ; spechum = qv / (1.0 + qv)' \
  ${f_fcst} \
  ${vdate}/tmp_file_f${fhr}h.nc

# Adicionar temperature e spechum ao FULL
ncks -A -v temperature,spechum \
  ${vdate}/tmp_file_f${fhr}h.nc \
  ${vdate}/FULL_f${fhr}.nc

# Adicionar surface_pressure, vento reconstruído e umidade relativa ao FULL
ncks -A -v surface_pressure,uReconstructZonal,uReconstructMeridional,relhum \
  ${f_fcst} \
  ${vdate}/FULL_f${fhr}.nc

# Limpeza
rm ${vdate}/tmp_file_f${fhr}h.nc

echo "  Concluído: ${vdate}/FULL_f${fhr}.nc"
EOF

    chmod +x add_variables_f${fhr}h_${icntpad}.bash

    # Avançar para próxima rodada
    idate=$("${ADV_TIME_EXE}" "${idate}" "+24h")

done

ncnt=${icnt}
echo ""
echo "=== ${ncnt} scripts gerados ==="

if [ "${ncnt}" -eq 0 ]; then
    echo "Nenhum arquivo para processar."
    exit 0
fi

# ============================================================
# Submeter job PBS para rodar em paralelo
# ============================================================
cores_per_node=128

cat > qsub_addvar_f${fhr}h.bash << EOF
#!/bin/bash
#PBS -S /bin/bash
#PBS -q pesqmidi
#PBS -l select=1:ncpus=${cores_per_node}
#PBS -l walltime=01:10:00
#PBS -N add_variables_f${fhr}h
#PBS -j oe
#PBS -o add_variables_f${fhr}h.out

echo "Job iniciado em: \$(date)"
echo "Host: \$(hostname)"

#source /lustre/projetos/satdas/opt/spack/linux-sles15-zen4/gcc-13.3.0/lmod-8.7.37-6uohtfnul3kvi74dn5y2gj4dkj2hd77p/lmod/lmod/init/bash
#source /lustre/projetos/satdas/diego_workdir/spack_env_for_mpas_bundle/gcc13.3-openmpi.sh

source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash

cd ${workdir} || exit 1

SECONDS=0
nbatch=\$(((${ncnt}+${cores_per_node}-1)/${cores_per_node}))
icnt=0

for ibatch in \$(seq 1 \${nbatch}); do
    for i in \$(seq 1 ${cores_per_node}); do
        icnt=\$((icnt+1))
        if test "\${icnt}" -le "${ncnt}"; then
            icntpad=\$(printf "%.6d" "\${icnt}")
            echo "Batch \${ibatch} - job \${i}: add_variables_f${fhr}h_\${icntpad}.bash"
            bash add_variables_f${fhr}h_\${icntpad}.bash &
        fi
    done
    wait
done

wait
echo "ELAPSED TIME = \${SECONDS} s"
rm -f ./add_variables_f${fhr}h_??????.bash
EOF

chmod +x qsub_addvar_f${fhr}h.bash

Job_ID=$(qsub qsub_addvar_f${fhr}h.bash)
echo "Job submetido com ID: ${Job_ID}"
echo "${Job_ID}" > job_id_addvar_f${fhr}h.txt
