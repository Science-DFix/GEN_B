cd /lustre/projetos/satdas/diego_workdir/SOURCE/scripts/GEN_B/prep

# 1. Gerar pesos ESMF (só uma vez)
bash 1_generate_ESMF_weights.bash

# 2. Gerar template PTB (só uma vez)
bash 2_generate_template_PTB.bash

# 3. Converter uv -> psi/chi para f24
bash 3_convert_uv_to_psichi.bash 24

# 4. Converter uv -> psi/chi para f48
bash 3_convert_uv_to_psichi.bash 48

# 5. Adicionar variáveis ao f24
bash 4_add_variables.bash 24

# 6. Adicionar variáveis ao f48
bash 4_add_variables.bash 48

# 7. Calcular perturbações PTB = f48 - f24
bash 5_ncdiff.bash
