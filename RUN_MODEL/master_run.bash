#!/bin/bash
# ==============================================================================
# MASTER RUN SCRIPT - MPAS-A (Init + Forecast)
# Cluster: Jaci (CPTEC/INPE)
# Chamado por: submete_jaci.pbs
# ==============================================================================

# --- 1. Processamento (vem do PBS via export) ---
export NP=${NP:-256}

# --- 2. PRECISÃO: "single" ou "double" ---
# single: usa build_mpas_sp + MPAS-JEDI precisão simples (SfcCorrected disponível)
# double: usa build-jedi   + MPAS-JEDI precisão dupla
export PRECISION="double"

# --- 3. Diretórios de build conforme precisão ---
if [ "${PRECISION}" = "single" ]; then
    export DIR_BUILD="/lustre/projetos/satdas/diego_workdir/TESTE_MPAS_JEDI/build_mpas_sp"
    export MPAS_DOUBLE_PRECISION="false"
else
    export DIR_BUILD="/lustre/projetos/satdas/diego_workdir/build-mpich"
    export MPAS_DOUBLE_PRECISION="true"
fi
export DIR_EXE="${DIR_BUILD}/bin"
export DIR_PHYSICS="${DIR_BUILD}/_deps/mpas_data-src/atmosphere/physics_wrf/files"

# --- 4. Configurações da Previsão ---
export RUN_DURATION="2_00:00:00"
export OUTPUT_INTERVAL="06:00:00"
export DIAG_INTERVAL="03:00:00"
export DT="360"
export RADT_INTERVAL="00:30:00"
export SST_UPDATE="false"
export PHYSICS_SUITE="mesoscale_reference"
export IAU_OPTION="off"

# --- 5. Período de Rodada ---
ANOS="2026"
MESES="01"
DIAS="01"
HORAS="00"

# --- 6. Log central ---
LOG_GERAL="execucao_total.log"

echo "======================================================" | tee -a $LOG_GERAL
echo " PRECISÃO : ${PRECISION}"                              | tee -a $LOG_GERAL
echo " BUILD    : ${DIR_BUILD}"                              | tee -a $LOG_GERAL
echo " Iniciado : $(date)"                                   | tee -a $LOG_GERAL
echo "======================================================" | tee -a $LOG_GERAL

# --- 7. Loop de Execução ---
for ano in $ANOS; do
    for mes in $MESES; do
        for dia in $DIAS; do
            for hora in $HORAS; do
                export TIMESTAMP="${ano}${mes}${dia}${hora}"
                DIR_INIT="/lustre/projetos/satdas/diego_workdir/SOURCE/rodadas/MPAS-A/${TIMESTAMP}"
                DIR_FCST="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/PREV_MPAS/${TIMESTAMP}"

                echo "=== INICIANDO CICLO $TIMESTAMP EM $(date) ===" | tee -a $LOG_GERAL

                # --- PASSO 1: INIT ---
                start_init=$(date +%s)
                ./run_mpas_atmosphere.bash
                res_init=$?
                end_init=$(date +%s)
                diff_init=$((end_init - start_init))

                if [ $res_init -eq 0 ]; then
                    echo "Init OK: $((diff_init/60))m $((diff_init%60))s" > "${DIR_INIT}/tempo.log"
                    echo "Precisão: ${PRECISION}" >> "${DIR_INIT}/tempo.log"

                    # --- PASSO 2: FORECAST ---
                    start_fcst=$(date +%s)
                    ./run_mpas_forecast.bash
                    res_fcst=$?
                    end_fcst=$(date +%s)
                    diff_fcst=$((end_fcst - start_fcst))

                    if [ $res_fcst -eq 0 ]; then
                        echo "Forecast OK: $((diff_fcst/60))m $((diff_fcst%60))s" > "${DIR_FCST}/tempo.log"
                        echo "Precisão: ${PRECISION}" >> "${DIR_FCST}/tempo.log"
                        echo "SUCESSO: $TIMESTAMP | Init: ${diff_init}s | Fcst: ${diff_fcst}s" | tee -a $LOG_GERAL
                    else
                        echo "ERRO no Forecast de $TIMESTAMP" | tee -a $LOG_GERAL
                        exit 1
                    fi
                else
                    echo "ERRO no Init de $TIMESTAMP" | tee -a $LOG_GERAL
                    exit 1
                fi

            done
        done
    done
done

echo "=== CONCLUÍDO EM $(date) ===" | tee -a $LOG_GERAL
