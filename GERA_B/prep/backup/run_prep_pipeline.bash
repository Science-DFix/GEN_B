#!/bin/bash
set -e

echo "==============================================="
echo "   MPAS B-MATRIX PREP PIPELINE"
echo "==============================================="
echo ""

# =====================================================
# CONFIGURAÇÕES DO USUÁRIO
# =====================================================

RES_LL="1.0"

REF_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/PREV_MPAS/2026010100/history.2026-01-02_00.00.00.nc"

LABELI="2026010100"
LABELF="2026010500"

INIT_STEP=24
FHR1=24
FHR2=48

# =====================================================
# CHECAGEM DE SCRIPTS
# =====================================================

for script in \
1_generate_ESMF_weights.bash \
2_generate_template_PTB.bash \
3_convert_uv_to_psichi.bash \
4_add_variables.bash \
5_ncdiff.bash
do
    if [ ! -f "$script" ]; then
        echo "ERRO: script não encontrado -> $script"
        exit 1
    fi
done

echo "Todos os scripts encontrados."
echo ""

# =====================================================
# ETAPA 1 — PESOS ESMF
# =====================================================

echo "==============================================="
echo "1) GERANDO PESOS ESMF"
echo "==============================================="

bash 1_generate_ESMF_weights.bash ${RES_LL}

echo ""
echo "Pesos ESMF gerados."
echo ""

# =====================================================
# ETAPA 2 — TEMPLATE PTB
# =====================================================

echo "==============================================="
echo "2) GERANDO TEMPLATE PTB"
echo "==============================================="

bash 2_generate_template_PTB.bash ${REF_FILE}

echo ""
echo "Template gerado."
echo ""

# =====================================================
# ETAPA 3A — UV → PSI/CHI PARA F24
# =====================================================

echo "==============================================="
echo "3A) CONVERTENDO U/V → PSI/CHI (F24)"
echo "==============================================="

bash 3_convert_uv_to_psichi.bash \
${RES_LL}x${RES_LL} \
${LABELI} \
${LABELF} \
${INIT_STEP} \
${FHR1}

echo ""
echo "Conversão dinâmica F24 finalizada."
echo ""

# =====================================================
# ETAPA 4A — ADICIONANDO VARIÁVEIS AO F24
# =====================================================

echo "==============================================="
echo "4A) ADICIONANDO VARIÁVEIS AO F24"
echo "==============================================="

bash 4_add_variables.bash \
${LABELI} \
${LABELF} \
${INIT_STEP} \
${FHR1}

echo ""
echo "Variáveis físicas adicionadas ao F24."
echo ""

# =====================================================
# ETAPA 3B — UV → PSI/CHI PARA F48
# =====================================================

echo "==============================================="
echo "3B) CONVERTENDO U/V → PSI/CHI (F48)"
echo "==============================================="

bash 3_convert_uv_to_psichi.bash \
${RES_LL}x${RES_LL} \
${LABELI} \
${LABELF} \
${INIT_STEP} \
${FHR2}

echo ""
echo "Conversão dinâmica F48 finalizada."
echo ""

# =====================================================
# ETAPA 4B — ADICIONANDO VARIÁVEIS AO F48
# =====================================================

echo "==============================================="
echo "4B) ADICIONANDO VARIÁVEIS AO F48"
echo "==============================================="

bash 4_add_variables.bash \
${LABELI} \
${LABELF} \
${INIT_STEP} \
${FHR2}

echo ""
echo "Variáveis físicas adicionadas ao F48."
echo ""

# =====================================================
# ETAPA 5 — GERANDO PTB = F48 - F24
# =====================================================

echo "==============================================="
echo "5) GERANDO PERTURBAÇÕES (PTB = F48 - F24)"
echo "==============================================="

bash 5_ncdiff.bash \
${LABELI} \
${LABELF} \
${INIT_STEP} \
${FHR1} \
${FHR2}

echo ""
echo "==============================================="
echo "PIPELINE FINALIZADA COM SUCESSO"
echo "==============================================="
echo ""
