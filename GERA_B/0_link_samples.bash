#!/bin/bash
set -euo pipefail

# ============================================================
# Configuração fixa
# ============================================================
DIR_BTRAIN="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/BTRAIN_PREP"
RAW_SAMPLES_DIR="${DIR_BTRAIN}/output"
SAMPLES_DIR="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/GEN_B/proc/samples"
WRFBIN="/lustre/projetos/satdas/diego_workdir/WRFDA/var/build"

# ============================================================
# Período das valid times com PTB disponíveis
# PTB gerados: 2026010200 a 2026010700 (6 perturbações)
# ============================================================
date=2025123100
lastdate=2026013100

workdir="${SAMPLES_DIR}"

mkdir -p "${workdir}"
cd "${workdir}"

imem=1  # sample index

while [ "${date}" -le "${lastdate}" ]; do

    echo "running for ${date}"

    fileTarget="${RAW_SAMPLES_DIR}/${date}/PTB_f48mf24.nc"
    if [ -s "${fileTarget}" ]; then
        member=$(printf "%03d" "${imem}")
        ln -fs "${fileTarget}" "./PTB_f48mf24_${member}.nc"
        echo "  linked: PTB_f48mf24_${member}.nc -> ${fileTarget}"
        imem=$((imem+1))
    else
        echo "  skipping: ${fileTarget} not found"
    fi

    date=$("${WRFBIN}/da_advance_time.exe" "${date}" "+24h")

done

echo ""
echo "=== Total de amostras linkadas: $((imem-1)) ==="
echo "Diretório: ${SAMPLES_DIR}"
ls -l "${SAMPLES_DIR}"

cd ..
