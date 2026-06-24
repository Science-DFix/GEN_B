#!/bin/bash
set -euo pipefail

# ============================================================
# Ambiente
# ============================================================
source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash

# ============================================================
# Configuração fixa
# ============================================================
DIR_WORK="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/BTRAIN_PREP"
ADV_TIME_EXE="/lustre/projetos/satdas/diego_workdir/WRFDA/var/build/da_advance_time.exe"

outputDir="output"
workdir="${DIR_WORK}/${outputDir}"

mkdir -p "${workdir}"
cd "${workdir}"

# ============================================================
# Período de valid time
# O loop usa vdate = valid time dos arquivos FULL
# vdate começa em idate+24h da primeira rodada
# ============================================================
vdate=2025122900
lastvdate=2026013100

fhr1=24
fhr2=48

# ============================================================
# Loop principal
# ============================================================
icnt=0

while [ "${vdate}" -le "${lastvdate}" ]; do

    echo "==> valid time: ${vdate}"

    f_fcst1="${vdate}/FULL_f${fhr1}.nc"
    f_fcst2="${vdate}/FULL_f${fhr2}.nc"
    f_ptb="${vdate}/PTB_f${fhr2}mf${fhr1}.nc"

    # Verificar se ambos FULL existem
    if [ -s "${f_fcst1}" ] && [ -s "${f_fcst2}" ]; then

        icnt=$((icnt+1))
        icntpad=$(printf "%.6d" "${icnt}")

        cat > ncdiff_${icntpad}.bash << EOF
#!/bin/bash
set -euo pipefail

source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash

echo "  Calculando PTB: ${vdate}"
ncdiff -O ${f_fcst2} ${f_fcst1} ${f_ptb}
echo "  Gerado: ${f_ptb}"
EOF

        chmod +x ncdiff_${icntpad}.bash

    else
        echo "    AVISO: FULL_f24.nc e/ou FULL_f48.nc ausente em ${vdate}/ — pulando"
    fi

    vdate=$("${ADV_TIME_EXE}" "${vdate}" "+24h")

done

ncnt=${icnt}
echo ""
echo "=== ${ncnt} scripts ncdiff gerados ==="

if [ "${ncnt}" -eq 0 ]; then
    echo "Nenhum par FULL_f24/FULL_f48 encontrado. Rode os scripts 3 e 4 primeiro."
    exit 0
fi

# ============================================================
# Submeter job PBS para rodar em paralelo
# ============================================================
cores_per_node=128

cat > qsub_ncdiff.bash << EOF
#!/bin/bash
#PBS -S /bin/bash
#PBS -q pesqmidi
#PBS -l select=1:ncpus=${cores_per_node}
#PBS -l walltime=00:30:00
#PBS -N ncdiff_ptb
#PBS -j oe
#PBS -o ncdiff_ptb.out

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
            echo "Batch \${ibatch} - job \${i}: ncdiff_\${icntpad}.bash"
            bash ncdiff_\${icntpad}.bash &
        fi
    done
    wait
done

wait
echo "ELAPSED TIME = \${SECONDS} s"
rm -f ./ncdiff_??????.bash
EOF

chmod +x qsub_ncdiff.bash

Job_ID=$(qsub qsub_ncdiff.bash)
echo "Job submetido com ID: ${Job_ID}"
echo "${Job_ID}" > job_id_ncdiff.txt
