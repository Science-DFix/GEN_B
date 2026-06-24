#!/bin/bash

# --- CONFIGURAÇÃO DE SAÍDA ---
BASE_OUT="/lustre/projetos/satdas/diego_workdir/SOURCE/datainput/gfs"

# --- CONFIGURAÇÃO GLOBAL ---
CICLO="06"

# --- LOOP DE ANOS ---
for ano in $(seq 2025 2025); do
    # --- LOOP DE MESES ---
    for mes in $(seq -f "%02g" 12 12); do
        # --- LOOP DE DIAS ---
        for dia in $(seq -f "%02g" 29 31); do

            ANOMESDIA="${ano}${mes}${dia}"
            # Define o diretório final: LOCAL_SAIDA/anomesdiaciclo
            LOCAL_SAIDA="${BASE_OUT}/${ANOMESDIA}${CICLO}"

            # Cria o diretório se não existir
            mkdir -p "$LOCAL_SAIDA"

            # Configuração das opções do wget (apontando para o diretório específico)
            # -N: timestamping (não baixa se já existir e for igual)
            # -P: define o diretório de destino
            OPTS="-N -P $LOCAL_SAIDA --no-check-certificate"

            # --- LOOP DE PREVISÃO ---
            for prev in $(seq -f "%02g" 00 3 48); do

                # URL do servidor Pelican (Duke University)
                # Note o uso de f0${prev} para manter o formato f000, f003, etc.
                URL="https://pelican-cache.rc.duke.edu:443/ncar/gdex/d084001/${ano}/${ANOMESDIA}/gfs.0p25.${ANOMESDIA}${CICLO}.f0${prev}.grib2"

                echo "----------------------------------------------------------------"
                echo "Baixando: gfs.0p25.${ANOMESDIA}${CICLO}.f0${prev}.grib2"
                echo "Destino: $LOCAL_SAIDA"

                # Executa o wget
                wget $OPTS "$URL"

            done
        done
    done
done

echo "Processo de download GFS concluído."
exit
